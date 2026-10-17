import Foundation
import Combine
import WidgetKit

@MainActor
final class PlannerStore: ObservableObject {
    @Published private(set) var plan = PreparationPlan()
    @Published private(set) var cache: SchoolWeekCache
    @Published private(set) var loading = false
    @Published private(set) var timetableError: String?
    @Published private(set) var mealError: String?
    @Published private(set) var recordError: String?
    @Published private(set) var reminderError: String?
    @Published private(set) var storageBlocked = false
    let settings: SchoolSettings
    let api: SchoolAPI
    private let archive: PlannerArchive
    private let cacheURL: URL
    private var requestID = UUID()

    init(settings: SchoolSettings, api: SchoolAPI, mode: String, directory: URL? = nil) {
        self.settings = settings
        self.api = api
        let directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SchoolPlanner", isDirectory: true)
        archive = PlannerArchive(directory: directory)
        cacheURL = directory.appendingPathComponent("week-cache-v1.json")
        cache = SchoolWeekCache(selection: settings, origin: api.baseURL.absoluteString, mode: mode)
        do { plan = try archive.load() }
        catch {
            storageBlocked = true
            recordError = "저장된 준비 기록을 읽지 못했어요. 원본을 보존했으며 새 기록으로 덮어쓰지 않습니다. \(error.localizedDescription)"
        }
        if let data = try? Data(contentsOf: cacheURL),
           let saved = try? JSONDecoder().decode(SchoolWeekCache.self, from: data),
           saved.selection.planningKey == settings.planningKey, saved.origin == api.baseURL.absoluteString,
           saved.mode == mode {
            cache = saved
        }
        // Never leave the previous school's timetable in a widget while a new selection loads.
        publishWidget()
        synchronizeReminders()
    }

    func timetable(on day: String) -> Timetable? {
        let original = cache.timetables.first { $0.date == day }
        let edits = plan.corrections.filter { $0.selection == settings.planningKey && $0.date == day }
        guard original != nil || !edits.isEmpty else { return nil }
        var lessons = original?.lessons ?? []
        for edit in edits {
            lessons.removeAll { $0.period == edit.period }
            lessons.append(Timetable.Lesson(period: edit.period, subject: edit.subject, ambiguous: false))
        }
        return Timetable(date: day, lessons: lessons.sorted { $0.period < $1.period })
    }
    func needsTimetableConfirmation(on day: String) -> Bool {
        guard cache.timetables.first(where: { $0.date == day })?.lessons.isEmpty == false,
              let effective = timetable(on: day) else { return true }
        return !effective.missingPeriods.isEmpty || effective.lessons.contains { $0.ambiguous == true }
    }
    func correction(on day: String, period: Int) -> LessonCorrection? {
        plan.corrections.first { $0.selection == settings.planningKey && $0.date == day && $0.period == period }
    }
    func correct(_ correction: LessonCorrection) throws {
        guard correction.selection == settings.planningKey, SchoolCalendar.date(correction.date) != nil,
              (1...20).contains(correction.period), !PreparationPlan.subjectKey(correction.subject).isEmpty else {
            throw SchoolError.message("수업의 날짜·교시·과목을 확인해 주세요.")
        }
        var value = plan
        value.corrections.removeAll { $0.id == correction.id }
        value.corrections.append(correction)
        try commit(value)
    }
    func removeCorrection(_ correction: LessonCorrection) throws {
        var value = plan
        value.corrections.removeAll { $0.id == correction.id }
        try commit(value)
    }
    func meals(on day: String) -> Meals? { cache.meals.first { $0.date == day } }
    func occurrences(on day: String) -> [PreparationOccurrence] {
        plan.occurrences(on: day, selection: settings.planningKey, lessons: timetable(on: day)?.lessons)
    }
    var rules: [PreparationRule] { plan.rules.filter { $0.selection == settings.planningKey } }
    var tasks: [PreparationTask] { plan.tasks.filter { $0.selection == settings.planningKey } }

    func refresh(containing day: String) async {
        let days = SchoolCalendar.week(containing: day)
        guard let first = days.first, let last = days.last else { return }
        let id = UUID()
        requestID = id
        loading = true; timetableError = nil; mealError = nil
        defer { if requestID == id { loading = false } }
        // Start both services together and publish each result without waiting for the other.
        async let timetable: Void = refreshTimetable(from: first, to: last, request: id)
        async let meals: Void = refreshMeals(from: first, to: last, request: id)
        _ = await (timetable, meals)
    }

    private func refreshTimetable(from: String, to: String, request id: UUID) async {
        do {
            let values = try await api.timetables(settings: settings, from: from, to: to)
            guard requestID == id, !Task.isCancelled else { return }
            cache.timetables = values
            cache.timetableCheckedAt = Date()
            persistCache()
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            timetableError = error.localizedDescription
        }
    }

    private func refreshMeals(from: String, to: String, request id: UUID) async {
        do {
            let values = try await api.meals(settings: settings, from: from, to: to)
            guard requestID == id, !Task.isCancelled else { return }
            cache.meals = values
            cache.mealCheckedAt = Date()
            persistCache()
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            mealError = error.localizedDescription
        }
    }

    func addRule(subject: String, items: [String]) throws {
        let subject = PreparationPlan.subjectKey(subject)
        var seen = Set<String>()
        let items = items.map(PreparationPlan.subjectKey).filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !subject.isEmpty, !items.isEmpty else { throw SchoolError.message("과목과 준비물을 입력해 주세요.") }
        var value = plan
        if let index = value.rules.firstIndex(where: { $0.selection == settings.planningKey && PreparationPlan.subjectKey($0.subject) == subject }) {
            value.rules[index].items = items
            value.rules[index].enabled = true
        } else {
            guard !rules.contains(where: \.enabled) else {
                throw SchoolError.message("자동 준비는 한 과목을 계속 무료로 사용할 수 있어요. 다른 과목은 날짜를 골라 직접 등록할 수 있습니다. 여러 과목을 연결하는 Plus는 아직 판매하지 않아요.")
            }
            value.rules.append(PreparationRule(selection: settings.planningKey, subject: subject, items: items))
        }
        try commit(value)
    }
    func deleteRule(_ rule: PreparationRule) throws {
        var value = plan
        value.rules.removeAll { $0.id == rule.id }
        try commit(value)
    }
    func addTask(_ task: PreparationTask) throws {
        guard task.selection == settings.planningKey, SchoolCalendar.date(task.date) != nil,
              !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchoolError.message("제목과 날짜를 확인해 주세요.")
        }
        if let reminder = task.reminder {
            guard reminder > Date() else { throw SchoolError.message("알림은 앞으로의 시각을 선택해 주세요.") }
            guard plan.reminders(selection: settings.planningKey, after: Date()).count < 60 else {
                throw SchoolError.message("예약 알림이 60개예요. 기존 일정을 완료하거나 알림 없이 저장해 주세요.")
            }
        }
        var value = plan
        value.tasks.append(task)
        try commit(value)
    }
    func deleteTask(_ task: PreparationTask) throws {
        var value = plan
        value.tasks.removeAll { $0.id == task.id }
        try commit(value)
    }
    func toggle(_ occurrence: PreparationOccurrence) {
        var value = plan
        value.toggle(occurrence)
        do { try commit(value) } catch { recordError = error.localizedDescription }
    }
    private func commit(_ value: PreparationPlan) throws {
        guard !storageBlocked else { throw SchoolError.message("원본 기록을 보호하고 있어요. 준비 기록을 복구한 뒤 다시 시도해 주세요.") }
        do {
            try archive.save(value)
            plan = value
            recordError = nil
            publishWidget()
            synchronizeReminders()
        } catch {
            recordError = "준비 기록을 저장하지 못했어요. 저장 공간을 확인해 주세요."
            throw error
        }
    }
    private func persistCache() {
        // A cache is replaceable, unlike the preparation archive. Its date/provenance survives offline use.
        do {
            try FileManager.default.createDirectory(at: archive.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
        } catch { recordError = "최근 학교 자료를 기기에 저장하지 못했어요. 준비 기록은 별도로 보관됩니다." }
        publishWidget()
    }
    private func publishWidget() {
        var widget = cache
        let dates = Set(cache.timetables.map(\.date) + plan.corrections.filter { $0.selection == settings.planningKey }.map(\.date))
        widget.timetables = dates.sorted().compactMap { timetable(on: $0) }
        widget.correctedDates = Set(plan.corrections.filter { $0.selection == settings.planningKey }.map(\.date))
        SchoolWidgetCache.write(widget)
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func synchronizeReminders() {
        Task { reminderError = await PreparationNotifications.shared.synchronize(plan: plan, selection: settings.planningKey) }
    }
}
