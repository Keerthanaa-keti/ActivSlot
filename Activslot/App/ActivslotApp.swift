import SwiftUI
import UserNotifications
import BackgroundTasks

@main
struct ActivslotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var calendarManager = CalendarManager.shared
    @StateObject private var userPreferences = UserPreferences.shared
    @StateObject private var outlookManager = OutlookManager.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .environmentObject(calendarManager)
                .environmentObject(userPreferences)
                .environmentObject(outlookManager)
                .environmentObject(notificationManager)
                .environmentObject(subscriptionManager)
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
                .task {
                    // Initial sync on launch (scenePhase onChange doesn't fire on first launch)
                    handleScenePhaseChange(.active)
                }
                #if DEBUG
                .task {
                    await runDebugTestScenarioIfRequested()
                }
                .onOpenURL { url in
                    handleDebugURL(url)
                }
                #endif
        }
    }

    #if DEBUG
    /// Handles activslot:// deep links for simulator testing.
    ///   activslot://test/<scenario>   — data scenarios
    ///   activslot://action/autopilot  — trigger autopilot walk scheduling
    ///   activslot://action/notify     — fire a test walk-buddy notification
    private func handleDebugURL(_ url: URL) {
        guard url.scheme == "activslot" else { return }
        let host     = url.host ?? ""
        let segment  = url.pathComponents.dropFirst().first ?? ""
        print("DEBUG URL: activslot://\(host)/\(segment)")

        Task {
            switch (host, segment) {

            // ── test scenarios ───────────────────────────────────────────
            case ("test", "sarah"):        await TestDataManager.shared.setupSarahScenario()
            case ("test", "alex"):         await TestDataManager.shared.setupAlexScenario()
            case ("test", "walk_buddy"):   await TestDataManager.shared.setupWalkBuddyTestScenario()
            case ("test", "walk_buddy_b"): await TestDataManager.shared.setupWalkBuddyTestScenarioB()
            case ("test", "busy"):         await TestDataManager.shared.setupBusyExecutiveScenario()
            case ("test", "light"):        await TestDataManager.shared.setupLightDayScenario()
            case ("test", "almost_goal"):  await TestDataManager.shared.setupAlmostThereScenario()
            case ("test", "goal_reached"): await TestDataManager.shared.setupGoalReachedScenario()
            case ("test", "clear"):        await TestDataManager.shared.clearAllTestData()

            // ── actions ───────────────────────────────────────────────────
            case ("action", "autopilot"):
                // Schedule walks for TODAY (not just tomorrow) for immediate testing
                await AutopilotManager.shared.scheduleWalksForTomorrow()
                print("DEBUG: Autopilot scheduling triggered")

            case ("action", "notify"):
                // Fire a test walk-buddy suggestion notification immediately
                let testSlot = SharedWalkSlot(
                    startTime: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date(),
                    duration: 30,
                    confidenceScore: 0.9
                )
                NotificationManager.shared.scheduleWalkBuddySuggestion(
                    slot: testSlot,
                    partnerName: CoupleWalkManager.shared.partnerProfile?.partnerName ?? "Your Partner"
                )
                print("DEBUG: Walk buddy notification scheduled")

            case ("action", "behind"):
                // Trigger a "behind on steps" notification for testing
                await NotificationManager.shared.scheduleBehindOnStepsNotification(
                    deficit: 3000, suggestedSlot: nil)
                print("DEBUG: Behind-on-steps notification scheduled")

            case ("navigate", "walk_buddy"):
                NotificationCenter.default.post(name: .openWalkBuddy, object: nil)
                print("DEBUG: Navigating to Walk Buddy")

            case ("navigate", "tab"):
                // activslot://navigate/tab?index=0|1|2
                if let query = url.query, let idx = Int(query.replacingOccurrences(of: "index=", with: "")) {
                    NotificationCenter.default.post(name: .switchTab, object: nil, userInfo: ["index": idx])
                }

            case ("navigate", "dismiss"):
                NotificationCenter.default.post(name: .dismissSheet, object: nil)

            case ("navigate", "paywall"):
                NotificationCenter.default.post(name: .openPaywall, object: nil)

            default:
                print("DEBUG URL: unknown route activslot://\(host)/\(segment)")
            }
        }
    }

    /// Runs a test scenario based on launch argument or environment variable
    /// Usage: Set TEST_SCENARIO environment variable to one of:
    /// - "busy_executive", "light_day", "almost_goal", "goal_reached", "walkable_meetings", "full_test"
    private func runDebugTestScenarioIfRequested() async {
        // Check for test scenario from environment variable
        guard let scenario = ProcessInfo.processInfo.environment["TEST_SCENARIO"] else {
            return
        }

        print("DEBUG: Running test scenario: \(scenario)")

        let testManager = TestDataManager.shared

        switch scenario.lowercased() {
        case "busy_executive":
            await testManager.setupBusyExecutiveScenario()
        case "light_day":
            await testManager.setupLightDayScenario()
        case "almost_goal":
            await testManager.setupAlmostThereScenario()
        case "goal_reached":
            await testManager.setupGoalReachedScenario()
        case "walkable_meetings":
            await testManager.setupWalkableMeetingsScenario()
        case "full_test":
            await testManager.generateFullTestScenario()
        case "clear":
            await testManager.clearAllTestData()
        case "production_tests":
            // Production tests - run from TestDataManager
            print("Production tests available in TestDataManager")
        default:
            print("DEBUG: Unknown test scenario: \(scenario)")
        }

        print("DEBUG: Test scenario '\(scenario)' completed")
    }
    #endif

    /// Tracks when the app last completed a full foreground refresh
    private static var lastForegroundRefresh: Date?

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // App became active - refresh notification authorization status
            NotificationManager.shared.checkAuthorizationStatus()

            // Skip full refresh if app was backgrounded for less than 5 minutes
            let now = Date()
            if let lastRefresh = Self.lastForegroundRefresh,
               now.timeIntervalSince(lastRefresh) < 300 {
                // Still refresh calendar events (lightweight) but skip heavy operations
                Task {
                    await calendarManager.refreshEvents()
                }
                return
            }
            Self.lastForegroundRefresh = now

            // Refresh calendar data and regenerate plans
            Task {
                // Refresh calendar events first
                await calendarManager.refreshEvents()

                // Analyze walking patterns if not yet loaded
                let planner = SmartPlannerEngine.shared
                if planner.dayOfWeekPatterns == nil {
                    await planner.analyzeDayOfWeekPatterns()
                }

                // Regenerate movement plans with updated calendar data
                await MovementPlanManager.shared.generatePlans()

                // Continuous optimization for smart daily planning
                // Checks cooldowns, active hours, and step progress internally
                await DailyPlanSyncCoordinator.shared.optimizeIfNeeded()

                // Check and evaluate checkpoints if we're at a checkpoint time
                await DailyPlanSyncCoordinator.shared.checkAndEvaluateCheckpoints()

                // Refresh daily notifications and autopilot scheduling
                await NotificationManager.shared.refreshDailyNotifications()
                await AutopilotManager.shared.scheduleWalksForTomorrow()
            }

        case .background:
            // App went to background - good time to schedule notifications and autopilot walks
            Task {
                await NotificationManager.shared.refreshDailyNotifications()
                await AutopilotManager.shared.scheduleWalksForTomorrow()

                // Evening sync for tomorrow's plan (if past sync time)
                let hour = Calendar.current.component(.hour, from: Date())
                let prefs = UserPreferences.shared
                if hour >= prefs.smartPlanSyncTimeHour {
                    await DailyPlanSyncCoordinator.shared.syncTomorrowPlan()
                }

                // Cleanup old managed events
                DailyPlanSyncCoordinator.shared.cleanupOldManagedEvents()
            }

        case .inactive:
            break

        @unknown default:
            break
        }
    }
}

// MARK: - Background Task Identifiers

enum BackgroundTaskIdentifier {
    static let eveningPlanSync = "com.activslot.healthapp.eveningPlanSync"
    static let checkpointEvaluation = "com.activslot.healthapp.checkpointEvaluation"
}

// MARK: - App Delegate for Notification Handling

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Register notification categories (for action buttons)
        NotificationManager.shared.registerNotificationCategories()

        // Register background tasks
        registerBackgroundTasks()

        return true
    }

    // MARK: - Background Task Registration

    private func registerBackgroundTasks() {
        // Register evening plan sync task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.eveningPlanSync,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleEveningPlanSync(task: refreshTask)
        }

        // Register checkpoint evaluation task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.checkpointEvaluation,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleCheckpointEvaluation(task: refreshTask)
        }

        // Schedule initial tasks
        scheduleEveningPlanSyncTask()
        scheduleNextCheckpointTask()
    }

    private func handleEveningPlanSync(task: BGAppRefreshTask) {
        // Set expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            let prefs = UserPreferences.shared
            guard prefs.smartPlanAutoSyncEnabled else {
                task.setTaskCompleted(success: true)
                return
            }

            // Analyze patterns if needed
            await SmartPlannerEngine.shared.analyzeDayOfWeekPatterns()

            // Generate and sync tomorrow's plan
            await DailyPlanSyncCoordinator.shared.syncTomorrowPlan()

            task.setTaskCompleted(success: true)

            // Schedule next evening sync
            self.scheduleEveningPlanSyncTask()
        }
    }

    private func handleCheckpointEvaluation(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        Task {
            let prefs = UserPreferences.shared
            guard prefs.smartPlanAutoSyncEnabled && prefs.smartPlanCheckpointsEnabled else {
                task.setTaskCompleted(success: true)
                return
            }

            // Evaluate current checkpoint
            await DailyPlanSyncCoordinator.shared.evaluateCheckpoint()

            task.setTaskCompleted(success: true)

            // Schedule next checkpoint
            self.scheduleNextCheckpointTask()
        }
    }

    func scheduleEveningPlanSyncTask() {
        let prefs = UserPreferences.shared
        let calendar = Calendar.current

        // Schedule for sync time (default 8 PM)
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = prefs.smartPlanSyncTimeHour
        components.minute = prefs.smartPlanSyncTimeMinute

        guard var scheduledDate = calendar.date(from: components) else { return }

        // If it's already past the sync time, schedule for tomorrow
        if scheduledDate <= Date() {
            scheduledDate = calendar.date(byAdding: .day, value: 1, to: scheduledDate) ?? scheduledDate
        }

        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifier.eveningPlanSync)
        request.earliestBeginDate = scheduledDate

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("Scheduled evening plan sync for \(scheduledDate)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to schedule evening plan sync: \(error)")
            #endif
        }
    }

    func scheduleNextCheckpointTask() {
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)

        // Find next checkpoint hour (10, 13, 16, 19)
        let checkpointHours = SmartPlannerEngine.DayCheckpoints.defaultCheckpointHours
        var nextCheckpointHour: Int?

        for hour in checkpointHours {
            if hour > currentHour {
                nextCheckpointHour = hour
                break
            }
        }

        // If no checkpoint left today, schedule for first checkpoint tomorrow
        guard let targetHour = nextCheckpointHour else {
            // Schedule for first checkpoint tomorrow
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
                components.hour = checkpointHours.first ?? 10
                components.minute = 0

                if let scheduledDate = calendar.date(from: components) {
                    submitCheckpointTask(at: scheduledDate)
                }
            }
            return
        }

        // Schedule for next checkpoint today
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = targetHour
        components.minute = 0

        if let scheduledDate = calendar.date(from: components) {
            submitCheckpointTask(at: scheduledDate)
        }
    }

    private func submitCheckpointTask(at date: Date) {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifier.checkpointEvaluation)
        request.earliestBeginDate = date

        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("Scheduled checkpoint evaluation for \(date)")
            #endif
        } catch {
            #if DEBUG
            print("Failed to schedule checkpoint evaluation: \(error)")
            #endif
        }
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification banner even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification action (user tapped on notification or action button)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier

        // Handle different notification types
        if let notificationType = userInfo["type"] as? String {
            switch notificationType {
            case "eveningBriefing":
                handleEveningBriefingAction(actionIdentifier, userInfo: userInfo)

            case "walkableMeeting":
                handleWalkableMeetingAction(actionIdentifier, userInfo: userInfo)

            case "workoutReminder":
                handleWorkoutReminderAction(actionIdentifier, userInfo: userInfo)

            case "planReady":
                handlePlanReadyAction(actionIdentifier, userInfo: userInfo)

            case "behindOnSteps":
                handleBehindOnStepsAction(actionIdentifier, userInfo: userInfo)

            case "walkableMeetingPre":
                handleWalkableMeetingAction(actionIdentifier, userInfo: userInfo)

            default:
                break
            }
        }

        completionHandler()
    }

    private func handleEveningBriefingAction(_ action: String, userInfo: [AnyHashable: Any]) {
        switch action {
        case "PLAN_DAY", UNNotificationDefaultActionIdentifier:
            // User wants to plan - app opens to home view automatically
            // Could post a notification to navigate to a specific view if needed
            NotificationCenter.default.post(name: .openDayPlan, object: nil, userInfo: userInfo)

        case "DISMISS":
            break

        default:
            break
        }
    }

    private func handleWalkableMeetingAction(_ action: String, userInfo: [AnyHashable: Any]) {
        switch action {
        case "START_WALKING", UNNotificationDefaultActionIdentifier:
            // User wants to start walking - could start a walk tracking session
            NotificationCenter.default.post(name: .startWalkSession, object: nil, userInfo: userInfo)

        case "SKIP":
            break

        default:
            break
        }
    }

    private func handleWorkoutReminderAction(_ action: String, userInfo: [AnyHashable: Any]) {
        switch action {
        case "START_WORKOUT", UNNotificationDefaultActionIdentifier:
            // User wants to start workout
            NotificationCenter.default.post(name: .startWorkoutSession, object: nil, userInfo: userInfo)

        case "SNOOZE":
            // Schedule another reminder in 15 minutes
            let snoozeTime = Date().addingTimeInterval(15 * 60)
            NotificationManager.shared.scheduleWorkoutReminder(at: snoozeTime, message: "Snoozed reminder - time to workout!")

        default:
            break
        }
    }

    private func handlePlanReadyAction(_ action: String, userInfo: [AnyHashable: Any]) {
        switch action {
        case "VIEW_PLAN", UNNotificationDefaultActionIdentifier:
            // Navigate to smart plan view
            NotificationCenter.default.post(name: .openSmartPlan, object: nil, userInfo: userInfo)

        default:
            break
        }
    }

    private func handleBehindOnStepsAction(_ action: String, userInfo: [AnyHashable: Any]) {
        switch action {
        case "ADD_WALK", UNNotificationDefaultActionIdentifier:
            // Open app to add catch-up walk
            NotificationCenter.default.post(name: .addCatchUpWalk, object: nil, userInfo: userInfo)

        default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openDayPlan = Notification.Name("openDayPlan")
    static let startWalkSession = Notification.Name("startWalkSession")
    static let startWorkoutSession = Notification.Name("startWorkoutSession")
    static let openSmartPlan = Notification.Name("openSmartPlan")
    static let addCatchUpWalk = Notification.Name("addCatchUpWalk")
    static let openWalkBuddy = Notification.Name("openWalkBuddy")
    static let switchTab = Notification.Name("switchTab")
    static let dismissSheet = Notification.Name("dismissSheet")
    static let openPaywall = Notification.Name("openPaywall")
}
