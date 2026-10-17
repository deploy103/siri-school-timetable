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
    var id = UUID()
    let selection: String
    var title: String
    var date: String
    var subject: String = ""
    var kind: Kind = .item
    var reminder: Date? = nil
}

struct LessonCorrection: Codable, Identifiable, Equatable {
    let selection: String
    let date: String
    let period: Int
    var subject: String
    var room: String
    var id: String { "\(selection):\(date):\(period)" }
}

struct PreparationOccurrence: Identifiable, Equatable {
    let id: String
    let title: String
    let subject: String
    let date: String
    let automatic: Bool
    let completed: Bool
}

struct PreparationPlan: Codable, Equatable {
    var version = 1
    var rules: [PreparationRule] = []
    var tasks: [PreparationTask] = []
    var completed: Set<String> = []
    var corrections: [LessonCorrection] = []

    static func subjectKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    func occurrences(on date: String, selection: String, lessons: [Timetable.Lesson]?, automaticLimit: Int = 1) -> [PreparationOccurrence] {
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
        guard value.version == 1 else { throw SchoolError.message("다른 버전의 준비 기록이에요. 앱 업데이트를 확인해 주세요.") }
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
