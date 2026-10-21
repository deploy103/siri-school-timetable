import Foundation

enum SchoolCalendar {
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Seoul")!
        value.firstWeekday = 2
        return value
    }
    static func key(_ date: Date = Date()) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    static func date(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard key.count == 10, parts.count == 3,
              let value = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              self.key(value) == key else { return nil }
        return value
    }
    static func adding(_ days: Int, to key: String) -> String? {
        date(key).flatMap { calendar.date(byAdding: .day, value: days, to: $0) }.map(self.key)
    }
    static func week(containing key: String) -> [String] {
        guard let date = date(key) else { return [] }
        let weekday = calendar.component(.weekday, from: date)
        let monday = adding(-((weekday + 5) % 7), to: key)!
        return (0..<7).compactMap { adding($0, to: monday) }
    }
    static func range(from: String, to: String) -> [String]? {
        guard let start = date(from), let end = date(to), start <= end else { return nil }
        let count = calendar.dateComponents([.day], from: start, to: end).day! + 1
        guard (1...7).contains(count) else { return nil }
        return (0..<count).compactMap { adding($0, to: from) }
    }
    static func label(_ key: String, format: String = "M월 d일 EEEE") -> String {
        guard let date = date(key) else { return key }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

extension SchoolSettings {
    var planningKey: String {
        // Array encoding prevents separator characters in a class/department from colliding.
        let values = [school.officeCode, school.schoolCode, String(schoolClass.grade), schoolClass.className, schoolClass.department ?? ""]
        return (try! JSONEncoder().encode(values)).base64EncodedString()
    }
}

enum SchoolSelectionLink {
    static func url(_ settings: SchoolSettings) -> URL? {
        guard let data = try? JSONEncoder().encode(settings) else { return nil }
        var components = URLComponents()
        components.scheme = "schooltoday"
        components.host = "class"
        components.queryItems = [URLQueryItem(name: "school", value: data.base64EncodedString())]
        return components.url
    }
    static func read(_ url: URL) throws -> SchoolSettings {
        guard url.absoluteString.count < 8192, url.scheme == "schooltoday", url.host == "class",
              let values = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              values.count == 1, values[0].name == "school", let encoded = values[0].value,
              let data = Data(base64Encoded: encoded), let settings = try? JSONDecoder().decode(SchoolSettings.self, from: data),
              !settings.school.officeCode.isEmpty, !settings.school.schoolCode.isEmpty,
              !settings.school.name.isEmpty, (1...12).contains(settings.schoolClass.grade),
              !settings.schoolClass.className.isEmpty else {
            throw SchoolError.message("학교 설정 링크가 올바르지 않아요. 친구에게 다시 공유해 달라고 해 주세요.")
        }
        return settings
    }
}

struct SchoolRange<Day: Codable>: Codable {
    let from: String
    let to: String
    let days: [Day]
}

struct SchoolWeekCache: Codable {
    let selection: SchoolSettings
    let origin: String
    var timetables: [Timetable] = []
    var meals: [Meals] = []
    var timetableCheckedAt: Date?
    var mealCheckedAt: Date?
    var mode = ""
    var correctedDates: Set<String> = []
    var preparation: [String: [PreparationOccurrence]]? = nil
    var preparationUntil: Date? = nil
}

struct PreparationRule: Codable, Identifiable, Equatable {
    var id = UUID()
    let selection: String
    var subject: String
    var items: [String]
    var enabled = true
}

struct PreparationTask: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case item, deadline }
    enum Category: String, Codable, CaseIterable {
        case assessment, exam, homework
        var label: String {
            switch self {
            case .assessment: return "수행평가"
            case .exam: return "시험"
            case .homework: return "숙제"
            }
        }
    }
    enum ScheduleGroup: String, CaseIterable {
        case overdue = "날짜가 지났어요", today = "오늘", week = "앞으로 7일", later = "이후 일정"
    }
    var id = UUID()
    let selection: String
    var title: String
    var date: String
    var subject: String = ""
    var kind: Kind = .item
    var reminder: Date? = nil
    var extraReminders: [Date]? = nil
    var category: Category? = nil
    var notes: String? = nil

    var completionID: String { "task:\(id.uuidString)" }
    var kindLabel: String { kind == .item ? "준비물" : category?.label ?? "마감" }

    func scheduleGroup(relativeTo now: Date) -> ScheduleGroup {
        let today = SchoolCalendar.key(now)
        if date < today { return .overdue }
        if date == today { return .today }
        return date <= SchoolCalendar.adding(7, to: today)! ? .week : .later
    }

    func relativeDate(to now: Date) -> String {
        guard let due = SchoolCalendar.date(date) else { return date }
        let days = SchoolCalendar.calendar.dateComponents([.day], from: SchoolCalendar.calendar.startOfDay(for: now), to: due).day!
        if days == 0 { return "오늘" }
        if days == 1 { return "내일" }
        return days < 0 ? "\(-days)일 지남" : "\(days)일 남음"
    }
}

struct LessonCorrection: Codable, Identifiable, Equatable {
    let selection: String
    let date: String
    let period: Int
    var subject: String
    var room: String
    var id: String { "\(selection):\(date):\(period)" }
}

struct PreparationOccurrence: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subject: String
    let date: String
    let automatic: Bool
    let completed: Bool
}

struct PreparationPlan: Codable, Equatable {
    // Older apps must reject, rather than silently discard, classification and notes on resave.
    var version = 3
    var rules: [PreparationRule] = []
    var tasks: [PreparationTask] = []
    var completed: Set<String> = []
    var corrections: [LessonCorrection] = []
    var stages: [PreparationStage] = []
    var preferences: [PreparationPreference] = []

    static func subjectKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    func scheduledTasks(selection: String, completed isCompleted: Bool = false) -> [PreparationTask] {
        tasks.filter { $0.selection == selection && completed.contains($0.completionID) == isCompleted }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
    }

    func occurrences(on date: String, selection: String, lessons: [Timetable.Lesson]?, automaticLimit: Int = 1, includeStages: Bool = false) -> [PreparationOccurrence] {
        let subjects = Set((lessons ?? []).filter { $0.ambiguous != true }.map { Self.subjectKey($0.subject) })
        var result: [PreparationOccurrence] = []
        // Keep creation order stable when a subscription expires. Records remain intact.
        for rule in rules.filter({ $0.selection == selection && $0.enabled }).prefix(automaticLimit) {
            guard subjects.contains(Self.subjectKey(rule.subject)) else { continue }
            var seen = Set<String>()
            for item in rule.items {
                let title = Self.subjectKey(item)
                guard !title.isEmpty, seen.insert(title).inserted else { continue }
                let id = "rule:\(rule.id.uuidString):\(date):\(title)"
                result.append(PreparationOccurrence(id: id, title: title, subject: rule.subject, date: date, automatic: true, completed: completed.contains(id)))
            }
        }
        for task in tasks where task.selection == selection {
            let id = "task:\(task.id.uuidString)"
            if task.date == date {
                result.append(PreparationOccurrence(id: id, title: task.title, subject: task.subject, date: date, automatic: false, completed: completed.contains(id)))
            }
        }
        if includeStages {
            for stage in stages where stage.date == date {
                guard let task = tasks.first(where: { $0.id == stage.taskID && $0.selection == selection }),
                      !completed.contains("task:\(task.id.uuidString)") else { continue }
                let id = "stage:\(stage.id.uuidString)"
                result.append(PreparationOccurrence(id: id, title: stage.title, subject: task.title, date: date, automatic: false, completed: completed.contains(id)))
            }
        }
        return result
    }

    mutating func toggle(_ occurrence: PreparationOccurrence) {
        if completed.contains(occurrence.id) { completed.remove(occurrence.id) }
        else { completed.insert(occurrence.id) }
    }

    func reminders(selection: String, after now: Date) -> [PreparationTask] {
        tasks.filter {
            $0.selection == selection && ($0.reminder.map { $0 > now } ?? false) && !completed.contains("task:\($0.id.uuidString)")
        }.sorted { $0.reminder! < $1.reminder! }.prefix(60).map { $0 }
    }
}

/// Local records and purchase restoration are deliberately separate. Never overwrite unreadable records.
struct PlannerArchive {
    let directory: URL
    func load() throws -> PreparationPlan {
        let url = directory.appendingPathComponent("preparation-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return PreparationPlan() }
        let value = try JSONDecoder().decode(PreparationPlan.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }
    func save(_ value: PreparationPlan) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent("preparation-v1.json"), options: options)
    }
}

struct PreparationStage: Codable, Identifiable, Equatable {
    var id = UUID()
    let taskID: UUID
    var title: String
    var date: String
    var reminder: Date? = nil
}

struct PreparationPreference: Codable, Equatable {
    let selection: String
    var eveningMinute: Int? = nil
    var morningMinute: Int? = nil
    var pausedUntil: String? = nil
    var privateWidget = false
    var bellTimes: [SchoolBellTime]? = nil
}

struct SchoolBellTime: Codable, Identifiable, Equatable {
    var id = UUID()
    var period: Int
    var startMinute: Int
    var endMinute: Int
}

struct PreparationNotice: Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
    let preparationDate: String
}

enum PlannerAccessError: Error, LocalizedError {
    case plusRequired
    var errorDescription: String? { "한 과목 자동 준비는 무료예요. 여러 과목·마감 준비 단계·추가 알림은 Plus로 사용할 수 있어요." }
}

enum DeadlineTemplate: String, CaseIterable, Identifiable {
    case presentation = "발표", report = "보고서", practice = "실습 제출"
    var id: String { rawValue }
    func stages(for task: PreparationTask) -> [PreparationStage] {
        let titles: [String]
        switch self {
        case .presentation: titles = ["발표 자료 조사", "자료·발표 파일 확인", "발표 준비 확인"]
        case .report: titles = ["보고서 자료 모으기", "초안·출처 확인", "파일 제출 확인"]
        case .practice: titles = ["실습 요구사항 확인", "결과·장비 점검", "실습 결과 제출"]
        }
        return zip([3, 1, 0], titles).compactMap { offset, title in
            guard let date = SchoolCalendar.adding(-offset, to: task.date) else { return nil }
            return PreparationStage(taskID: task.id, title: title, date: date)
        }
    }
}

extension PreparationPlan {
    enum CodingKeys: String, CodingKey { case version, rules, tasks, completed, corrections, stages, preferences }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let sourceVersion = try values.decode(Int.self, forKey: .version)
        guard (1...3).contains(sourceVersion) else { throw SchoolError.message("다른 버전의 준비 기록이에요. 앱 업데이트를 확인해 주세요.") }
        version = 3
        rules = try values.decode([PreparationRule].self, forKey: .rules)
        tasks = try values.decode([PreparationTask].self, forKey: .tasks)
        completed = try values.decode(Set<String>.self, forKey: .completed)
        corrections = try values.decode([LessonCorrection].self, forKey: .corrections)
        stages = try values.decodeIfPresent([PreparationStage].self, forKey: .stages) ?? []
        preferences = try values.decodeIfPresent([PreparationPreference].self, forKey: .preferences) ?? []
    }

    func validate() throws {
        guard version == 3,
              Set(rules.map(\.id)).count == rules.count, Set(tasks.map(\.id)).count == tasks.count,
              Set(stages.map(\.id)).count == stages.count, Set(corrections.map(\.id)).count == corrections.count,
              Set(preferences.map(\.selection)).count == preferences.count,
              rules.allSatisfy({ !$0.selection.isEmpty && !Self.subjectKey($0.subject).isEmpty && !$0.items.isEmpty && $0.items.allSatisfy { !Self.subjectKey($0).isEmpty } }),
              tasks.allSatisfy({ !$0.selection.isEmpty && !Self.subjectKey($0.title).isEmpty && SchoolCalendar.date($0.date) != nil && ($0.notes?.count ?? 0) <= 2000 && ($0.category == nil || $0.kind == .deadline) }),
              corrections.allSatisfy({ !$0.selection.isEmpty && SchoolCalendar.date($0.date) != nil && (1...20).contains($0.period) && !Self.subjectKey($0.subject).isEmpty }),
              stages.allSatisfy({ stage in SchoolCalendar.date(stage.date) != nil && !Self.subjectKey(stage.title).isEmpty && tasks.contains { $0.id == stage.taskID && $0.kind == .deadline && stage.date <= $0.date } }),
              preferences.allSatisfy({ !$0.selection.isEmpty && ($0.eveningMinute.map { (0..<1440).contains($0) } ?? true) && ($0.morningMinute.map { (0..<1440).contains($0) } ?? true) && ($0.pausedUntil.map { SchoolCalendar.date($0) != nil } ?? true) && Self.validBellTimes($0.bellTimes ?? []) }) else {
            throw SchoolError.message("준비 기록의 날짜·과목·식별자가 올바르지 않아 적용하지 않았어요.")
        }
    }

    static func validBellTimes(_ times: [SchoolBellTime]) -> Bool {
        let sorted = times.sorted { $0.period < $1.period }
        return Set(times.map(\.id)).count == times.count && Set(times.map(\.period)).count == times.count && times.allSatisfy {
            (1...20).contains($0.period) && (0..<1440).contains($0.startMinute) && $0.startMinute < $0.endMinute && $0.endMinute < 1440
        } && zip(sorted, sorted.dropFirst()).allSatisfy { $0.endMinute <= $1.startMinute }
    }

    func lessonStatus(selection: String, timetable: Timetable?, now: Date) -> String? {
        guard let timetable, timetable.date == SchoolCalendar.key(now),
              let times = preferences.first(where: { $0.selection == selection })?.bellTimes,
              Self.validBellTimes(times) else { return nil }
        let components = SchoolCalendar.calendar.dateComponents([.hour, .minute], from: now)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let lessons = timetable.lessons.filter { $0.ambiguous != true }
        let remaining = times.sorted { $0.startMinute < $1.startMinute }.filter { time in
            time.endMinute > minute && lessons.contains { $0.period == time.period }
        }
        guard let first = remaining.first, let lesson = lessons.first(where: { $0.period == first.period }) else { return nil }
        let next = remaining.dropFirst().first.flatMap { time in lessons.first { $0.period == time.period } }
        if first.startMinute <= minute {
            return "지금 \(first.period)교시 \(lesson.subject)" + (next.map { " · 다음 \($0.period)교시 \($0.subject)" } ?? "")
        }
        return "다음 \(first.period)교시 \(lesson.subject) · \(String(format: "%02d:%02d", first.startMinute / 60, first.startMinute % 60)) 시작"
    }

    func notices(selection: String, cache: SchoolWeekCache?, plus: Bool, after now: Date, plusUntil: Date? = nil, limit: Int = 60) -> [PreparationNotice] {
        var result: [PreparationNotice] = []
        for task in tasks where task.selection == selection && !completed.contains("task:\(task.id.uuidString)") {
            let extra = plus ? (task.extraReminders ?? []).filter { date in plusUntil.map { date < $0 } ?? true } : []
            let dates = Set(([task.reminder].compactMap { $0 }) + extra)
            for date in dates where date > now {
                result.append(PreparationNotice(id: "task.\(task.id).\(date.timeIntervalSince1970)", title: task.kind == .deadline ? "마감 확인" : "챙길 것 확인", body: task.title, fireDate: date, preparationDate: task.date))
            }
        }
        if plus {
            for stage in stages where !completed.contains("stage:\(stage.id.uuidString)") {
                guard let task = tasks.first(where: { $0.id == stage.taskID && $0.selection == selection }),
                      !completed.contains("task:\(task.id.uuidString)"), let date = stage.reminder, date > now,
                      plusUntil.map({ date < $0 }) ?? true else { continue }
                result.append(PreparationNotice(id: "stage.\(stage.id)", title: "마감 준비", body: "\(task.title) · \(stage.title)", fireDate: date, preparationDate: stage.date))
            }
            if let preference = preferences.first(where: { $0.selection == selection }) {
                for offset in 0..<7 {
                    let key = SchoolCalendar.adding(offset, to: SchoolCalendar.key(now))!
                    if let pause = preference.pausedUntil, key <= pause { continue }
                    for (kind, minute) in [("evening", preference.eveningMinute), ("morning", preference.morningMinute)] {
                        guard let minute, let day = SchoolCalendar.date(key),
                              let fire = SchoolCalendar.calendar.date(byAdding: .minute, value: minute, to: day), fire > now,
                              plusUntil.map({ fire < $0 }) ?? true else { continue }
                        let target: String
                        if kind == "evening" {
                            let upcoming = (cache?.timetables ?? []).filter { $0.date > key && !$0.lessons.isEmpty }.map(\.date).sorted()
                            target = upcoming.first ?? SchoolCalendar.adding(1, to: key)!
                        } else { target = key }
                        let lessons = cache?.timetables.first { $0.date == target }?.lessons
                        let items = occurrences(on: target, selection: selection, lessons: lessons, automaticLimit: .max, includeStages: true).filter { !$0.completed }
                        if items.isEmpty && lessons != nil { continue }
                        let body = lessons == nil ? "시간표 확인 필요 · 앱에서 최신 자료와 준비를 확인해 주세요." : items.prefix(5).map(\.title).joined(separator: " · ")
                        result.append(PreparationNotice(id: "\(kind).\(key)", title: kind == "evening" ? "다음 등교 준비" : "아침 준비 재확인", body: body, fireDate: fire, preparationDate: target))
                    }
                }
            }
        }
        return Array(result.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }.prefix(limit))
    }
}

enum SchoolWidgetCache {
    static let group = "group.com.deploy103.schooltoday"
    static let key = "schooltoday.widget-week.v1"
    static func read(defaults: UserDefaults? = UserDefaults(suiteName: group)) -> SchoolWeekCache? {
        defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(SchoolWeekCache.self, from: $0) }
    }
    static func write(_ cache: SchoolWeekCache?, defaults: UserDefaults? = UserDefaults(suiteName: group)) {
        if let cache, let data = try? JSONEncoder().encode(cache) { defaults?.set(data, forKey: key) }
        else { defaults?.removeObject(forKey: key) }
    }
}
