import Foundation
import Combine
import StoreKit

@MainActor
final class TipJarStore: ObservableObject {

    enum PurchaseResult: Equatable {
        case idle
        case success
        case pending
        case cancelled
        case unavailable
        case failed
    }

    struct ProductOption: Identifiable {
        let id: String
        let fallbackTitle: String
    }

    static let smallTipID = "com.pulseaisolution.skitracker.tip.small"
    static let largeTipID = "com.pulseaisolution.skitracker.tip.large"

    let options: [ProductOption] = [
        ProductOption(id: "com.pulseaisolution.skitracker.tip.small", fallbackTitle: "$2.99"),
        ProductOption(id: "com.pulseaisolution.skitracker.tip.large", fallbackTitle: "$5.99")
    ]

    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var activePurchaseID: String?
    @Published var purchaseResult: PurchaseResult = .idle

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: options.map(\.id))
            productsByID = Dictionary(uniqueKeysWithValues: storeProducts.map { ($0.id, $0) })
        } catch {
            productsByID = [:]
        }
    }

    func title(for option: ProductOption) -> String {
        productsByID[option.id]?.displayPrice ?? option.fallbackTitle
    }

    func purchase(option: ProductOption) async {
        guard let product = productsByID[option.id] else {
            purchaseResult = .unavailable
            return
        }

        activePurchaseID = option.id
        defer { activePurchaseID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                purchaseResult = .success
            case .pending:
                purchaseResult = .pending
            case .userCancelled:
                purchaseResult = .cancelled
            @unknown default:
                purchaseResult = .failed
            }
        } catch {
            purchaseResult = .failed
        }
    }

    private func checkVerified<T>(_ verification: VerificationResult<T>) throws -> T {
        switch verification {
        case .verified(let signedType):
            return signedType
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

private enum StoreError: Error {
    case failedVerification
}
