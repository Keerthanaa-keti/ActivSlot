import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showWalkBuddy = false

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
        .onReceive(NotificationCenter.default.publisher(for: .openWalkBuddy)) { _ in
            showWalkBuddy = true
        }
        #endif
    }
}

#Preview {
    ContentView()
}
