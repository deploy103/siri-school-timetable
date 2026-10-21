import XCTest
import StoreKit
import StoreKitTest
@testable import StoreKitTestHost

/// Run each ordered contract alone without parallel testing (session and store are shared).
/// The empty host does not construct PlusStore; configure the local session before its first use.
/// This covers the real store implementation, not SchoolTodayApp's launch lifecycle.
final class PlusStoreKitTests: XCTestCase {
    /// Diagnostic reference only: run alone on a fresh runner without constructing the app store.
    @MainActor
    func testRawStoreKitExternalYearlyDelivery() async throws {
        func log(_ event: String) {
            print("SKRAW wall=\(Date().timeIntervalSince1970) uptime=\(ProcessInfo.processInfo.systemUptime) \(event)")
        }
        func details(_ transaction: Transaction) -> String {
            "id=\(transaction.id) product=\(transaction.productID) environment=\(transaction.environment) purchased=\(transaction.purchaseDate.timeIntervalSince1970) expires=\(String(describing: transaction.expirationDate?.timeIntervalSince1970)) revoked=\(String(describing: transaction.revocationDate?.timeIntervalSince1970)) upgraded=\(transaction.isUpgraded)"
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Plus", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
        session.timeRate = .realTime
        log("configured rate=\(session.timeRate)")

        let clock = ContinuousClock()
        var aboutToAwaitNext = false
        var listenerExited = false
        var received: [(at: ContinuousClock.Instant, result: VerificationResult<Transaction>)] = []
        let listener = Task { @MainActor in
            defer { listenerExited = true; log("listener exited cancelled=\(Task.isCancelled)") }
            var iterator = Transaction.updates.makeAsyncIterator()
            log("about to await first next; SDK registration is UNCONFIRMED")
            aboutToAwaitNext = true
            while let result = await iterator.next() {
                received.append((clock.now, result))
                switch result {
                case .verified(let transaction): log("received verified \(details(transaction))")
                case .unverified(let transaction, let error): log("received unverified \(details(transaction)) error=\(error)")
                }
                guard !Task.isCancelled else { return }
            }
        }
        addTeardownBlock { @MainActor in
            log("teardown begin")
            listener.cancel()
            session.clearTransactions()
            session.resetToDefaultState()
            log("session cleared; awaiting listener exit; exited=\(listenerExited)")
            await listener.value
            log("teardown end")
        }

        let startDeadline = clock.now.advanced(by: .seconds(10))
        while !aboutToAwaitNext && clock.now < startDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard aboutToAwaitNext, !listenerExited, clock.now < startDeadline else {
            XCTFail("Raw listener did not reach its first next(); no delivery control established")
            throw Timeout.access
        }
        let yearlyID = "com.deploy103.schooltoday.plus.yearly"
        log("external purchase begin; local listener milestone only, SDK registration UNCONFIRMED")
        let transaction = try await session.buyProduct(identifier: yearlyID)
        log("external returned \(details(transaction)); buffered=\(received.count)")
        guard transaction.productID == yearlyID, transaction.environment == .xcode,
              transaction.revocationDate == nil, !transaction.isUpgraded,
              transaction.expirationDate.map({ $0 > Date() }) == true else {
            XCTFail("Raw purchase did not return a live local yearly transaction")
            throw Timeout.entitlements
        }

        let deadline = clock.now.advanced(by: .seconds(10))
        func delivered() -> Bool {
            received.contains { event in
                guard event.at < deadline, case .verified(let value) = event.result else { return false }
                return value.id == transaction.id && value.productID == yearlyID && value.environment == .xcode
            }
        }
        log("passive wait begin; matching verified delivery required; budget=10s")
        while !delivered() && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard delivered(), clock.now < deadline else {
            XCTFail("Raw StoreKit missed matching verified yearly delivery; events=\(received.count) listenerExited=\(listenerExited)")
            let began = clock.now
            let observationDeadline = began.advanced(by: .seconds(120))
            log("observation begin; outcome already FAILED; budget=120s events=\(received.count)")
            while clock.now < observationDeadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            log("observation end elapsed=\(began.duration(to: clock.now)) events=\(received.count) listenerExited=\(listenerExited); outcome remains FAILED")
            throw Timeout.access
        }
        log("passive matching verified delivery passed; events=\(received.count)")
    }

    /// Run alone in a fresh host: distinguish passive delivery from accelerated-clock handoff.
    @MainActor
    func testExternalYearlyDeliveryInRealTime() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Plus", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
        session.timeRate = .realTime
        PlusStore.diagnostic("yearly control configured rate=\(session.timeRate)")
        let store = PlusStore.shared
        addTeardownBlock {
            await PlusStore.diagnostic("yearly control teardown begin")
            session.clearTransactions()
            session.resetToDefaultState()
            await store.refresh()
            await PlusStore.diagnostic("yearly control teardown end")
        }

        await store.load()
        // Wait only on diagnostic state: no additional StoreKit enumeration or refresh.
        let readinessClock = ContinuousClock()
        let began = readinessClock.now
        let readinessDeadline = began.advanced(by: .seconds(120))
        PlusStore.diagnostic("yearly control readiness begin startupFinished=\(store.diagnosticStartupRefreshFinished) inFlight=\(store.diagnosticRefreshesInFlight)")
        while (!store.diagnosticStartupRefreshFinished || store.diagnosticRefreshesInFlight > 0)
                && readinessClock.now < readinessDeadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        PlusStore.diagnostic("yearly control readiness end elapsed=\(began.duration(to: readinessClock.now)) startupFinished=\(store.diagnosticStartupRefreshFinished) inFlight=\(store.diagnosticRefreshesInFlight)")
        guard readinessClock.now < readinessDeadline,
              store.diagnosticStartupRefreshFinished, store.diagnosticRefreshesInFlight == 0 else {
            XCTFail("Initial refreshes did not settle before the yearly control")
            throw Timeout.access
        }
        XCTAssertFalse(store.isPlus)
        guard !store.isPlus else { throw Timeout.access }
        let yearlyID = "com.deploy103.schooltoday.plus.yearly"
        _ = try XCTUnwrap(store.products.first { $0.id == yearlyID })
        PlusStore.diagnostic("yearly control external purchase begin")
        let transaction = try await session.buyProduct(identifier: yearlyID)
        PlusStore.diagnostic("yearly control external returned \(PlusStore.diagnosticTransaction(transaction))")
        // No entitlement reads or manual refresh between purchase and the passive assertion.
        try await waitForYearlyControlAccess(true, store: store)
        try await assertVerifiedAccess(productID: yearlyID)
        try session.refundTransaction(identifier: UInt(transaction.id))
        try await waitForYearlyControlAccess(false, store: store)
    }

    @MainActor
    func testLocalSubscriptionLifecycle() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Plus", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.storefront = "USA"
        session.locale = Locale(identifier: "en_US")
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
        guard store.isPlus, !store.purchasing else { throw Timeout.access }
        let purchased = try await assertVerifiedAccess(productID: monthlyID)

        PlusStore.diagnostic("test disable renewal begin id=\(purchased.id)")
        try session.disableAutoRenewForTransaction(identifier: UInt(purchased.id))
        PlusStore.diagnostic("test disable renewal end id=\(purchased.id)")
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
    private func waitForYearlyControlAccess(_ expected: Bool, store: PlusStore,
                                             file: StaticString = #filePath, line: UInt = #line) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        PlusStore.diagnostic("yearly control passive wait begin expected=\(expected) access=\(store.isPlus)")
        while store.isPlus != expected && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard store.isPlus == expected, clock.now < deadline else {
            XCTFail("Passive transaction listener missed access change to \(expected)", file: file, line: line)
            // Outcome is final. Observe only app state; Apple reads could influence delivery.
            let began = clock.now
            let observationDeadline = began.advanced(by: .seconds(120))
            var previous = store.isPlus
            PlusStore.diagnostic("yearly control observation begin; outcome already FAILED; budget=120s access=\(previous)")
            defer {
                PlusStore.diagnostic("yearly control observation end elapsed=\(began.duration(to: clock.now)) access=\(store.isPlus); outcome remains FAILED")
            }
            while clock.now < observationDeadline {
                try await Task.sleep(for: .milliseconds(50))
                let current = store.isPlus
                if current != previous {
                    PlusStore.diagnostic("yearly control observed transition elapsed=\(began.duration(to: clock.now)) access=\(current); outcome remains FAILED")
                    previous = current
                }
            }
            throw Timeout.access
        }
        PlusStore.diagnostic("yearly control passive wait passed expected=\(expected) access=\(store.isPlus)")
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
        guard store.isPlus == expected, clock.now < deadline else {
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
        var previous: [String]?
        PlusStore.diagnostic("test natural lapse observation begin; budget=20s")
        repeat {
            var entitled = false
            var observed: [String] = []
            let began = clock.now
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   PlusStore.productIDs.contains(transaction.productID) {
                    entitled = true
                    observed.append(PlusStore.diagnosticTransaction(transaction))
                }
            }
            let snapshot = observed.sorted()
            let elapsed = began.duration(to: clock.now)
            if snapshot != previous || elapsed >= .seconds(1) {
                PlusStore.diagnostic("test lapse enumeration elapsed=\(elapsed) transactions=\(snapshot)")
                previous = snapshot
            }
            // A slow read must not turn an empty result after the budget into a pass.
            if clock.now >= deadline { break }
            if !entitled { return }
            try await Task.sleep(for: .milliseconds(50))
        } while clock.now < deadline
        XCTFail("StoreKit still reports a current entitlement after natural expiration", file: file, line: line)
        throw Timeout.entitlements
    }

    private enum Timeout: Error { case access, entitlements }

    @MainActor
    @discardableResult
    private func assertVerifiedAccess(productID: String,
                                      file: StaticString = #filePath, line: UInt = #line) async throws -> Transaction {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID,
                  transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            PlusStore.diagnostic("test verified-access observation \(PlusStore.diagnosticTransaction(transaction))")
            XCTAssertEqual(transaction.environment, .xcode, "Only local test transactions are allowed",
                           file: file, line: line)
            let unexpired = transaction.expirationDate.map { $0 > Date() } ?? false
            XCTAssertTrue(unexpired,
                          "Expected an unexpired subscription", file: file, line: line)
            guard transaction.environment == .xcode, unexpired else { throw Timeout.entitlements }
            return transaction
        }
        XCTFail("No verified current entitlement for \(productID)", file: file, line: line)
        throw Timeout.entitlements
    }
}
