import Foundation
import StoreKit
import SwiftUI

// MARK: - Premium Feature Types

enum PremiumFeature: String, CaseIterable {
    case autopilot = "Autopilot Mode"
    case walkBuddy = "Walk Buddy"
    case insights = "AI Insights"
    case smartNotifications = "Smart Notifications"
    case calendarExport = "Calendar Export"
    case fullStreaks = "Full Streak System"

    var icon: String {
        switch self {
        case .autopilot: return "airplane"
        case .walkBuddy: return "figure.2.and.child.holdinghands"
        case .insights: return "brain.head.profile"
        case .smartNotifications: return "bell.badge.fill"
        case .calendarExport: return "calendar.badge.plus"
        case .fullStreaks: return "flame.fill"
        }
    }

    var description: String {
        switch self {
        case .autopilot: return "Auto-schedule walks around your calendar"
        case .walkBuddy: return "Coordinate walks with a partner"
        case .insights: return "Pattern graphs, plan explanations & timeline"
        case .smartNotifications: return "Walkable meeting alerts & step nudges"
        case .calendarExport: return "Sync walks to external calendars"
        case .fullStreaks: return "Progressive colors & identity levels"
        }
    }
}

// MARK: - Subscription Manager

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    // Product identifiers
    static let weeklyID = "com.activslot.healthapp.pro.weekly"
    static let monthlyID = "com.activslot.healthapp.pro.monthly"
    static let annualID = "com.activslot.healthapp.pro.annual"

    static let allProductIDs: Set<String> = [weeklyID, monthlyID, annualID]

    // Published state
    @Published private(set) var isProUser: Bool = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    // Cached entitlement
    @AppStorage("cachedProEntitlement") private var cachedEntitlement: Bool = false

    private var transactionListener: Task<Void, Error>?

    private init() {
        // Use cached entitlement until we verify with StoreKit
        isProUser = cachedEntitlement

        // Start listening for transactions
        transactionListener = listenForTransactions()

        // Load products and check entitlements
        Task {
            await loadProducts()
            await checkEntitlements()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product Loading

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: Self.allProductIDs)
            // Sort: weekly, monthly, annual
            products = storeProducts.sorted { p1, p2 in
                let order: [String: Int] = [
                    Self.weeklyID: 0,
                    Self.monthlyID: 1,
                    Self.annualID: 2
                ]
                return (order[p1.id] ?? 99) < (order[p2.id] ?? 99)
            }
        } catch {
            #if DEBUG
            print("SubscriptionManager: Failed to load products: \(error)")
            #endif
            errorMessage = "Failed to load subscription options."
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async throws -> Bool {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await updateEntitlements(transaction)
            await transaction.finish()
            return true

        case .userCancelled:
            return false

        case .pending:
            errorMessage = "Purchase is pending approval."
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            try await AppStore.sync()
            await checkEntitlements()
        } catch {
            errorMessage = "Failed to restore purchases."
        }
    }

    // MARK: - Entitlement Checking

    func checkEntitlements() async {
        var activePurchases: Set<String> = []

        for await result in StoreKit.Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                if transaction.revocationDate == nil {
                    activePurchases.insert(transaction.productID)
                }
            }
        }

        purchasedProductIDs = activePurchases
        let isPro = !activePurchases.isEmpty
        isProUser = isPro
        cachedEntitlement = isPro
    }

    func isFeatureUnlocked(_ feature: PremiumFeature) -> Bool {
        isProUser
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if let transaction = try? self?.checkVerified(result) {
                    await self?.updateEntitlements(transaction)
                    await transaction.finish()
                }
            }
        }
    }

    private func updateEntitlements(_ transaction: StoreKit.Transaction) async {
        if transaction.revocationDate == nil {
            purchasedProductIDs.insert(transaction.productID)
        } else {
            purchasedProductIDs.remove(transaction.productID)
        }

        let isPro = !purchasedProductIDs.isEmpty
        isProUser = isPro
        cachedEntitlement = isPro
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let value):
            return value
        }
    }

    // MARK: - Helpers

    var weeklyProduct: Product? { products.first { $0.id == Self.weeklyID } }
    var monthlyProduct: Product? { products.first { $0.id == Self.monthlyID } }
    var annualProduct: Product? { products.first { $0.id == Self.annualID } }

    /// Formatted savings text for annual plan vs monthly
    var annualSavingsText: String? {
        guard let monthly = monthlyProduct,
              let annual = annualProduct else { return nil }

        let monthlyAnnualized = monthly.price * 12
        let savings = monthlyAnnualized - annual.price
        guard savings > 0 else { return nil }

        let percent = NSDecimalNumber(decimal: savings / monthlyAnnualized * 100).intValue
        return "Save \(percent)%"
    }
}

// MARK: - Errors

enum SubscriptionError: LocalizedError {
    case verificationFailed
    case purchaseFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed: return "Transaction verification failed"
        case .purchaseFailed: return "Purchase failed"
        }
    }
}
