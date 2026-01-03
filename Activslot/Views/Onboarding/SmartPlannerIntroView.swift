import SwiftUI

// MARK: - Smart Planner Introduction View
// This view shows the user their ACTUAL plan based on their calendar
// Key principle from Hooked: Show immediate value to create investment

struct SmartPlannerIntroView: View {
    let onContinue: () -> Void

    @StateObject private var planner = SmartPlannerEngine.shared
    @EnvironmentObject var userPreferences: UserPreferences
    @EnvironmentObject var calendarManager: CalendarManager

    @State private var isLoading = true
    @State private var showPlan = false
    @State private var animateElements = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .padding(.top, 32)

                        Text("Your AI Walking Coach")
                            .font(.title)
                            .fontWeight(.bold)

                        Text("I've analyzed your calendar and created a personalized plan")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    if isLoading {
                        // Loading state with analysis animation
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.2)

                            VStack(spacing: 8) {
                                AnalysisStepView(text: "Reading your calendar...", delay: 0)
                                AnalysisStepView(text: "Finding gaps between meetings...", delay: 0.5)
                                AnalysisStepView(text: "Optimizing walk times...", delay: 1.0)
                                AnalysisStepView(text: "Creating your plan...", delay: 1.5)
                            }
                        }
                        .padding(.vertical, 40)
                    } else if let plan = planner.currentDayPlan {
                        // Show the actual plan
                        VStack(spacing: 20) {
                            // Summary card
                            PlanSummaryCard(plan: plan)
                                .opacity(showPlan ? 1 : 0)
                                .offset(y: showPlan ? 0 : 20)
                                .animation(.spring(response: 0.5).delay(0.1), value: showPlan)

                            // Today's activities preview
                            if !plan.activities.isEmpty {
                                TodayActivitiesPreview(activities: plan.activities)
                                    .opacity(showPlan ? 1 : 0)
                                    .offset(y: showPlan ? 0 : 20)
                                    .animation(.spring(response: 0.5).delay(0.2), value: showPlan)
                            }

                            // Walkable meetings highlight
                            if !plan.walkableMeetings.isEmpty {
                                WalkableMeetingsHighlight(meetings: plan.walkableMeetings)
                                    .opacity(showPlan ? 1 : 0)
                                    .offset(y: showPlan ? 0 : 20)
                                    .animation(.spring(response: 0.5).delay(0.3), value: showPlan)
                            }

                            // Key promise
                            KeyPromiseCard()
                                .opacity(showPlan ? 1 : 0)
                                .offset(y: showPlan ? 0 : 20)
                                .animation(.spring(response: 0.5).delay(0.4), value: showPlan)
                        }
                        .padding(.horizontal)
                    } else {
                        // Fallback if no plan generated
                        NoCalendarFallbackView()
                    }

                    Spacer(minLength: 100)
                }
            }

            // CTA
            VStack(spacing: 12) {
                Button(action: onContinue) {
                    HStack {
                        Text("Start My Journey")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .disabled(isLoading)
                .opacity(isLoading ? 0.5 : 1)
            }
            .padding(.bottom, 40)
            .background(Color(.systemBackground))
        }
        .task {
            await generatePlan()
        }
    }

    private func generatePlan() async {
        // Simulate analysis time for effect
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        // Generate actual plan
        _ = await planner.generateDailyPlan(for: Date())

        await MainActor.run {
            isLoading = false

            // Trigger reveal animation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showPlan = true
            }
        }
    }
}

// MARK: - Analysis Step View

struct AnalysisStepView: View {
    let text: String
    let delay: Double

    @State private var isVisible = false
    @State private var isComplete = false

    var body: some View {
        HStack(spacing: 12) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isVisible {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 20, height: 20)
            }

            Text(text)
                .font(.subheadline)
                .foregroundColor(isVisible ? .primary : .secondary)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation { isVisible = true }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5) {
                withAnimation { isComplete = true }
            }
        }
    }
}

// MARK: - Plan Summary Card

struct PlanSummaryCard: View {
    let plan: SmartPlannerEngine.DailyMovementPlan

    var body: some View {
        VStack(spacing: 16) {
            // Goal vs Planned
            HStack(spacing: 20) {
                StatBox(
                    value: "\(plan.stepsNeeded.formatted())",
                    label: "Steps to Go",
                    color: .orange
                )

                StatBox(
                    value: "\(plan.totalPlannedSteps.formatted())",
                    label: "Planned",
                    color: .green
                )
            }

            // Confidence
            HStack {
                Text("Plan Confidence")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    let dots = Int(plan.confidence * 5) // Convert 0-1 to 0-5 dots
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .fill(i < dots ? Color.green : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

struct StatBox: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Today's Activities Preview

struct TodayActivitiesPreview: View {
    let activities: [SmartPlannerEngine.PlannedActivity]

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "figure.walk.motion")
                    .foregroundColor(.green)
                Text("Your Walks Today")
                    .font(.headline)
            }

            ForEach(activities.prefix(3)) { activity in
                HStack {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)

                    Text(timeFormatter.string(from: activity.startTime))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("• \(activity.duration) min")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("~\(activity.estimatedSteps) steps")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
}

// MARK: - Walkable Meetings Highlight

struct WalkableMeetingsHighlight: View {
    let meetings: [SmartPlannerEngine.WalkableMeeting]

    private var recommendedCount: Int {
        meetings.filter { $0.isRecommended }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(recommendedCount) Walking Meeting\(recommendedCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Turn these calls into step opportunities")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("+\(meetings.filter { $0.isRecommended }.reduce(0) { $0 + $1.estimatedSteps }.formatted())")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Key Promise Card

struct KeyPromiseCard: View {
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("What I'll Do For You")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 8) {
                PromiseRow(icon: "bell.badge", text: "Remind you before walkable meetings")
                PromiseRow(icon: "chart.line.uptrend.xyaxis", text: "Track your progress throughout the day")
                PromiseRow(icon: "arrow.triangle.2.circlepath", text: "Adjust your plan if you fall behind")
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.1), .blue.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
    }
}

struct PromiseRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.purple)
                .frame(width: 20)

            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - No Calendar Fallback

struct NoCalendarFallbackView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundColor(.orange)

            Text("Couldn't access your calendar")
                .font(.headline)

            Text("That's okay! I can still help you reach your step goals. You can connect your calendar later in Settings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 40)
    }
}

#Preview {
    SmartPlannerIntroView(onContinue: {})
        .environmentObject(UserPreferences.shared)
        .environmentObject(CalendarManager.shared)
}
