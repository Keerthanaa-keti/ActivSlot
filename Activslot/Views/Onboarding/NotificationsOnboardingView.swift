import SwiftUI

// MARK: - Notifications Onboarding Step
// Requests notification permission and explains the key notification types

struct NotificationsOnboardingView: View {
    let onContinue: () -> Void

    @State private var isRequesting = false
    @State private var permissionGranted = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)
            }
            .padding(.bottom, 32)

            // Title
            Text("Stay on Track")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 12)

            // Subtitle
            Text("Smart notifications help you walk more\nwithout thinking about it.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)

            // Notification types
            VStack(spacing: 14) {
                NotificationFeatureRow(
                    icon: "moon.stars.fill",
                    iconColor: .purple,
                    title: "Evening Briefing",
                    subtitle: "Preview tomorrow's walk plan each evening"
                )

                NotificationFeatureRow(
                    icon: "phone.arrow.up.right.fill",
                    iconColor: .blue,
                    title: "Walk This Call",
                    subtitle: "Get reminded before walkable meetings"
                )

                NotificationFeatureRow(
                    icon: "figure.walk.motion",
                    iconColor: .green,
                    title: "Walk Reminders",
                    subtitle: "Gentle nudges when it's time to move"
                )
            }
            .padding(.horizontal, 32)

            Spacer()

            // CTA
            Button {
                requestNotifications()
            } label: {
                HStack {
                    if isRequesting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 8)
                    }
                    Text(permissionGranted ? "Enabled!" : "Enable Notifications")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(permissionGranted ? Color.green : Color.orange)
                .cornerRadius(14)
            }
            .disabled(isRequesting || permissionGranted)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            // Skip
            Button {
                onContinue()
            } label: {
                Text("Skip for now")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)
        }
    }

    private func requestNotifications() {
        isRequesting = true

        Task {
            do {
                let granted = try await NotificationManager.shared.requestAuthorization()
                await MainActor.run {
                    isRequesting = false
                    if granted {
                        permissionGranted = true
                        // Auto-enable key notification features
                        NotificationManager.shared.eveningBriefingEnabled = true
                        NotificationManager.shared.walkableMeetingRemindersEnabled = true

                        // Brief delay then continue
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            onContinue()
                        }
                    } else {
                        onContinue()
                    }
                }
            } catch {
                await MainActor.run {
                    isRequesting = false
                    onContinue()
                }
            }
        }
    }
}

// MARK: - Notification Feature Row

struct NotificationFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    NotificationsOnboardingView(onContinue: {})
}
