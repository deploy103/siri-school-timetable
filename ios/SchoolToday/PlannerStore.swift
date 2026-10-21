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
    @Published private(set) var plusEnabled = false
    let settings: SchoolSettings
    let api: SchoolAPI
    private let archive: PlannerArchive
    private let cacheURL: URL
    private var requestID = UUID()
    private var plusUntil: Date?

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
        plan.occurrences(on: day, selection: settings.planningKey, lessons: timetable(on: day)?.lessons, automaticLimit: plusEnabled ? .max : 1, includeStages: plusEnabled)
    }
    var rules: [PreparationRule] { plan.rules.filter { $0.selection == settings.planningKey } }
    var tasks: [PreparationTask] { plan.tasks.filter { $0.selection == settings.planningKey } }
    var preference: PreparationPreference { plan.preferences.first { $0.selection == settings.planningKey } ?? PreparationPreference(selection: settings.planningKey) }

    func updateAccess(_ enabled: Bool, until: Date? = nil) {
        guard plusEnabled != enabled || plusUntil != until else { return }
        plusEnabled = enabled
        plusUntil = until
        publishWidget()
        synchronizeReminders()
    }

    func setPreference(_ preference: PreparationPreference) throws {
        guard preference.selection == settings.planningKey else { return }
        var value = plan
        value.preferences.removeAll { $0.selection == preference.selection }
        value.preferences.append(preference)
        try commit(value)
    }

    func useFreeRule(_ rule: PreparationRule) throws {
        guard rule.selection == settings.planningKey else { return }
        var value = plan
        value.rules.removeAll { $0.id == rule.id }
        value.rules.insert(rule, at: 0)
        try commit(value)
    }

    func transferRules(from selection: String, subjects: [UUID: String]) throws {
        var value = plan
        for old in plan.rules where old.selection == selection {
            guard let subject = subjects[old.id].map(PreparationPlan.subjectKey), !subject.isEmpty,
                  !value.rules.contains(where: { $0.selection == settings.planningKey && PreparationPlan.subjectKey($0.subject) == subject }) else { continue }
            value.rules.append(PreparationRule(selection: settings.planningKey, subject: subject, items: old.items))
        }
        try commit(value)
    }

    func replacePlan(_ value: PreparationPlan, expected: PreparationPlan) throws {
        guard plan == expected else { throw SchoolError.message("기록이 변경됐어요. 현재 기록으로 다시 확인해 주세요.") }
        try value.validate()
        guard !storageBlocked else { throw SchoolError.message("읽을 수 없는 원본 기록을 먼저 복구해 주세요.") }
        let source = archive.directory.appendingPathComponent("preparation-v1.json")
        if FileManager.default.fileExists(atPath: source.path) {
            let backup = archive.directory.appendingPathComponent("before-restore-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: source, to: backup)
        }
        try commit(value)
    }

    func cloudBaseline() throws -> (data: Data?, account: String?) {
        let url = archive.directory.appendingPathComponent("cloud-baseline.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil) }
        let value = try JSONDecoder().decode(CloudBaseline.self, from: Data(contentsOf: url))
        guard value.data == nil || value.account != nil else { throw SchoolError.message("동기화 계정 기록을 읽지 못했어요. 원본을 보호하고 있습니다.") }
        return (value.data, value.account)
    }

    func saveCloudBaseline(data: Data?, account: String?) throws {
        try FileManager.default.createDirectory(at: archive.directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        try JSONEncoder().encode(CloudBaseline(data: data, account: account)).write(to: archive.directory.appendingPathComponent("cloud-baseline.json"), options: options)
    }

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
        if !plusEnabled, let free = rules.first(where: \.enabled), PreparationPlan.subjectKey(free.subject) != subject {
            throw PlannerAccessError.plusRequired
        }
        var value = plan
        if let index = value.rules.firstIndex(where: { $0.selection == settings.planningKey && PreparationPlan.subjectKey($0.subject) == subject }) {
            value.rules[index].items = items
            value.rules[index].enabled = true
        } else {
            value.rules.append(PreparationRule(selection: settings.planningKey, subject: subject, items: items))
        }
        try commit(value)
    }
    func deleteRule(_ rule: PreparationRule) throws {
        var value = plan
        value.rules.removeAll { $0.id == rule.id }
        try commit(value)
    }
    func checkTaskAccess(_ task: PreparationTask, stages: [PreparationStage]) throws {
        guard !plusEnabled else { return }
        let previous = tasks.first { $0.id == task.id }
        let previousStages = plan.stages.filter { $0.taskID == task.id }
        // Expiration permits retaining or removing saved features, never adding new ones.
        guard (task.extraReminders ?? []).allSatisfy({ (previous?.extraReminders ?? []).contains($0) }),
              stages.allSatisfy({ previousStages.contains($0) }) else { throw PlannerAccessError.plusRequired }
    }
    func addTask(_ task: PreparationTask, stages: [PreparationStage] = []) throws {
        guard task.selection == settings.planningKey, SchoolCalendar.date(task.date) != nil,
              !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchoolError.message("제목과 날짜를 확인해 주세요.")
        }
        try checkTaskAccess(task, stages: stages)
        let previous = tasks.first { $0.id == task.id }
        let previousStages = plan.stages.filter { $0.taskID == task.id }
        let reminders = [task.reminder].compactMap { $0 } + (task.extraReminders ?? []) + stages.compactMap(\.reminder)
        let previousReminders = [previous?.reminder].compactMap { $0 } + (previous?.extraReminders ?? []) + previousStages.compactMap(\.reminder)
        guard reminders.allSatisfy({ $0 > Date() || previousReminders.contains($0) }) else { throw SchoolError.message("알림은 앞으로의 시각을 선택해 주세요.") }
        var value = plan
        value.tasks.removeAll { $0.id == task.id && $0.selection == settings.planningKey }
        value.tasks.append(task)
        value.stages.removeAll { $0.taskID == task.id }
        value.stages.append(contentsOf: stages)
        let count = value.notices(selection: settings.planningKey, cache: cache, plus: plusEnabled, after: Date(), plusUntil: plusUntil, limit: .max).count
        guard count <= 60 else { throw SchoolError.message("예약 알림은 최대 60개예요. 기존 알림을 줄이거나 알림 없이 저장해 주세요.") }
        try commit(value)
    }
    func deleteTask(_ task: PreparationTask) throws {
        var value = plan
        value.tasks.removeAll { $0.id == task.id }
        value.stages.removeAll { $0.taskID == task.id }
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
            try value.validate()
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
        synchronizeReminders()
    }
    private func publishWidget() {
        var widget = cache
        let dates = Set(cache.timetables.map(\.date) + plan.corrections.filter { $0.selection == settings.planningKey }.map(\.date))
        widget.timetables = dates.sorted().compactMap { timetable(on: $0) }
        widget.correctedDates = Set(plan.corrections.filter { $0.selection == settings.planningKey }.map(\.date))
        if plusEnabled && preference.privateWidget {
            widget.preparationUntil = plusUntil
            widget.preparation = Dictionary(uniqueKeysWithValues: (0..<8).map { offset in
                let key = SchoolCalendar.adding(offset, to: SchoolCalendar.key())!
                return (key, occurrences(on: key))
            })
        } else { widget.preparation = nil; widget.preparationUntil = nil }
        SchoolWidgetCache.write(widget)
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func synchronizeReminders() {
        var effective = cache
        effective.timetables = cache.timetables.compactMap { timetable(on: $0.date) }
        Task { reminderError = await PreparationNotifications.shared.synchronize(plan: plan, selection: settings.planningKey, cache: effective, plus: plusEnabled, plusUntil: plusUntil) }
    }
}

private struct CloudBaseline: Codable {
    let data: Data?
    let account: String?
}
