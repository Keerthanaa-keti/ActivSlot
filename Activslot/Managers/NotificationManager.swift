import Foundation
import UserNotifications

// MARK: - Notification Identifiers

enum NotificationIdentifier {
    static let eveningBriefing = "evening-briefing"
    static let walkableMeetingPrefix = "walkable-meeting-"
    static let workoutReminder = "workout-reminder"
    static let afternoonCheckIn = "afternoon-checkin"
    static let daySummary = "day-summary"
    static let streakAtRisk = "streak-at-risk"
    static let planReady = "plan-ready"
    static let behindOnSteps = "behind-on-steps"
    static let walkableMeetingPreNotification = "walkable-meeting-pre-"
    static let walkReminder = "walk-reminder-"
}

// MARK: - Notification Action Identifiers

enum NotificationAction {
    static let snooze15Min = "SNOOZE_15_MIN"
    static let snooze1Hour = "SNOOZE_1_HOUR"
    static let snoozeEndOfDay = "SNOOZE_END_OF_DAY"
    static let startWalk = "START_WALK"
    static let dismiss = "DISMISS"
}

// MARK: - Notification Categories

enum NotificationCategory {
    static let walkReminder = "WALK_REMINDER"
    static let behindOnSteps = "BEHIND_ON_STEPS"
    static let eveningBriefing = "EVENING_BRIEFING"
}

// MARK: - Tomorrow Briefing Data

struct TomorrowBriefing {
    let date: Date
    let totalMeetingMinutes: Int
    let realMeetingCount: Int
    let walkableMeetings: [CalendarEvent]
    let bestWorkoutWindow: DateInterval?
    let dayType: DayType

    enum DayType {
        case light      // < 2 hours meetings
        case moderate   // 2-5 hours meetings
        case heavy      // > 5 hours meetings

        var emoji: String {
            switch self {
            case .light: return "🌤️"
            case .moderate: return "⛅"
            case .heavy: return "🌧️"
            }
        }

        var description: String {
            switch self {
            case .light: return "Light day"
            case .moderate: return "Moderate day"
            case .heavy: return "Busy day"
            }
        }
    }

    var walkableSteps: Int {
        walkableMeetings.reduce(0) { $0 + $1.estimatedSteps }
    }

    init(date: Date, events: [CalendarEvent], freeSlots: [DateInterval]) {
        self.date = date

        // Filter to real meetings only
        let realMeetings = events.filter { $0.isRealMeeting }
        self.realMeetingCount = realMeetings.count
        self.totalMeetingMinutes = realMeetings.reduce(0) { $0 + $1.duration }
        self.walkableMeetings = realMeetings.filter { $0.isWalkable }

        // Determine day type
        if totalMeetingMinutes < 120 {
            self.dayType = .light
        } else if totalMeetingMinutes <= 300 {
            self.dayType = .moderate
        } else {
            self.dayType = .heavy
        }

        // Find best workout window (prefer morning for heavy days)
        let userPrefs = UserPreferences.shared
        let preferMorning = dayType == .heavy || userPrefs.preferredGymTime == .morning

        if preferMorning {
            // Find morning slot (before 9 AM)
            self.bestWorkoutWindow = freeSlots.first { interval in
                let hour = Calendar.current.component(.hour, from: interval.start)
                return hour < 9 && interval.duration >= Double(userPrefs.workoutDuration.rawValue * 60)
            } ?? freeSlots.first { $0.duration >= Double(userPrefs.workoutDuration.rawValue * 60) }
        } else {
            // Find slot matching preference
            self.bestWorkoutWindow = freeSlots.first { $0.duration >= Double(userPrefs.workoutDuration.rawValue * 60) }
        }
    }
}

// MARK: - Notification Manager

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    // Snooze state
    @Published var snoozedUntil: Date? {
        didSet {
            if let date = snoozedUntil {
                UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "notification_snoozedUntil")
            } else {
                UserDefaults.standard.removeObject(forKey: "notification_snoozedUntil")
            }
        }
    }

    var isSnoozed: Bool {
        guard let snoozedUntil = snoozedUntil else { return false }
        return Date() < snoozedUntil
    }

    // Notification Settings (stored in UserDefaults)
    @Published var eveningBriefingEnabled: Bool {
        didSet { UserDefaults.standard.set(eveningBriefingEnabled, forKey: "notification_eveningBriefing") }
    }
    @Published var walkableMeetingRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(walkableMeetingRemindersEnabled, forKey: "notification_walkableMeetings") }
    }
    @Published var workoutRemindersEnabled: Bool {
        didSet { UserDefaults.standard.set(workoutRemindersEnabled, forKey: "notification_workoutReminders") }
    }
    @Published var eveningBriefingTime: Date {
        didSet { UserDefaults.standard.set(eveningBriefingTime.timeIntervalSince1970, forKey: "notification_eveningBriefingTime") }
    }
    @Published var walkableMeetingLeadTime: Int { // minutes before meeting
        didSet { UserDefaults.standard.set(walkableMeetingLeadTime, forKey: "notification_walkableLeadTime") }
    }

    private init() {
        // Load settings from UserDefaults
        self.eveningBriefingEnabled = UserDefaults.standard.object(forKey: "notification_eveningBriefing") as? Bool ?? true
        self.walkableMeetingRemindersEnabled = UserDefaults.standard.object(forKey: "notification_walkableMeetings") as? Bool ?? true
        self.workoutRemindersEnabled = UserDefaults.standard.object(forKey: "notification_workoutReminders") as? Bool ?? true

        // Default evening briefing time: 8 PM
        if let storedTime = UserDefaults.standard.object(forKey: "notification_eveningBriefingTime") as? Double {
            self.eveningBriefingTime = Date(timeIntervalSince1970: storedTime)
        } else {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = 20
            components.minute = 0
            self.eveningBriefingTime = Calendar.current.date(from: components) ?? Date()
        }

        self.walkableMeetingLeadTime = UserDefaults.standard.object(forKey: "notification_walkableLeadTime") as? Int ?? 10

        // Load snooze state
        if let snoozedTimestamp = UserDefaults.standard.object(forKey: "notification_snoozedUntil") as? Double {
            let date = Date(timeIntervalSince1970: snoozedTimestamp)
            self.snoozedUntil = date > Date() ? date : nil
        }

        checkAuthorizationStatus()
        registerNotificationCategories()
    }

    // MARK: - Notification Categories Registration

    func registerNotificationCategories() {
        // Common actions
        let dismissAction = UNNotificationAction(
            identifier: NotificationAction.dismiss,
            title: "Dismiss",
            options: []
        )

        // Snooze actions
        let snooze15Min = UNNotificationAction(
            identifier: NotificationAction.snooze15Min,
            title: "Snooze 15 min",
            options: []
        )

        let snooze1Hour = UNNotificationAction(
            identifier: NotificationAction.snooze1Hour,
            title: "Snooze 1 hour",
            options: []
        )

        let snoozeEndOfDay = UNNotificationAction(
            identifier: NotificationAction.snoozeEndOfDay,
            title: "Snooze until tomorrow",
            options: []
        )

        let startWalk = UNNotificationAction(
            identifier: NotificationAction.startWalk,
            title: "Start Walk",
            options: [.foreground]
        )

        // Walk reminder category (with full snooze options)
        let walkReminderCategory = UNNotificationCategory(
            identifier: NotificationCategory.walkReminder,
            actions: [startWalk, snooze15Min, snooze1Hour, snoozeEndOfDay],
            intentIdentifiers: [],
            options: []
        )

        // Behind on steps category (with snooze options)
        let behindOnStepsCategory = UNNotificationCategory(
            identifier: NotificationCategory.behindOnSteps,
            actions: [startWalk, snooze15Min, snooze1Hour],
            intentIdentifiers: [],
            options: []
        )

        // Evening Briefing category
        let planAction = UNNotificationAction(
            identifier: "PLAN_DAY",
            title: "Plan My Day",
            options: [.foreground]
        )
        let eveningCategory = UNNotificationCategory(
            identifier: NotificationCategory.eveningBriefing,
            actions: [planAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Walkable Meeting category
        let startWalkingAction = UNNotificationAction(
            identifier: "START_WALKING",
            title: "Start Walking",
            options: [.foreground]
        )
        let walkableCategory = UNNotificationCategory(
            identifier: "WALKABLE_MEETING",
            actions: [startWalkingAction, snooze15Min, snooze1Hour],
            intentIdentifiers: [],
            options: []
        )

        // Workout Reminder category
        let startWorkoutAction = UNNotificationAction(
            identifier: "START_WORKOUT",
            title: "Let's Go!",
            options: [.foreground]
        )
        let workoutCategory = UNNotificationCategory(
            identifier: "WORKOUT_REMINDER",
            actions: [startWorkoutAction, snooze15Min],
            intentIdentifiers: [],
            options: []
        )

        // Plan Ready category
        let viewPlanAction = UNNotificationAction(
            identifier: "VIEW_PLAN",
            title: "View Plan",
            options: [.foreground]
        )
        let planReadyCategory = UNNotificationCategory(
            identifier: "PLAN_READY",
            actions: [viewPlanAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        // Walk Buddy category
        let confirmWalkAction = UNNotificationAction(
            identifier: "CONFIRM_WALK",
            title: "Let's Do It!",
            options: [.foreground]
        )
        let walkBuddyCategory = UNNotificationCategory(
            identifier: "WALK_BUDDY_SUGGESTION",
            actions: [confirmWalkAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            walkReminderCategory,
            behindOnStepsCategory,
            eveningCategory,
            walkableCategory,
            workoutCategory,
            planReadyCategory,
            walkBuddyCategory
        ])
    }

    // MARK: - Snooze Methods

    func snooze(for duration: SnoozeDuration) {
        let calendar = Calendar.current
        let now = Date()

        switch duration {
        case .fifteenMinutes:
            snoozedUntil = calendar.date(byAdding: .minute, value: 15, to: now)
        case .oneHour:
            snoozedUntil = calendar.date(byAdding: .hour, value: 1, to: now)
        case .endOfDay:
            // Set to midnight tonight (start of tomorrow)
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.day = (components.day ?? 1) + 1
            components.hour = 0
            components.minute = 0
            snoozedUntil = calendar.date(from: components)
        }

        // Cancel pending walk notifications
        cancelAllWalkReminders()
    }

    func clearSnooze() {
        snoozedUntil = nil
    }

    enum SnoozeDuration {
        case fifteenMinutes
        case oneHour
        case endOfDay
    }

    // MARK: - Handle Notification Actions

    func handleNotificationAction(identifier: String, notificationIdentifier: String, userInfo: [AnyHashable: Any]) {
        switch identifier {
        case NotificationAction.snooze15Min:
            snooze(for: .fifteenMinutes)
        case NotificationAction.snooze1Hour:
            snooze(for: .oneHour)
        case NotificationAction.snoozeEndOfDay:
            snooze(for: .endOfDay)
        case NotificationAction.startWalk:
            // This is handled by the app delegate to open the walk screen
            break
        default:
            break
        }
    }

    func cancelAllWalkReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let walkIdentifiers = requests
                .filter { $0.identifier.hasPrefix(NotificationIdentifier.walkReminder) ||
                         $0.identifier.hasPrefix(NotificationIdentifier.walkableMeetingPrefix) ||
                         $0.identifier == NotificationIdentifier.behindOnSteps }
                .map { $0.identifier }

            center.removePendingNotificationRequests(withIdentifiers: walkIdentifiers)
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async throws -> Bool {
        let options: UNAuthorizationOptions = [.alert, .badge, .sound]

        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        await MainActor.run {
            self.isAuthorized = granted
        }
        return granted
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Evening Briefing Notification

    func scheduleEveningBriefing(briefing: TomorrowBriefing) {
        guard isAuthorized && eveningBriefingEnabled else { return }

        // Remove existing evening notification
        cancelNotification(identifier: NotificationIdentifier.eveningBriefing)

        let content = UNMutableNotificationContent()
        content.title = "\(briefing.dayType.emoji) Tomorrow's Game Plan"
        content.body = buildEveningBriefingBody(briefing: briefing)
        content.sound = .default
        content.categoryIdentifier = "EVENING_BRIEFING"

        // Add action buttons
        content.userInfo = [
            "type": "eveningBriefing",
            "date": briefing.date.timeIntervalSince1970
        ]

        // Schedule for the configured time today
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.hour, .minute], from: eveningBriefingTime)

        // If it's already past the briefing time today, schedule for tomorrow
        let now = Date()
        var scheduledDate = calendar.date(from: DateComponents(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now),
            day: calendar.component(.day, from: now),
            hour: dateComponents.hour,
            minute: dateComponents.minute
        )) ?? now

        if scheduledDate <= now {
            scheduledDate = calendar.date(byAdding: .day, value: 1, to: scheduledDate) ?? scheduledDate
        }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledDate),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.eveningBriefing,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("Error scheduling evening briefing: \(error)")
            }
            #endif
        }
    }

    private func buildEveningBriefingBody(briefing: TomorrowBriefing) -> String {
        var parts: [String] = []
        let formatter = DateFormatter()
        formatter.timeStyle = .short

        // Meeting summary
        let hours = briefing.totalMeetingMinutes / 60
        let mins = briefing.totalMeetingMinutes % 60
        if hours > 0 {
            parts.append("\(hours)h\(mins > 0 ? " \(mins)m" : "") of meetings")
        } else if mins > 0 {
            parts.append("\(mins)m of meetings")
        }

        // Workout recommendation
        if let workoutWindow = briefing.bestWorkoutWindow {
            let time = formatter.string(from: workoutWindow.start)
            if briefing.dayType == .heavy {
                parts.append("Best workout: \(time) (before meetings)")
            } else {
                parts.append("Workout window: \(time)")
            }
        }

        // Walkable meetings
        if !briefing.walkableMeetings.isEmpty {
            let count = briefing.walkableMeetings.count
            let steps = briefing.walkableSteps.formatted()
            parts.append("\(count) walkable meeting\(count > 1 ? "s" : "") (~\(steps) steps)")
        }

        if parts.isEmpty {
            return "Plan your movement for tomorrow!"
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Walkable Meeting Notification

    func scheduleWalkableMeetingReminder(for event: CalendarEvent) {
        guard isAuthorized && walkableMeetingRemindersEnabled else { return }
        guard UserDefaults.standard.bool(forKey: "cachedProEntitlement") else { return }
        guard event.isWalkable else { return }

        let content = UNMutableNotificationContent()
        content.title = "Walk this call?"
        content.body = "\"\(event.title)\" in \(walkableMeetingLeadTime) min\n\(event.attendeeCount) attendees • \(event.duration) min • ~\(event.estimatedSteps.formatted()) steps"
        content.sound = .default
        content.categoryIdentifier = "WALKABLE_MEETING"

        content.userInfo = [
            "type": "walkableMeeting",
            "eventId": event.id,
            "eventTitle": event.title
        ]

        // Schedule X minutes before meeting
        let triggerDate = event.startDate.addingTimeInterval(-Double(walkableMeetingLeadTime) * 60)

        // Only schedule if it's in the future
        guard triggerDate > Date() else { return }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: triggerDate.timeIntervalSinceNow,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "\(NotificationIdentifier.walkableMeetingPrefix)\(event.id)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("Error scheduling walkable meeting reminder: \(error)")
            }
            #endif
        }
    }

    func scheduleAllWalkableMeetingReminders(for events: [CalendarEvent]) {
        guard isAuthorized && walkableMeetingRemindersEnabled else { return }

        // Remove all existing walkable meeting notifications
        cancelNotificationsWithPrefix(NotificationIdentifier.walkableMeetingPrefix)

        // ATOMIC HABITS: Only ONE notification for the BEST walkable meeting
        // Don't overwhelm users with multiple reminders
        // Find the single best walkable meeting (shortest with fewest attendees = most walkable)
        let walkableEvents = events.filter { $0.isWalkable && $0.startDate > Date() }
        let bestWalkableMeeting = walkableEvents
            .sorted { event1, event2 in
                // Prefer 1:1s (fewer attendees), then shorter meetings
                if event1.attendeeCount != event2.attendeeCount {
                    return event1.attendeeCount < event2.attendeeCount
                }
                return event1.duration < event2.duration
            }
            .first

        // Schedule notification only for the best one
        if let best = bestWalkableMeeting {
            scheduleWalkableMeetingReminder(for: best)
        }
    }

    // MARK: - Workout Reminder

    func scheduleWorkoutReminder(at time: Date, message: String? = nil) {
        guard isAuthorized && workoutRemindersEnabled else { return }
        guard time > Date() else { return }

        // Remove existing workout reminder
        cancelNotification(identifier: NotificationIdentifier.workoutReminder)

        let content = UNMutableNotificationContent()
        content.title = "Workout Time"
        content.body = message ?? "Your scheduled workout is coming up in 15 minutes!"
        content.sound = .default
        content.categoryIdentifier = "WORKOUT_REMINDER"

        // Schedule 15 minutes before
        let triggerDate = time.addingTimeInterval(-15 * 60)
        guard triggerDate > Date() else { return }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: triggerDate.timeIntervalSinceNow,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.workoutReminder,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Streak At Risk Notification

    func scheduleStreakAtRiskNotification(currentSteps: Int, goalSteps: Int, currentStreak: Int) {
        guard isAuthorized else { return }
        guard UserDefaults.standard.bool(forKey: "cachedProEntitlement") else { return }
        guard currentStreak > 0 else { return } // Only if they have a streak to protect
        guard currentSteps < goalSteps else { return } // Only if goal not yet met

        // Cancel any existing streak notification
        cancelNotification(identifier: NotificationIdentifier.streakAtRisk)

        let stepsNeeded = goalSteps - currentSteps
        let content = UNMutableNotificationContent()

        if currentStreak >= 7 {
            content.title = "🔥 Don't lose your \(currentStreak)-day streak!"
        } else {
            content.title = "Keep your streak alive!"
        }
        content.body = "You need \(stepsNeeded.formatted()) more steps today. A 15-min walk can do it!"
        content.sound = .default
        content.categoryIdentifier = "STREAK_AT_RISK"

        content.userInfo = [
            "type": "streakAtRisk",
            "stepsNeeded": stepsNeeded,
            "currentStreak": currentStreak
        ]

        // Schedule for 7 PM today if not already past
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 19
        components.minute = 0

        guard let scheduledDate = calendar.date(from: components),
              scheduledDate > Date() else { return }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.hour, .minute], from: scheduledDate),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.streakAtRisk,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("Error scheduling streak at risk notification: \(error)")
            }
            #endif
        }
    }

    // MARK: - Smart Planner Notifications

    /// Schedule notification when tomorrow's plan is ready (sent in evening)
    func schedulePlanReadyNotification(plan: SmartPlannerEngine.DailyMovementPlan) {
        guard isAuthorized else { return }

        // Cancel any existing plan ready notification
        cancelNotification(identifier: NotificationIdentifier.planReady)

        let content = UNMutableNotificationContent()
        content.title = "Tomorrow's Plan Ready"

        // Build summary
        let walkCount = plan.activities.count
        let totalSteps = plan.totalPlannedSteps
        let walkableMeetingCount = plan.walkableMeetings.count

        var bodyParts: [String] = []
        bodyParts.append("\(walkCount) walk\(walkCount == 1 ? "" : "s") planned (~\(totalSteps.formatted()) steps)")

        if walkableMeetingCount > 0 {
            bodyParts.append("\(walkableMeetingCount) walkable meeting\(walkableMeetingCount == 1 ? "" : "s") identified")
        }

        if plan.isOnTrack {
            bodyParts.append("On track to exceed your goal!")
        }

        content.body = bodyParts.joined(separator: "\n")
        content.sound = .default
        content.categoryIdentifier = "PLAN_READY"

        content.userInfo = [
            "type": "planReady",
            "date": plan.date.timeIntervalSince1970,
            "walkCount": walkCount,
            "totalSteps": totalSteps
        ]

        // Schedule for 8 PM today
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = 20
        components.minute = 0

        guard let scheduledDate = calendar.date(from: components) else { return }

        // If already past 8 PM, don't schedule (plan should already be ready)
        guard scheduledDate > Date() else {
            // Send immediately instead
            let immediateTrigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: NotificationIdentifier.planReady,
                content: content,
                trigger: immediateTrigger
            )
            UNUserNotificationCenter.current().add(request)
            return
        }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.hour, .minute], from: scheduledDate),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.planReady,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("Error scheduling plan ready notification: \(error)")
            }
            #endif
        }
    }

    /// Schedule notification when user is behind on steps at a checkpoint
    func scheduleBehindOnStepsNotification(deficit: Int, suggestedSlot: SmartPlannerEngine.PlannedActivity.TimeSlot?) async {
        guard isAuthorized else { return }
        guard UserDefaults.standard.bool(forKey: "cachedProEntitlement") else { return }

        // Check if notifications are snoozed
        guard !isSnoozed else {
            #if DEBUG
            print("NotificationManager: Skipping behind-on-steps notification - snoozed until \(snoozedUntil?.description ?? "unknown")")
            #endif
            return
        }

        // Cancel any existing behind notification
        cancelNotification(identifier: NotificationIdentifier.behindOnSteps)

        let content = UNMutableNotificationContent()
        content.title = "You're \(deficit.formatted()) steps behind"

        var bodyText: String
        if let slot = suggestedSlot {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let slotTime = formatter.string(from: slot.start)
            let duration = Int(slot.end.timeIntervalSince(slot.start) / 60)
            bodyText = "A \(duration)-minute walk at \(slotTime) can help you catch up!"
        } else {
            bodyText = "Try taking a quick walk when you can to get back on track."
        }

        content.body = bodyText
        content.sound = .default
        content.categoryIdentifier = "BEHIND_ON_STEPS"

        content.userInfo = [
            "type": "behindOnSteps",
            "deficit": deficit,
            "hasSuggestedSlot": suggestedSlot != nil
        ]

        // Schedule immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: NotificationIdentifier.behindOnSteps,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("Error scheduling behind on steps notification: \(error)")
            }
            #endif
        }
    }

    /// Schedule pre-notification for walkable meeting (15 minutes before)
    func scheduleWalkableMeetingPreNotification(for meeting: SmartPlannerEngine.WalkableMeeting) {
        guard isAuthorized && walkableMeetingRemindersEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Walkable meeting in 15 min"
        content.body = "\"\(meeting.title)\" - Get ready to walk and talk! (~\(meeting.estimatedSteps.formatted()) steps)"
        content.sound = .default
        content.categoryIdentifier = "WALKABLE_MEETING"

        content.userInfo = [
            "type": "walkableMeetingPre",
            "meetingId": meeting.id.uuidString,
            "meetingTitle": meeting.title
        ]

        // Schedule 15 minutes before meeting
        let triggerDate = meeting.startTime.addingTimeInterval(-15 * 60)
        guard triggerDate > Date() else { return }

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: triggerDate.timeIntervalSinceNow,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "\(NotificationIdentifier.walkableMeetingPreNotification)\(meeting.id.uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error = error {
                print("Error scheduling walkable meeting pre-notification: \(error)")
            }
            #endif
        }
    }

    /// Schedule pre-notifications for all walkable meetings in a plan
    func scheduleWalkableMeetingPreNotifications(for plan: SmartPlannerEngine.DailyMovementPlan) {
        guard isAuthorized && walkableMeetingRemindersEnabled else { return }

        // Cancel existing pre-notifications
        cancelNotificationsWithPrefix(NotificationIdentifier.walkableMeetingPreNotification)

        // Schedule new pre-notifications
        for meeting in plan.walkableMeetings {
            scheduleWalkableMeetingPreNotification(for: meeting)
        }
    }

    // MARK: - Daily Refresh

    /// Call this method to refresh all notifications for today/tomorrow
    func refreshDailyNotifications() async {
        guard isAuthorized else { return }

        let calendarManager = CalendarManager.shared
        let userPrefs = UserPreferences.shared
        let healthKitManager = HealthKitManager.shared
        let streakManager = StreakManager.shared

        // Get tomorrow's date
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

        // Fetch tomorrow's events
        if let tomorrowEvents = try? await calendarManager.fetchEvents(for: tomorrow) {
            // Get free slots for tomorrow
            let freeSlots = (try? await calendarManager.findFreeSlots(
                for: tomorrow,
                minimumDuration: userPrefs.workoutDuration.rawValue
            )) ?? []

            // Create briefing and schedule notification
            let briefing = TomorrowBriefing(date: tomorrow, events: tomorrowEvents, freeSlots: freeSlots)
            scheduleEveningBriefing(briefing: briefing)
        }

        // Get today's events for walkable meeting reminders
        if let todayEvents = try? await calendarManager.fetchEvents(for: Date()) {
            scheduleAllWalkableMeetingReminders(for: todayEvents)
        }

        // Schedule streak-at-risk notification if user has a streak to protect
        let currentSteps = healthKitManager.todaySteps
        let goalSteps = userPrefs.dailyStepGoal
        let currentStreak = streakManager.currentStreak
        scheduleStreakAtRiskNotification(
            currentSteps: currentSteps,
            goalSteps: goalSteps,
            currentStreak: currentStreak
        )
    }

    // MARK: - Cancel Helpers

    func cancelNotification(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelNotificationsWithPrefix(_ prefix: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let idsToRemove = requests.filter { $0.identifier.hasPrefix(prefix) }.map { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: idsToRemove)
        }
    }

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // MARK: - Walk Buddy Notifications

    /// Sends a local notification suggesting a shared walk slot to the current user.
    /// (Partner receives a push via CloudKit — this notifies the current user that they've "sent" the suggestion.)
    func scheduleWalkBuddySuggestion(slot: SharedWalkSlot, partnerName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Walk with \(partnerName)?"
        content.body = "You both have a free slot at \(slot.formattedTime) (\(slot.formattedDuration)). Tap to confirm!"
        content.sound = .default
        content.categoryIdentifier = "WALK_BUDDY_SUGGESTION"
        content.userInfo = [
            "type": "walkBuddySuggestion",
            "slotTime": slot.startTime.timeIntervalSince1970,
            "slotDuration": slot.duration,
            "partnerName": partnerName
        ]

        // Fire immediately (user has already tapped "Suggest")
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let identifier = "walkBuddy-\(Int(slot.startTime.timeIntervalSince1970))"

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Legacy Support (backward compatibility)

extension NotificationManager {
    func scheduleEveningPlanNotification(for plan: DayMovementPlan) {
        // Convert legacy plan to new briefing format
        let events = plan.walkSuggestions.map { suggestion in
            CalendarEvent(
                id: UUID().uuidString,
                title: suggestion.meetingTitle,
                startDate: suggestion.startTime,
                endDate: Calendar.current.date(byAdding: .minute, value: suggestion.duration, to: suggestion.startTime) ?? suggestion.startTime,
                attendeeCount: 5,
                isOrganizer: false
            )
        }

        let freeSlots: [DateInterval] = []
        let briefing = TomorrowBriefing(date: plan.date, events: events, freeSlots: freeSlots)
        scheduleEveningBriefing(briefing: briefing)
    }

    func scheduleWalkableMeetingNotification(for event: CalendarEvent) {
        scheduleWalkableMeetingReminder(for: event)
    }

    func scheduleWalkableMeetingNotifications(for events: [CalendarEvent]) {
        scheduleAllWalkableMeetingReminders(for: events)
    }
}
