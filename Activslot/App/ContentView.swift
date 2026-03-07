import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showWalkBuddy = false
    @State private var showPaywall = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingContainerView()
            }
        }
        #if DEBUG
        .sheet(isPresented: $showWalkBuddy) {
            NavigationStack {
                CoupleWalkView()
                    .navigationTitle("Walk Buddy")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showWalkBuddy = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openWalkBuddy)) { _ in
            showPaywall = false
            showWalkBuddy = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissSheet)) { _ in
            showWalkBuddy = false
            showPaywall = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPaywall)) { _ in
            showWalkBuddy = false
            showPaywall = true
        }
        #endif
    }
}

#Preview {
    ContentView()
}
