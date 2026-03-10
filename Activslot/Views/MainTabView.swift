import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: Int
    @State private var calendarTodayTapCount = 0
    @State private var showTomorrowTrigger = 0

    init() {
        #if DEBUG
        // Allow starting on specific tab via environment variable (0=MyPlan, 1=Calendar, 2=Settings)
        if let tabStr = ProcessInfo.processInfo.environment["START_TAB"],
           let tab = Int(tabStr) {
            _selectedTab = State(initialValue: tab)
        } else {
            _selectedTab = State(initialValue: 0)
        }
        #else
        _selectedTab = State(initialValue: 0)
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                SmartPlanView(showTomorrowTrigger: showTomorrowTrigger)
                    .tabItem {
                        Label("My Plan", systemImage: "list.bullet.clipboard")
                    }
                    .tag(0)

                ActivslotCalendarView(resetToTodayTrigger: calendarTodayTapCount)
                    .tabItem {
                        Label("Calendar", systemImage: "calendar")
                    }
                    .tag(1)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(2)
            }
            .tint(.green)

            // Invisible button overlay on Calendar tab to detect re-tap
            GeometryReader { geometry in
                let tabWidth = geometry.size.width / 3

                Color.clear
                    .frame(width: tabWidth, height: 49)
                    .contentShape(Rectangle())
                    .position(x: tabWidth * 1.5, y: geometry.size.height - 24.5)
                    .onTapGesture {
                        if selectedTab == 1 {
                            calendarTodayTapCount += 1
                        } else {
                            selectedTab = 1
                        }
                    }
            }
        }
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { notification in
            if let index = notification.userInfo?["index"] as? Int {
                selectedTab = index
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDayPlan)) { _ in
            selectedTab = 0
            showTomorrowTrigger += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSmartPlan)) { _ in
            selectedTab = 0
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(HealthKitManager.shared)
        .environmentObject(UserPreferences.shared)
        .environmentObject(CalendarManager.shared)
}
