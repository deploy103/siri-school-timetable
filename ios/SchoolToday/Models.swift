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

struct SchoolSettings: Codable, Hashable, Sendable {
    let school: School
    let schoolClass: SchoolClass
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
}

struct Meals: Decodable, Sendable {
    struct Meal: Decodable, Identifiable, Sendable {
        let code: String
        let name: String
        let dishes: [String]
        let calories: String
        var id: String { "\(code):\(name)" }
    }
    let date: String
    let meals: [Meal]
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
    static func readSchool(defaults: UserDefaults = .standard) -> SchoolSettings? {
        guard let data = defaults.data(forKey: schoolKey) else { return nil }
        return try? JSONDecoder().decode(SchoolSettings.self, from: data)
    }
    static func writeSchool(_ school: SchoolSettings?, defaults: UserDefaults = .standard) throws {
        if let school { defaults.set(try JSONEncoder().encode(school), forKey: schoolKey) }
        else { defaults.removeObject(forKey: schoolKey) }
    }
    static func server(defaults: UserDefaults = .standard) -> String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "SchoolAPIBaseURL") as? String ?? ""
        #if DEBUG
        return defaults.string(forKey: serverKey) ?? configured
        #else
        // A shipping app must not inherit a development server override.
        return configured
        #endif
    }
}
