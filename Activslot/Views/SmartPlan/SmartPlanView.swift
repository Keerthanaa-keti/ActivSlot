import SwiftUI

struct SmartPlanView: View {
    @EnvironmentObject var userPreferences: UserPreferences
    @StateObject private var planner = SmartPlannerEngine.shared

    @State private var selectedDate = Date()
    @State private var isRefreshing = false
    @State private var showingActivityDetail: SmartPlannerEngine.PlannedActivity?
    @State private var showingWalkableMeetings = false
    @State private var todayEvents: [CalendarEvent] = []
    @State private var showTimeline = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Step Goal Progress Card
                    if let plan = planner.currentDayPlan {
                        SmartStepProgressCard(plan: plan)
                    }

                    // Checkpoint Progress Bar
                    CheckpointProgressCard(
                        currentSteps: planner.currentDayPlan?.estimatedCurrentSteps ?? 0,
                        goalSteps: userPreferences.dailyStepGoal
                    )

                    // Walk Pattern Graph - shows user's typical activity for this day of week
                    let patternData = planner.getHourlyPatternData(for: selectedDate)
                    let explanation = planner.getPatternExplanation(for: selectedDate)
                    let dayName = Calendar.current.weekdaySymbols[Calendar.current.component(.weekday, from: selectedDate) - 1]

                    if !patternData.isEmpty {
                        WalkPatternGraphCard(
                            patternData: patternData,
                            explanation: explanation,
                            dayName: dayName
                        )
                        .premiumGated(.insights)
                    }

                    // Day Timeline (Visual Overview)
                    if let plan = planner.currentDayPlan, !todayEvents.isEmpty {
                        DayTimelineView(plan: plan, events: todayEvents)
                            .environmentObject(userPreferences)
                            .premiumGated(.insights)
                    }

                    // Today's Plan
                    if let plan = planner.currentDayPlan {
                        DailyPlanSection(
                            plan: plan,
                            onActivityTap: { activity in
                                showingActivityDetail = activity
                            },
                            onComplete: { activity in
                                planner.recordActivityCompleted(activity.id)
                                refreshPlan()
                            },
                            onSkip: { activity in
                                planner.recordActivitySkipped(activity.id)
                                refreshPlan()
                            }
                        )

                        // Walkable Meetings
                        if !plan.walkableMeetings.isEmpty {
                            WalkableMeetingsSection(meetings: plan.walkableMeetings)
                        }

                        // Why This Plan - Explanation of AI decisions
                        WhyThisPlanCard(plan: plan, patterns: planner.userPatterns)
                            .premiumGated(.insights)

                        // Plan Insights
                        PlanInsightsCard(plan: plan, patterns: planner.userPatterns)
                            .premiumGated(.insights)
                    } else {
                        LoadingPlanView()
                    }
                }
                .padding()
            }
            .navigationTitle("Today's Plan")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await refreshPlanAsync()
            }
            .task {
                await initialLoad()
            }
            .sheet(item: $showingActivityDetail) { activity in
                SmartActivityDetailSheet(
                    activity: activity,
                    onAddToCalendar: {
                        Task {
                            _ = try? await planner.addToCalendar(activity)
                        }
                    }
                )
            }
        }
    }

    private func initialLoad() async {
        // Analyze patterns if not done recently
        if planner.userPatterns == nil {
            await planner.analyzeUserPatterns()
        }

        let calendarManager = CalendarManager.shared

        #if DEBUG
        // Auto-create sample events for testing if none exist
        if calendarManager.isAuthorized {
            let events = try? await calendarManager.fetchEvents(for: Date())
            if events?.isEmpty ?? true {
                print("DEBUG: No events found, creating sample schedule...")
                try? await calendarManager.createSampleEventsForTesting()
            }
        }
        #endif

        // Fetch today's events for timeline
        if let events = try? await calendarManager.fetchEvents(for: Date()) {
            await MainActor.run {
                todayEvents = events
            }
        }

        _ = await planner.generateDailyPlan(for: Date())
    }

    private func refreshPlan() {
        Task {
            await refreshPlanAsync()
        }
    }

    private func refreshPlanAsync() async {
        // Refresh events for timeline
        if let events = try? await CalendarManager.shared.fetchEvents(for: selectedDate) {
            await MainActor.run {
                todayEvents = events
            }
        }
        _ = await planner.generateDailyPlan(for: selectedDate)
    }
}

// MARK: - Step Goal Progress Card

struct SmartStepProgressCard: View {
    let plan: SmartPlannerEngine.DailyMovementPlan

    private var progress: Double {
        guard plan.targetSteps > 0 else { return 0 }
        return min(1.0, Double(plan.estimatedCurrentSteps) / Double(plan.targetSteps))
    }

    private var plannedProgress: Double {
        guard plan.targetSteps > 0 else { return 0 }
        return min(1.0, Double(plan.estimatedCurrentSteps + plan.totalPlannedSteps) / Double(plan.targetSteps))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step Goal")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(plan.estimatedCurrentSteps.formatted())")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(plan.stepsNeeded == 0 ? .green : .primary)
                            .contentTransition(.numericText())
                        Text("/ \(plan.targetSteps.formatted())")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Confidence indicator with label
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Plan Confidence")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 3) {
                        ForEach(0..<5) { i in
                            Circle()
                                .fill(i < Int(plan.confidence * 5) ? Color.green : Color.gray.opacity(0.2))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }

            // Progress ring with gradient
            ZStack {
                // Background track
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 14)

                // Planned progress (lighter)
                Circle()
                    .trim(from: 0, to: plannedProgress)
                    .stroke(
                        Color.green.opacity(0.25),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Current progress with gradient
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [.green.opacity(0.7), .green],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: progress)

                // Center content
                VStack(spacing: 6) {
                    if plan.stepsNeeded > 0 {
                        Text("\(plan.stepsNeeded.formatted())")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                        Text("steps to go")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolEffect(.bounce, value: plan.stepsNeeded)
                        Text("Goal reached!")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                }
            }
            .frame(height: 160)
            .padding(.vertical, 8)

            // Plan summary
            HStack(spacing: 16) {
                // Scheduled walks
                VStack {
                    Text("\(plan.activities.count)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Walks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 30)

                // Steps from scheduled walks
                VStack {
                    let walkSteps = plan.activities.reduce(0) { $0 + $1.estimatedSteps }
                    Text("~\(walkSteps.formatted())")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("From walks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 30)

                // Walking meetings
                VStack {
                    let walkingMeetings = plan.walkableMeetings.filter { $0.isRecommended }.count
                    Text("\(walkingMeetings)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Walk meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 30)

                // Steps from walking meetings
                VStack {
                    let meetingSteps = plan.walkableMeetings.filter { $0.isRecommended }.reduce(0) { $0 + $1.estimatedSteps }
                    Text("~\(meetingSteps.formatted())")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("From meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Reasoning
            Text(plan.reasoning)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Checkpoint Progress Card

struct CheckpointProgressCard: View {
    let currentSteps: Int
    let goalSteps: Int

    // Checkpoint targets: 10am (25%), 1pm (50%), 4pm (75%), 7pm (90%)
    private let checkpoints: [(hour: Int, label: String, target: Double)] = [
        (10, "10 AM", 0.25),
        (13, "1 PM", 0.50),
        (16, "4 PM", 0.75),
        (19, "7 PM", 0.90)
    ]

    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    private var activeCheckpointIndex: Int {
        // Find the next checkpoint (or the last one if past all)
        for (index, checkpoint) in checkpoints.enumerated() {
            if currentHour < checkpoint.hour {
                return max(0, index - 1)
            }
        }
        return checkpoints.count - 1
    }

    private var nextCheckpoint: (hour: Int, label: String, target: Double)? {
        checkpoints.first { $0.hour > currentHour }
    }

    private var currentProgress: Double {
        guard goalSteps > 0 else { return 0 }
        return min(1.0, Double(currentSteps) / Double(goalSteps))
    }

    private var checkpointStatus: CheckpointStatus {
        guard let next = nextCheckpoint else {
            // Past all checkpoints - check if goal is met
            return currentProgress >= 0.9 ? .onTrack : .behind
        }

        let expectedProgress = next.target - 0.05 // Small buffer
        if currentProgress >= expectedProgress {
            return .ahead
        } else if currentProgress >= expectedProgress - 0.15 {
            return .onTrack
        } else {
            return .behind
        }
    }

    enum CheckpointStatus {
        case ahead, onTrack, behind

        var color: Color {
            switch self {
            case .ahead: return .green
            case .onTrack: return .blue
            case .behind: return .orange
            }
        }

        var icon: String {
            switch self {
            case .ahead: return "bolt.fill"
            case .onTrack: return "checkmark.circle.fill"
            case .behind: return "exclamationmark.triangle.fill"
            }
        }

        var message: String {
            switch self {
            case .ahead: return "Ahead of schedule!"
            case .onTrack: return "On track"
            case .behind: return "Behind - time for a walk?"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "flag.checkered")
                    .foregroundColor(.blue)
                Text("Checkpoint Progress")
                    .font(.headline)
                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Image(systemName: checkpointStatus.icon)
                        .font(.caption)
                    Text(checkpointStatus.message)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(checkpointStatus.color)
            }

            // Progress bar with checkpoint markers
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 12)

                    // Progress fill
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [checkpointStatus.color.opacity(0.7), checkpointStatus.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * currentProgress, height: 12)
                        .animation(.easeOut(duration: 0.5), value: currentProgress)

                    // Checkpoint markers
                    ForEach(Array(checkpoints.enumerated()), id: \.offset) { index, checkpoint in
                        let xPosition = geometry.size.width * checkpoint.target

                        VStack(spacing: 2) {
                            // Marker line
                            Rectangle()
                                .fill(index <= activeCheckpointIndex ? Color.green : Color.gray.opacity(0.5))
                                .frame(width: 2, height: 20)

                            // Label
                            Text(checkpoint.label)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .position(x: xPosition, y: 18)
                    }

                    // Current position indicator
                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .fill(checkpointStatus.color)
                                .frame(width: 10, height: 10)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 2)
                        .position(x: geometry.size.width * currentProgress, y: 6)
                }
            }
            .frame(height: 44)

            // Next checkpoint info
            if let next = nextCheckpoint {
                let targetSteps = Int(Double(goalSteps) * next.target)
                let stepsToGo = max(0, targetSteps - currentSteps)

                HStack {
                    Text("Next: \(next.label)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if stepsToGo > 0 {
                        Text("\(stepsToGo.formatted()) steps to reach checkpoint")
                            .font(.caption)
                            .foregroundColor(checkpointStatus.color)
                    } else {
                        Text("Checkpoint reached!")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            } else {
                HStack {
                    Text("All checkpoints passed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if currentProgress >= 1.0 {
                        Text("Goal achieved!")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Day Timeline View

struct DayTimelineView: View {
    let plan: SmartPlannerEngine.DailyMovementPlan
    let events: [CalendarEvent]

    @EnvironmentObject var userPreferences: UserPreferences

    private let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 50

    private var startHour: Int {
        max(6, userPreferences.wakeTime.hour)
    }

    private var endHour: Int {
        min(22, userPreferences.sleepTime.hour)
    }

    private var currentHour: Int {
        Calendar.current.component(.hour, from: Date())
    }

    private var currentMinute: Int {
        Calendar.current.component(.minute, from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.blue)
                Text("Day Timeline")
                    .font(.headline)
                Text("(\(eventsInRange.count) events)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Now: \(formatCurrentTime())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Hour grid lines with event blocks inline
                        VStack(spacing: 0) {
                            ForEach(startHour...endHour, id: \.self) { hour in
                                ZStack(alignment: .topLeading) {
                                    HStack(alignment: .top, spacing: 8) {
                                        // Time label
                                        Text(formatHour(hour))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .frame(width: timeColumnWidth, alignment: .trailing)

                                        // Grid line
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(height: 1)
                                    }

                                    // Events starting at this hour
                                    ForEach(eventsStartingAtHour(hour), id: \.id) { event in
                                        inlineEventBlock(for: event)
                                    }

                                    // Activities starting at this hour
                                    ForEach(activitiesStartingAtHour(hour), id: \.id) { activity in
                                        inlineActivityBlock(for: activity)
                                    }
                                }
                                .frame(height: hourHeight)
                                .id(hour)
                            }
                        }

                        // Current time indicator
                        if currentHour >= startHour && currentHour <= endHour {
                            currentTimeIndicator
                        }
                    }
                }
                .onAppear {
                    // Scroll to current hour
                    if currentHour >= startHour && currentHour <= endHour {
                        proxy.scrollTo(max(startHour, currentHour - 2), anchor: .top)
                    }
                }
            }
            .frame(height: min(CGFloat(endHour - startHour + 1) * hourHeight, 350))
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }

    private var eventsInRange: [CalendarEvent] {
        // Filter to events within the visible time range (excluding all-day events)
        events.filter { event in
            guard !event.isAllDay else { return false }
            let eventHour = Calendar.current.component(.hour, from: event.startDate)
            // Include events even if they're OOO, but show them differently
            return eventHour >= startHour && eventHour <= endHour
        }
    }

    private func eventsStartingAtHour(_ hour: Int) -> [CalendarEvent] {
        events.filter { event in
            guard !event.isAllDay else { return false }
            let eventHour = Calendar.current.component(.hour, from: event.startDate)
            return eventHour == hour
        }
    }

    private func activitiesStartingAtHour(_ hour: Int) -> [SmartPlannerEngine.PlannedActivity] {
        plan.activities.filter { activity in
            let activityHour = Calendar.current.component(.hour, from: activity.startTime)
            return activityHour == hour
        }
    }

    private func inlineEventBlock(for event: CalendarEvent) -> some View {
        let startMinute = Calendar.current.component(.minute, from: event.startDate)
        let duration = event.endDate.timeIntervalSince(event.startDate) / 60
        let height = max(24, min(CGFloat(duration) / 60.0 * hourHeight, hourHeight * 2))
        let topOffset = CGFloat(startMinute) / 60.0 * hourHeight

        let isWalkable = plan.walkableMeetings.first { $0.calendarEventID == event.id }?.isRecommended ?? false

        return HStack(spacing: 4) {
            if isWalkable {
                Image(systemName: "figure.walk")
                    .font(.caption2)
                    .foregroundColor(.white)
            }
            Text(event.title)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isWalkable ? Color.blue : Color.gray.opacity(0.7))
        )
        .padding(.leading, timeColumnWidth + 8)
        .padding(.trailing, 4)
        .offset(y: topOffset)
    }

    private func inlineActivityBlock(for activity: SmartPlannerEngine.PlannedActivity) -> some View {
        let startMinute = Calendar.current.component(.minute, from: activity.startTime)
        let height = max(24, min(CGFloat(activity.duration) / 60.0 * hourHeight, hourHeight * 2))
        let topOffset = CGFloat(startMinute) / 60.0 * hourHeight

        return HStack(spacing: 4) {
            Image(systemName: "figure.walk.motion")
                .font(.caption2)
                .foregroundColor(.white)
            Text("Walk")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Spacer()
            Text("~\(activity.estimatedSteps)")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
        )
        .padding(.leading, timeColumnWidth + 8)
        .padding(.trailing, 4)
        .offset(y: topOffset)
    }

    private var currentTimeIndicator: some View {
        let yOffset = CGFloat(currentHour - startHour) * hourHeight + CGFloat(currentMinute) / 60.0 * hourHeight

        return HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Rectangle()
                .fill(Color.red)
                .frame(height: 2)
        }
        .padding(.leading, timeColumnWidth + 4)
        .offset(y: yOffset - 4)
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        let date = Calendar.current.date(from: DateComponents(hour: hour)) ?? Date()
        return formatter.string(from: date)
    }

    private func formatCurrentTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }

    private func activityTitle(for activity: SmartPlannerEngine.PlannedActivity) -> String {
        switch activity.type {
        case .microWalk: return "Quick Walk"
        case .morningWalk: return "Morning"
        case .lunchWalk: return "Lunch Walk"
        case .eveningWalk: return "Evening"
        case .scheduledWalk: return "Walk"
        case .postMeetingWalk: return "Post-Meeting"
        case .gymWorkout: return "Gym"
        }
    }
}

// MARK: - Daily Plan Section

struct DailyPlanSection: View {
    let plan: SmartPlannerEngine.DailyMovementPlan
    let onActivityTap: (SmartPlannerEngine.PlannedActivity) -> Void
    let onComplete: (SmartPlannerEngine.PlannedActivity) -> Void
    let onSkip: (SmartPlannerEngine.PlannedActivity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Movement Plan")
                .font(.headline)

            if plan.activities.isEmpty {
                let meetingSteps = plan.walkableMeetings.filter { $0.isRecommended }.reduce(0) { $0 + $1.estimatedSteps }
                let goalCoveredByMeetings = plan.stepsNeeded > 0 && meetingSteps >= plan.stepsNeeded

                VStack(spacing: 12) {
                    if plan.stepsNeeded == 0 {
                        // User already hit their step goal
                        Image(systemName: "trophy.fill")
                            .font(.largeTitle)
                            .foregroundColor(.yellow)
                        Text("Goal achieved!")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("You've already hit your step goal today. Keep up the great work!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else if goalCoveredByMeetings && meetingSteps > 0 {
                        // Walking meetings can cover remaining goal
                        Image(systemName: "figure.walk.motion")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        Text("Walking meetings can cover your goal!")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Take your \(plan.walkableMeetings.filter { $0.isRecommended }.count) recommended meetings as walking calls to hit ~\(meetingSteps.formatted()) steps.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else if !plan.walkableMeetings.isEmpty {
                        // Has walkable meetings but not enough
                        Image(systemName: "figure.walk")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text("No walks scheduled")
                            .foregroundColor(.secondary)
                        Text("Your calendar is packed, but consider the walking meetings below!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        // No walks and no walkable meetings
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No walks scheduled")
                            .foregroundColor(.secondary)
                        Text("Your calendar is very busy today. Try to find small gaps for quick walks.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(plan.activities) { activity in
                    ActivityRow(
                        activity: activity,
                        onTap: { onActivityTap(activity) },
                        onComplete: { onComplete(activity) },
                        onSkip: { onSkip(activity) }
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct ActivityRow: View {
    let activity: SmartPlannerEngine.PlannedActivity
    let onTap: () -> Void
    let onComplete: () -> Void
    let onSkip: () -> Void

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    private var icon: String {
        switch activity.type {
        case .microWalk: return "figure.walk"
        case .morningWalk: return "sunrise.fill"
        case .lunchWalk: return "fork.knife"
        case .eveningWalk: return "sunset.fill"
        case .scheduledWalk: return "figure.walk.motion"
        case .postMeetingWalk: return "arrow.right.circle"
        case .gymWorkout: return "dumbbell.fill"
        }
    }

    private var priorityColor: Color {
        switch activity.priority {
        case .critical: return .red
        case .recommended: return .orange
        case .optional: return .blue
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status/Type indicator
            ZStack {
                Circle()
                    .fill(activity.status == .completed ? Color.green : priorityColor.opacity(0.15))
                    .frame(width: 44, height: 44)

                if activity.status == .completed {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .fontWeight(.bold)
                } else {
                    Image(systemName: icon)
                        .foregroundColor(priorityColor)
                }
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(activityTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .strikethrough(activity.status == .skipped)

                    if activity.priority == .critical {
                        Text("KEY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .clipShape(Capsule())
                    }
                }

                Text(timeFormatter.string(from: activity.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("~\(activity.estimatedSteps) steps • \(activity.duration) min")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Actions
            if activity.status == .planned {
                HStack(spacing: 8) {
                    Button {
                        onComplete()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                    }

                    Button {
                        onSkip()
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: activity.status == .completed ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundColor(activity.status == .completed ? .green : .secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var activityTitle: String {
        switch activity.type {
        case .microWalk: return "Quick Walk"
        case .morningWalk: return "Morning Walk"
        case .lunchWalk: return "Lunch Walk"
        case .eveningWalk: return "Evening Walk"
        case .scheduledWalk: return "Scheduled Walk"
        case .postMeetingWalk: return "Post-Meeting Walk"
        case .gymWorkout: return "Gym Workout"
        }
    }
}

// MARK: - Walkable Meetings Section

struct WalkableMeetingsSection: View {
    let meetings: [SmartPlannerEngine.WalkableMeeting]

    private var recommendedMeetings: [SmartPlannerEngine.WalkableMeeting] {
        meetings.filter { $0.isRecommended }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.wave.2")
                    .foregroundColor(.blue)
                Text("Walking Meeting Opportunities")
                    .font(.headline)
            }

            if recommendedMeetings.isEmpty {
                Text("No ideal walking meetings today")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(recommendedMeetings) { meeting in
                    SmartWalkableMeetingRow(meeting: meeting)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct SmartWalkableMeetingRow: View {
    let meeting: SmartPlannerEngine.WalkableMeeting

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: "phone.and.waveform")
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack {
                    Text(timeFormatter.string(from: meeting.startTime))
                    Text("•")
                    Text("\(meeting.duration) min")
                    if meeting.isOneOnOne {
                        Text("• 1:1")
                            .foregroundColor(.green)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("+\(meeting.estimatedSteps)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                Text("steps")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Why This Plan Card

struct WhyThisPlanCard: View {
    let plan: SmartPlannerEngine.DailyMovementPlan
    let patterns: SmartPlannerEngine.UserActivityPatterns?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse
            Button {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.purple)
                    Text("Why This Plan?")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // Overall strategy
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Strategy")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)

                        Text(planStrategy)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Individual walk explanations
                    if !plan.activities.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scheduled Walks")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)

                            ForEach(plan.activities) { activity in
                                WhyActivityRow(activity: activity)
                            }
                        }
                    }

                    // Walkable meetings explanation
                    let recommendedMeetings = plan.walkableMeetings.filter { $0.isRecommended }
                    if !recommendedMeetings.isEmpty {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Walking Meetings")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)

                            Text("We identified \(recommendedMeetings.count) meeting\(recommendedMeetings.count == 1 ? "" : "s") that could be walking calls. These are typically 1:1s or small sync meetings where you don't need to present or take notes.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Pattern-based explanation
                    if let patterns = patterns {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Based on Your Patterns")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)

                            if patterns.goalAchievementRate > 0.5 {
                                Text("You hit your goal \(Int(patterns.goalAchievementRate * 100))% of the time. This plan is calibrated to your proven success patterns.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("Your current goal hit rate is \(Int(patterns.goalAchievementRate * 100))%. This plan focuses on achievable walks to help build momentum.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Collapsed summary
                Text(plan.reasoning)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }

    private var planStrategy: String {
        let walkCount = plan.activities.count
        let meetingCount = plan.walkableMeetings.filter { $0.isRecommended }.count
        let totalPlannedSteps = plan.totalPlannedSteps

        if plan.stepsNeeded == 0 {
            return "You've already hit your goal! Any additional walks are bonus activity."
        }

        var strategy = ""

        if walkCount == 0 && meetingCount > 0 {
            strategy = "Your calendar is packed, so we're relying on \(meetingCount) walking meeting\(meetingCount == 1 ? "" : "s") to help you reach your goal."
        } else if walkCount > 0 && meetingCount > 0 {
            strategy = "We've combined \(walkCount) dedicated walk\(walkCount == 1 ? "" : "s") with \(meetingCount) walking meeting opportunity\(meetingCount == 1 ? "" : "ies") to cover your \(plan.stepsNeeded.formatted()) remaining steps."
        } else if walkCount > 0 {
            strategy = "We found \(walkCount) open slot\(walkCount == 1 ? "" : "s") in your calendar for walks that can cover \(totalPlannedSteps.formatted()) steps."
        } else {
            strategy = "Your calendar is very busy today. Consider rescheduling a meeting or taking walking calls."
        }

        return strategy
    }
}

struct WhyActivityRow: View {
    let activity: SmartPlannerEngine.PlannedActivity

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(timeFormatter.string(from: activity.startTime)) - \(activity.duration) min walk")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(activity.reason)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Plan Insights Card

struct PlanInsightsCard: View {
    let plan: SmartPlannerEngine.DailyMovementPlan
    let patterns: SmartPlannerEngine.UserActivityPatterns?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Insights")
                    .font(.headline)
            }

            if let patterns = patterns {
                VStack(alignment: .leading, spacing: 8) {
                    InsightRow(
                        icon: "chart.line.uptrend.xyaxis",
                        text: "Your average: \(patterns.averageDailySteps.formatted()) steps/day"
                    )

                    InsightRow(
                        icon: "target",
                        text: "Goal hit rate: \(Int(patterns.goalAchievementRate * 100))% of days"
                    )

                    if patterns.weekdayAverage < patterns.weekendAverage {
                        InsightRow(
                            icon: "briefcase",
                            text: "Weekdays are harder - \(patterns.weekdayAverage.formatted()) vs \(patterns.weekendAverage.formatted()) steps"
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

struct InsightRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Loading View

struct LoadingPlanView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Analyzing your calendar...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Smart Activity Detail Sheet

struct SmartActivityDetailSheet: View {
    let activity: SmartPlannerEngine.PlannedActivity
    let onAddToCalendar: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isAdding = false  // Prevent double-tap

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text(activityTitle)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(timeFormatter.string(from: activity.startTime))
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .padding(.top)

                // Stats
                HStack(spacing: 30) {
                    VStack {
                        Text("\(activity.duration)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("minutes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Text("~\(activity.estimatedSteps)")
                            .font(.title)
                            .fontWeight(.bold)
                        Text("steps")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Reason
                VStack(alignment: .leading, spacing: 8) {
                    Text("Why this time?")
                        .font(.headline)
                    Text(activity.reason)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Spacer()

                // Add to calendar button - with loading state to prevent double-tap
                Button {
                    guard !isAdding else { return }
                    isAdding = true
                    onAddToCalendar()
                    // Brief delay before dismiss to ensure event is added
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        dismiss()
                    }
                } label: {
                    HStack {
                        if isAdding {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "calendar.badge.plus")
                        }
                        Text(isAdding ? "Adding..." : "Add to Calendar")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isAdding ? Color.gray : Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isAdding)
            }
            .padding()
            .navigationTitle("Activity Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var activityTitle: String {
        switch activity.type {
        case .microWalk: return "Quick Walk"
        case .morningWalk: return "Morning Walk"
        case .lunchWalk: return "Lunch Walk"
        case .eveningWalk: return "Evening Walk"
        case .scheduledWalk: return "Scheduled Walk"
        case .postMeetingWalk: return "Post-Meeting Walk"
        case .gymWorkout: return "Gym Workout"
        }
    }
}

// MARK: - Walk Pattern Graph Card

struct WalkPatternGraphCard: View {
    let patternData: [SmartPlannerEngine.HourlyPatternData]
    let explanation: String
    let dayName: String

    private var maxSteps: Int {
        patternData.map(\.averageSteps).max() ?? 1000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.orange)
                Text("Your \(dayName) Pattern")
                    .font(.headline)
                Spacer()
            }

            // Explanation text
            Text(explanation)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Bar graph - always visible
            VStack(alignment: .leading, spacing: 4) {
                Text("Steps by hour")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)

                // Scrollable horizontal bar chart
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(patternData) { data in
                            VStack(spacing: 2) {
                                // Step count on top of bar
                                if data.averageSteps > 0 {
                                    Text("\(data.averageSteps)")
                                        .font(.system(size: 7))
                                        .foregroundColor(.secondary)
                                }

                                // Bar - yellow/amber for intensity, green border if recommended
                                let height: CGFloat = data.averageSteps > 0
                                    ? max(12, CGFloat(data.averageSteps) / CGFloat(max(maxSteps, 1)) * 80)
                                    : (data.isRecommended ? 30 : 8)

                                RoundedRectangle(cornerRadius: 3)
                                    .fill(barColor(for: data))
                                    .frame(width: 24, height: height)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(data.isRecommended ? Color.green : Color.clear, lineWidth: 2)
                                    )

                                // Hour label
                                Text(shortHourLabel(data.hour))
                                    .font(.system(size: 8))
                                    .foregroundColor(data.isRecommended ? .green : .secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Legend
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.yellow)
                            .frame(width: 12, height: 8)
                        Text("Steps")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.yellow)
                            .frame(width: 12, height: 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.green, lineWidth: 1.5)
                            )
                        Text("Recommended")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }

    private func barColor(for data: SmartPlannerEngine.HourlyPatternData) -> Color {
        if data.averageSteps > 0 {
            // Yellow intensity based on step count
            let intensity = CGFloat(data.averageSteps) / CGFloat(max(maxSteps, 1))
            return Color.yellow.opacity(0.4 + intensity * 0.6)
        }
        // No step data: show recommended hours in green, others in light gray
        return data.isRecommended ? Color.green.opacity(0.4) : Color.gray.opacity(0.25)
    }

    private func shortHourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }
}

#Preview {
    SmartPlanView()
        .environmentObject(UserPreferences.shared)
}
