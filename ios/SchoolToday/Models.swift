import Foundation

struct School: Codable, Hashable, Identifiable, Sendable {
    let officeCode: String
    let schoolCode: String
    let name: String
    let kind: String
    let address: String
    let region: String
    var id: String { "\(officeCode):\(schoolCode)" }
}

struct SchoolClass: Codable, Hashable, Identifiable, Sendable {
    let grade: Int
    let className: String
    let department: String?
    var id: String { "\(department ?? ""):\(grade):\(className)" }
    var label: String {
        [department, "\(grade)학년 \(className)반"].compactMap { $0 }.joined(separator: " · ")
    }
}

enum SchoolShortcut: String, CaseIterable {
    case timetable, meal
    var title: String { self == .timetable ? "시간표" : "급식" }
    var defaultPhrase: String {
        self == .timetable ? "오늘의 학교 시간표 알려줘" : "오늘의 학교 급식 알려줘"
    }
    var other: SchoolShortcut { self == .timetable ? .meal : .timetable }

    /// Runs a personal shortcut saved in the user's Shortcuts collection, not an App Shortcut.
    static func runURL(named name: String) -> URL {
        var parts = URLComponents()
        parts.scheme = "shortcuts"
        parts.host = "run-shortcut"
        parts.queryItems = [URLQueryItem(name: "name", value: name)]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }
}

enum HighSchoolType: String, Codable, CaseIterable {
    case general, vocational
    var title: String { self == .general ? "일반고" : "특성화고" }
}

struct SchoolSettings: Codable, Hashable, Sendable {
    let school: School
    let schoolClass: SchoolClass
    var highSchoolType: HighSchoolType? = nil
    var classLabel: String {
        highSchoolType == .general ? "\(schoolClass.grade)학년 \(schoolClass.className)반" : schoolClass.label
    }
    var schoolQuery: [URLQueryItem] {
        [URLQueryItem(name: "officeCode", value: school.officeCode), URLQueryItem(name: "schoolCode", value: school.schoolCode)]
    }
    var timetableQuery: [URLQueryItem] {
        schoolQuery + [
            URLQueryItem(name: "kind", value: school.kind),
            URLQueryItem(name: "grade", value: String(schoolClass.grade)),
            URLQueryItem(name: "className", value: schoolClass.className),
        ] + (schoolClass.department.map { [URLQueryItem(name: "department", value: $0)] } ?? [])
    }
}

struct Timetable: Decodable, Sendable {
    struct Lesson: Decodable, Identifiable, Sendable {
        let period: Int
        let subject: String
        let ambiguous: Bool?
        var id: Int { period }
    }
    let date: String
    let lessons: [Lesson]

    var missingPeriods: [Int] {
        guard let last = lessons.map(\.period).max(), last > 1 else { return [] }
        let published = Set(lessons.map(\.period))
        return (1..<last).filter { !published.contains($0) }
    }

    var summary: String {
        guard !lessons.isEmpty else { return "등록된 시간표가 없습니다." }
        return lessons.sorted { $0.period < $1.period }
            .map { "\($0.period)교시 \($0.subject)\($0.ambiguous == true ? " (선택 수업)" : "")" }
            .joined(separator: "\n")
    }
}

struct Meals: Decodable, Sendable {
    struct Meal: Decodable, Identifiable, Sendable {
        let code: String
        let name: String
        let dishes: [String]
        let calories: String
        let nutrition: String?
        let origin: String?
        var id: String { "\(code):\(name)" }
    }
    let date: String
    let meals: [Meal]

    var summary: String {
        guard !meals.isEmpty else { return "등록된 급식이 없습니다." }
        return meals.sorted { (Int($0.code) ?? 0) < (Int($1.code) ?? 0) }
            .map { "[\($0.name)]\n\($0.dishes.joined(separator: "\n"))" }
            .joined(separator: "\n\n")
    }
}

enum MealAllergens {
    static let names = [
        "난류", "우유", "메밀", "땅콩", "대두", "밀", "고등어", "게", "새우", "돼지고기",
        "복숭아", "토마토", "아황산류", "호두", "닭고기", "쇠고기", "오징어", "조개류(굴·전복·홍합 포함)", "잣",
    ]

    /// Only NEIS suffixes are annotations; numbers inside a dish name are not.
    static func numbers(in dish: String) -> [Int] {
        let pattern = #"(?:\(\s*(\d{1,2}(?:\s*\.\s*\d{1,2})*)\s*\.?\s*\)|(?<=\D)(\d{1,2}(?:\s*\.\s*\d{1,2})*)\s*\.)\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: dish, range: NSRange(dish.startIndex..., in: dish)) else { return [] }
        let group = match.range(at: 1).location == NSNotFound ? 2 : 1
        guard let range = Range(match.range(at: group), in: dish) else { return [] }
        return Set(dish[range].split(separator: ".").compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...names.count).contains($0) }).sorted()
    }

    static func description(for dish: String) -> String? {
        let numbers = numbers(in: dish)
        return numbers.isEmpty ? nil : numbers.map { names[$0 - 1] }.joined(separator: " · ")
    }
}

struct Health: Decodable, Sendable {
    struct NEIS: Decodable, Sendable {
        let mode: String
    }
    let neis: NEIS
}

enum SchoolError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let message): return message }
    }
}

enum SchoolPreferences {
    static let schoolKey = "schooltoday.school.v1"
    static let serverKey = "schooltoday.server.v1"
    static func shortcutName(for shortcut: SchoolShortcut, defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: "schooltoday.shortcut-name.\(shortcut.rawValue).v1") ?? shortcut.defaultPhrase
    }
    static func writeShortcutName(_ name: String, for shortcut: SchoolShortcut, defaults: UserDefaults = .standard) {
        defaults.set(name, forKey: "schooltoday.shortcut-name.\(shortcut.rawValue).v1")
    }
    static func readSchool(defaults: UserDefaults = .standard) -> SchoolSettings? {
        guard let data = defaults.data(forKey: schoolKey) else { return nil }
        return try? JSONDecoder().decode(SchoolSettings.self, from: data)
    }
    static func writeSchool(_ school: SchoolSettings?, defaults: UserDefaults = .standard) throws {
        if let school { defaults.set(try JSONEncoder().encode(school), forKey: schoolKey) }
        else { defaults.removeObject(forKey: schoolKey) }
    }
    static func server() -> String {
        Bundle.main.object(forInfoDictionaryKey: "SchoolAPIBaseURL") as? String ?? ""
    }
}
