import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss

    let triggeredBy: PremiumFeature?

    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    @State private var showError = false
    @State private var errorText = ""
    @State private var showTerms = false
    @State private var showPrivacy = false

    init(triggeredBy: PremiumFeature? = nil) {
        self.triggeredBy = triggeredBy
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    featureGrid

                    if subscriptionManager.isLoading {
                        ProgressView("Loading plans...")
                            .padding(40)
                    } else if subscriptionManager.products.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title)
                                .foregroundColor(.orange)
                            Text("Subscriptions are being set up")
                                .font(.headline)
                            Text("Plans will be available soon. Please try again later.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            if let error = subscriptionManager.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                            Button("Try Again") {
                                Task { await subscriptionManager.loadProducts() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(40)
                    } else {
                        planSelector
                        purchaseButton
                    }

                    legalLinks
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorText)
            }
            .task {
                if subscriptionManager.products.isEmpty {
                    await subscriptionManager.loadProducts()
                }
                selectedProduct = subscriptionManager.annualProduct ?? subscriptionManager.products.first
            }
            .onChange(of: subscriptionManager.isProUser) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("ActivSlot Pro")
                .font(.title)
                .fontWeight(.bold)

            if let feature = triggeredBy {
                Text("Unlock \(feature.rawValue) and more")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text("Get the most out of your walking plan")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Feature Grid

    private var featureGrid: some View {
        VStack(spacing: 0) {
            ForEach(PremiumFeature.allCases, id: \.self) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.body)
                        .foregroundColor(feature == triggeredBy ? .orange : .green)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(feature.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)

                if feature != PremiumFeature.allCases.last {
                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
        )
    }

    // MARK: - Plan Selector

    private var planSelector: some View {
        VStack(spacing: 12) {
            ForEach(subscriptionManager.products, id: \.id) { product in
                PlanOptionRow(
                    product: product,
                    isSelected: selectedProduct?.id == product.id,
                    badge: badgeText(for: product)
                ) {
                    selectedProduct = product
                }
            }

            if subscriptionManager.products.isEmpty && subscriptionManager.isLoading {
                ProgressView("Loading plans...")
                    .padding()
            }
        }
    }

    private func badgeText(for product: Product) -> String? {
        if product.id == SubscriptionManager.annualID {
            return subscriptionManager.annualSavingsText ?? "Best Value"
        }
        return nil
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        VStack(spacing: 12) {
            Button {
                Task { await handlePurchase() }
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else if let product = selectedProduct {
                        if product.id == SubscriptionManager.annualID {
                            Text("Start 7-Day Free Trial")
                        } else {
                            Text("Subscribe for \(product.displayPrice)/\(periodLabel(product))")
                        }
                    } else {
                        Text("Subscribe")
                    }
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(selectedProduct == nil || isPurchasing)

            if selectedProduct?.id == SubscriptionManager.annualID {
                Text("7-day free trial, then \(selectedProduct?.displayPrice ?? "")/year")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button("Restore Purchases") {
                Task { await subscriptionManager.restorePurchases() }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Legal Links

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Button("Terms of Service") {
                showTerms = true
            }
            .font(.caption2)
            .foregroundColor(.secondary)

            Text("|")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button("Privacy Policy") {
                showPrivacy = true
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.bottom, 8)
        .sheet(isPresented: $showTerms) {
            NavigationStack {
                TermsOfServiceView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showTerms = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showPrivacy = false }
                        }
                    }
            }
        }
    }

    // MARK: - Helpers

    private func handlePurchase() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let success = try await subscriptionManager.purchase(product)
            if success {
                dismiss()
            }
        } catch {
            errorText = error.localizedDescription
            showError = true
        }
    }

    private func periodLabel(_ product: Product) -> String {
        switch product.id {
        case SubscriptionManager.weeklyID: return "week"
        case SubscriptionManager.monthlyID: return "month"
        case SubscriptionManager.annualID: return "year"
        default: return "period"
        }
    }
}

// MARK: - Plan Option Row

struct PlanOptionRow: View {
    let product: Product
    let isSelected: Bool
    let badge: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .orange : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(planName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.orange)
                                )
                        }
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.orange : Color(.separator), lineWidth: isSelected ? 2 : 0.5)
                    )
            )
        }
    }

    private var planName: String {
        switch product.id {
        case SubscriptionManager.weeklyID: return "Weekly"
        case SubscriptionManager.monthlyID: return "Monthly"
        case SubscriptionManager.annualID: return "Annual"
        default: return product.displayName
        }
    }

    private var subtitle: String {
        switch product.id {
        case SubscriptionManager.weeklyID: return "Billed weekly"
        case SubscriptionManager.monthlyID: return "Billed monthly"
        case SubscriptionManager.annualID: return "7-day free trial included"
        default: return ""
        }
    }
}

#Preview {
    PaywallView(triggeredBy: .insights)
}
