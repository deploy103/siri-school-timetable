import Foundation
import Combine
import CloudKit

/// No subscriptions, background tasks, persistence, or network requests until explicitly called.
@MainActor
final class PlannerCloud: ObservableObject {
    static let shared = PlannerCloud()
    @Published private(set) var busy = false
    @Published private(set) var message: String?

    struct SyncResult {
        let plan: PreparationPlan
        /// Persist these exact bytes, together with account, only after applying plan locally.
        let base: Data
        let account: String
    }

    struct Conflict: Error, LocalizedError {
        let local: PreparationPlan
        let remote: PreparationPlan
        let remoteData: Data
        let account: String
        var errorDescription: String? { "기기와 iCloud의 준비 기록이 모두 변경됐어요. 사용할 기록을 직접 선택해 주세요." }
    }

    enum Failure: Error, LocalizedError {
        case busy, accountUnavailable, accountChanged(current: String), remoteMissing
        case unreadableArchive, unsupportedArchive, payloadTooLarge, incompleteSave, concurrentChange

        var errorDescription: String? {
            switch self {
            case .busy: return "이미 준비 기록을 동기화하고 있어요."
            case .accountUnavailable: return "iCloud 계정에 로그인하고 접근을 허용해 주세요."
            case .accountChanged: return "iCloud 계정이 바뀌었어요. 새 계정 사용을 확인한 뒤 동기화 기준을 초기화해 주세요."
            case .remoteMissing: return "이전에 동기화한 iCloud 기록이 없어졌어요. 자동으로 다시 만들지 않았어요. 복원을 직접 확인해 주세요."
            case .unreadableArchive: return "준비 기록을 읽을 수 없어 덮어쓰지 않았어요."
            case .unsupportedArchive: return "지원하지 않는 준비 기록 형식이에요. 앱 업데이트를 확인해 주세요."
            case .payloadTooLarge: return "준비 기록이 동기화 제한(256 KiB)을 초과했어요. 기록을 줄인 뒤 다시 시도해 주세요."
            case .incompleteSave: return "iCloud 저장 결과를 확인할 수 없어요. 다시 동기화해 주세요."
            case .concurrentChange: return "동기화 중 iCloud 기록이 바뀌었어요. 다시 동기화하고 사용할 기록을 선택해 주세요."
            }
        }
    }

    enum Choice { case local, remote }
    private lazy var container = CKContainer(identifier: "iCloud.com.deploy103.schooltoday")
    private let recordID = CKRecord.ID(recordName: "preparation-v1")
    private let maximumBytes = 256 * 1024
    private var database: CKDatabase { container.privateCloudDatabase }

    private init() {}

    /// After explicit account-change confirmation, the caller discards its persisted base/account
    /// and calls with both nil. This still conflicts if the new account has different nonempty data.
    /// After confirmed remote-loss recovery, discard base only; retain the expected account.
    func synchronize(local: PreparationPlan, base: Data?, expectedAccount: String?) async throws -> SyncResult {
        try begin()
        defer { busy = false }
        do {
            let account = try await identity(expected: expectedAccount)
            let localData = try encode(local)
            let ancestor = try base.map { try decode($0) }
            let record = try await fetch()
            guard let record else {
                guard base == nil else { throw Failure.remoteMissing }
                let result = try await save(local, data: localData, record: nil, account: account)
                message = "준비 기록을 동기화했어요."
                return result
            }
            let (remote, remoteData) = try archive(record)
            let chosen: PreparationPlan
            if local == remote { chosen = remote }
            else if let ancestor {
                if local == ancestor { chosen = remote }
                else if remote == ancestor { chosen = local }
                else { throw Conflict(local: local, remote: remote, remoteData: remoteData, account: account) }
            } else if local == PreparationPlan() { chosen = remote }
            else if remote == PreparationPlan() { chosen = local }
            else { throw Conflict(local: local, remote: remote, remoteData: remoteData, account: account) }

            let result: SyncResult
            if chosen == remote {
                result = SyncResult(plan: remote, base: remoteData, account: account)
            } else {
                result = try await save(chosen, data: localData, record: record, account: account)
            }
            message = "준비 기록을 동기화했어요."
            return result
        } catch {
            message = safeMessage(error)
            throw error
        }
    }

    /// Only call after a user chooses a side. Refetches the change tag and refuses a stale choice.
    /// Neither unreadable archives nor deleted remote records can be overridden by this API.
    func resolve(_ conflict: Conflict, choosing choice: Choice) async throws -> SyncResult {
        try begin()
        defer { busy = false }
        do {
            let account = try await identity(expected: conflict.account)
            guard let record = try await fetch() else { throw Failure.remoteMissing }
            let (remote, data) = try archive(record)
            guard data == conflict.remoteData else { throw Failure.concurrentChange }
            let result: SyncResult
            switch choice {
            case .remote: result = SyncResult(plan: remote, base: data, account: account)
            case .local:
                result = try await save(conflict.local, data: encode(conflict.local), record: record, account: account)
            }
            message = "선택한 준비 기록을 동기화했어요."
            return result
        } catch {
            message = safeMessage(error)
            throw error
        }
    }

    private func begin() throws {
        guard !busy else { throw Failure.busy }
        busy = true
        message = nil
    }

    private func identity(expected: String?) async throws -> String {
        guard try await container.accountStatus() == .available else { throw Failure.accountUnavailable }
        // Resolve the current-user alias to its stable, account-specific record ID.
        // Never persist CKCurrentUserDefaultName itself: it is identical across accounts.
        let id = try await container.userRecordID().recordName
        if let expected, expected != id { throw Failure.accountChanged(current: id) }
        return id
    }

    private func fetch() async throws -> CKRecord? {
        do { return try await database.record(for: recordID) }
        catch let error as CKError where error.code == .unknownItem { return nil }
    }

    private func archive(_ record: CKRecord) throws -> (PreparationPlan, Data) {
        guard record.recordType == "SchoolPreparation", let data = record["payload"] as? Data else {
            throw Failure.unreadableArchive
        }
        return (try decode(data), data)
    }

    private func decode(_ data: Data) throws -> PreparationPlan {
        guard data.count <= maximumBytes else { throw Failure.payloadTooLarge }
        do {
            let plan = try JSONDecoder().decode(PreparationPlan.self, from: data)
            try plan.validate()
            // Reject unknown top-level fields rather than silently dropping a newer app's data.
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let known = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan)) as? [String: Any]
            guard let object, let known, Set(object.keys).isSubset(of: Set(known.keys)) else {
                throw Failure.unsupportedArchive
            }
            return plan
        } catch let error as Failure { throw error }
        catch { throw Failure.unreadableArchive }
    }

    private func encode(_ plan: PreparationPlan) throws -> Data {
        try plan.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(plan)
        guard data.count <= maximumBytes else { throw Failure.payloadTooLarge }
        return data
    }

    private func save(_ plan: PreparationPlan, data: Data, record: CKRecord?, account: String) async throws -> SyncResult {
        // Recheck identity immediately before any write; do not retry a failed/concurrent save.
        _ = try await identity(expected: account)
        try Task.checkCancellation()
        let target = record ?? CKRecord(recordType: "SchoolPreparation", recordID: recordID)
        target["payload"] = data as CKRecordValue
        let response = try await database.modifyRecords(
            saving: [target], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true
        )
        guard let outcome = response.saveResults[recordID] else { throw Failure.incompleteSave }
        let saved = try outcome.get() // Per-record failure must not be mistaken for success.
        let (savedPlan, savedData) = try archive(saved)
        guard savedPlan == plan, savedData == data else { throw Failure.incompleteSave }
        return SyncResult(plan: savedPlan, base: savedData, account: account)
    }

    private func safeMessage(_ error: Error) -> String {
        // CloudKit diagnostics may contain record details. Never publish or log them here.
        if let error = error as? Failure { return error.errorDescription ?? "동기화하지 못했어요." }
        if let error = error as? Conflict { return error.errorDescription ?? "기록을 선택해 주세요." }
        return "iCloud 동기화에 실패했어요. 연결을 확인하고 다시 시도해 주세요."
    }
}
