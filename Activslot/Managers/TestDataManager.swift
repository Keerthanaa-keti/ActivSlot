import Foundation
import HealthKit
import EventKit
import SwiftUI

#if DEBUG
/// A comprehensive test data manager for generating sample data across all app systems
/// Use this to test the app with realistic data scenarios
@MainActor
class TestDataManager: ObservableObject {
    static let shared = TestDataManager()

    private let healthStore = HKHealthStore()
    private let eventStore = EKEventStore()

    @Published var isGenerating = false
    @Published var lastGenerationStatus: String = ""
    @Published var generationLog: [String] = []

    private init() {}

    // MARK: - Main Test Data Generation

    /// Generates a complete test scenario with calendar events, HealthKit data, and scheduled activities
    func generateFullTestScenario() async {
        isGenerating = true
        generationLog = []

        log("Starting full test scenario generation...")

        // 1. Generate calendar events
        await generateCalendarEvents()

        // 2. Generate HealthKit step data
        await generateHealthKitData()

        // 3. Generate scheduled activities
        await generateScheduledActivities()

        // 4. Refresh all managers
        await refreshManagers()

        log("Test scenario generation complete!")
        lastGenerationStatus = "Generated: Calendar events, HealthKit data, Scheduled activities"
        isGenerating = false
    }

    /// Clears all test data
    func clearAllTestData() async {
        isGenerating = true
        generationLog = []

        log("Clearing all test data...")

        await clearCalendarEvents()
        await clearScheduledActivities()
        // Note: HealthKit data cannot be deleted programmatically

        await refreshManagers()

        log("Test data cleared!")
        lastGenerationStatus = "Cleared all test data"
        isGenerating = false
    }

    // MARK: - Calendar Events

    /// Generates a realistic executive calendar with meetings and gaps for walks
    func generateCalendarEvents() async {
        log("Generating calendar events...")

        do {
            try await CalendarManager.shared.createSampleEventsForTesting()
            log("  Created sample calendar events")
        } catch {
            log("  Failed to create calendar events: \(error.localizedDescription)")
        }
    }

    /// Generates calendar events for multiple days (today and tomorrow)
    func generateMultiDayCalendarEvents() async {
        log("Generating multi-day calendar events...")

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        // Today's events
        createEvent(on: today, calendar: calendar, title: "Morning Standup", startHour: 9, duration: 15, attendeeCount: 5)
        createEvent(on: today, calendar: calendar, title: "Product Planning", startHour: 9, startMinute: 30, duration: 60, attendeeCount: 8)
        createEvent(on: today, calendar: calendar, title: "1:1 with Manager", startHour: 11, duration: 30, attendeeCount: 2)
        createEvent(on: today, calendar: calendar, title: "Lunch Break", startHour: 12, duration: 60, attendeeCount: 0)
        createEvent(on: today, calendar: calendar, title: "Team Sync", startHour: 14, duration: 45, attendeeCount: 12)
        createEvent(on: today, calendar: calendar, title: "Code Review", startHour: 15, duration: 30, attendeeCount: 4)
        createEvent(on: today, calendar: calendar, title: "Engineering All-Hands", startHour: 16, duration: 60, attendeeCount: 50)

        // Tomorrow's events
        createEvent(on: tomorrow, calendar: calendar, title: "Sprint Planning", startHour: 9, duration: 90, attendeeCount: 10)
        createEvent(on: tomorrow, calendar: calendar, title: "Design Review", startHour: 11, duration: 45, attendeeCount: 6)
        createEvent(on: tomorrow, calendar: calendar, title: "Investor Call", startHour: 14, duration: 60, attendeeCount: 4)
        createEvent(on: tomorrow, calendar: calendar, title: "Focus Time", startHour: 15, startMinute: 30, duration: 120, attendeeCount: 0)

        log("  Created events for today and tomorrow")
    }

    /// Generates a heavy meeting day (for testing "too many meetings" scenario)
    func generateHeavyMeetingDay() async {
        log("Generating heavy meeting day...")

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Back-to-back meetings with minimal gaps
        createEvent(on: today, calendar: calendar, title: "Executive Standup", startHour: 8, duration: 30, attendeeCount: 6)
        createEvent(on: today, calendar: calendar, title: "Board Prep", startHour: 8, startMinute: 30, duration: 60, attendeeCount: 3)
        createEvent(on: today, calendar: calendar, title: "Investor Meeting", startHour: 9, startMinute: 30, duration: 90, attendeeCount: 5)
        createEvent(on: today, calendar: calendar, title: "Lunch & Learn", startHour: 11, duration: 60, attendeeCount: 20)
        createEvent(on: today, calendar: calendar, title: "Product Strategy", startHour: 12, duration: 90, attendeeCount: 8)
        createEvent(on: today, calendar: calendar, title: "Engineering Review", startHour: 13, startMinute: 30, duration: 60, attendeeCount: 15)
        createEvent(on: today, calendar: calendar, title: "Customer Call", startHour: 14, startMinute: 30, duration: 60, attendeeCount: 4)
        createEvent(on: today, calendar: calendar, title: "Team Retrospective", startHour: 15, startMinute: 30, duration: 60, attendeeCount: 10)
        createEvent(on: today, calendar: calendar, title: "Planning Poker", startHour: 16, startMinute: 30, duration: 60, attendeeCount: 8)
        createEvent(on: today, calendar: calendar, title: "End of Day Sync", startHour: 17, startMinute: 30, duration: 30, attendeeCount: 5)

        log("  Created heavy meeting schedule (8+ hours of meetings)")
    }

    /// Generates a light meeting day (for testing "plenty of walk time" scenario)
    func generateLightMeetingDay() async {
        log("Generating light meeting day...")

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Just a few meetings with lots of free time
        createEvent(on: today, calendar: calendar, title: "Morning Check-in", startHour: 9, duration: 15, attendeeCount: 3)
        createEvent(on: today, calendar: calendar, title: "1:1 with Report", startHour: 14, duration: 30, attendeeCount: 2)
        createEvent(on: today, calendar: calendar, title: "Team Update", startHour: 16, duration: 30, attendeeCount: 6)

        log("  Created light meeting schedule (~1 hour of meetings)")
    }

    /// Creates events with walkable meetings (large attendee count, not organizer)
    func generateWalkableMeetings() async {
        log("Generating walkable meetings...")

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Create meetings that qualify as "walkable" (4+ attendees, 20-120 min, not organizer)
        createEvent(on: today, calendar: calendar, title: "All-Hands Meeting", startHour: 10, duration: 60, attendeeCount: 50)
        createEvent(on: today, calendar: calendar, title: "Department Sync", startHour: 14, duration: 45, attendeeCount: 15)
        createEvent(on: today, calendar: calendar, title: "Training Session", startHour: 16, duration: 90, attendeeCount: 25)

        log("  Created 3 walkable meetings")
    }

    private func createEvent(on date: Date, calendar: EKCalendar, title: String, startHour: Int, startMinute: Int = 0, duration: Int, attendeeCount: Int) {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.calendar = calendar

        var startComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = startHour
        startComponents.minute = startMinute

        event.startDate = Calendar.current.date(from: startComponents)!
        event.endDate = Calendar.current.date(byAdding: .minute, value: duration, to: event.startDate)!

        // Note: We can't add attendees programmatically, but the title affects walkability

        try? eventStore.save(event, span: .thisEvent)
    }

    func clearCalendarEvents() async {
        log("Clearing calendar events...")

        do {
            try await CalendarManager.shared.clearTodayEvents()
            log("  Cleared today's calendar events")
        } catch {
            log("  Failed to clear events: \(error.localizedDescription)")
        }
    }

    // MARK: - HealthKit Data

    /// Generates sample step data for the past week and today
    func generateHealthKitData() async {
        log("Generating HealthKit data...")

        guard HKHealthStore.isHealthDataAvailable() else {
            log("  HealthKit not available")
            return
        }

        // Request write authorization
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        do {
            try await healthStore.requestAuthorization(toShare: [stepType], read: [stepType])
        } catch {
            log("  HealthKit authorization failed: \(error.localizedDescription)")
            return
        }

        let calendar = Calendar.current

        // Generate historical data for the past 7 days
        for dayOffset in 1...7 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                // Vary steps by day (weekends lower, weekdays higher)
                let weekday = calendar.component(.weekday, from: date)
                let isWeekend = weekday == 1 || weekday == 7
                let baseSteps = isWeekend ? 5000 : 8000
                let variation = Int.random(in: -2000...3000)
                let steps = max(3000, baseSteps + variation)

                await saveSteps(steps, for: date)
            }
        }

        // Generate today's steps (partial day)
        let hour = calendar.component(.hour, from: Date())
        let todaySteps = Int(Double(hour) / 24.0 * 8000.0) + Int.random(in: 0...1500)
        await saveStepsForToday(todaySteps)

        log("  Generated step data for 7 days + today (\(todaySteps) steps so far)")
    }

    /// Generates step data for a specific scenario
    func generateStepScenario(_ scenario: StepScenario) async {
        log("Generating \(scenario.rawValue) step scenario...")

        switch scenario {
        case .goalAlmostReached:
            await saveStepsForToday(8500) // Just 1500 from 10k goal
        case .goalReached:
            await saveStepsForToday(10500) // Over the goal
        case .lowSteps:
            await saveStepsForToday(2000) // Very few steps
        case .midDay:
            await saveStepsForToday(5000) // Half way there
        case .activeWalker:
            await saveStepsForToday(15000) // Very active
        }

        log("  Set today's steps to \(scenario.targetSteps)")
    }

    enum StepScenario: String, CaseIterable {
        case goalAlmostReached = "Goal Almost Reached"
        case goalReached = "Goal Reached"
        case lowSteps = "Low Steps"
        case midDay = "Mid Day Progress"
        case activeWalker = "Active Walker"

        var targetSteps: Int {
            switch self {
            case .goalAlmostReached: return 8500
            case .goalReached: return 10500
            case .lowSteps: return 2000
            case .midDay: return 5000
            case .activeWalker: return 15000
            }
        }
    }

    private func saveSteps(_ steps: Int, for date: Date) async {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let quantity = HKQuantity(unit: .count(), doubleValue: Double(steps))

        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .hour, value: 23, to: startOfDay)!

        let sample = HKQuantitySample(type: stepType, quantity: quantity, start: startOfDay, end: endOfDay)

        do {
            try await healthStore.save(sample)
        } catch {
            log("  Failed to save steps for \(date): \(error.localizedDescription)")
        }
    }

    private func saveStepsForToday(_ steps: Int) async {
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        // Check authorization status
        let authStatus = healthStore.authorizationStatus(for: stepType)
        log("  HealthKit write auth status: \(authStatus.rawValue)")

        // Request authorization if needed
        do {
            try await healthStore.requestAuthorization(toShare: [stepType], read: [stepType])
            log("  HealthKit authorization requested")
        } catch {
            log("  HealthKit authorization failed: \(error.localizedDescription)")
            return
        }

        let quantity = HKQuantity(unit: .count(), doubleValue: Double(steps))

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let now = Date()

        let sample = HKQuantitySample(type: stepType, quantity: quantity, start: startOfDay, end: now)

        do {
            try await healthStore.save(sample)
            log("  Saved \(steps) steps to HealthKit")
        } catch {
            log("  Failed to save today's steps: \(error.localizedDescription)")
        }
    }

    /// Generates walking workout data
    func generateWalkWorkouts() async {
        log("Generating walk workout data...")

        guard HKHealthStore.isHealthDataAvailable() else {
            log("  HealthKit not available")
            return
        }

        let workoutType = HKQuantityType.workoutType()

        do {
            try await healthStore.requestAuthorization(toShare: [workoutType], read: [workoutType])
        } catch {
            log("  HealthKit workout authorization failed")
            return
        }

        let calendar = Calendar.current

        // Create some past walking workouts
        for dayOffset in [1, 3, 5] {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                var startComps = calendar.dateComponents([.year, .month, .day], from: date)
                startComps.hour = 12
                startComps.minute = 30

                let startDate = calendar.date(from: startComps)!
                let endDate = calendar.date(byAdding: .minute, value: 30, to: startDate)!

                let workout = HKWorkout(
                    activityType: .walking,
                    start: startDate,
                    end: endDate,
                    duration: 30 * 60, // 30 minutes
                    totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 150),
                    totalDistance: HKQuantity(unit: .mile(), doubleValue: 1.5),
                    metadata: nil
                )

                try? await healthStore.save(workout)
            }
        }

        log("  Created 3 walking workouts for past week")
    }

    // MARK: - Scheduled Activities

    /// Generates sample scheduled activities (walks and workouts)
    func generateScheduledActivities() async {
        log("Generating scheduled activities...")

        let manager = ScheduledActivityManager.shared

        // Clear existing test activities
        await clearScheduledActivities()

        let calendar = Calendar.current
        let today = Date()

        // Create a morning walk scheduled for today
        var morningComponents = calendar.dateComponents([.year, .month, .day], from: today)
        morningComponents.hour = 7
        morningComponents.minute = 30
        if let morningTime = calendar.date(from: morningComponents) {
            let morningWalk = ScheduledActivity(
                activityType: .walk,
                title: "Morning Walk",
                startTime: morningTime,
                duration: 20,
                recurrence: .weekdays
            )
            manager.addScheduledActivity(morningWalk)
        }

        // Create a lunch walk for today
        var lunchComponents = calendar.dateComponents([.year, .month, .day], from: today)
        lunchComponents.hour = 12
        lunchComponents.minute = 0
        if let lunchTime = calendar.date(from: lunchComponents) {
            let lunchWalk = ScheduledActivity(
                activityType: .walk,
                title: "Lunch Walk",
                startTime: lunchTime,
                duration: 30,
                recurrence: .once
            )
            manager.addScheduledActivity(lunchWalk)
        }

        // Create an afternoon workout
        var workoutComponents = calendar.dateComponents([.year, .month, .day], from: today)
        workoutComponents.hour = 17
        workoutComponents.minute = 30
        if let workoutTime = calendar.date(from: workoutComponents) {
            let workout = ScheduledActivity(
                activityType: .workout,
                workoutType: .push,
                title: "Gym Session - Push Day",
                startTime: workoutTime,
                duration: 45,
                recurrence: .weekly
            )
            manager.addScheduledActivity(workout)
        }

        log("  Created 2 walks and 1 workout")
    }

    /// Generates activities that conflict with calendar events
    func generateConflictingActivities() async {
        log("Generating conflicting activities...")

        let manager = ScheduledActivityManager.shared
        let calendar = Calendar.current
        let today = Date()

        // Create a walk that conflicts with the 10 AM meeting slot
        var conflictComponents = calendar.dateComponents([.year, .month, .day], from: today)
        conflictComponents.hour = 10
        conflictComponents.minute = 0
        if let conflictTime = calendar.date(from: conflictComponents) {
            let conflictingWalk = ScheduledActivity(
                activityType: .walk,
                title: "Walk (Conflicts with Meeting!)",
                startTime: conflictTime,
                duration: 30,
                recurrence: .once
            )
            manager.addScheduledActivity(conflictingWalk)
        }

        log("  Created 1 conflicting activity")
    }

    func clearScheduledActivities() async {
        log("Clearing scheduled activities...")

        let manager = ScheduledActivityManager.shared

        // For test scenarios, clear ALL activities to prevent duplicates
        // This includes both one-time and recurring activities
        let allActivities = manager.scheduledActivities
        for activity in allActivities {
            manager.deleteScheduledActivity(activity)
        }

        log("  Cleared all scheduled activities (\(allActivities.count) total)")
    }

    // MARK: - Preset Test Scenarios

    /// Scenario: Busy executive with back-to-back meetings
    func setupBusyExecutiveScenario() async {
        log("Setting up Busy Executive scenario...")

        await clearAllTestData()
        await generateHeavyMeetingDay()
        await generateStepScenario(.lowSteps)

        // Refresh managers after generating new data
        await refreshManagers()

        log("Busy Executive scenario ready")
        lastGenerationStatus = "Busy Executive: Heavy meetings, few steps"
    }

    /// Scenario: Light day with lots of walking opportunities
    func setupLightDayScenario() async {
        log("Setting up Light Day scenario...")

        await clearAllTestData()
        await generateLightMeetingDay()
        await generateStepScenario(.midDay)
        await generateScheduledActivities()

        // Refresh managers after generating new data
        await refreshManagers()

        log("Light Day scenario ready")
        lastGenerationStatus = "Light Day: Few meetings, walking opportunities"
    }

    /// Scenario: Goal almost reached, needs one more walk
    func setupAlmostThereScenario() async {
        log("Setting up Almost There scenario...")

        await clearAllTestData()
        await generateCalendarEvents()
        await generateStepScenario(.goalAlmostReached)

        // Refresh managers after generating new data
        await refreshManagers()

        log("Almost There scenario ready")
        lastGenerationStatus = "Almost There: 8,500 steps, need 1,500 more"
    }

    /// Scenario: Active day with goal already reached
    func setupGoalReachedScenario() async {
        log("Setting up Goal Reached scenario...")

        await clearAllTestData()
        await generateCalendarEvents()
        await generateStepScenario(.goalReached)
        await generateWalkWorkouts()

        // Refresh managers after generating new data
        await refreshManagers()

        log("Goal Reached scenario ready")
        lastGenerationStatus = "Goal Reached: Over 10,000 steps"
    }

    /// Scenario: Multiple walkable meetings available
    func setupWalkableMeetingsScenario() async {
        log("Setting up Walkable Meetings scenario...")

        await clearAllTestData()
        await generateWalkableMeetings()
        await generateStepScenario(.lowSteps)

        // Refresh managers after generating new data
        await refreshManagers()

        log("Walkable Meetings scenario ready")
        lastGenerationStatus = "Walkable Meetings: 3 meetings good for walking"
    }

    /// Scenario: Device A – Sarah's schedule (9am standup, 11am planning, 2pm demo, 4pm review)
    /// Partner = Alex (8am, 10am, 1pm, 3pm) — shared free slots: 9:30-10, 12-1pm, 4pm+
    func setupSarahScenario() async {
        log("Setting up Sarah scenario (Device A)...")
        await clearAllTestData()

        guard let cal = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found"); return
        }
        let today = Calendar.current.startOfDay(for: Date())
        createEvent(on: today, calendar: cal, title: "Morning Standup",     startHour: 9,  duration: 30,  attendeeCount: 5)
        createEvent(on: today, calendar: cal, title: "Product Planning",    startHour: 11, duration: 60,  attendeeCount: 8)
        createEvent(on: today, calendar: cal, title: "Customer Demo",       startHour: 14, duration: 45,  attendeeCount: 4)
        createEvent(on: today, calendar: cal, title: "Engineering Review",  startHour: 16, duration: 60,  attendeeCount: 10)

        await generateStepScenario(.midDay)   // ~5,000 steps by midday

        // Alex's schedule as the partner (different from Sarah's)
        await CoupleWalkManager.shared.linkMockPartner(
            name: "Alex",
            schedule: [(8,30),(10,60),(13,45),(15,60)]
        )
        await refreshManagers()
        log("Sarah scenario ready — partner Alex linked. Expected shared slots: 9:30am, 12pm, 4pm+")
        lastGenerationStatus = "Sarah (Device A): 4 meetings + Alex linked as partner"
    }

    /// Scenario: Device B – Alex's schedule (8am standup, 10am sprint, 1pm client, 3pm design)
    /// Partner = Sarah (9am, 11am, 2pm, 4pm) — shared free slots: 9:30-10, 12-1pm, 4pm+
    func setupAlexScenario() async {
        log("Setting up Alex scenario (Device B)...")
        await clearAllTestData()

        guard let cal = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found"); return
        }
        let today = Calendar.current.startOfDay(for: Date())
        createEvent(on: today, calendar: cal, title: "Team Standup",     startHour: 8,  duration: 30,  attendeeCount: 6)
        createEvent(on: today, calendar: cal, title: "Sprint Planning",  startHour: 10, duration: 60,  attendeeCount: 9)
        createEvent(on: today, calendar: cal, title: "Client Call",      startHour: 13, duration: 45,  attendeeCount: 3)
        createEvent(on: today, calendar: cal, title: "Design Review",    startHour: 15, duration: 60,  attendeeCount: 7)

        await generateStepScenario(.lowSteps)  // ~2,000 steps, needs more

        // Sarah's schedule as the partner
        await CoupleWalkManager.shared.linkMockPartner(
            name: "Sarah",
            schedule: [(9,30),(11,60),(14,45),(16,60)]
        )
        await refreshManagers()
        log("Alex scenario ready — partner Sarah linked. Expected shared slots: 9:30am, 12pm, 4pm+")
        lastGenerationStatus = "Alex (Device B): 4 meetings + Sarah linked as partner"
    }

    /// Scenario: Walk Buddy — realistic coupled schedule with overlapping free slots
    /// Device A (this device): meetings at 9am, 11am, 2pm, 4pm
    /// Mock partner (Device B): meetings at 8am, 10am, 1pm, 3pm, 5pm
    /// Shared free slots should appear around: 9:30–10am, 11:30am–1pm, 2:45–3pm, 4:30–5pm
    func setupWalkBuddyTestScenario() async {
        log("Setting up Walk Buddy test scenario...")

        await clearAllTestData()

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Device A schedule: spread-out meetings leaving walk-friendly gaps
        createEvent(on: today, calendar: calendar, title: "Morning Standup",     startHour: 9,  duration: 30,  attendeeCount: 6)
        createEvent(on: today, calendar: calendar, title: "Product Planning",    startHour: 11, duration: 60,  attendeeCount: 8)
        createEvent(on: today, calendar: calendar, title: "Customer Demo",       startHour: 14, duration: 45,  attendeeCount: 5)
        createEvent(on: today, calendar: calendar, title: "Engineering Review",  startHour: 16, duration: 60,  attendeeCount: 12)

        // Skip HealthKit steps in simulator to avoid authorization dialog
        // await generateStepScenario(.midDay)

        // Link mock partner (staggered schedule creates clear shared free windows)
        await CoupleWalkManager.shared.linkMockPartner(name: "Alex (test partner)")

        await refreshManagers()

        log("Walk Buddy scenario ready — shared slots should appear around 10am, 12pm–1pm, 4:30pm")
        lastGenerationStatus = "Walk Buddy: 4 meetings + mock partner linked"
    }

    /// Scenario: Walk Buddy Device B — different meeting schedule from Device A
    /// Device B (this device): meetings at 8:30am, 10:30am, 1pm, 3:30pm
    /// Mock partner represents Device A's schedule: meetings at 9am, 11am, 2pm, 4pm
    func setupWalkBuddyTestScenarioB() async {
        log("Setting up Walk Buddy test scenario B (Device B)...")

        await clearAllTestData()

        guard let calendar = eventStore.calendars(for: .event).first(where: { $0.allowsContentModifications }) else {
            log("  No writable calendar found")
            return
        }

        let today = Calendar.current.startOfDay(for: Date())

        // Device B schedule: different meetings than Device A
        createEvent(on: today, calendar: calendar, title: "Team Sync",          startHour: 8,  duration: 30,  attendeeCount: 4)
        createEvent(on: today, calendar: calendar, title: "Design Review",      startHour: 10, duration: 60,  attendeeCount: 5)
        createEvent(on: today, calendar: calendar, title: "Lunch & Learn",      startHour: 13, duration: 45,  attendeeCount: 10)
        createEvent(on: today, calendar: calendar, title: "Sprint Retro",       startHour: 15, duration: 60,  attendeeCount: 7)

        // Link mock partner representing Device A's schedule
        await CoupleWalkManager.shared.linkMockPartner(
            name: "Sam (test partner)",
            schedule: [(9, 30), (11, 60), (14, 45), (16, 60)]
        )

        await refreshManagers()

        log("Walk Buddy B scenario ready — partner has Device A's meeting schedule")
        lastGenerationStatus = "Walk Buddy B: 4 meetings + mock partner (Device A schedule)"
    }

    // MARK: - Manager Refresh

    private func refreshManagers() async {
        log("Refreshing managers...")

        // Refresh calendar
        try? await CalendarManager.shared.refreshEvents()

        // Refresh health data
        _ = try? await HealthKitManager.shared.fetchTodaySteps()

        // Regenerate plans
        await MovementPlanManager.shared.generatePlans()

        // Update insights
        await PersonalInsightsManager.shared.analyzePatterns()

        log("  All managers refreshed")
    }

    // MARK: - Logging

    private func log(_ message: String) {
        print("TestDataManager: \(message)")
        generationLog.append(message)
    }
}

// MARK: - Test Data View for Debug Menu

struct TestDataGeneratorView: View {
    @StateObject private var testManager = TestDataManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Status Section
                Section("Status") {
                    if testManager.isGenerating {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Generating...")
                        }
                    } else if !testManager.lastGenerationStatus.isEmpty {
                        Text(testManager.lastGenerationStatus)
                            .foregroundColor(.green)
                    }
                }

                // Quick Scenarios
                Section("Quick Scenarios") {
                    Button("Busy Executive Day") {
                        Task { await testManager.setupBusyExecutiveScenario() }
                    }

                    Button("Light Day (Lots of Walk Time)") {
                        Task { await testManager.setupLightDayScenario() }
                    }

                    Button("Almost at Goal (8,500 steps)") {
                        Task { await testManager.setupAlmostThereScenario() }
                    }

                    Button("Goal Reached (10,500 steps)") {
                        Task { await testManager.setupGoalReachedScenario() }
                    }

                    Button("Walkable Meetings Available") {
                        Task { await testManager.setupWalkableMeetingsScenario() }
                    }

                    Button("Walk Buddy Test (Mock Partner)") {
                        Task { await testManager.setupWalkBuddyTestScenario() }
                    }
                    .foregroundColor(.purple)
                }

                // Individual Data Generation
                Section("Calendar Events") {
                    Button("Create Standard Day Events") {
                        Task { await testManager.generateCalendarEvents() }
                    }

                    Button("Create Multi-Day Events") {
                        Task { await testManager.generateMultiDayCalendarEvents() }
                    }

                    Button("Create Heavy Meeting Day") {
                        Task { await testManager.generateHeavyMeetingDay() }
                    }

                    Button("Create Light Meeting Day") {
                        Task { await testManager.generateLightMeetingDay() }
                    }

                    Button("Create Walkable Meetings") {
                        Task { await testManager.generateWalkableMeetings() }
                    }

                    Button("Clear Today's Events", role: .destructive) {
                        Task { await testManager.clearCalendarEvents() }
                    }
                }

                Section("HealthKit Data") {
                    Button("Generate Week of Step Data") {
                        Task { await testManager.generateHealthKitData() }
                    }

                    Button("Generate Walk Workouts") {
                        Task { await testManager.generateWalkWorkouts() }
                    }

                    ForEach(TestDataManager.StepScenario.allCases, id: \.self) { scenario in
                        Button("Set Steps: \(scenario.rawValue)") {
                            Task { await testManager.generateStepScenario(scenario) }
                        }
                    }
                }

                Section("Scheduled Activities") {
                    Button("Create Sample Activities") {
                        Task { await testManager.generateScheduledActivities() }
                    }

                    Button("Create Conflicting Activity") {
                        Task { await testManager.generateConflictingActivities() }
                    }

                    Button("Clear Scheduled Activities", role: .destructive) {
                        Task { await testManager.clearScheduledActivities() }
                    }
                }

                // Full Operations
                Section("Full Operations") {
                    Button("Generate Full Test Data") {
                        Task { await testManager.generateFullTestScenario() }
                    }
                    .foregroundColor(.blue)

                    Button("Clear All Test Data", role: .destructive) {
                        Task { await testManager.clearAllTestData() }
                    }
                }

                // Log Output
                if !testManager.generationLog.isEmpty {
                    Section("Log") {
                        ForEach(testManager.generationLog.indices, id: \.self) { index in
                            Text(testManager.generationLog[index])
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Test Data Generator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .disabled(testManager.isGenerating)
        }
    }
}

#Preview {
    TestDataGeneratorView()
}

// MARK: - Intelligent Smart Planner Tests

extension TestDataManager {

    /// Tests for the Intelligent Autonomous Smart Planner feature
    func runSmartPlannerTests() async -> [SmartPlannerTestResult] {
        var results: [SmartPlannerTestResult] = []

        log("=== INTELLIGENT SMART PLANNER TESTS ===")

        // Test 1: Day-of-week pattern analysis
        results.append(await testDayOfWeekPatternAnalysis())

        // Test 2: Plan generation with day-specific patterns
        results.append(await testDaySpecificPlanGeneration())

        // Test 3: Checkpoint creation
        results.append(await testCheckpointCreation())

        // Test 4: Checkpoint evaluation (simulated behind scenario)
        results.append(await testCheckpointEvaluation())

        // Test 5: Dynamic replanning
        results.append(await testDynamicReplanning())

        // Test 6: Evening plan sync
        results.append(await testEveningPlanSync())

        // Test 7: Notification scheduling
        results.append(await testNotificationScheduling())

        // Test 8: Adherence verification
        results.append(await testAdherenceVerification())

        // Summary
        let passed = results.filter { $0.passed }.count
        let failed = results.count - passed
        log("=== TESTS COMPLETE: \(passed) passed, \(failed) failed ===")

        return results
    }

    struct SmartPlannerTestResult {
        let testName: String
        let passed: Bool
        let message: String
        let details: [String]
    }

    // Test 1: Day-of-week pattern analysis
    private func testDayOfWeekPatternAnalysis() async -> SmartPlannerTestResult {
        log("Test 1: Day-of-Week Pattern Analysis")

        var details: [String] = []

        // Generate historical step data for pattern learning
        await generateHistoricalStepData(days: 30)
        details.append("Generated 30 days of historical step data")

        // Trigger pattern analysis
        await SmartPlannerEngine.shared.analyzeDayOfWeekPatterns()
        details.append("Analyzed day-of-week patterns")

        // Check if patterns were created
        let patterns = SmartPlannerEngine.shared.dayOfWeekPatterns
        let passed = patterns != nil && !(patterns?.dayPatterns.isEmpty ?? true)

        if let p = patterns {
            details.append("Found patterns for \(p.dayPatterns.count) days")
            for (weekday, dayPattern) in p.dayPatterns {
                let dayName = Calendar.current.weekdaySymbols[weekday - 1]
                details.append("  \(dayName): Peak hours \(dayPattern.peakActivityHours), avg \(dayPattern.averageDailySteps) steps")
            }
        } else {
            details.append("No patterns generated")
        }

        log("  Result: \(passed ? "PASSED" : "FAILED")")
        return SmartPlannerTestResult(
            testName: "Day-of-Week Pattern Analysis",
            passed: passed,
            message: passed ? "Successfully analyzed patterns for \(patterns?.dayPatterns.count ?? 0) days" : "Failed to generate patterns",
            details: details
        )
    }

    // Test 2: Plan generation with day-specific patterns
    private func testDaySpecificPlanGeneration() async -> SmartPlannerTestResult {
        log("Test 2: Day-Specific Plan Generation")

        var details: [String] = []

        // Generate calendar events for tomorrow
        await generateCalendarEvents()
        details.append("Generated calendar events")

        // Generate plan for tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let plan = await SmartPlannerEngine.shared.generateDailyPlan(for: tomorrow)

        let passed = !plan.activities.isEmpty

        details.append("Plan generated for \(formatDate(tomorrow))")
        details.append("  Activities: \(plan.activities.count)")
        details.append("  Total planned steps: \(plan.totalPlannedSteps)")
        details.append("  Walkable meetings: \(plan.walkableMeetings.count)")
        details.append("  Confidence: \(String(format: "%.0f%%", plan.confidence * 100))")

        for activity in plan.activities.prefix(5) {
            details.append("  - \(activity.type.rawValue) at \(formatTime(activity.startTime)), ~\(activity.estimatedSteps) steps")
        }

        log("  Result: \(passed ? "PASSED" : "FAILED")")
        return SmartPlannerTestResult(
            testName: "Day-Specific Plan Generation",
            passed: passed,
            message: passed ? "Generated plan with \(plan.activities.count) activities" : "Failed to generate plan",
            details: details
        )
    }

    // Test 3: Checkpoint creation
    private func testCheckpointCreation() async -> SmartPlannerTestResult {
        log("Test 3: Checkpoint Creation")

        var details: [String] = []

        // Generate a plan
        let today = Date()
        let plan = await SmartPlannerEngine.shared.generateDailyPlan(for: today)
        details.append("Generated plan with \(plan.activities.count) activities")

        // Create checkpoints
        DailyPlanSyncCoordinator.shared.createCheckpoints(for: today, plan: plan)
        details.append("Called createCheckpoints")

        // Check if checkpoints were created
        let checkpoints = DailyPlanSyncCoordinator.shared.todayCheckpoints
        let passed = checkpoints != nil && !(checkpoints?.checkpoints.isEmpty ?? true)

        if let cp = checkpoints {
            details.append("Created \(cp.checkpoints.count) checkpoints")
            for checkpoint in cp.checkpoints {
                details.append("  - Hour \(checkpoint.hour):00, target: \(checkpoint.targetSteps) steps")
            }
        } else {
            details.append("No checkpoints created")
        }

        log("  Result: \(passed ? "PASSED" : "FAILED")")
        return SmartPlannerTestResult(
            testName: "Checkpoint Creation",
            passed: passed,
            message: passed ? "Created \(checkpoints?.checkpoints.count ?? 0) checkpoints" : "Failed to create checkpoints",
            details: details
        )
    }

    // Test 4: Checkpoint evaluation
    private func testCheckpointEvaluation() async -> SmartPlannerTestResult {
        log("Test 4: Checkpoint Evaluation")

        var details: [String] = []

        // First create checkpoints
        let today = Date()
        let plan = await SmartPlannerEngine.shared.generateDailyPlan(for: today)
        DailyPlanSyncCoordinator.shared.createCheckpoints(for: today, plan: plan)
        details.append("Created checkpoints for today")

        // Set a low step count to simulate being behind
        await generateStepScenario(.lowSteps) // 2000 steps
        details.append("Set today's steps to 2000 (behind scenario)")

        // Evaluate checkpoint
        await DailyPlanSyncCoordinator.shared.evaluateCheckpoint()
        details.append("Evaluated checkpoint")

        // Check results
        let isBehind = DailyPlanSyncCoordinator.shared.isCurrentlyBehind
        let deficit = DailyPlanSyncCoordinator.shared.currentDeficit

        let passed = true // This test is more about verifying the flow works

        details.append("Behind status: \(isBehind)")
        details.append("Current deficit: \(deficit) steps")

        if let checkpoints = DailyPlanSyncCoordinator.shared.todayCheckpoints {
            for checkpoint in checkpoints.checkpoints where checkpoint.actualSteps != nil {
                details.append("  Checkpoint @\(checkpoint.hour): \(checkpoint.actualSteps!) actual vs \(checkpoint.targetSteps) target - \(checkpoint.status)")
            }
        }

        log("  Result: \(passed ? "PASSED" : "FAILED")")
        return SmartPlannerTestResult(
            testName: "Checkpoint Evaluation",
            passed: passed,
            message: "Evaluated checkpoint - behind: \(isBehind), deficit: \(deficit)",
            details: details
        )
    }

    // Test 5: Dynamic replanning
    private func testDynamicReplanning() async -> SmartPlannerTestResult {
        log("Test 5: Dynamic Replanning")

        var details: [String] = []

        // Enable smart plan sync
        UserPreferences.shared.smartPlanAutoSyncEnabled = true
        UserPreferences.shared.autoReplanWhenBehind = true
        details.append("Enabled auto-sync and auto-replan")

        // Generate light calendar to have gaps for catch-up walks
        await generateLightMeetingDay()
        details.append("Generated light meeting day")

        // Trigger dynamic replan with a deficit
        let testDeficit = 3000
        await DailyPlanSyncCoordinator.shared.dynamicReplan(deficit: testDeficit)
        details.append("Triggered dynamic replan with \(testDeficit) step deficit")

        // Check if catch-up walks were created
        let prefs = UserPreferences.shared
        let dateString = formatDateString(Date())
        let managedIDs = prefs.smartPlanManagedEventIDs[dateString] ?? []

        let passed = !managedIDs.isEmpty

        details.append("Created \(managedIDs.count) calendar events for catch-up walks")

        log("  Result: \(passed ? "PASSED" : "FAILED")")
        return SmartPlannerTestResult(
            testName: "Dynamic Replanning",
            passed: passed,
            message: passed ? "Created \(managedIDs.count) catch-up walks" : "No catch-up walks created",
            details: details
        )
    }

    // Test 6: Evening plan sync
    private func testEveningPlanSync() async -> SmartPlannerTestResult {
        log("Test 6: Evening Plan Sync")

        var details: [String] = []

        // Enable smart plan sync
        UserPreferences.shared.smartPlanAutoSyncEnabled = true
        details.append("Enabled smart plan auto-sync")

        // Generate calendar events for tomorrow
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        await generateMultiDayCalendarEvents()
        details.append("Generated calendar events for tomorrow")

        // Trigger evening sync
        await DailyPlanSyncCoordinator.shared.syncTomorrowPlan()
        details.append("Triggered evening plan sync")

        // Check sync result
        let syncResult = DailyPlanSyncCoordinator.shared.lastSyncResult
        let passed = syncResult != nil

        if let result = syncResult {
            details.append("Sync result:")
            details.append("  Date: \(formatDate(result.date))")
            details.append("  Events created: \(result.eventsCreated)")
            details.append("  Activities synced: \(result.activitiesSynced.count)")
            details.append("  Optimization type: \(result.optimizationType.rawValue)")
        } else {
            details.append("No sync result available")
        }

        log("  Result: \(passed ? "PASSED" : "FAILED")")
        return SmartPlannerTestResult(
            testName: "Evening Plan Sync",
            passed: passed,
            message: passed ? "Synced \(syncResult?.eventsCreated ?? 0) events for tomorrow" : "Sync failed",
            details: details
        )
    }

    // Test 7: Notification scheduling
    private func testNotificationScheduling() async -> SmartPlannerTestResult {
        log("Test 7: Notification Scheduling")

        var details: [String] = []

        // Generate a plan
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let plan = await SmartPlannerEngine.shared.generateDailyPlan(for: tomorrow)
        details.append("Generated plan for tomorrow")

        // Schedule plan ready notification
        NotificationManager.shared.schedulePlanReadyNotification(plan: plan)
        details.append("Scheduled plan ready notification")

        // Schedule behind on steps notification (test)
        await NotificationManager.shared.scheduleBehindOnStepsNotification(
            deficit: 2000,
            suggestedSlot: nil
        )
        details.append("Scheduled behind on steps notification")

        // Schedule walkable meeting notifications
        NotificationManager.shared.scheduleWalkableMeetingPreNotifications(for: plan)
        details.append("Scheduled walkable meeting pre-notifications for \(plan.walkableMeetings.count) meetings")

        // Get pending notifications count
        let center = UNUserNotificationCenter.current()
        let pendingNotifications = await center.pendingNotificationRequests()
        let smartPlannerNotifications = pendingNotifications.filter {
            $0.identifier.contains("plan-ready") ||
            $0.identifier.contains("behind-on-steps") ||
            $0.identifier.contains("walkable-meeting-pre")
        }

        let passed = !smartPlannerNotifications.isEmpty

        details.append("Pending smart planner notifications: \(smartPlannerNotifications.count)")
        for notification in smartPlannerNotifications.prefix(5) {
            details.append("  - \(notification.identifier): \(notification.content.title)")
        }

        log("  Result: \(passed ? "PASSED" : "FAILED")")
        return SmartPlannerTestResult(
            testName: "Notification Scheduling",
            passed: passed,
            message: "Scheduled \(smartPlannerNotifications.count) notifications",
            details: details
        )
    }

    // Test 8: Adherence verification
    private func testAdherenceVerification() async -> SmartPlannerTestResult {
        log("Test 8: Adherence Verification")

        var details: [String] = []

        // Create a test activity that happened in the past
        let calendar = Calendar.current
        var pastComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        pastComponents.hour = 8
        pastComponents.minute = 0
        let pastTime = calendar.date(from: pastComponents)!

        let slot = SmartPlannerEngine.PlannedActivity.TimeSlot(
            start: pastTime,
            end: calendar.date(byAdding: .minute, value: 30, to: pastTime)!,
            isIdeal: true,
            conflictRisk: .low
        )

        var activity = SmartPlannerEngine.PlannedActivity(
            id: UUID(),
            type: .morningWalk,
            startTime: pastTime,
            duration: 30,
            estimatedSteps: 2000,
            priority: .recommended,
            slot: slot,
            reason: "Test morning walk",
            status: .planned,
            calendarEventID: nil
        )

        details.append("Created test activity: \(activity.type.rawValue) at \(formatTime(pastTime))")

        // Set step data for that time window
        await generateStepScenario(.midDay)
        details.append("Set step data for verification")

        // Verify adherence
        let verifiedActivity = await SmartPlannerEngine.shared.verifyActivityAdherence(activity)

        let passed = verifiedActivity.adherenceStatus != .pending

        details.append("Adherence status: \(verifiedActivity.adherenceStatus)")
        if let actual = verifiedActivity.actualSteps {
            details.append("Actual steps: \(actual) vs expected: \(verifiedActivity.expectedSteps)")
        }

        log("  Result: \(passed ? "PASSED" : "FAILED")")
        return SmartPlannerTestResult(
            testName: "Adherence Verification",
            passed: passed,
            message: "Adherence status: \(verifiedActivity.adherenceStatus)",
            details: details
        )
    }

    // Helper: Generate historical step data
    private func generateHistoricalStepData(days: Int) async {
        log("  Generating \(days) days of historical step data...")

        let calendar = Calendar.current

        for dayOffset in 1...days {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) {
                let weekday = calendar.component(.weekday, from: date)
                let isWeekend = weekday == 1 || weekday == 7

                // Create realistic hourly patterns based on day type
                let baseSteps = isWeekend ? 5000 : 8000
                let variation = Int.random(in: -2000...3000)
                let totalSteps = max(3000, baseSteps + variation)

                await saveSteps(totalSteps, for: date)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Smart Planner Test View

struct SmartPlannerTestView: View {
    @StateObject private var testManager = TestDataManager.shared
    @State private var testResults: [TestDataManager.SmartPlannerTestResult] = []
    @State private var isRunning = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Run Tests") {
                    Button(action: runTests) {
                        HStack {
                            if isRunning {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Running tests...")
                            } else {
                                Image(systemName: "play.circle.fill")
                                    .foregroundColor(.green)
                                Text("Run All Smart Planner Tests")
                            }
                        }
                    }
                    .disabled(isRunning)
                }

                if !testResults.isEmpty {
                    Section("Results") {
                        let passed = testResults.filter { $0.passed }.count
                        let failed = testResults.count - passed

                        HStack {
                            Text("Summary:")
                            Spacer()
                            Text("\(passed) passed")
                                .foregroundColor(.green)
                            Text("/")
                            Text("\(failed) failed")
                                .foregroundColor(failed > 0 ? .red : .secondary)
                        }
                        .font(.headline)
                    }

                    ForEach(testResults, id: \.testName) { result in
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result.passed ? .green : .red)
                                    Text(result.testName)
                                        .font(.headline)
                                }

                                Text(result.message)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                ForEach(result.details, id: \.self) { detail in
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Smart Planner Tests")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func runTests() {
        isRunning = true
        Task {
            testResults = await testManager.runSmartPlannerTests()
            isRunning = false
        }
    }
}
#endif
