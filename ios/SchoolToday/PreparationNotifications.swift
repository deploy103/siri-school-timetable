import Foundation
import UserNotifications

actor PreparationNotifications {
    static let shared = PreparationNotifications()
    private var pending: (PreparationPlan, String)?
    private var updating = false
    private var waiters: [CheckedContinuation<String?, Never>] = []

    func authorize() async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return try await center.requestAuthorization(options: [.alert, .sound])
        default: return false
        }
    }

    func synchronize(plan: PreparationPlan, selection: String) async -> String? {
        pending = (plan, selection)
        if updating { return await withCheckedContinuation { waiters.append($0) } }
        updating = true
        defer { updating = false }
        let center = UNUserNotificationCenter.current()
        var failure: String?
        // Drain serially: an older add() must finish before a newer plan cancels/replaces it.
        while let (plan, selection) = pending {
            pending = nil
            failure = nil
            let old = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix("schooltoday.preparation.") }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: old)
            let settings = await center.notificationSettings()
            guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
                if !plan.reminders(selection: selection, after: Date()).isEmpty { failure = "알림이 꺼져 있어요. iPhone 설정에서 알림을 허용해 주세요." }
                continue
            }
            for task in plan.reminders(selection: selection, after: Date()) {
                guard let date = task.reminder else { continue }
                let content = UNMutableNotificationContent()
                content.title = task.kind == .deadline ? "마감 확인" : "챙길 것 확인"
                content.body = task.title
                content.sound = .default
                content.userInfo = ["preparationDate": task.date, "selection": selection]
                let components = SchoolCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                var zoned = components
                zoned.timeZone = SchoolCalendar.calendar.timeZone
                let trigger = UNCalendarNotificationTrigger(dateMatching: zoned, repeats: false)
                let request = UNNotificationRequest(identifier: "schooltoday.preparation.\(task.id.uuidString)", content: content, trigger: trigger)
                do { try await center.add(request) }
                catch { failure = "기록은 저장했지만 일부 알림을 예약하지 못했어요. 알림 설정을 확인한 뒤 앱을 다시 열어 주세요." }
            }
        }
        for waiter in waiters { waiter.resume(returning: failure) }
        waiters.removeAll()
        return failure
    }
}

extension Notification.Name {
    static let showSchoolPreparation = Notification.Name("SchoolToday.ShowPreparation")
}
