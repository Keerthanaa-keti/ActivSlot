import SwiftUI

// MARK: - Premium Feature Overlay

struct PremiumFeatureOverlay: View {
    let feature: PremiumFeature
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showPaywall = false

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.title2)
                    .foregroundColor(.white)

                Text("PRO")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.orange)
                    )

                Text(feature.rawValue)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial.opacity(0.95))
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(triggeredBy: feature)
        }
    }
}

// MARK: - Premium Gated View Modifier

struct PremiumGatedModifier: ViewModifier {
    let feature: PremiumFeature
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared

    func body(content: Content) -> some View {
        if subscriptionManager.isProUser {
            content
        } else {
            content
                .blur(radius: 4)
                .overlay {
                    PremiumFeatureOverlay(feature: feature)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

extension View {
    func premiumGated(_ feature: PremiumFeature) -> some View {
        modifier(PremiumGatedModifier(feature: feature))
    }
}

// MARK: - Premium Badge (inline indicator for settings rows)

struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.orange, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
    }
}

// MARK: - Upgrade Prompt Banner

struct UpgradePromptBanner: View {
    let message: String
    @State private var showPaywall = false

    var body: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Unlock ActivSlot Pro")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("Upgrade")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .orange.opacity(0.15), radius: 8, y: 2)
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
