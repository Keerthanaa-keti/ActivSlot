import Foundation
import EventKit
import HealthKit

// MARK: - Smart Planner Engine
/// Enterprise-grade intelligent movement planner that:
/// 1. Learns from your HealthKit patterns (when you actually walk, how much)
/// 2. Analyzes calendar for walkable meetings and free slots
/// 3. Calculates optimal plan to hit step goal with minimal disruption
/// 4. Tracks plan adherence and adapts recommendations over time
/// 5. Works backwards from 10K goal to create a realistic daily plan

class SmartPlannerEngine: ObservableObject {
    static let shared = SmartPlannerEngine()

    // Dependencies
    private let healthKitManager = HealthKitManager.shared
    private let calendarManager = CalendarManager.shared
    private let eventStore = EKEventStore()

    // Published state
    @Published var currentDayPlan: DailyMovementPlan?
    @Published var isAnalyzing = false
    @Published var userPatterns: UserActivityPatterns?
    @Published var planAdherence: PlanAdherence?
    @Published var dayOfWeekPatterns: DayOfWeekPatterns?

    // UserDefaults keys
    private let patternsKey = "smartPlanner_userPatterns"
    private let adherenceKey = "smartPlanner_planAdherence"
    private let lastAnalysisKey = "smartPlanner_lastAnalysisDate"
    private let dayOfWeekPatternsKey = "smartPlanner_dayOfWeekPatterns"

    private init() {
        loadCachedData()
    }

    // MARK: - Core Data Models

    /// A complete daily movement plan
    struct DailyMovementPlan: Codable, Identifiable {
        let id: UUID
        let date: Date
        let targetSteps: Int
        let estimatedCurrentSteps: Int
        let stepsNeeded: Int
        let activities: [PlannedActivity]
        let walkableMeetings: [WalkableMeeting]
        let confidence: Double // 0-1, how confident we are this plan is achievable
        let reasoning: String // Why we made these recommendations
        let generatedAt: Date

        var totalPlannedSteps: Int {
            activities.reduce(0) { $0 + $1.estimatedSteps } +
            walkableMeetings.filter { $0.isRecommended }.reduce(0) { $0 + $1.estimatedSteps }
        }

        var remainingGap: Int {
            max(0, stepsNeeded - totalPlannedSteps)
        }

        var isOnTrack: Bool {
            remainingGap < 500 // Within 500 steps is considered on track
        }
    }

    /// A planned activity (walk, workout, etc.)
    struct PlannedActivity: Codable, Identifiable {
        let id: UUID
        let type: ActivityType
        let startTime: Date
        let duration: Int // minutes
        let estimatedSteps: Int
        let priority: Priority
        let slot: TimeSlot
        let reason: String // Why this time was chosen
        var status: ActivityStatus
        var calendarEventID: String?

        // Adherence tracking fields
        var expectedSteps: Int { estimatedSteps }
        var actualSteps: Int?
        var verifiedAt: Date?
        var adherenceStatus: AdherenceStatus = .pending

        enum ActivityType: String, Codable {
            case scheduledWalk = "scheduled_walk"
            case microWalk = "micro_walk"      // 5-10 min between meetings
            case postMeetingWalk = "post_meeting"
            case morningWalk = "morning_walk"
            case eveningWalk = "evening_walk"
            case lunchWalk = "lunch_walk"
            case gymWorkout = "gym_workout"
        }

        enum Priority: String, Codable {
            case critical = "critical"    // Must do to hit goal
            case recommended = "recommended"
            case optional = "optional"
        }

        enum ActivityStatus: String, Codable {
            case planned = "planned"
            case inProgress = "in_progress"
            case completed = "completed"
            case skipped = "skipped"
            case rescheduled = "rescheduled"
        }

        struct TimeSlot: Codable {
            let start: Date
            let end: Date
            let isIdeal: Bool // Matches user's preferred times
            let conflictRisk: ConflictRisk

            enum ConflictRisk: String, Codable {
                case low = "low"
                case medium = "medium"
                case high = "high"
            }
        }
    }

    /// A meeting that could be taken as a walking meeting
    struct WalkableMeeting: Codable, Identifiable {
        let id: UUID
        let calendarEventID: String
        let title: String
        let startTime: Date
        let duration: Int
        let attendeeCount: Int
        let isOneOnOne: Bool
        let estimatedSteps: Int
        let walkabilityScore: Double // 0-1
        let isRecommended: Bool
        let reason: String
    }

    // MARK: - User Pattern Learning

    /// Learned patterns from user's HealthKit history
    struct UserActivityPatterns: Codable {
        var averageDailySteps: Int
        var weekdayAverage: Int
        var weekendAverage: Int
        var bestPerformingDays: [Int] // 1-7, Sunday=1
        var peakActivityHours: [Int] // Hours when user is most active
        var typicalWalkDuration: Int // Average walk length in minutes
        var stepsPerMinuteWalking: Int // User's walking pace
        var goalAchievementRate: Double // % of days hitting goal
        var consistentWalkTimes: [TimeWindow] // Times user regularly walks
        var lastUpdated: Date

        struct TimeWindow: Codable {
            let hour: Int
            let frequency: Double // 0-1, how often they walk at this time
        }

        /// Default patterns for new users
        static var defaults: UserActivityPatterns {
            UserActivityPatterns(
                averageDailySteps: 6000,
                weekdayAverage: 5500,
                weekendAverage: 7000,
                bestPerformingDays: [7, 1], // Sat, Sun
                peakActivityHours: [8, 12, 17], // Morning, lunch, evening
                typicalWalkDuration: 20,
                stepsPerMinuteWalking: 100, // ~100 steps/min is average
                goalAchievementRate: 0.3,
                consistentWalkTimes: [
                    TimeWindow(hour: 8, frequency: 0.4),
                    TimeWindow(hour: 12, frequency: 0.5),
                    TimeWindow(hour: 18, frequency: 0.3)
                ],
                lastUpdated: Date()
            )
        }
    }

    /// Tracks how well user follows the plan
    struct PlanAdherence: Codable {
        var totalPlansGenerated: Int
        var activitiesCompleted: Int
        var activitiesSkipped: Int
        var averageCompletionRate: Double
        var bestTimeSlots: [String: Double] // "morning" -> 0.8 completion rate
        var preferredActivityDuration: Int
        var reschedulingFrequency: Double
        var lastUpdated: Date

        static var initial: PlanAdherence {
            PlanAdherence(
                totalPlansGenerated: 0,
                activitiesCompleted: 0,
                activitiesSkipped: 0,
                averageCompletionRate: 0.5,
                bestTimeSlots: [:],
                preferredActivityDuration: 20,
                reschedulingFrequency: 0.2,
                lastUpdated: Date()
            )
        }
    }

    // MARK: - Day-of-Week Pattern Learning

    /// Per-day activity patterns - learns "Tuesday behavior" vs "Monday behavior"
    /// This enables highly personalized planning: "On Tuesdays, you walk at 7am and 12pm"
    struct DayOfWeekPatterns: Codable {
        /// Dictionary keyed by weekday (1=Sunday, 2=Monday, ..., 7=Saturday)
        var dayPatterns: [Int: DayPattern]
        var lastUpdated: Date

        struct DayPattern: Codable {
            let weekday: Int
            var peakActivityHours: [Int]              // Hours when user is most active on THIS day
            var hourlyStepAverages: [Int: Int]        // hour -> average steps on this day
            var totalDaysSampled: Int                 // How many of this weekday we've analyzed
            var averageDailySteps: Int                // Average total steps on this day
            var adherenceRate: Double                 // Plan completion rate for this day (0-1)
            var bestSlotSuccessRates: [Int: Double]   // hour -> success rate for planned activities

            /// Get recommended walk times for this day based on historical patterns
            var recommendedWalkTimes: [HourlyWalkPattern] {
                // Find hours with significant activity (>500 steps average)
                hourlyStepAverages
                    .filter { $0.value > 500 }
                    .sorted { $0.value > $1.value }
                    .prefix(5)
                    .map { HourlyWalkPattern(hour: $0.key, averageSteps: $0.value, frequency: 1.0, averageDuration: max(10, $0.value / 100)) }
            }

            static func empty(weekday: Int) -> DayPattern {
                DayPattern(
                    weekday: weekday,
                    peakActivityHours: [8, 12, 17],
                    hourlyStepAverages: [:],
                    totalDaysSampled: 0,
                    averageDailySteps: 0,
                    adherenceRate: 0.5,
                    bestSlotSuccessRates: [:]
                )
            }
        }

        struct HourlyWalkPattern: Codable {
            let hour: Int
            let averageSteps: Int
            let frequency: Double       // 0-1, how often they walk at this hour
            let averageDuration: Int    // estimated minutes based on steps
        }

        /// Initialize with empty patterns for all days
        static var empty: DayOfWeekPatterns {
            var patterns: [Int: DayPattern] = [:]
            for weekday in 1...7 {
                patterns[weekday] = .empty(weekday: weekday)
            }
            return DayOfWeekPatterns(dayPatterns: patterns, lastUpdated: Date())
        }

        /// Get pattern for a specific date's weekday
        func pattern(for date: Date) -> DayPattern? {
            let weekday = Calendar.current.component(.weekday, from: date)
            return dayPatterns[weekday]
        }
    }

    // MARK: - Adherence Tracking Enhancements

    /// Status of adherence verification for a planned activity
    enum AdherenceStatus: String, Codable {
        case pending = "pending"       // Not yet verified
        case verified = "verified"     // Completed as planned (>80% of expected steps)
        case partial = "partial"       // Did some but not all (40-80%)
        case missed = "missed"         // Did not complete (<40%)
    }

    // MARK: - Day Checkpoint System

    /// Progress checkpoints throughout the day to monitor if user is on track
    struct DayCheckpoints: Codable {
        let date: Date
        var checkpoints: [Checkpoint]
        var lastEvaluated: Date?

        struct Checkpoint: Codable, Identifiable {
            let id: UUID
            let hour: Int                 // Hour of day (10, 13, 16, 19)
            let targetSteps: Int          // Expected steps by this time
            var actualSteps: Int?
            var evaluatedAt: Date?
            var status: CheckpointStatus
            var notificationSent: Bool

            enum CheckpointStatus: String, Codable {
                case pending = "pending"
                case onTrack = "on_track"   // Within 20% of target
                case behind = "behind"      // More than 20% below target
                case ahead = "ahead"        // More than 20% above target
            }

            init(hour: Int, targetSteps: Int) {
                self.id = UUID()
                self.hour = hour
                self.targetSteps = targetSteps
                self.actualSteps = nil
                self.evaluatedAt = nil
                self.status = .pending
                self.notificationSent = false
            }
        }

        /// Default checkpoint hours: 10am, 1pm, 4pm, 7pm
        static let defaultCheckpointHours = [10, 13, 16, 19]

        /// Create checkpoints for a day with step targets
        static func create(for date: Date, goalSteps: Int) -> DayCheckpoints {
            // Progressive targets: 25%, 50%, 75%, 90% of goal
            let percentages: [Double] = [0.25, 0.50, 0.75, 0.90]
            let checkpoints = zip(defaultCheckpointHours, percentages).map { hour, pct in
                Checkpoint(hour: hour, targetSteps: Int(Double(goalSteps) * pct))
            }
            return DayCheckpoints(date: date, checkpoints: checkpoints, lastEvaluated: nil)
        }
    }

    // MARK: - Main Planning Logic

    /// Generate a smart daily plan for the given date
    /// Uses day-of-week specific patterns when available (e.g., "On Tuesdays, you walk at 7am and 12pm")
    func generateDailyPlan(for date: Date) async -> DailyMovementPlan {
        await MainActor.run { isAnalyzing = true }
        defer { Task { await MainActor.run { isAnalyzing = false } } }

        let prefs = UserPreferences.shared
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(date)

        // 1. Get current step count (if today)
        let currentSteps = isToday ? (try? await healthKitManager.fetchTodaySteps()) ?? 0 : 0

        // 2. Calculate steps needed
        let targetSteps = prefs.dailyStepGoal
        let stepsNeeded = max(0, targetSteps - currentSteps)

        // 3. Fetch calendar events
        let events = (try? await calendarManager.fetchEvents(for: date)) ?? []

        // 4. Analyze for walkable meetings
        let walkableMeetings = analyzeWalkableMeetings(events: events)

        // 5. Find available time slots
        let availableSlots = findAvailableSlots(
            for: date,
            events: events,
            currentTime: isToday ? Date() : calendar.startOfDay(for: date)
        )

        // 6. Get day-specific patterns if available
        // This enables personalized planning: "On Tuesdays, you typically walk at 7am and 12pm"
        let dayPattern = getPatternForDate(date)
        let daySpecificPeakHours = dayPattern?.peakActivityHours
        let daySpecificSuccessRates = dayPattern?.bestSlotSuccessRates

        #if DEBUG
        if let pattern = dayPattern {
            let dayName = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
            print("SmartPlannerEngine: Using \(dayName)-specific patterns - peaks at \(pattern.peakActivityHours)")
        }
        print("SmartPlannerEngine: Steps needed: \(stepsNeeded), Available slots: \(availableSlots.count), Walkable meetings: \(walkableMeetings.filter { $0.isRecommended }.count)")
        #endif

        // 7. Create optimal activity plan using day-specific patterns
        let activities = createOptimalPlan(
            stepsNeeded: stepsNeeded,
            availableSlots: availableSlots,
            walkableMeetings: walkableMeetings,
            patterns: userPatterns ?? .defaults,
            adherence: planAdherence ?? .initial,
            prefs: prefs,
            daySpecificPeakHours: daySpecificPeakHours,
            daySpecificSuccessRates: daySpecificSuccessRates
        )

        // 7. Calculate confidence and reasoning
        let (confidence, reasoning) = calculateConfidenceAndReasoning(
            stepsNeeded: stepsNeeded,
            activities: activities,
            walkableMeetings: walkableMeetings,
            patterns: userPatterns ?? .defaults
        )

        let plan = DailyMovementPlan(
            id: UUID(),
            date: date,
            targetSteps: targetSteps,
            estimatedCurrentSteps: currentSteps,
            stepsNeeded: stepsNeeded,
            activities: activities,
            walkableMeetings: walkableMeetings,
            confidence: confidence,
            reasoning: reasoning,
            generatedAt: Date()
        )

        await MainActor.run {
            currentDayPlan = plan
        }

        return plan
    }

    // MARK: - Walkable Meeting Analysis

    private func analyzeWalkableMeetings(events: [CalendarEvent]) -> [WalkableMeeting] {
        events.compactMap { event -> WalkableMeeting? in
            guard event.isRealMeeting else { return nil }

            let duration = Int(event.endDate.timeIntervalSince(event.startDate) / 60)
            let attendeeCount = event.attendeeCount
            let isOneOnOne = attendeeCount <= 2

            // Calculate walkability score
            var walkabilityScore = 0.0

            // One-on-one meetings are more walkable
            if isOneOnOne { walkabilityScore += 0.4 }
            else if attendeeCount <= 3 { walkabilityScore += 0.2 }

            // 30-60 minute meetings are ideal
            if duration >= 30 && duration <= 60 { walkabilityScore += 0.3 }
            else if duration >= 20 && duration <= 90 { walkabilityScore += 0.2 }

            // Check if title suggests walkable
            let title = event.title.lowercased()
            let walkableKeywords = ["1:1", "one on one", "sync", "catch up", "check in", "chat", "coffee"]
            if walkableKeywords.contains(where: { title.contains($0) }) {
                walkabilityScore += 0.3
            }

            // Non-walkable indicators
            let nonWalkableKeywords = ["presentation", "demo", "workshop", "training", "all hands", "standup", "review"]
            if nonWalkableKeywords.contains(where: { title.contains($0) }) {
                walkabilityScore = max(0, walkabilityScore - 0.5)
            }

            let isRecommended = walkabilityScore >= 0.5 && isOneOnOne
            let estimatedSteps = isRecommended ? Int(Double(duration) * 100) : 0 // ~100 steps/min walking

            var reason = ""
            if isRecommended {
                reason = isOneOnOne ? "Perfect for a walking 1:1" : "Could be a walking meeting"
            } else if !isOneOnOne {
                reason = "Too many attendees for walking"
            } else {
                reason = "Meeting type not ideal for walking"
            }

            return WalkableMeeting(
                id: UUID(),
                calendarEventID: event.id,
                title: event.title,
                startTime: event.startDate,
                duration: duration,
                attendeeCount: attendeeCount,
                isOneOnOne: isOneOnOne,
                estimatedSteps: estimatedSteps,
                walkabilityScore: walkabilityScore,
                isRecommended: isRecommended,
                reason: reason
            )
        }
    }

    // MARK: - Available Slot Analysis

    private func findAvailableSlots(
        for date: Date,
        events: [CalendarEvent],
        currentTime: Date
    ) -> [AvailableSlot] {
        let prefs = UserPreferences.shared
        let calendar = Calendar.current

        // Build busy intervals - only include real meetings (excludes all-day, OOO, and long meetings)
        var busyIntervals: [(start: Date, end: Date)] = []
        for event in events where event.isRealMeeting {
            busyIntervals.append((start: event.startDate, end: event.endDate))
        }
        busyIntervals.sort { $0.start < $1.start }

        // Define day boundaries
        var startComponents = calendar.dateComponents([.year, .month, .day], from: date)
        startComponents.hour = prefs.wakeTime.hour + 1
        let dayStart = max(calendar.date(from: startComponents) ?? date, currentTime)

        var endComponents = calendar.dateComponents([.year, .month, .day], from: date)
        endComponents.hour = min(prefs.sleepTime.hour - 1, 21)
        let dayEnd = calendar.date(from: endComponents) ?? date

        guard dayStart < dayEnd else { return [] }

        // Find gaps
        var slots: [AvailableSlot] = []
        var cursor = dayStart

        for interval in busyIntervals {
            if interval.start > cursor {
                let gapDuration = Int(interval.start.timeIntervalSince(cursor) / 60)
                if gapDuration >= 5 { // Minimum 5 minutes
                    let slotType = categorizeSlot(start: cursor, duration: gapDuration, prefs: prefs)
                    slots.append(AvailableSlot(
                        start: cursor,
                        end: interval.start,
                        duration: gapDuration,
                        type: slotType,
                        isDuringMeal: prefs.isDuringMeal(cursor),
                        isPreferredTime: isPreferredTime(cursor, prefs: prefs)
                    ))
                }
            }
            cursor = max(cursor, interval.end)
        }

        // Final gap until end of day
        if cursor < dayEnd {
            let gapDuration = Int(dayEnd.timeIntervalSince(cursor) / 60)
            if gapDuration >= 5 {
                let slotType = categorizeSlot(start: cursor, duration: gapDuration, prefs: prefs)
                slots.append(AvailableSlot(
                    start: cursor,
                    end: dayEnd,
                    duration: gapDuration,
                    type: slotType,
                    isDuringMeal: prefs.isDuringMeal(cursor),
                    isPreferredTime: isPreferredTime(cursor, prefs: prefs)
                ))
            }
        }

        #if DEBUG
        print("SmartPlannerEngine: Found \(slots.count) available slots")
        for slot in slots.prefix(5) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            print("  - \(formatter.string(from: slot.start)) to \(formatter.string(from: slot.end)): \(slot.duration) min, meal: \(slot.isDuringMeal)")
        }
        #endif

        return slots
    }

    struct AvailableSlot {
        let start: Date
        let end: Date
        let duration: Int
        let type: SlotType
        let isDuringMeal: Bool
        let isPreferredTime: Bool

        enum SlotType {
            case microBreak      // 5-10 min
            case shortWalk       // 11-20 min
            case standardWalk    // 21-40 min
            case extendedTime    // 40+ min
        }
    }

    private func categorizeSlot(start: Date, duration: Int, prefs: UserPreferences) -> AvailableSlot.SlotType {
        if duration <= 10 { return .microBreak }
        if duration <= 20 { return .shortWalk }
        if duration <= 40 { return .standardWalk }
        return .extendedTime
    }

    private func isPreferredTime(_ date: Date, prefs: UserPreferences) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)

        switch prefs.preferredWalkTime {
        case .morning: return hour >= 6 && hour < 11
        case .afternoon: return hour >= 11 && hour < 17
        case .evening: return hour >= 17 && hour < 21
        case .noPreference: return true
        }
    }

    /// Check if a time slot strongly conflicts with user's preference
    /// Used to heavily penalize or exclude slots outside preference window
    private func conflictsWithPreference(_ date: Date, prefs: UserPreferences) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)

        switch prefs.preferredWalkTime {
        case .morning: return hour >= 17 // Morning preference = don't want evening
        case .evening: return hour < 14  // Evening preference = don't want morning
        case .afternoon: return hour < 9 || hour >= 20 // Afternoon = avoid early morning and late evening
        case .noPreference: return false
        }
    }

    /// Check if it's a weekend day (for adjusting wake time buffer)
    private func isWeekend(_ date: Date) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
    }

    // MARK: - Optimal Plan Creation

    private func createOptimalPlan(
        stepsNeeded: Int,
        availableSlots: [AvailableSlot],
        walkableMeetings: [WalkableMeeting],
        patterns: UserActivityPatterns,
        adherence: PlanAdherence,
        prefs: UserPreferences,
        daySpecificPeakHours: [Int]? = nil,
        daySpecificSuccessRates: [Int: Double]? = nil
    ) -> [PlannedActivity] {

        guard stepsNeeded > 0 else { return [] }

        var activities: [PlannedActivity] = []
        var remainingSteps = stepsNeeded

        // Calculate steps from walkable meetings - but only credit 30% since users often
        // don't actually walk during all recommended meetings
        // This ensures we still schedule backup walks for reliability
        let walkingMeetingSteps = walkableMeetings
            .filter { $0.isRecommended }
            .reduce(0) { $0 + $1.estimatedSteps }
        let creditedMeetingSteps = Int(Double(walkingMeetingSteps) * 0.30)
        remainingSteps -= creditedMeetingSteps

        // Always schedule at least one walk even if walkable meetings could cover goal
        // This ensures the user has explicit walk times blocked
        let minimumWalksToSchedule = remainingSteps <= 0 ? 1 : 0
        if remainingSteps <= 0 && minimumWalksToSchedule > 0 {
            remainingSteps = 2000 // Schedule at least one ~20min walk
        }

        #if DEBUG
        print("SmartPlannerEngine: createOptimalPlan - stepsNeeded: \(stepsNeeded), walkingMeetingSteps: \(walkingMeetingSteps), creditedMeetingSteps: \(creditedMeetingSteps), remainingSteps: \(remainingSteps)")
        print("SmartPlannerEngine: availableSlots: \(availableSlots.count), non-meal slots: \(availableSlots.filter { !$0.isDuringMeal }.count)")
        #endif

        // Use day-specific peak hours if available, otherwise fall back to general patterns
        // This is key for personalized planning: "On Tuesdays you walk at 7am and 12pm"
        let effectivePeakHours = daySpecificPeakHours ?? patterns.peakActivityHours

        // Strategy: Prioritize non-meal slots, but use meal slots as fallback
        let nonMealSlots = availableSlots.filter { !$0.isDuringMeal }
        let slotsToUse = nonMealSlots.isEmpty ? availableSlots : nonMealSlots

        #if DEBUG
        print("SmartPlannerEngine: Using \(slotsToUse.count) slots (\(nonMealSlots.isEmpty ? "including meal slots as fallback" : "non-meal only"))")
        #endif

        // Strategy: Prioritize slots based on user EXPLICIT preferences first,
        // then day-specific patterns, then general patterns
        // Key insight: User's stated preference (e.g., "evening") should be DECISIVE
        let targetDate = availableSlots.first?.start ?? Date()
        let isWeekendDay = isWeekend(targetDate)

        let scoredSlots = slotsToUse
            .map { slot -> (slot: AvailableSlot, score: Double) in
                var score = 0.0
                let hour = Calendar.current.component(.hour, from: slot.start)

                // CRITICAL: User's explicit preference is DECISIVE
                // If user says "evening", morning slots get HEAVILY penalized
                if conflictsWithPreference(slot.start, prefs: prefs) {
                    score -= 1.0  // Major penalty - push to bottom of list
                }

                // Strong bonus for matching user's preferred time
                if slot.isPreferredTime { score += 0.6 }  // Increased from 0.2

                // Day-specific patterns (when user actually walks on this day of week)
                if effectivePeakHours.contains(hour) { score += 0.25 }

                // Consider day-specific hour success rates if available
                if let successRates = daySpecificSuccessRates,
                   let hourSuccessRate = successRates[hour] {
                    score += hourSuccessRate * 0.2
                }

                // Weekend adjustment: Extra buffer after wake time
                // On weekends, penalize early morning more heavily
                if isWeekendDay && hour < (prefs.wakeTime.hour + 2) {
                    score -= 0.5  // Don't suggest walks too soon after weekend wake time
                }

                // Prefer longer slots for main activities
                if slot.duration >= 20 { score += 0.1 }
                if slot.duration >= 30 { score += 0.05 }

                // Consider general adherence data (lowest priority)
                let timeOfDay = categorizeTimeOfDay(hour)
                if let completionRate = adherence.bestTimeSlots[timeOfDay] {
                    score += completionRate * 0.1
                }

                return (slot, score)
            }
            .sorted { $0.score > $1.score }

        // Fill in activities - limit to 3 walks max to avoid overwhelming the user
        // Quality over quantity: fewer, better-timed walks are more likely to be completed
        let maxActivities = 3
        let stepsPerMinute = patterns.stepsPerMinuteWalking > 0 ? patterns.stepsPerMinuteWalking : 100

        for (slot, score) in scoredSlots {
            guard remainingSteps > 0 else { break }
            guard activities.count < maxActivities else { break }

            // Skip slots with very negative scores (strongly conflict with preferences)
            // unless we have no activities yet and really need one
            if score < -0.5 && activities.count > 0 { continue }

            // Calculate ideal duration for this slot
            let minutesNeeded = (remainingSteps / stepsPerMinute) + 5 // Add buffer
            let duration = min(slot.duration - 5, minutesNeeded, 45) // Cap at 45 min, leave buffer

            guard duration >= 5 else { continue } // Skip if too short

            let estimatedSteps = duration * stepsPerMinute
            let activityType = determineActivityType(slot: slot, duration: duration)
            let priority = determinePriority(
                remainingSteps: remainingSteps,
                estimatedSteps: estimatedSteps,
                totalNeeded: stepsNeeded
            )

            let hour = Calendar.current.component(.hour, from: slot.start)
            let reason = generateSlotReason(
                hour: hour,
                duration: duration,
                isPreferred: slot.isPreferredTime,
                patterns: patterns
            )

            let activity = PlannedActivity(
                id: UUID(),
                type: activityType,
                startTime: slot.start,
                duration: duration,
                estimatedSteps: estimatedSteps,
                priority: priority,
                slot: PlannedActivity.TimeSlot(
                    start: slot.start,
                    end: Calendar.current.date(byAdding: .minute, value: duration, to: slot.start) ?? slot.end,
                    isIdeal: slot.isPreferredTime,
                    conflictRisk: .low
                ),
                reason: reason,
                status: .planned
            )

            activities.append(activity)
            remainingSteps -= estimatedSteps
        }

        return activities.sorted { $0.startTime < $1.startTime }
    }

    private func determineActivityType(slot: AvailableSlot, duration: Int) -> PlannedActivity.ActivityType {
        let hour = Calendar.current.component(.hour, from: slot.start)

        switch slot.type {
        case .microBreak:
            return .microWalk
        case .shortWalk, .standardWalk:
            if hour >= 11 && hour <= 13 {
                return .lunchWalk
            } else if hour < 10 {
                return .morningWalk
            } else if hour >= 17 {
                return .eveningWalk
            }
            return .scheduledWalk
        case .extendedTime:
            if hour < 10 { return .morningWalk }
            if hour >= 17 { return .eveningWalk }
            return .scheduledWalk
        }
    }

    private func determinePriority(
        remainingSteps: Int,
        estimatedSteps: Int,
        totalNeeded: Int
    ) -> PlannedActivity.Priority {
        // If this activity covers more than 40% of remaining, it's critical
        let percentageOfRemaining = Double(estimatedSteps) / Double(remainingSteps)
        if percentageOfRemaining > 0.4 { return .critical }
        if percentageOfRemaining > 0.2 { return .recommended }
        return .optional
    }

    private func categorizeTimeOfDay(_ hour: Int) -> String {
        if hour < 12 { return "morning" }
        if hour < 17 { return "afternoon" }
        return "evening"
    }

    private func generateSlotReason(
        hour: Int,
        duration: Int,
        isPreferred: Bool,
        patterns: UserActivityPatterns
    ) -> String {
        var reasons: [String] = []

        if isPreferred {
            reasons.append("Matches your preferred walking time")
        }

        if patterns.peakActivityHours.contains(hour) {
            reasons.append("You're typically most active around this time")
        }

        if duration >= 30 {
            reasons.append("\(duration)-min slot covers significant steps")
        } else if duration >= 15 {
            reasons.append("Quick walk to boost your step count")
        } else {
            reasons.append("Micro-break to keep moving")
        }

        return reasons.joined(separator: ". ")
    }

    // MARK: - Confidence & Reasoning

    private func calculateConfidenceAndReasoning(
        stepsNeeded: Int,
        activities: [PlannedActivity],
        walkableMeetings: [WalkableMeeting],
        patterns: UserActivityPatterns
    ) -> (Double, String) {

        let plannedSteps = activities.reduce(0) { $0 + $1.estimatedSteps } +
                          walkableMeetings.filter { $0.isRecommended }.reduce(0) { $0 + $1.estimatedSteps }

        let coverageRatio = stepsNeeded > 0 ? min(1.0, Double(plannedSteps) / Double(stepsNeeded)) : 1.0

        // Adjust confidence based on user's historical goal achievement
        var confidence = coverageRatio * 0.6 + patterns.goalAchievementRate * 0.4

        // Cap at 0.95 - never be 100% confident
        confidence = min(0.95, confidence)

        // Generate reasoning
        var reasoning = ""

        if stepsNeeded == 0 {
            reasoning = "You've already hit your step goal! Great job!"
        } else if coverageRatio >= 0.9 {
            reasoning = "This plan covers your step goal. \(activities.count) walks scheduled across the day."
        } else if coverageRatio >= 0.7 {
            reasoning = "Plan covers \(Int(coverageRatio * 100))% of steps needed. Consider walking meetings to close the gap."
        } else {
            let gap = stepsNeeded - plannedSteps
            reasoning = "Limited availability today. You'll need ~\(gap) extra steps from walking meetings or longer walks."
        }

        if !walkableMeetings.filter({ $0.isRecommended }).isEmpty {
            reasoning += " Walking meeting opportunities identified."
        }

        return (confidence, reasoning)
    }

    // MARK: - Pattern Learning

    /// Analyze HealthKit data to learn user patterns
    func analyzeUserPatterns() async {
        let calendar = Calendar.current
        var dailySteps: [Date: Int] = [:]
        var hourlyActivity: [Int: [Int]] = [:] // hour -> [step counts]

        // Fetch last 30 days of step data
        for dayOffset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            if let steps = try? await healthKitManager.fetchSteps(for: date) {
                dailySteps[date] = steps
            }
        }

        guard !dailySteps.isEmpty else { return }

        // Calculate averages
        let allSteps = Array(dailySteps.values)
        let averageSteps = allSteps.reduce(0, +) / max(1, allSteps.count)

        // Weekday vs weekend
        var weekdaySteps: [Int] = []
        var weekendSteps: [Int] = []

        for (date, steps) in dailySteps {
            let weekday = calendar.component(.weekday, from: date)
            if weekday == 1 || weekday == 7 {
                weekendSteps.append(steps)
            } else {
                weekdaySteps.append(steps)
            }
        }

        let weekdayAverage = weekdaySteps.isEmpty ? averageSteps : weekdaySteps.reduce(0, +) / weekdaySteps.count
        let weekendAverage = weekendSteps.isEmpty ? averageSteps : weekendSteps.reduce(0, +) / weekendSteps.count

        // Best performing days
        var dayPerformance: [Int: [Int]] = [:]
        for (date, steps) in dailySteps {
            let weekday = calendar.component(.weekday, from: date)
            dayPerformance[weekday, default: []].append(steps)
        }

        let bestDays = dayPerformance
            .map { ($0.key, $0.value.reduce(0, +) / max(1, $0.value.count)) }
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0.0 }

        // Calculate goal achievement rate
        let targetSteps = UserPreferences.shared.dailyStepGoal
        let daysHitGoal = allSteps.filter { $0 >= targetSteps }.count
        let achievementRate = Double(daysHitGoal) / Double(max(1, allSteps.count))

        let patterns = UserActivityPatterns(
            averageDailySteps: averageSteps,
            weekdayAverage: weekdayAverage,
            weekendAverage: weekendAverage,
            bestPerformingDays: Array(bestDays),
            peakActivityHours: [8, 12, 17], // Default until we can analyze hourly
            typicalWalkDuration: 20, // Default
            stepsPerMinuteWalking: 100, // Default
            goalAchievementRate: achievementRate,
            consistentWalkTimes: [
                UserActivityPatterns.TimeWindow(hour: 8, frequency: 0.4),
                UserActivityPatterns.TimeWindow(hour: 12, frequency: 0.5),
                UserActivityPatterns.TimeWindow(hour: 18, frequency: 0.3)
            ],
            lastUpdated: Date()
        )

        await MainActor.run {
            self.userPatterns = patterns
        }

        savePatterns(patterns)
    }

    // MARK: - Plan Adherence Tracking

    /// Record when user completes an activity
    func recordActivityCompleted(_ activityID: UUID, actualSteps: Int? = nil) {
        guard var plan = currentDayPlan,
              let index = plan.activities.firstIndex(where: { $0.id == activityID }) else { return }

        var activity = plan.activities[index]
        activity.status = .completed

        // Update adherence stats
        var adherence = planAdherence ?? .initial
        adherence.activitiesCompleted += 1
        adherence.averageCompletionRate = Double(adherence.activitiesCompleted) /
            Double(max(1, adherence.activitiesCompleted + adherence.activitiesSkipped))

        // Track which time slots work best
        let hour = Calendar.current.component(.hour, from: activity.startTime)
        let timeOfDay = categorizeTimeOfDay(hour)
        let currentRate = adherence.bestTimeSlots[timeOfDay] ?? 0.5
        adherence.bestTimeSlots[timeOfDay] = (currentRate + 1.0) / 2.0 // Moving average toward 1.0

        adherence.lastUpdated = Date()
        planAdherence = adherence
        saveAdherence(adherence)
    }

    /// Record when user skips an activity
    func recordActivitySkipped(_ activityID: UUID, reason: String? = nil) {
        guard var adherence = planAdherence else { return }

        adherence.activitiesSkipped += 1
        adherence.averageCompletionRate = Double(adherence.activitiesCompleted) /
            Double(max(1, adherence.activitiesCompleted + adherence.activitiesSkipped))

        // Track which time slots don't work
        if let plan = currentDayPlan,
           let activity = plan.activities.first(where: { $0.id == activityID }) {
            let hour = Calendar.current.component(.hour, from: activity.startTime)
            let timeOfDay = categorizeTimeOfDay(hour)
            let currentRate = adherence.bestTimeSlots[timeOfDay] ?? 0.5
            adherence.bestTimeSlots[timeOfDay] = (currentRate + 0.0) / 2.0 // Moving average toward 0.0
        }

        adherence.lastUpdated = Date()
        planAdherence = adherence
        saveAdherence(adherence)
    }

    // MARK: - Calendar Integration

    /// Add planned activity to user's calendar
    func addToCalendar(_ activity: PlannedActivity) async throws -> String? {
        let prefs = UserPreferences.shared
        guard !prefs.autopilotCalendarID.isEmpty else { return nil }

        let calendars = eventStore.calendars(for: .event)
        guard let calendar = calendars.first(where: { $0.calendarIdentifier == prefs.autopilotCalendarID }) else {
            return nil
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = activityTitle(for: activity)
        event.startDate = activity.startTime
        event.endDate = activity.slot.end

        event.notes = """
        \(activity.reason)

        Estimated steps: ~\(activity.estimatedSteps)
        Duration: \(activity.duration) minutes
        Priority: \(activity.priority.rawValue.capitalized)

        ---
        Smart-planned by Activslot
        """

        let alarm = EKAlarm(relativeOffset: TimeInterval(-5 * 60))
        event.addAlarm(alarm)

        try eventStore.save(event, span: .thisEvent)
        return event.eventIdentifier
    }

    private func activityTitle(for activity: PlannedActivity) -> String {
        switch activity.type {
        case .microWalk: return "Quick Walk 🚶"
        case .morningWalk: return "Morning Walk ☀️"
        case .lunchWalk: return "Lunch Walk 🥗"
        case .eveningWalk: return "Evening Walk 🌆"
        case .scheduledWalk: return "Scheduled Walk 🚶"
        case .postMeetingWalk: return "Post-Meeting Walk 🚶"
        case .gymWorkout: return "Gym Workout 💪"
        }
    }

    // MARK: - Persistence

    private func loadCachedData() {
        if let data = UserDefaults.standard.data(forKey: patternsKey),
           let patterns = try? JSONDecoder().decode(UserActivityPatterns.self, from: data) {
            userPatterns = patterns
        }

        if let data = UserDefaults.standard.data(forKey: adherenceKey),
           let adherence = try? JSONDecoder().decode(PlanAdherence.self, from: data) {
            planAdherence = adherence
        }

        if let data = UserDefaults.standard.data(forKey: dayOfWeekPatternsKey),
           let patterns = try? JSONDecoder().decode(DayOfWeekPatterns.self, from: data) {
            dayOfWeekPatterns = patterns
        }
    }

    private func savePatterns(_ patterns: UserActivityPatterns) {
        if let data = try? JSONEncoder().encode(patterns) {
            UserDefaults.standard.set(data, forKey: patternsKey)
        }
    }

    private func saveAdherence(_ adherence: PlanAdherence) {
        if let data = try? JSONEncoder().encode(adherence) {
            UserDefaults.standard.set(data, forKey: adherenceKey)
        }
    }

    private func saveDayOfWeekPatterns(_ patterns: DayOfWeekPatterns) {
        if let data = try? JSONEncoder().encode(patterns) {
            UserDefaults.standard.set(data, forKey: dayOfWeekPatternsKey)
        }
    }

    // MARK: - Day-of-Week Pattern Analysis

    /// Analyze 60 days of HealthKit data to learn day-of-week specific patterns
    /// "On Tuesdays, you typically walk at 7am and 12pm with 2500 steps each"
    func analyzeDayOfWeekPatterns() async {
        await MainActor.run { isAnalyzing = true }
        defer { Task { await MainActor.run { isAnalyzing = false } } }

        let calendar = Calendar.current

        // Fetch 60 days of hourly step data
        guard let hourlyData = try? await healthKitManager.fetchHourlyStepsForDays(days: 60) else {
            #if DEBUG
            print("SmartPlannerEngine: Failed to fetch hourly data for day-of-week analysis")
            #endif
            return
        }

        // Group data by weekday
        var weekdayData: [Int: [(date: Date, hourlySteps: [Int: Int], totalSteps: Int)]] = [:]
        for weekday in 1...7 {
            weekdayData[weekday] = []
        }

        for (date, hourlySteps) in hourlyData {
            let weekday = calendar.component(.weekday, from: date)
            let totalSteps = hourlySteps.values.reduce(0, +)
            weekdayData[weekday]?.append((date: date, hourlySteps: hourlySteps, totalSteps: totalSteps))
        }

        // Build patterns for each day of the week
        var newPatterns = DayOfWeekPatterns.empty

        for weekday in 1...7 {
            guard let dayData = weekdayData[weekday], !dayData.isEmpty else { continue }

            // Calculate average steps per hour across all samples of this weekday
            var hourlyAverages: [Int: Int] = [:]
            var hourlyCounts: [Int: Int] = [:]

            for sample in dayData {
                for (hour, steps) in sample.hourlySteps {
                    hourlyAverages[hour, default: 0] += steps
                    hourlyCounts[hour, default: 0] += 1
                }
            }

            // Convert to averages
            for (hour, total) in hourlyAverages {
                if let count = hourlyCounts[hour], count > 0 {
                    hourlyAverages[hour] = total / count
                }
            }

            // Find peak activity hours (top 5 hours by average steps)
            let peakHours = hourlyAverages
                .sorted { $0.value > $1.value }
                .prefix(5)
                .map { $0.key }
                .sorted()

            // Calculate average daily steps for this weekday
            let avgDailySteps = dayData.isEmpty ? 0 : dayData.map { $0.totalSteps }.reduce(0, +) / dayData.count

            // Get existing adherence rate or default to 0.5
            let existingAdherenceRate = dayOfWeekPatterns?.dayPatterns[weekday]?.adherenceRate ?? 0.5
            let existingSuccessRates = dayOfWeekPatterns?.dayPatterns[weekday]?.bestSlotSuccessRates ?? [:]

            newPatterns.dayPatterns[weekday] = DayOfWeekPatterns.DayPattern(
                weekday: weekday,
                peakActivityHours: peakHours,
                hourlyStepAverages: hourlyAverages,
                totalDaysSampled: dayData.count,
                averageDailySteps: avgDailySteps,
                adherenceRate: existingAdherenceRate,
                bestSlotSuccessRates: existingSuccessRates
            )
        }

        newPatterns.lastUpdated = Date()

        // Save and publish
        await MainActor.run {
            self.dayOfWeekPatterns = newPatterns
        }
        saveDayOfWeekPatterns(newPatterns)

        #if DEBUG
        print("SmartPlannerEngine: Day-of-week patterns analyzed")
        for weekday in 1...7 {
            if let pattern = newPatterns.dayPatterns[weekday] {
                let dayName = calendar.weekdaySymbols[weekday - 1]
                print("  \(dayName): avg \(pattern.averageDailySteps) steps, peaks at \(pattern.peakActivityHours)")
            }
        }
        #endif
    }

    /// Get the pattern for a specific date (uses day of week)
    func getPatternForDate(_ date: Date) -> DayOfWeekPatterns.DayPattern? {
        return dayOfWeekPatterns?.pattern(for: date)
    }

    // MARK: - Pattern Visualization Data

    /// Data structure for UI to display walk pattern graph
    struct HourlyPatternData: Identifiable {
        let id = UUID()
        let hour: Int
        let averageSteps: Int
        let isRecommended: Bool  // Based on user preference + patterns
        let label: String  // "8 AM", "12 PM", etc.
    }

    /// Get hourly walk pattern data for a specific day of week (for visualization)
    /// Returns array of 24 hours with average steps and recommendation status
    func getHourlyPatternData(for date: Date) -> [HourlyPatternData] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let prefs = UserPreferences.shared

        // Get day-specific pattern if available
        let dayPattern = dayOfWeekPatterns?.dayPatterns[weekday]

        // Build 24-hour data
        var result: [HourlyPatternData] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"  // "8 AM", "12 PM", etc.

        for hour in 0..<24 {
            // Skip hours outside active window
            let wakeHour = prefs.wakeTime.hour
            let sleepHour = prefs.sleepTime.hour

            // Skip very early or late hours
            guard hour >= max(wakeHour - 1, 5) && hour <= min(sleepHour + 1, 23) else { continue }

            let avgSteps = dayPattern?.hourlyStepAverages[hour] ?? 0

            // Determine if this hour is recommended based on preference + patterns
            var isRecommended = false

            // Check if matches user's preferred time
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = hour
            if let hourDate = calendar.date(from: components) {
                isRecommended = isPreferredTime(hourDate, prefs: prefs)

                // Boost if it's also a peak activity hour
                if let peakHours = dayPattern?.peakActivityHours, peakHours.contains(hour) {
                    isRecommended = isRecommended || avgSteps > 500
                }

                // Don't recommend if it conflicts with preference
                if conflictsWithPreference(hourDate, prefs: prefs) {
                    isRecommended = false
                }
            }

            // Create label
            var labelComponents = calendar.dateComponents([.year, .month, .day], from: date)
            labelComponents.hour = hour
            labelComponents.minute = 0
            let labelDate = calendar.date(from: labelComponents) ?? date
            let label = formatter.string(from: labelDate)

            result.append(HourlyPatternData(
                hour: hour,
                averageSteps: avgSteps,
                isRecommended: isRecommended,
                label: label
            ))
        }

        return result
    }

    /// Get summary text explaining why we're recommending these times
    func getPatternExplanation(for date: Date) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let dayName = calendar.weekdaySymbols[weekday - 1]
        let prefs = UserPreferences.shared

        let preferenceText: String
        switch prefs.preferredWalkTime {
        case .morning: preferenceText = "mornings"
        case .afternoon: preferenceText = "afternoons"
        case .evening: preferenceText = "evenings"
        case .noPreference: preferenceText = "throughout the day"
        }

        guard let dayPattern = dayOfWeekPatterns?.dayPatterns[weekday],
              dayPattern.totalDaysSampled > 0 else {
            return "Based on your preference for \(preferenceText). We'll learn your \(dayName) patterns over time."
        }

        let peakHours = dayPattern.peakActivityHours.prefix(3)
        let peakTimes = peakHours.map { formatHour($0) }.joined(separator: ", ")

        return "On \(dayName)s, you typically walk around \(peakTimes). Showing suggestions that match your \(preferenceText) preference."
    }

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    // MARK: - Adherence Verification

    /// Verify if user actually walked during a planned activity window
    func verifyActivityAdherence(_ activity: PlannedActivity) async -> PlannedActivity {
        let startTime = activity.startTime
        let endTime = activity.slot.end

        let actualSteps = (try? await healthKitManager.fetchSteps(from: startTime, to: endTime)) ?? 0

        var verifiedActivity = activity
        verifiedActivity.actualSteps = actualSteps
        verifiedActivity.verifiedAt = Date()

        // Determine adherence status based on completion ratio
        let expectedSteps = activity.estimatedSteps
        let ratio = expectedSteps > 0 ? Double(actualSteps) / Double(expectedSteps) : 0

        if ratio >= 0.8 {
            verifiedActivity.adherenceStatus = .verified
        } else if ratio >= 0.4 {
            verifiedActivity.adherenceStatus = .partial
        } else {
            verifiedActivity.adherenceStatus = .missed
        }

        // Update day-of-week adherence data
        await updateDayOfWeekAdherence(for: activity, wasCompleted: ratio >= 0.8)

        #if DEBUG
        print("SmartPlannerEngine: Verified activity - expected \(expectedSteps), actual \(actualSteps) (\(Int(ratio * 100))%)")
        #endif

        return verifiedActivity
    }

    /// Update adherence statistics for a specific day of week and hour
    private func updateDayOfWeekAdherence(for activity: PlannedActivity, wasCompleted: Bool) async {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: activity.startTime)
        let hour = calendar.component(.hour, from: activity.startTime)

        guard var patterns = dayOfWeekPatterns,
              var dayPattern = patterns.dayPatterns[weekday] else { return }

        // Update hour success rate with exponential moving average
        let currentRate = dayPattern.bestSlotSuccessRates[hour] ?? 0.5
        let newRate = wasCompleted ? 1.0 : 0.0
        dayPattern.bestSlotSuccessRates[hour] = (currentRate + newRate) / 2.0

        // Update overall day adherence rate
        let totalCompleted = wasCompleted ? 1 : 0
        dayPattern.adherenceRate = (dayPattern.adherenceRate + Double(totalCompleted)) / 2.0

        patterns.dayPatterns[weekday] = dayPattern
        patterns.lastUpdated = Date()

        await MainActor.run {
            self.dayOfWeekPatterns = patterns
        }
        saveDayOfWeekPatterns(patterns)
    }
}
