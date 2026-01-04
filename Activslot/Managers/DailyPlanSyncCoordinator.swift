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

    // Checkpoint system for monitoring daily progress
    @Published var todayCheckpoints: SmartPlannerEngine.DayCheckpoints?
    @Published var isCurrentlyBehind: Bool = false
    @Published var currentDeficit: Int = 0

    // Tracking for continuous optimization
    private var lastOptimizationTime: Date?
    private var lastKnownStepCount: Int = 0
    private let optimizationCooldown: TimeInterval = 30 * 60 // 30 minutes between auto-optimizations
    private let significantStepChange: Int = 1000 // Re-optimize if steps change by this much
    private var lastCheckpointEvaluationTime: Date?

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

    // MARK: - Checkpoint System

    /// Create checkpoints when a plan is generated for tracking progress throughout the day
    func createCheckpoints(for date: Date, plan: SmartPlannerEngine.DailyMovementPlan) {
        let calendar = Calendar.current
        let prefs = UserPreferences.shared

        // Only create checkpoints for today or tomorrow
        guard calendar.isDateInToday(date) || calendar.isDateInTomorrow(date) else { return }

        var checkpoints: [SmartPlannerEngine.DayCheckpoints.Checkpoint] = []
        let checkpointHours = SmartPlannerEngine.DayCheckpoints.defaultCheckpointHours

        // Calculate cumulative expected steps at each checkpoint
        var cumulativeExpected = 0

        for hour in checkpointHours {
            // Skip checkpoint hours that are before wake time or after sleep time
            guard hour >= prefs.wakeTime.hour && hour < prefs.sleepTime.hour else { continue }

            // Sum up expected steps from activities before this checkpoint
            let activitiesBeforeCheckpoint = plan.activities.filter { activity in
                let activityHour = calendar.component(.hour, from: activity.startTime)
                return activityHour < hour
            }

            cumulativeExpected = activitiesBeforeCheckpoint.reduce(0) { $0 + $1.estimatedSteps }

            // Also add a proportional amount of passive steps based on time of day
            let hoursAwake = hour - prefs.wakeTime.hour
            let passiveStepsPerHour = 300 // Rough estimate of passive steps
            cumulativeExpected += hoursAwake * passiveStepsPerHour

            let checkpoint = SmartPlannerEngine.DayCheckpoints.Checkpoint(
                hour: hour,
                targetSteps: cumulativeExpected
            )
            checkpoints.append(checkpoint)
        }

        let dayCheckpoints = SmartPlannerEngine.DayCheckpoints(
            date: date,
            checkpoints: checkpoints,
            lastEvaluated: nil
        )

        // Store and publish
        DispatchQueue.main.async {
            self.todayCheckpoints = dayCheckpoints
        }

        // Persist to UserDefaults
        if let encoded = try? JSONEncoder().encode(dayCheckpoints) {
            UserDefaults.standard.set(encoded, forKey: "dailyCheckpoints_\(formatDateString(date))")
        }

        #if DEBUG
        print("DailyPlanSyncCoordinator: Created \(checkpoints.count) checkpoints for \(formatDateString(date))")
        #endif
    }

    /// Load checkpoints for today if they exist
    func loadTodayCheckpoints() {
        let dateString = formatDateString(Date())
        guard let data = UserDefaults.standard.data(forKey: "dailyCheckpoints_\(dateString)"),
              let checkpoints = try? JSONDecoder().decode(SmartPlannerEngine.DayCheckpoints.self, from: data) else {
            return
        }

        DispatchQueue.main.async {
            self.todayCheckpoints = checkpoints
        }
    }

    /// Evaluate the current checkpoint - called periodically or at checkpoint times
    func evaluateCheckpoint() async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled else { return }

        // Load checkpoints if not already loaded
        if todayCheckpoints == nil {
            loadTodayCheckpoints()
        }

        guard var checkpoints = todayCheckpoints else { return }

        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)

        // Find the current or most recent checkpoint to evaluate
        guard let checkpointIndex = checkpoints.checkpoints.firstIndex(where: { checkpoint in
            checkpoint.hour <= currentHour && checkpoint.status == .pending
        }) else {
            return // No checkpoint to evaluate
        }

        // Avoid re-evaluating too frequently
        if let lastEval = lastCheckpointEvaluationTime,
           now.timeIntervalSince(lastEval) < 15 * 60 { // 15 min cooldown
            return
        }

        // Fetch current step count
        let actualSteps: Int
        do {
            actualSteps = try await healthKitManager.fetchTodaySteps()
        } catch {
            #if DEBUG
            print("DailyPlanSyncCoordinator: Failed to fetch steps for checkpoint: \(error)")
            #endif
            return
        }

        // Update checkpoint
        var checkpoint = checkpoints.checkpoints[checkpointIndex]
        checkpoint.actualSteps = actualSteps
        checkpoint.evaluatedAt = now

        // Determine status
        let deficit = checkpoint.targetSteps - actualSteps
        let deficitPercentage = Double(deficit) / Double(checkpoint.targetSteps)

        if deficit <= 0 {
            checkpoint.status = .ahead
        } else if deficitPercentage < 0.15 { // Within 15% is on track
            checkpoint.status = .onTrack
        } else {
            checkpoint.status = .behind
        }

        checkpoints.checkpoints[checkpointIndex] = checkpoint
        checkpoints.lastEvaluated = now

        // Update published state
        await MainActor.run {
            self.todayCheckpoints = checkpoints
            self.isCurrentlyBehind = checkpoint.status == .behind
            self.currentDeficit = max(0, deficit)
        }

        lastCheckpointEvaluationTime = now

        // Persist updated checkpoints
        if let encoded = try? JSONEncoder().encode(checkpoints) {
            UserDefaults.standard.set(encoded, forKey: "dailyCheckpoints_\(formatDateString(now))")
        }

        #if DEBUG
        print("DailyPlanSyncCoordinator: Checkpoint @\(checkpoint.hour):00 - Target: \(checkpoint.targetSteps), Actual: \(actualSteps), Status: \(checkpoint.status)")
        #endif

        // Handle behind schedule
        if checkpoint.status == .behind && !checkpoint.notificationSent {
            await handleBehindSchedule(deficit: deficit, checkpointIndex: checkpointIndex)
        }
    }

    /// Handle when user is behind on steps
    /// ATOMIC HABITS: We don't nag users with multiple "behind" notifications
    /// The streak-at-risk notification in the evening is sufficient
    /// This just marks the checkpoint and optionally replans, but NO notification spam
    private func handleBehindSchedule(deficit: Int, checkpointIndex: Int) async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled else { return }

        // Mark notification as sent (even though we're not sending one)
        // This prevents repeated processing
        if var checkpoints = todayCheckpoints {
            checkpoints.checkpoints[checkpointIndex].notificationSent = true
            await MainActor.run {
                self.todayCheckpoints = checkpoints
            }

            // Persist
            if let encoded = try? JSONEncoder().encode(checkpoints) {
                UserDefaults.standard.set(encoded, forKey: "dailyCheckpoints_\(formatDateString(Date()))")
            }
        }

        // ATOMIC HABITS: Instead of nagging with notifications, just silently replan
        // The evening streak-at-risk notification is enough
        // If auto-replan is enabled, adjust the plan to help user catch up
        if prefs.autoReplanWhenBehind {
            await dynamicReplan(deficit: deficit)
        }

        #if DEBUG
        print("DailyPlanSyncCoordinator: Behind by \(deficit) steps - adjusted plan (no notification, Atomic Habits principle)")
        #endif
    }

    /// Find next available slot in calendar for a catch-up walk
    private func findNextAvailableSlot(minimumMinutes: Int) async -> SmartPlannerEngine.PlannedActivity.TimeSlot? {
        let calendar = Calendar.current
        let now = Date()
        let prefs = UserPreferences.shared

        // Get today's events
        let todayEvents = (try? await calendarManager.fetchEvents(for: now)) ?? []

        // Look for gaps starting from now until sleep time
        guard let sleepTime = calendar.date(
            bySettingHour: prefs.sleepTime.hour,
            minute: prefs.sleepTime.minute,
            second: 0,
            of: now
        ) else { return nil }

        var searchStart = now

        // Round up to next 15-minute interval
        let minutes = calendar.component(.minute, from: searchStart)
        let roundedMinutes = ((minutes / 15) + 1) * 15
        if let rounded = calendar.date(bySetting: .minute, value: roundedMinutes % 60, of: searchStart) {
            searchStart = rounded
            if roundedMinutes >= 60 {
                searchStart = calendar.date(byAdding: .hour, value: 1, to: searchStart) ?? searchStart
            }
        }

        // Find first gap that's at least minimumMinutes long
        while searchStart < sleepTime {
            guard let slotEnd = calendar.date(byAdding: .minute, value: minimumMinutes, to: searchStart) else {
                break
            }

            // Check if this slot conflicts with any events
            let hasConflict = todayEvents.contains { event in
                return searchStart < event.endDate && slotEnd > event.startDate
            }

            if !hasConflict && slotEnd <= sleepTime {
                return SmartPlannerEngine.PlannedActivity.TimeSlot(
                    start: searchStart,
                    end: slotEnd,
                    isIdeal: false,
                    conflictRisk: .low
                )
            }

            // Move to end of conflicting event or next interval
            if let conflictingEvent = todayEvents.first(where: { event in
                return searchStart < event.endDate && slotEnd > event.startDate
            }) {
                searchStart = conflictingEvent.endDate
                // Round up to next 15-minute interval
                let mins = calendar.component(.minute, from: searchStart)
                let roundedMins = ((mins / 15) + 1) * 15
                if let rounded = calendar.date(bySetting: .minute, value: roundedMins % 60, of: searchStart) {
                    searchStart = rounded
                    if roundedMins >= 60 {
                        searchStart = calendar.date(byAdding: .hour, value: 1, to: searchStart) ?? searchStart
                    }
                }
            } else {
                searchStart = calendar.date(byAdding: .minute, value: 15, to: searchStart) ?? sleepTime
            }
        }

        return nil
    }

    /// Dynamically replan the rest of the day when behind on steps
    func dynamicReplan(deficit: Int) async {
        let prefs = UserPreferences.shared
        guard prefs.smartPlanAutoSyncEnabled else { return }

        #if DEBUG
        print("DailyPlanSyncCoordinator: Dynamic replan triggered - deficit: \(deficit) steps")
        #endif

        // Calculate additional walks needed
        let stepsPerWalk = 1500 // Average steps per 15-min walk
        let additionalWalksNeeded = max(1, (deficit + stepsPerWalk - 1) / stepsPerWalk)

        // Find available slots for catch-up walks
        var catchUpSlots: [SmartPlannerEngine.PlannedActivity.TimeSlot] = []
        var searchStart = Date()

        for _ in 0..<additionalWalksNeeded {
            if let slot = await findNextAvailableSlotAfter(searchStart, minimumMinutes: 15) {
                catchUpSlots.append(slot)
                searchStart = slot.end
            } else {
                break
            }
        }

        guard !catchUpSlots.isEmpty else {
            #if DEBUG
            print("DailyPlanSyncCoordinator: No available slots for catch-up walks")
            #endif
            return
        }

        // Create catch-up activities
        var catchUpActivities: [SmartPlannerEngine.PlannedActivity] = []
        let stepsPerSlot = deficit / catchUpSlots.count

        for slot in catchUpSlots {
            let duration = Int(slot.end.timeIntervalSince(slot.start) / 60)
            let activity = SmartPlannerEngine.PlannedActivity(
                id: UUID(),
                type: .microWalk,
                startTime: slot.start,
                duration: duration,
                estimatedSteps: stepsPerSlot,
                priority: .critical,
                slot: slot,
                reason: "Catch-up walk to get back on track",
                status: .planned,
                calendarEventID: nil
            )
            catchUpActivities.append(activity)
        }

        // Sync catch-up walks to calendar
        let (createdIDs, createdCount) = await createCalendarEvents(for: catchUpActivities, date: Date())

        // Store managed event IDs
        let dateString = formatDateString(Date())
        var managedIDs = prefs.smartPlanManagedEventIDs
        var existingIDs = managedIDs[dateString] ?? []
        existingIDs.append(contentsOf: createdIDs)
        managedIDs[dateString] = existingIDs
        prefs.smartPlanManagedEventIDs = managedIDs

        #if DEBUG
        print("DailyPlanSyncCoordinator: Created \(createdCount) catch-up walks")
        #endif
    }

    /// Find next available slot after a given time
    private func findNextAvailableSlotAfter(_ startTime: Date, minimumMinutes: Int) async -> SmartPlannerEngine.PlannedActivity.TimeSlot? {
        let calendar = Calendar.current
        let prefs = UserPreferences.shared

        guard let sleepTime = calendar.date(
            bySettingHour: prefs.sleepTime.hour,
            minute: prefs.sleepTime.minute,
            second: 0,
            of: startTime
        ) else { return nil }

        // Add 15-minute buffer
        guard var searchStart = calendar.date(byAdding: .minute, value: 15, to: startTime) else {
            return nil
        }

        // Round up to next 15-minute interval
        let minutes = calendar.component(.minute, from: searchStart)
        let roundedMinutes = ((minutes / 15) + 1) * 15
        if let rounded = calendar.date(bySetting: .minute, value: roundedMinutes % 60, of: searchStart) {
            searchStart = rounded
            if roundedMinutes >= 60 {
                searchStart = calendar.date(byAdding: .hour, value: 1, to: searchStart) ?? searchStart
            }
        }

        let todayEvents = (try? await calendarManager.fetchEvents(for: startTime)) ?? []

        while searchStart < sleepTime {
            guard let slotEnd = calendar.date(byAdding: .minute, value: minimumMinutes, to: searchStart) else {
                break
            }

            let hasConflict = todayEvents.contains { event in
                return searchStart < event.endDate && slotEnd > event.startDate
            }

            if !hasConflict && slotEnd <= sleepTime {
                return SmartPlannerEngine.PlannedActivity.TimeSlot(
                    start: searchStart,
                    end: slotEnd,
                    isIdeal: false,
                    conflictRisk: .low
                )
            }

            searchStart = calendar.date(byAdding: .minute, value: 15, to: searchStart) ?? sleepTime
        }

        return nil
    }

    /// Check and evaluate checkpoints - call this when app becomes active
    func checkAndEvaluateCheckpoints() async {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)

        // Check if we're at or past a checkpoint time
        let checkpointHours = SmartPlannerEngine.DayCheckpoints.defaultCheckpointHours

        if checkpointHours.contains(where: { abs($0 - currentHour) <= 1 }) {
            await evaluateCheckpoint()
        }
    }
}
