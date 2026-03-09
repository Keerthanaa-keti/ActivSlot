import SwiftUI

// MARK: - Onboarding Container
// Streamlined onboarding based on Hooked framework:
// 1. Hook (Value Proposition) - Show the promise
// 2. Enable (Permissions) - Get Health & Calendar access
// 3. Calendar (Connect work calendar)
// 4. Notifications - Enable smart alerts
// 5. Walk Buddy - Connect a partner (optional)
// 6. Reward (Smart Planner) - Deliver immediate value

struct OnboardingContainerView: View {
    @StateObject private var userPreferences = UserPreferences.shared
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var outlookManager: OutlookManager

    @State private var currentPage = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let totalPages = 6

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                // Step 1: Hook - Show the value
                ValuePropositionView(onContinue: { currentPage = 1 })
                    .tag(0)

                // Step 2: Enable - Get permissions
                PermissionsView(onContinue: { currentPage = 2 })
                    .environmentObject(healthKitManager)
                    .environmentObject(calendarManager)
                    .environmentObject(outlookManager)
                    .tag(1)

                // Step 3: Connect work calendar instructions
                CalendarConnectionGuideView(onContinue: { currentPage = 3 })
                    .tag(2)

                // Step 4: Notifications - Enable smart alerts
                NotificationsOnboardingView(onContinue: { currentPage = 4 })
                    .tag(3)

                // Step 5: Walk Buddy - Connect a partner
                WalkBuddyOnboardingView(onContinue: { currentPage = 5 })
                    .tag(4)

                // Step 6: Reward - Show immediate value with their data
                SmartPlannerIntroView(onContinue: {
                    completeOnboarding()
                })
                .environmentObject(userPreferences)
                .environmentObject(calendarManager)
                .tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Progress indicator
            OnboardingProgressBar(currentStep: currentPage, totalSteps: totalPages)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
        }
        .background(Color(.systemBackground))
    }

    private func completeOnboarding() {
        // Mark onboarding complete
        hasCompletedOnboarding = true

        // Auto-enable calendar sync so walks appear in user's calendar
        CalendarSyncService.shared.autoSyncEnabled = true
        UserPreferences.shared.smartPlanAutoSyncEnabled = true

        // Auto-select default calendar for walk sync if none set
        Task {
            let calendarManager = CalendarManager.shared
            if calendarManager.isAuthorized {
                // Pick the default calendar for events
                let calendars = calendarManager.availableCalendars
                if let defaultCalendar = calendars.first(where: { $0.allowsModifications }) {
                    UserPreferences.shared.smartPlanCalendarID = defaultCalendar.calendarIdentifier
                }
            }

            let notificationManager = NotificationManager.shared
            if notificationManager.isAuthorized {
                // Schedule first evening briefing
                let briefing = TomorrowBriefing(
                    date: Date().addingTimeInterval(86400),
                    events: [],
                    freeSlots: []
                )
                notificationManager.scheduleEveningBriefing(briefing: briefing)
            }
        }
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStep ? Color.green : Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }
}

#Preview {
    OnboardingContainerView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(CalendarManager.shared)
        .environmentObject(OutlookManager.shared)
}
