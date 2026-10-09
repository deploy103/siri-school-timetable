import Foundation

struct SchoolAPI: Sendable {
    let baseURL: URL
    let session: URLSession

    init(server: String, session: URLSession = .shared) throws {
        guard let parts = URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let url = parts.url else {
            throw SchoolError.message("HTTPS 서버 주소를 확인해 주세요. 경로나 계정 정보가 없는 주소가 필요합니다.")
        }
        baseURL = url
        self.session = session
    }

    func url(path: String, query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        parts.path = path
        parts.queryItems = query.isEmpty ? nil : query
        // The server uses URLSearchParams, where a literal + means a space.
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url!
    }

    private func request(path: String, query: [URLQueryItem] = [], text: Bool = false) async throws -> Data {
        var request = URLRequest(url: url(path: path, query: query), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(text ? "text/plain" : "application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError {
            if error.code == .cancelled { throw error }
            if error.code == .timedOut {
                throw SchoolError.message("학교 서비스의 응답이 늦어지고 있어요. 잠시 뒤 다시 실행해 주세요.")
            }
            throw SchoolError.message("학교 서비스에 연결하지 못했어요. 인터넷 연결을 확인한 뒤 다시 실행해 주세요.")
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else {
            throw SchoolError.message("서버 응답을 확인할 수 없습니다.")
        }
        guard (200..<300).contains(response.statusCode) else {
            struct Failure: Decodable {
                struct Detail: Decodable { let message: String }
                let error: Detail
            }
            let message = text ? String(data: data, encoding: .utf8) : (try? JSONDecoder().decode(Failure.self, from: data))?.error.message
            throw SchoolError.message(message ?? "학교 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.")
        }
        return data
    }

    func health() async throws -> Health {
        try await JSONDecoder().decode(Health.self, from: request(path: "/api/health"))
    }
    func schools(name: String) async throws -> [School] {
        struct Result: Decodable { let schools: [School] }
        return try await JSONDecoder().decode(Result.self, from: request(path: "/api/schools", query: [URLQueryItem(name: "name", value: name)])).schools
    }
    func classes(school: School) async throws -> [SchoolClass] {
        struct Result: Decodable { let classes: [SchoolClass] }
        let query = [URLQueryItem(name: "officeCode", value: school.officeCode), URLQueryItem(name: "schoolCode", value: school.schoolCode)]
        return try await JSONDecoder().decode(Result.self, from: request(path: "/api/classes", query: query)).classes
    }
    func timetable(settings: SchoolSettings) async throws -> Timetable {
        try await JSONDecoder().decode(Timetable.self, from: request(path: "/api/timetable/today", query: settings.timetableQuery))
    }
    func meals(settings: SchoolSettings) async throws -> Meals {
        try await JSONDecoder().decode(Meals.self, from: request(path: "/api/meal/today", query: settings.schoolQuery))
    }
    func speech(settings: SchoolSettings, meal: Bool) async throws -> String {
        let health = try await health()
        let data = try await request(path: meal ? "/api/voice/meal" : "/api/voice/timetable", query: meal ? settings.schoolQuery : settings.timetableQuery, text: true)
        guard let text = String(data: data, encoding: .utf8) else { throw SchoolError.message("음성 안내를 읽을 수 없습니다.") }
        return (health.neis.mode == "mock" ? "실제 학교 자료가 아닌 예제 데이터입니다. " : "") + text
    }
}
