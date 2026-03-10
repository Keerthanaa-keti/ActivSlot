import SwiftUI

// MARK: - Couple Walk View
// Lets two partners share free/busy availability and discover shared walk slots.

struct CoupleWalkView: View {
    @ObservedObject private var coupleWalkManager = CoupleWalkManager.shared
    @EnvironmentObject var calendarManager: CalendarManager
    @EnvironmentObject var outlookManager: OutlookManager

    @State private var inviteCode = ""
    @State private var generatedCode = ""
    @State private var showGeneratedCode = false
    @State private var showInviteEntry = false
    @State private var showUnlinkConfirmation = false
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if coupleWalkManager.isLinked, let partner = coupleWalkManager.partnerProfile {
                    // MARK: Connected State
                    PartnerConnectedCard(
                        partner: partner,
                        onRefresh: {
                            Task { await coupleWalkManager.refreshSharedSlots() }
                        },
                        onUnlink: { showUnlinkConfirmation = true }
                    )

                    // Shared walk slots
                    SharedSlotsSection(
                        slots: coupleWalkManager.sharedWalkSlots,
                        partnerName: partner.partnerName,
                        isLoading: coupleWalkManager.isLoading
                    )

                } else {
                    // MARK: Not Connected State
                    ConnectPartnerSection(
                        generatedCode: generatedCode,
                        showGeneratedCode: $showGeneratedCode,
                        inviteCode: $inviteCode,
                        showInviteEntry: $showInviteEntry,
                        onGenerateCode: generateCode,
                        onAcceptInvite: acceptInvite
                    )

                    #if DEBUG
                    // Simulator testing shortcut — bypasses CloudKit
                    Button {
                        Task { await coupleWalkManager.linkMockPartner() }
                    } label: {
                        Label("Link Mock Partner (Debug)", systemImage: "wrench.and.screwdriver")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 4)
                    #endif
                }

                // Privacy note
                PrivacyNoteCard()
            }
            .padding()
        }
        .navigationTitle("Walk Buddy")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            if coupleWalkManager.isLinked {
                await coupleWalkManager.refreshSharedSlots()
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .confirmationDialog(
            "Unlink Walk Buddy?",
            isPresented: $showUnlinkConfirmation,
            titleVisibility: .visible
        ) {
            Button("Unlink", role: .destructive) {
                coupleWalkManager.unlinkPartner()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to share a new invite code to reconnect.")
        }
        .task {
            if coupleWalkManager.isLinked {
                await coupleWalkManager.refreshSharedSlots()
            }
        }
    }

    // MARK: - Actions

    private func generateCode() {
        Task {
            do {
                let code = try await coupleWalkManager.generateInviteCode()
                await MainActor.run {
                    generatedCode = code
                    showGeneratedCode = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func acceptInvite() {
        let code = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6 else {
            errorMessage = "Please enter a 6-character invite code."
            showError = true
            return
        }

        Task {
            do {
                try await coupleWalkManager.acceptInvite(code: code)
                await MainActor.run {
                    inviteCode = ""
                    showInviteEntry = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Connect Partner Section

private struct ConnectPartnerSection: View {
    let generatedCode: String
    @Binding var showGeneratedCode: Bool
    @Binding var inviteCode: String
    @Binding var showInviteEntry: Bool
    let onGenerateCode: () -> Void
    let onAcceptInvite: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Hero
            VStack(spacing: 12) {
                Image(systemName: "figure.2.and.child.holdinghands")
                    .font(.system(size: 56))
                    .foregroundColor(.purple)

                Text("Walk Together")
                    .font(.title2)
                    .bold()

                Text("Connect with a partner to find walk times that work for both of your schedules.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)

            Divider()

            // Option 1: Generate code
            VStack(alignment: .leading, spacing: 12) {
                Label("Share Your Availability", systemImage: "qrcode")
                    .font(.headline)

                Text("Generate a code for your partner to enter.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if showGeneratedCode && !generatedCode.isEmpty {
                    // Display the generated code prominently
                    VStack(spacing: 8) {
                        Text("Your invite code:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(generatedCode)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(12)

                        Text("This code expires in 72 hours")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        ShareLink(
                            item: "Join me on ActivSlot! Use code \(generatedCode) to connect as Walk Buddies.",
                            subject: Text("Let's walk together!")
                        ) {
                            Label("Share Code", systemImage: "square.and.arrow.up")
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button(action: onGenerateCode) {
                        Label("Generate Invite Code", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            // Option 2: Enter partner's code
            VStack(alignment: .leading, spacing: 12) {
                Label("Enter Partner's Code", systemImage: "keyboard")
                    .font(.headline)

                Text("Got a code from your partner? Enter it here.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if showInviteEntry {
                    HStack {
                        TextField("6-character code", text: $inviteCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemBackground))
                            .cornerRadius(8)
                            .onChange(of: inviteCode) { _, newValue in
                                // Limit to 6 chars, uppercase
                                inviteCode = String(newValue.uppercased().prefix(6))
                            }

                        Button("Connect", action: onAcceptInvite)
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .disabled(inviteCode.count < 6)
                    }
                } else {
                    Button {
                        showInviteEntry = true
                    } label: {
                        Label("Enter Code", systemImage: "person.badge.plus")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.tertiarySystemBackground))
                            .foregroundColor(.purple)
                            .cornerRadius(10)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
        }
    }
}

// MARK: - Partner Connected Card

private struct PartnerConnectedCard: View {
    let partner: PartnerProfile
    let onRefresh: () -> Void
    let onUnlink: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 52, height: 52)
                Text(String(partner.partnerName.prefix(1)).uppercased())
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Connected")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Text(partner.partnerName)
                    .font(.headline)
                Text("Linked \(partner.linkedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Menu {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive, action: onUnlink) {
                    Label("Unlink Partner", systemImage: "person.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
                    .font(.title3)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Shared Slots Section

private struct SharedSlotsSection: View {
    let slots: [SharedWalkSlot]
    let partnerName: String
    let isLoading: Bool
    @EnvironmentObject var notificationManager: NotificationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Shared Walk Slots — Today")
                    .font(.headline)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if slots.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.minus")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No shared slots found today")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Try refreshing or check tomorrow's schedule.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(slots) { slot in
                    SharedWalkSlotCard(
                        slot: slot,
                        partnerName: partnerName
                    )
                }
            }
        }
    }
}

// MARK: - Shared Walk Slot Card

private struct SharedWalkSlotCard: View {
    let slot: SharedWalkSlot
    let partnerName: String
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var suggested = false

    var confidenceColor: Color {
        slot.confidenceScore >= 0.8 ? .green : slot.confidenceScore >= 0.6 ? .orange : .red
    }

    var body: some View {
        HStack(spacing: 14) {
            // Time column
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.formattedTime)
                    .font(.headline)
                Text(slot.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 80, alignment: .leading)

            Divider()
                .frame(height: 40)

            // Details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(confidenceColor)
                        .frame(width: 8, height: 8)
                    Text(slot.confidenceScore >= 0.8 ? "Great time" : "Good time")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Both you and \(partnerName) are free")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Suggest button
            Button {
                suggestToPartner(slot)
            } label: {
                Image(systemName: suggested ? "checkmark.circle.fill" : "paperplane.fill")
                    .foregroundColor(suggested ? .green : .purple)
                    .font(.title3)
            }
            .disabled(suggested)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }

    private func suggestToPartner(_ slot: SharedWalkSlot) {
        notificationManager.scheduleWalkBuddySuggestion(slot: slot, partnerName: partnerName)
        withAnimation { suggested = true }
    }
}

// MARK: - Privacy Note Card

private struct PrivacyNoteCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy Protected")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("Only free/busy time blocks are shared — never your meeting titles, attendees, or other details. Your partner sees \"Busy 2–3pm\", not what you're doing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.green.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        CoupleWalkView()
            .environmentObject(CalendarManager.shared)
            .environmentObject(OutlookManager.shared)
            .environmentObject(NotificationManager.shared)
    }
}
