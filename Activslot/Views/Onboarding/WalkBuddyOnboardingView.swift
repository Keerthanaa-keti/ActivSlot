import SwiftUI

// MARK: - Walk Buddy Onboarding Step
// Introduces the buddy walk feature and lets users connect or skip

struct WalkBuddyOnboardingView: View {
    let onContinue: () -> Void

    @ObservedObject private var coupleWalkManager = CoupleWalkManager.shared

    @State private var showConnectOptions = false
    @State private var inviteCode = ""
    @State private var generatedCode = ""
    @State private var showGeneratedCode = false
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.pink.opacity(0.1))
                            .frame(width: 100, height: 100)

                        Image(systemName: "figure.walk.motion")
                            .font(.system(size: 44))
                            .foregroundColor(.pink)
                            .overlay(
                                Image(systemName: "figure.walk.motion")
                                    .font(.system(size: 30))
                                    .foregroundColor(.pink.opacity(0.6))
                                    .offset(x: 28, y: 4)
                            )
                    }
                    .padding(.bottom, 8)

                    // Title
                    Text("Walk with Someone")
                        .font(.system(size: 28, weight: .bold))

                    // Subtitle
                    Text("Connect with a partner, friend, or colleague.\nActivSlot finds times that work for both of you.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    // Benefits
                    VStack(spacing: 14) {
                        BuddyBenefitRow(
                            icon: "calendar.badge.clock",
                            title: "Shared Free Slots",
                            subtitle: "Automatically finds times you're both free"
                        )

                        BuddyBenefitRow(
                            icon: "bell.badge",
                            title: "Joint Reminders",
                            subtitle: "Both get notified when it's walk time"
                        )

                        BuddyBenefitRow(
                            icon: "lock.shield",
                            title: "Calendar Privacy",
                            subtitle: "Only free/busy is shared, never event details"
                        )
                    }
                    .padding(.horizontal, 32)

                    if coupleWalkManager.isLinked {
                        // Already connected
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected with \(coupleWalkManager.partnerProfile?.partnerName ?? "partner")")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal, 32)
                    } else if showConnectOptions {
                        // Connect options
                        VStack(spacing: 16) {
                            // Generate code
                            if showGeneratedCode {
                                VStack(spacing: 8) {
                                    Text("Share this code with your buddy:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text(generatedCode)
                                        .font(.title2.monospaced())
                                        .fontWeight(.bold)
                                        .foregroundColor(.pink)
                                        .padding()
                                        .background(Color.pink.opacity(0.1))
                                        .cornerRadius(12)

                                    Button {
                                        UIPasteboard.general.string = generatedCode
                                    } label: {
                                        Label("Copy Code", systemImage: "doc.on.doc")
                                            .font(.caption)
                                    }
                                }
                            } else {
                                Button {
                                    generateCode()
                                } label: {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Generate Invite Code")
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(.pink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.pink.opacity(0.1))
                                    .cornerRadius(12)
                                }
                            }

                            // Divider
                            HStack {
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                                Text("or").font(.caption).foregroundColor(.secondary)
                                Rectangle().fill(Color.gray.opacity(0.3)).frame(height: 1)
                            }

                            // Enter code
                            VStack(spacing: 8) {
                                Text("Enter your buddy's code:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                HStack {
                                    TextField("Code", text: $inviteCode)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.characters)
                                        .autocorrectionDisabled()
                                        .font(.body.monospaced())

                                    Button {
                                        acceptInvite()
                                    } label: {
                                        Text("Join")
                                            .fontWeight(.medium)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(inviteCode.count >= 4 ? Color.pink : Color.gray.opacity(0.3))
                                            .cornerRadius(10)
                                    }
                                    .disabled(inviteCode.count < 4 || isLoading)
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                    }

                    Spacer(minLength: 60)
                }
            }

            // Bottom buttons
            VStack(spacing: 12) {
                if !showConnectOptions && !coupleWalkManager.isLinked {
                    Button {
                        withAnimation { showConnectOptions = true }
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                            Text("Connect a Walk Buddy")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.pink)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal, 24)
                }

                Button {
                    onContinue()
                } label: {
                    Text(coupleWalkManager.isLinked ? "Continue" : "Skip for now")
                        .font(coupleWalkManager.isLinked ? .headline : .subheadline)
                        .foregroundColor(coupleWalkManager.isLinked ? .white : .secondary)
                        .frame(maxWidth: coupleWalkManager.isLinked ? .infinity : nil)
                        .padding(.vertical, coupleWalkManager.isLinked ? 16 : 0)
                        .background(coupleWalkManager.isLinked ? Color.green : Color.clear)
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 40)
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func generateCode() {
        isLoading = true
        Task {
            do {
                let code = try await coupleWalkManager.generateInviteCode()
                await MainActor.run {
                    generatedCode = code
                    showGeneratedCode = true
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }

    private func acceptInvite() {
        isLoading = true
        Task {
            do {
                try await coupleWalkManager.acceptInvite(code: inviteCode)
                await MainActor.run {
                    isLoading = false
                    // Brief delay then continue
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        onContinue()
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Buddy Benefit Row

struct BuddyBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.pink)
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
    WalkBuddyOnboardingView(onContinue: {})
}
