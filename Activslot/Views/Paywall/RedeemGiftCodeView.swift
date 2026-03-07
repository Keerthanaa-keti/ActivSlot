import SwiftUI

struct RedeemGiftCodeView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isRedeeming = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "gift.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .pink],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                Text("Redeem Gift Code")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Enter your gift code to unlock ActivSlot Pro.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                TextField("Enter code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.title3.monospaced())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Button {
                    Task { await redeem() }
                } label: {
                    HStack {
                        if isRedeeming {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isRedeeming ? "Verifying..." : "Redeem")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(code.count >= 6 ? Color.orange : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(code.count < 6 || isRedeeming)
                .padding(.horizontal, 40)

                Spacer()
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Pro Unlocked!", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("You now have full access to all ActivSlot Pro features. Enjoy!")
            }
        }
    }

    private func redeem() async {
        errorMessage = nil
        isRedeeming = true
        defer { isRedeeming = false }

        if let error = await subscriptionManager.redeemGiftCode(code) {
            errorMessage = error
        } else {
            showSuccess = true
        }
    }
}
