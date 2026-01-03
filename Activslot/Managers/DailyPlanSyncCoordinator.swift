import Foundation
import EventKit
import UserNotifications

/// Coordinates automatic daily walk planning with calendar sync
/// - Generates plans using SmartPlannerEngine's pattern learning
/// - Syncs planned activities to user's calendar
/// - Continuously optimizes throughout the day based on progress
/// - Manages calendar event lifecycle (create, update, delete)
class DailyPlanSyncCoordinator: ObservableObject {
    static let shared = DailyPlanSyncCoordinator()

    private let smartPlanner = SmartPlannerEngine.shared
    private let calendarManager = CalendarManager.shared
    private let healthKitManager = HealthKitManager.shared
    private let eventStore = EKEventStore()

    @Published var isProcessing = false
    @Published var lastSyncResult: SyncResult?
    @Published var syncErrors: [SyncError] = []

    // Tracking for continuous optimization
    private var lastOptimizationTime: Date?
    private var lastKnownStepCount: Int = 0
    private let optimizationCooldown: TimeInterval = 30 * 60 // 30 minutes between auto-optimizations
    private let significantStepChange: Int = 1000 // Re-optimize if steps change by this much

    // MARK: - Data Types

    struct SyncResult {
        let date: Date
        let eventsCreated: Int
        let eventsUpdated: Int
        let eventsDeleted: Int
        let activitiesSynced: [SmartPlannerEngine.PlannedActivity]
        let syncedAt: Date
        let optimizationType: OptimizationType
    }

    enum OptimizationType: String {
        case initial = "Initial plan"
        case morningRefresh = "Morning refresh"
        case calendarChange = "Calendar changed"
        case stepProgress = "Step progress update"
        case periodic = "Periodic optimization"
        case manual = "Manual sync"
    }

    enum SyncError: Error, LocalizedError {
        case noCalendarSelected
        case calendarPermissionDenied
        case calendarNotFound
        case planGenerationFailed
        case eventCreationFailed(String)
        case eventUpdateFailed(String)
        case eventDeletionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noCalendarSelected: return "No calendar selected for sync"
            case .calendarPermissionDenied: return "Calendar permission denied"
            case .calendarNotFound: return "Selected calendar not found"
            case .planGenerationFailed: return "Failed to generate daily plan"
            case .eventCreationFailed(let msg): return "Failed to create event: \(msg)"
            case .eventUpdateFailed(let msg): return "Failed to update event: \(msg)"
            case .eventDeletionFailed(let msg): return "Failed to delete event: \(msg)"
            }
        }
    }

    private init() {}

    // MARK: - Main Sync Entry Points

    /// Called in evening to generate and sync tomorrow's plan
    func syncTomorrowPlan() async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled else { return }

        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return }
        await generateAndSync(for: tomorrow, optimizationType: .initial)
    }

    /// Called in morning to refresh/regenerate today's plan
    func refreshTodayPlan() async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled && prefs.smartPlanMorningRefreshEnabled else { return }

        await generateAndSync(for: Date(), optimizationType: .morningRefresh)
    }

    /// Manual sync for a specific date
    func syncPlan(for date: Date) async {
        await generateAndSync(for: date, optimizationType: .manual)
    }

    // MARK: - Continuous Optimization

    /// Called when app becomes active - checks if re-optimization is needed
    func optimizeIfNeeded() async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled else { return }

        // Only optimize during active hours
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= prefs.wakeTime.hour && hour < prefs.sleepTime.hour else { return }

        // Check cooldown
        if let lastTime = lastOptimizationTime,
           Date().timeIntervalSince(lastTime) < optimizationCooldown {
            // Check if step count changed significantly
            let currentSteps = await fetchCurrentSteps()
            if abs(currentSteps - lastKnownStepCount) >= significantStepChange {
                await generateAndSync(for: Date(), optimizationType: .stepProgress, forceUpdate: true)
                lastKnownStepCount = currentSteps
            }
            return
        }

        // Periodic optimization
        await generateAndSync(for: Date(), optimizationType: .periodic)
        lastOptimizationTime = Date()
        lastKnownStepCount = await fetchCurrentSteps()
    }

    /// Called when step count updates significantly
    func handleStepCountChange(newSteps: Int) async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled else { return }

        // Check if change is significant
        if abs(newSteps - lastKnownStepCount) >= significantStepChange {
            lastKnownStepCount = newSteps
            await generateAndSync(for: Date(), optimizationType: .stepProgress, forceUpdate: true)
        }
    }

    /// Called when user completes or skips an activity
    func handleActivityStatusChange() async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled else { return }

        // Re-optimize to fill gaps or adjust based on completion
        await generateAndSync(for: Date(), optimizationType: .stepProgress, forceUpdate: true)
    }

    private func fetchCurrentSteps() async -> Int {
        do {
            return try await healthKitManager.fetchTodaySteps()
        } catch {
            return lastKnownStepCount
        }
    }

    // MARK: - Core Sync Logic

    private func generateAndSync(
        for date: Date,
        optimizationType: OptimizationType = .initial,
        forceUpdate: Bool = false
    ) async {
        let prefs = UserPreferences.shared
        let dateString = formatDateString(date)
        let isToday = Calendar.current.isDateInToday(date)

        // Check if we should skip this sync (unless forced)
        if !forceUpdate && prefs.smartPlanLastSyncDate == dateString && !isToday {
            return
        }

        await MainActor.run {
            isProcessing = true
            syncErrors = []
        }
        defer { Task { await MainActor.run { isProcessing = false } } }

        // Validate prerequisites
        guard validatePrerequisites() else { return }

        // Step 1: Ensure patterns are analyzed
        if smartPlanner.userPatterns == nil {
            await smartPlanner.analyzeUserPatterns()
        }

        // Step 2: Generate the smart plan
        let plan = await smartPlanner.generateDailyPlan(for: date)

        // Step 3: For today's plan, only update FUTURE activities (preserve past ones)
        var activitiesToSync: [SmartPlannerEngine.PlannedActivity]
        var deletedCount = 0

        if isToday {
            let now = Date()

            // Filter to only future activities
            activitiesToSync = plan.activities.filter { activity in
                activity.startTime > now
            }

            // Delete only future managed events, keep past ones
            deletedCount = await deleteFutureEvents(for: dateString, after: now)

            #if DEBUG
            print("DailyPlanSyncCoordinator: Optimizing - keeping past activities, updating \(activitiesToSync.count) future slots")
            #endif
        } else {
            // For tomorrow or other dates, sync all activities
            activitiesToSync = plan.activities
            deletedCount = await deleteExistingEvents(for: dateString)
        }

        // Step 4: Create new calendar events for planned activities
        let (createdIDs, createdCount) = await createCalendarEvents(
            for: activitiesToSync,
            date: date
        )

        // Step 5: Store managed event IDs for lifecycle management
        var managedIDs = prefs.smartPlanManagedEventIDs
        if isToday {
            // Merge new IDs with existing ones (for past activities)
            var existingIDs = managedIDs[dateString] ?? []
            existingIDs.append(contentsOf: createdIDs)
            managedIDs[dateString] = existingIDs
        } else {
            managedIDs[dateString] = createdIDs
        }
        prefs.smartPlanManagedEventIDs = managedIDs

        // Step 6: Update sync tracking
        prefs.smartPlanLastSyncDate = dateString
        lastOptimizationTime = Date()

        // Step 7: Report result
        await MainActor.run {
            lastSyncResult = SyncResult(
                date: date,
                eventsCreated: createdCount,
                eventsUpdated: 0,
                eventsDeleted: deletedCount,
                activitiesSynced: activitiesToSync,
                syncedAt: Date(),
                optimizationType: optimizationType
            )
        }

        #if DEBUG
        print("DailyPlanSyncCoordinator: [\(optimizationType.rawValue)] Synced \(createdCount) events for \(dateString)")
        #endif
    }

    /// Delete only future events (for re-optimization that preserves past activities)
    private func deleteFutureEvents(for dateString: String, after cutoffTime: Date) async -> Int {
        let prefs = UserPreferences.shared
        guard let eventIDs = prefs.smartPlanManagedEventIDs[dateString] else { return 0 }

        var deletedCount = 0
        var remainingIDs: [String] = []

        for eventID in eventIDs {
            if let event = eventStore.event(withIdentifier: eventID) {
                // Only delete if event starts after cutoff time
                if event.startDate > cutoffTime {
                    do {
                        try eventStore.remove(event, span: .thisEvent)
                        deletedCount += 1
                    } catch {
                        await MainActor.run {
                            syncErrors.append(.eventDeletionFailed(error.localizedDescription))
                        }
                    }
                } else {
                    // Keep past events
                    remainingIDs.append(eventID)
                }
            }
        }

        // Update stored IDs to only include remaining (past) events
        var managedIDs = prefs.smartPlanManagedEventIDs
        managedIDs[dateString] = remainingIDs
        prefs.smartPlanManagedEventIDs = managedIDs

        return deletedCount
    }

    // MARK: - Prerequisites Validation

    private func validatePrerequisites() -> Bool {
        let prefs = UserPreferences.shared

        // Check calendar permission
        guard calendarManager.isAuthorized else {
            Task { @MainActor in syncErrors.append(.calendarPermissionDenied) }
            return false
        }

        // Check calendar selected
        guard !prefs.smartPlanCalendarID.isEmpty else {
            Task { @MainActor in syncErrors.append(.noCalendarSelected) }
            return false
        }

        // Check calendar exists
        let calendars = eventStore.calendars(for: .event)
        guard calendars.contains(where: { $0.calendarIdentifier == prefs.smartPlanCalendarID }) else {
            Task { @MainActor in
                syncErrors.append(.calendarNotFound)
                // Clear invalid selection
                UserPreferences.shared.smartPlanCalendarID = ""
            }
            return false
        }

        return true
    }

    // MARK: - Calendar Event Management

    private func createCalendarEvents(
        for activities: [SmartPlannerEngine.PlannedActivity],
        date: Date
    ) async -> ([String], Int) {
        let prefs = UserPreferences.shared
        var createdIDs: [String] = []
        var createdCount = 0

        let calendars = eventStore.calendars(for: .event)
        guard let calendar = calendars.first(where: {
            $0.calendarIdentifier == prefs.smartPlanCalendarID
        }) else {
            return ([], 0)
        }

        for activity in activities {
            do {
                let event = EKEvent(eventStore: eventStore)
                event.calendar = calendar
                event.title = activityTitle(for: activity)
                event.startDate = activity.startTime
                event.endDate = activity.slot.end
                event.notes = buildActivityNotes(for: activity)

                // Add 5-minute reminder
                let alarm = EKAlarm(relativeOffset: TimeInterval(-5 * 60))
                event.addAlarm(alarm)

                try eventStore.save(event, span: .thisEvent)

                if let eventID = event.eventIdentifier {
                    createdIDs.append(eventID)
                    createdCount += 1
                }
            } catch {
                await MainActor.run {
                    syncErrors.append(.eventCreationFailed(error.localizedDescription))
                }
            }
        }

        return (createdIDs, createdCount)
    }

    private func deleteExistingEvents(for dateString: String) async -> Int {
        let prefs = UserPreferences.shared
        guard let eventIDs = prefs.smartPlanManagedEventIDs[dateString] else { return 0 }

        var deletedCount = 0

        for eventID in eventIDs {
            if let event = eventStore.event(withIdentifier: eventID) {
                do {
                    try eventStore.remove(event, span: .thisEvent)
                    deletedCount += 1
                } catch {
                    await MainActor.run {
                        syncErrors.append(.eventDeletionFailed(error.localizedDescription))
                    }
                }
            }
        }

        // Clear stored IDs
        var managedIDs = prefs.smartPlanManagedEventIDs
        managedIDs.removeValue(forKey: dateString)
        prefs.smartPlanManagedEventIDs = managedIDs

        return deletedCount
    }

    // MARK: - Event Content Builders

    private func activityTitle(for activity: SmartPlannerEngine.PlannedActivity) -> String {
        switch activity.type {
        case .microWalk: return "Quick Walk"
        case .morningWalk: return "Morning Walk"
        case .lunchWalk: return "Lunch Walk"
        case .eveningWalk: return "Evening Walk"
        case .scheduledWalk: return "Scheduled Walk"
        case .postMeetingWalk: return "Post-Meeting Walk"
        case .gymWorkout: return "Gym Workout"
        }
    }

    private func buildActivityNotes(for activity: SmartPlannerEngine.PlannedActivity) -> String {
        let prefs = UserPreferences.shared
        let motivation = prefs.personalWhy?.motivationalMessage ?? "Time to move!"

        return """
        \(motivation)

        \(activity.reason)

        Estimated steps: ~\(activity.estimatedSteps.formatted())
        Duration: \(activity.duration) minutes
        Priority: \(activity.priority.rawValue.capitalized)

        ---
        Smart-planned by Activslot
        """
    }

    // MARK: - Helpers

    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Trigger on Calendar/Preference Changes

    /// Called when calendar events change to potentially regenerate plan
    func handleCalendarChange() async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled else { return }

        // Regenerate today's plan if we're in active hours
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 8 && hour < 20 {
            await generateAndSync(for: Date())
        }
    }

    /// Called when user preferences change (e.g., preferred walk time)
    func handlePreferenceChange() async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled else { return }

        // Regenerate today's plan
        await generateAndSync(for: Date())
    }

    // MARK: - Cleanup

    /// Clean up old managed event IDs (older than 7 days)
    func cleanupOldManagedEvents() {
        let calendar = Calendar.current
        var managedIDs = UserPreferences.shared.smartPlanManagedEventIDs

        guard let cutoffDate = calendar.date(byAdding: .day, value: -7, to: Date()) else { return }
        let cutoffString = formatDateString(cutoffDate)

        managedIDs = managedIDs.filter { dateString, _ in
            dateString >= cutoffString
        }

        UserPreferences.shared.smartPlanManagedEventIDs = managedIDs
    }
}
