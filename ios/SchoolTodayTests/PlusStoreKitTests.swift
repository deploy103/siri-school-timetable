import XCTest
import StoreKit
import StoreKitTest
@testable import StoreKitTestHost

/// One ordered contract: run without parallel testing (the StoreKit session and store are shared).
/// The empty host does not construct PlusStore; configure the local session before its first use.
/// This covers the real store implementation, not SchoolTodayApp's launch lifecycle.
final class PlusStoreKitTests: XCTestCase {
    @MainActor
    func testLocalSubscriptionLifecycle() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Plus", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
        // Drive a natural lapse: expireSubscription can leave SK2 subscribed on iOS Simulator.
        session.timeRate = .oneRenewalEveryTenSeconds
        PlusStore.diagnostic("test configured rate=\(session.timeRate)")
        let store = PlusStore.shared
        addTeardownBlock {
            await PlusStore.diagnostic("teardown begin")
            try await session.setSimulatedError(nil, forAPI: .loadProducts)
            session.clearTransactions()
            session.resetToDefaultState()
            await store.refresh()
            await PlusStore.diagnostic("teardown end")
        }

        // Exercise failure and retry against Apple's local server, not App Store availability.
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))),
                                            forAPI: .loadProducts)
        await store.load()
        XCTAssertFalse(store.loading)
        XCTAssertFalse(store.isPlus)
        XCTAssertTrue(store.products.isEmpty)
        XCTAssertTrue(store.eligibleTrials.isEmpty)
        XCTAssertEqual(store.message, "구독 가격을 불러오지 못했어요. 네트워크를 확인하고 다시 시도해 주세요.")

        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.load()
        XCTAssertFalse(store.isPlus)
        XCTAssertFalse(store.loading)
        XCTAssertNil(store.message)
        let monthlyID = "com.deploy103.schooltoday.plus.monthly"
        let yearlyID = "com.deploy103.schooltoday.plus.yearly"
        XCTAssertEqual(store.products.map(\.id), [monthlyID, yearlyID])
        let monthly = try XCTUnwrap(store.products.first { $0.id == monthlyID })
        let yearly = try XCTUnwrap(store.products.first { $0.id == yearlyID })
        let catalog = XCTAttachment(string: store.products.map { String(decoding: $0.jsonRepresentation, as: UTF8.self) }.joined(separator: "\n"))
        catalog.name = "Local StoreKit catalog"
        catalog.lifetime = .keepAlways
        add(catalog)
        XCTAssertEqual(monthly.type, .autoRenewable)
        XCTAssertEqual(yearly.type, .autoRenewable)
        XCTAssertEqual(monthly.price, Decimal(string: "1.90"))
        XCTAssertEqual(yearly.price, Decimal(string: "14.90"))
        XCTAssertEqual(monthly.priceFormatStyle.currencyCode, "USD")
        XCTAssertEqual(yearly.priceFormatStyle.currencyCode, "USD")
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.value, 1)
        XCTAssertEqual(yearly.subscription?.subscriptionPeriod.unit, .year)
        XCTAssertEqual(yearly.subscription?.subscriptionPeriod.value, 1)

        PlusStore.diagnostic("test monthly purchase begin")
        await store.purchase(monthly)
        PlusStore.diagnostic("test monthly purchase end access=\(store.isPlus)")
        XCTAssertTrue(store.isPlus, store.message ?? "Purchase did not activate access")
        XCTAssertFalse(store.purchasing)
        let purchased = try await assertVerifiedAccess(productID: monthlyID)

        try session.disableAutoRenewForTransaction(identifier: UInt(purchased.id))
        // Wait for Apple's independent lapse, then test our refresh against it.
        try await waitForNoEntitlements()
        PlusStore.diagnostic("test natural lapse confirmed; explicit refresh begin")
        await store.refresh()
        PlusStore.diagnostic("test post-lapse refresh end access=\(store.isPlus)")
        XCTAssertFalse(store.isPlus, "A lapsed subscription must not grant access")

        // Keep later restore/refund checks independent of the accelerated lapse clock.
        PlusStore.diagnostic("test before rate change rate=\(session.timeRate)")
        session.timeRate = .realTime
        PlusStore.diagnostic("test rate changed rate=\(session.timeRate)")
        // No refresh/load/restore in either poll: only Transaction.updates can change access.
        PlusStore.diagnostic("test external yearly purchase begin")
        let external = try await session.buyProduct(identifier: yearlyID)
        PlusStore.diagnostic("test external yearly returned \(PlusStore.diagnosticTransaction(external))")
        try await waitForAccess(true, store: store)
        try await assertVerifiedAccess(productID: yearlyID)

        // AppStore.sync runs against the local session, never a fabricated entitlement.
        await store.restore()
        XCTAssertFalse(store.purchasing)
        XCTAssertTrue(store.isPlus)
        XCTAssertEqual(store.message, "Plus 구독을 복원했어요.")
        try await assertVerifiedAccess(productID: yearlyID)
        try session.refundTransaction(identifier: UInt(external.id))
        try await waitForAccess(false, store: store)
    }

    @MainActor
    private func waitForAccess(_ expected: Bool, store: PlusStore,
                               file: StaticString = #filePath, line: UInt = #line) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        PlusStore.diagnostic("test passive wait begin expected=\(expected) access=\(store.isPlus)")
        while store.isPlus != expected && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard store.isPlus == expected else {
            PlusStore.diagnostic("test passive deadline FAILED expected=\(expected) access=\(store.isPlus)")
            XCTFail("Passive transaction listener missed access change to \(expected)", file: file, line: line)
            await failureSnapshot()
            throw Timeout.access
        }
        PlusStore.diagnostic("test passive wait passed expected=\(expected) access=\(store.isPlus)")
    }

    @MainActor
    private func failureSnapshot() async {
        // Read only after XCTFail: observing StoreKit must never rescue the passive-wait assertion.
        PlusStore.diagnostic("failure-only snapshot begin; outcome already FAILED")
        var count = 0
        for await result in Transaction.currentEntitlements {
            count += 1
            if case .verified(let transaction) = result {
                PlusStore.diagnostic("failure snapshot current \(PlusStore.diagnosticTransaction(transaction))")
            } else {
                PlusStore.diagnostic("failure snapshot current unverified")
            }
        }
        PlusStore.diagnostic("failure snapshot current ended count=\(count)")
        for id in PlusStore.productIDs {
            let latest = await Transaction.latest(for: id)
            if case .verified(let transaction)? = latest {
                PlusStore.diagnostic("failure snapshot latest \(PlusStore.diagnosticTransaction(transaction))")
            } else {
                PlusStore.diagnostic("failure snapshot latest product=\(id) absent or unverified")
            }
        }
        PlusStore.diagnostic("failure-only snapshot end; outcome remains FAILED")
    }

    @MainActor
    private func waitForNoEntitlements(file: StaticString = #filePath, line: UInt = #line) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(20))
        repeat {
            var entitled = false
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   PlusStore.productIDs.contains(transaction.productID) { entitled = true }
            }
            if !entitled { return }
            try await Task.sleep(for: .milliseconds(50))
        } while clock.now < deadline
        XCTFail("StoreKit still reports a current entitlement after natural expiration", file: file, line: line)
        throw Timeout.entitlements
    }

    private enum Timeout: Error { case access, entitlements }

    @discardableResult
    private func assertVerifiedAccess(productID: String,
                                      file: StaticString = #filePath, line: UInt = #line) async throws -> Transaction {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID,
                  transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            XCTAssertEqual(transaction.environment, .xcode, "Only local test transactions are allowed",
                           file: file, line: line)
            XCTAssertTrue(transaction.expirationDate.map { $0 > Date() } ?? false,
                          "Expected an unexpired subscription", file: file, line: line)
            return transaction
        }
        XCTFail("No verified current entitlement for \(productID)", file: file, line: line)
        throw Timeout.entitlements
    }
}
