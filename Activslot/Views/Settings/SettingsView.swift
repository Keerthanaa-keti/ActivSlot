import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var userPreferences: UserPreferences
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var outlookManager: OutlookManager

    @StateObject private var notificationManager = NotificationManager.shared
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    @State private var showResetConfirmation = false
    @State private var showCalendarSelection = false
    @State private var showOutlookError = false
    @State private var outlookErrorMessage = ""
    @State private var showPaywall = false
    @State private var showRedeemCode = false
    @State private var versionTapCount = 0
    @State private var showDebugUnlocked = false
    #if DEBUG
    @State private var showTestDataGenerator = false
    @AppStorage("debugToolsEnabled") private var debugToolsEnabled = false
    #endif

    // Time picker states
    @State private var wakeTime: Date = Date()
    @State private var sleepTime: Date = Date()
    @State private var breakfastTime: Date = Date()
    @State private var lunchTime: Date = Date()
    @State private var dinnerTime: Date = Date()

    var body: some View {
        NavigationStack {
            List {
                // ActivSlot Pro Section
                if !subscriptionManager.isProUser {
                    Section {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.title2)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.orange, .pink],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("ActivSlot Pro")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                    Text("Autopilot, insights, walk buddy & more")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text("Upgrade")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [.orange, .pink],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    )
                            }
                        }
                    } header: {
                        Text("ActivSlot Pro")
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ActivSlot Pro")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("All features unlocked")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("Active")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                }

                // Daily Schedule Section
                Section {
                    TimePickerRow(
                        title: "Wake Up",
                        icon: "sunrise.fill",
                        iconColor: .orange,
                        time: $wakeTime
                    )
                    .onChange(of: wakeTime) { _, newValue in
                        userPreferences.wakeTime = TimeOfDay.from(date: newValue)
                    }

                    TimePickerRow(
                        title: "Sleep",
                        icon: "moon.fill",
                        iconColor: .indigo,
                        time: $sleepTime
                    )
                    .onChange(of: sleepTime) { _, newValue in
                        userPreferences.sleepTime = TimeOfDay.from(date: newValue)
                    }
                } header: {
                    Text("Daily Schedule")
                } footer: {
                    Text("Active hours: \(userPreferences.activeHours)h - Target \(userPreferences.stepsPerHour) steps/hour")
                }

                // Meal Times Section
                Section {
                    TimePickerRow(
                        title: "Breakfast",
                        icon: "cup.and.saucer.fill",
                        iconColor: .brown,
                        time: $breakfastTime
                    )
                    .onChange(of: breakfastTime) { _, newValue in
                        userPreferences.breakfastTime = TimeOfDay.from(date: newValue)
                    }

                    TimePickerRow(
                        title: "Lunch",
                        icon: "fork.knife",
                        iconColor: .green,
                        time: $lunchTime
                    )
                    .onChange(of: lunchTime) { _, newValue in
                        userPreferences.lunchTime = TimeOfDay.from(date: newValue)
                    }

                    TimePickerRow(
                        title: "Dinner",
                        icon: "fork.knife.circle.fill",
                        iconColor: .red,
                        time: $dinnerTime
                    )
                    .onChange(of: dinnerTime) { _, newValue in
                        userPreferences.dinnerTime = TimeOfDay.from(date: newValue)
                    }
                } header: {
                    Text("Meal Times")
                } footer: {
                    Text("Walk suggestions are avoided during meal times")
                }

                // Calendar Section - Consolidated
                Section {
                    // Connected calendars summary
                    if calendarManager.hasOutlookCalendar || calendarManager.hasGoogleCalendar || outlookManager.isSignedIn {
                        if outlookManager.isSignedIn {
                            ConnectedCalendarRow(
                                icon: "envelope.fill",
                                iconColor: .blue,
                                title: "Outlook",
                                subtitle: outlookManager.userEmail ?? "Connected"
                            )
                        } else if calendarManager.hasOutlookCalendar {
                            ConnectedCalendarRow(
                                icon: "envelope.fill",
                                iconColor: .blue,
                                title: "Outlook via iOS",
                                subtitle: "Synced through iPhone Calendar"
                            )
                        }

                        if calendarManager.hasGoogleCalendar {
                            ConnectedCalendarRow(
                                icon: "g.circle.fill",
                                iconColor: .red,
                                title: "Google Calendar",
                                subtitle: "Synced through iPhone Calendar"
                            )
                        }
                    }

                    // Connect work calendar
                    NavigationLink {
                        WorkCalendarSetupView()
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            Text("Connect Work Calendar")
                                .font(.subheadline)
                        }
                    }

                    // Manage calendars
                    Button {
                        showCalendarSelection = true
                    } label: {
                        HStack {
                            Image(systemName: "checklist")
                                .foregroundColor(.green)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Choose Calendars")
                                    .foregroundColor(.primary)
                                if calendarManager.isAuthorized {
                                    Text("\(calendarManager.selectedCalendarIDs.count) of \(calendarManager.availableCalendars.count) selected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    // Export to calendar (Pro)
                    if subscriptionManager.isProUser {
                        NavigationLink {
                            CalendarSyncSettingsView()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                Text("Export Walks to Calendar")
                                    .font(.subheadline)
                            }
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.blue)
                                    .frame(width: 28)
                                Text("Export Walks to Calendar")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Spacer()
                                ProBadge()
                            }
                        }
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Connect your work calendar so we can find walking time between meetings")
                }

                // Walk Buddy Section
                Section {
                    if subscriptionManager.isProUser {
                        NavigationLink {
                            CoupleWalkView()
                        } label: {
                            HStack {
                                Image(systemName: "figure.2.and.child.holdinghands")
                                    .foregroundColor(.purple)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Walk Buddy")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text("Find shared walk times with a partner")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "figure.2.and.child.holdinghands")
                                    .foregroundColor(.purple)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Walk Buddy")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Text("Find shared walk times with a partner")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                ProBadge()
                            }
                        }
                    }
                } header: {
                    Text("Walk Buddy")
                } footer: {
                    Text("Share your availability with a partner to find walk times that work for both of you")
                }

                // Step Goal with Age-Based Suggestions
                Section {
                    Picker("Your Age Group", selection: Binding(
                        get: { userPreferences.ageGroup },
                        set: { userPreferences.ageGroup = $0 }
                    )) {
                        Text("Not set").tag(nil as AgeGroup?)
                        ForEach(AgeGroup.allCases, id: \.self) { age in
                            Text(age.rawValue).tag(age as AgeGroup?)
                        }
                    }

                    Stepper(
                        "Daily step goal: \(userPreferences.dailyStepGoal.formatted())",
                        value: Binding(
                            get: { userPreferences.dailyStepGoal },
                            set: { userPreferences.dailyStepGoal = $0 }
                        ),
                        in: 3000...20000,
                        step: 500
                    )

                    if let age = userPreferences.ageGroup {
                        Button("Apply Recommended: \(age.recommendedSteps.formatted()) steps") {
                            userPreferences.dailyStepGoal = age.recommendedSteps
                        }
                        .font(.caption)
                    }

                    Picker("Preferred walk time", selection: Binding(
                        get: { userPreferences.preferredWalkTime },
                        set: { userPreferences.preferredWalkTime = $0 }
                    )) {
                        ForEach(PreferredWalkTime.allCases, id: \.self) { time in
                            Text(time.rawValue).tag(time)
                        }
                    }
                } header: {
                    Text("Step Goal")
                } footer: {
                    if let age = userPreferences.ageGroup {
                        Text("Recommended for \(age.rawValue): \(age.recommendedSteps.formatted()) steps/day. Walk suggestions will prioritize your preferred time.")
                    } else {
                        Text("Walk suggestions will prioritize your preferred time of day")
                    }
                }

                // Smart Planning
                Section {
                    NavigationLink {
                        SmartPlanningSettingsView()
                            .environmentObject(userPreferences)
                            .environmentObject(calendarManager)
                    } label: {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.green)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Smart Planning")
                                    .foregroundColor(.primary)
                                Text("Goal-based daily plans")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(userPreferences.dailyStepGoal.formatted()) steps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Intelligent Planning")
                } footer: {
                    Text("The app learns your patterns and creates personalized plans to hit your step goal.")
                }

                // Your Journey / Identity
                Section {
                    NavigationLink {
                        IdentityProfileView()
                            .environmentObject(userPreferences)
                    } label: {
                        HStack {
                            Image(systemName: userPreferences.identityLevel.icon)
                                .foregroundColor(.purple)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Your Journey")
                                    .foregroundColor(.primary)
                                Text(userPreferences.identityLevel.title)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if userPreferences.currentStreak > 0 {
                                HStack(spacing: 4) {
                                    Text("\(userPreferences.currentStreak)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                    Image(systemName: "flame.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Progress")
                } footer: {
                    let total = userPreferences.totalWalksCompleted + userPreferences.totalWorkoutsCompleted
                    Text("\(total) total activities completed")
                }

                // Notifications
                Section {
                    if notificationManager.isAuthorized {
                        // Evening Briefing
                        Toggle(isOn: $notificationManager.eveningBriefingEnabled) {
                            HStack {
                                Image(systemName: "moon.stars.fill")
                                    .foregroundColor(.indigo)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Evening Briefing")
                                    Text("Preview tomorrow's schedule")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if notificationManager.eveningBriefingEnabled {
                            DatePicker(
                                "Briefing Time",
                                selection: $notificationManager.eveningBriefingTime,
                                displayedComponents: .hourAndMinute
                            )
                            .padding(.leading, 36)
                        }

                        // Walkable Meeting Reminders (Pro)
                        if subscriptionManager.isProUser {
                            Toggle(isOn: $notificationManager.walkableMeetingRemindersEnabled) {
                                HStack {
                                    Image(systemName: "figure.walk")
                                        .foregroundColor(.green)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Walk-This-Call Alerts")
                                        Text("Reminder before walkable meetings")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            if notificationManager.walkableMeetingRemindersEnabled {
                                Picker("Remind me", selection: $notificationManager.walkableMeetingLeadTime) {
                                    Text("5 min before").tag(5)
                                    Text("10 min before").tag(10)
                                    Text("15 min before").tag(15)
                                }
                                .padding(.leading, 36)
                            }
                        } else {
                            Button {
                                showPaywall = true
                            } label: {
                                HStack {
                                    Image(systemName: "figure.walk")
                                        .foregroundColor(.green)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Walk-This-Call Alerts")
                                            .foregroundColor(.primary)
                                        Text("Reminder before walkable meetings")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    ProBadge()
                                }
                            }
                        }

                    } else {
                        // Request Notification Permission
                        Button {
                            Task {
                                _ = try? await notificationManager.requestAuthorization()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bell.badge.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enable Notifications")
                                        .foregroundColor(.primary)
                                    Text("Get timely alerts for walks & workouts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    if notificationManager.isAuthorized {
                        Text("Evening briefings help you plan tomorrow. Walk-this-call alerts remind you before walkable meetings.")
                    } else {
                        Text("Enable notifications to receive smart reminders about your fitness schedule")
                    }
                }

                // Permissions Status
                Section {
                    HStack {
                        Label("Apple Health", systemImage: "heart.fill")
                        Spacer()
                        if healthKitManager.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Text("Not connected")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Label("Calendar", systemImage: "calendar")
                        Spacer()
                        if calendarManager.isAuthorized {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Text("Not connected")
                                .foregroundColor(.secondary)
                        }
                    }

                    if !healthKitManager.isAuthorized || !calendarManager.isAuthorized {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } header: {
                    Text("Permissions")
                }

                // Support
                Section {
                    NavigationLink {
                        FeedbackView()
                    } label: {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Send Feedback")
                                    .foregroundColor(.primary)
                                Text("support@thunaiapp.com")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Button {
                        requestAppStoreReview()
                    } label: {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .frame(width: 28)
                            Text("Rate on App Store")
                                .foregroundColor(.primary)
                        }
                    }
                } header: {
                    Text("Support")
                }

                // About
                Section {
                    Button {
                        handleVersionTap()
                    } label: {
                        HStack {
                            Text("Version")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(Bundle.main.appVersion)
                                .foregroundColor(.secondary)
                        }
                    }

                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Text("Privacy Policy")
                    }

                    NavigationLink {
                        TermsOfServiceView()
                    } label: {
                        Text("Terms of Service")
                    }

                    if subscriptionManager.isProUser {
                        Button("Manage Subscription") {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }

                    if !subscriptionManager.isProUser {
                        Button {
                            showRedeemCode = true
                        } label: {
                            HStack {
                                Image(systemName: "gift.fill")
                                    .foregroundColor(.orange)
                                Text("Redeem Gift Code")
                            }
                        }
                    } else if subscriptionManager.giftCodeRedeemed {
                        HStack {
                            Image(systemName: "gift.fill")
                                .foregroundColor(.green)
                            Text("Gift Code Active")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button("Reset Onboarding") {
                        showResetConfirmation = true
                    }
                    .foregroundColor(.red)
                } header: {
                    Text("About")
                }

                #if DEBUG
                if debugToolsEnabled {
                    Section {
                        Button {
                            showTestDataGenerator = true
                        } label: {
                            HStack {
                                Image(systemName: "testtube.2")
                                    .foregroundColor(.purple)
                                Text("Test Data Generator")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }

                        Button {
                            Task {
                                try? await calendarManager.createSampleEventsForTesting()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                    .foregroundColor(.blue)
                                Text("Create Sample Schedule")
                            }
                        }

                        Button {
                            Task {
                                try? await calendarManager.clearTodayEvents()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                Text("Clear Today's Events")
                            }
                        }

                        Button("Hide Debug Tools") {
                            debugToolsEnabled = false
                        }
                        .foregroundColor(.secondary)
                        .font(.caption)
                    } header: {
                        Text("Developer")
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .onAppear {
                loadTimeValues()
            }
            .alert("Reset Onboarding?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                }
            } message: {
                Text("This will show the onboarding screens again next time you open the app.")
            }
            .alert("Outlook Error", isPresented: $showOutlookError) {
                Button("OK") {}
            } message: {
                Text(outlookErrorMessage)
            }
            .sheet(isPresented: $showCalendarSelection) {
                CalendarSelectionView()
                    .environmentObject(calendarManager)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .sheet(isPresented: $showRedeemCode) {
                RedeemGiftCodeView()
            }
            .alert("Developer Mode", isPresented: $showDebugUnlocked) {
                Button("OK") {}
            } message: {
                Text("Debug tools are now visible at the bottom of Settings.")
            }
            #if DEBUG
            .sheet(isPresented: $showTestDataGenerator) {
                TestDataGeneratorView()
            }
            #endif
        }
    }

    private func loadTimeValues() {
        wakeTime = userPreferences.wakeTime.date
        sleepTime = userPreferences.sleepTime.date
        breakfastTime = userPreferences.breakfastTime.date
        lunchTime = userPreferences.lunchTime.date
        dinnerTime = userPreferences.dinnerTime.date
    }

    private func handleVersionTap() {
        #if DEBUG
        versionTapCount += 1
        if versionTapCount >= 7 && !debugToolsEnabled {
            debugToolsEnabled = true
            showDebugUnlocked = true
            versionTapCount = 0
        }
        #endif
    }

    private func requestAppStoreReview() {
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}

// MARK: - Connected Calendar Row

struct ConnectedCalendarRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        }
    }
}

// MARK: - Time Picker Row

struct TimePickerRow: View {
    let title: String
    let icon: String
    let iconColor: Color
    @Binding var time: Date

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 28)

            Text(title)

            Spacer()

            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(UserPreferences.shared)
        .environmentObject(HealthKitManager.shared)
        .environmentObject(CalendarManager.shared)
        .environmentObject(OutlookManager.shared)
}
