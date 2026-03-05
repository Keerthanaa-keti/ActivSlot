import SwiftUI

// MARK: - Onboarding Container
// Streamlined 3-step onboarding based on Hooked framework:
// 1. Hook (Value Proposition) - Show the promise
// 2. Enable (Permissions) - Get necessary access
// 3. Reward (Smart Planner) - Deliver immediate value

struct OnboardingContainerView: View {
    @StateObject private var userPreferences = UserPreferences.shared
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var outlookManager: OutlookManager

    @State private var currentPage = 0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let totalPages = 4

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

                // Step 4: Reward - Show immediate value with their data
                SmartPlannerIntroView(onContinue: {
                    completeOnboarding()
                })
                .environmentObject(userPreferences)
                .environmentObject(calendarManager)
                .tag(3)
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

        // Schedule notifications
        Task {
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
