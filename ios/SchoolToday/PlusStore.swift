import Combine
import StoreKit

/// Instantiate `shared` at app launch; call `refresh()` when the app becomes active.
/// Access is derived only from Apple's verified current entitlements, never local preferences.
@MainActor
final class PlusStore: ObservableObject {
    static let shared = PlusStore()
    static let productIDs = [
        "com.deploy103.schooltoday.plus.monthly",
        "com.deploy103.schooltoday.plus.yearly"
    ]

    @Published private(set) var isPlus = false
    @Published private(set) var validUntil: Date?
    @Published private(set) var products: [Product] = []
    @Published private(set) var eligibleTrials: Set<String> = []
    @Published private(set) var loading = false
    @Published private(set) var purchasing = false
    @Published private(set) var message: String?
    private var updates: Task<Void, Never>?
    private var refreshGeneration = 0

    private init() {
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard let self else { return }
                switch result {
                case .verified(let transaction):
                    guard Self.productIDs.contains(transaction.productID),
                          transaction.productType == .autoRenewable else { continue }
                    await self.refresh()
                    await transaction.finish()
                case .unverified(let transaction, _):
                    if Self.productIDs.contains(transaction.productID) {
                        self.message = "구독을 안전하게 확인하지 못했어요. 잠시 후 다시 확인해 주세요."
                    }
                }
            }
        }
        Task { [weak self] in
            await self?.refresh()
        }
    }

    deinit { updates?.cancel() }

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        message = nil
        await refresh()
        do {
            let catalog = try await Product.products(for: Self.productIDs)
            products = catalog.filter { $0.type == .autoRenewable && $0.subscription != nil }
                .sorted { (Self.productIDs.firstIndex(of: $0.id) ?? 2) < (Self.productIDs.firstIndex(of: $1.id) ?? 2) }
            var trials = Set<String>()
            for product in products {
                if let subscription = product.subscription, subscription.introductoryOffer?.paymentMode == .freeTrial,
                   await subscription.isEligibleForIntroOffer { trials.insert(product.id) }
            }
            eligibleTrials = trials
            if products.isEmpty { message = "구독 상품을 불러오지 못했어요. 다시 시도해 주세요." }
        } catch {
            message = "구독 가격을 불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요."
        }
    }

    func refresh() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        var entitled = false
        var until: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            // currentEntitlements includes billing grace periods and excludes expired subscriptions.
            entitled = true
            // Bound work handed to the OS even if the app is never opened after expiration.
            // A verified grace entitlement gets a short lease until it is checked again.
            let end = transaction.expirationDate.flatMap { $0 > Date() ? $0 : nil } ?? Date().addingTimeInterval(3600)
            until = max(until ?? end, end)
        }
        if generation == refreshGeneration { validUntil = until; isPlus = entitled }
    }

    func purchase(_ product: Product) async {
        guard !purchasing, !isPlus else { return }
        guard Self.productIDs.contains(product.id), product.type == .autoRenewable else { return }
        purchasing = true
        message = nil
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result,
                      Self.productIDs.contains(transaction.productID),
                      transaction.productType == .autoRenewable else {
                    message = "결제를 확인하지 못했어요. 구입 복원을 시도해 주세요."
                    return
                }
                await refresh()
                await transaction.finish()
                message = isPlus ? "Plus가 활성화되었어요." : "결제는 확인했지만 활성 구독이 없어요. 구입 복원을 시도해 주세요."
            case .pending:
                message = "구입 승인을 기다리고 있어요. 승인되면 자동으로 활성화됩니다."
            case .userCancelled:
                message = "구입을 취소했어요. 결제하지 않고 계속 이용할 수 있어요."
            @unknown default:
                message = "구입 상태를 확인 중이에요. 잠시 후 다시 확인해 주세요."
            }
        } catch {
            message = "구입을 완료하지 못했어요. 네트워크와 Apple 계정을 확인하고 다시 시도해 주세요."
        }
    }

    func restore() async {
        guard !purchasing else { return }
        purchasing = true
        message = nil
        defer { purchasing = false }
        do {
            try await AppStore.sync()
            await refresh()
            message = isPlus ? "Plus 구독을 복원했어요." : "이 Apple 계정에 활성 Plus 구독이 없어요."
        } catch {
            message = "구입을 복원하지 못했어요. Apple 계정과 네트워크를 확인해 주세요."
        }
    }
}
