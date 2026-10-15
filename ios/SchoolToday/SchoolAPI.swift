import Foundation

struct SchoolAPI: Sendable {
    let baseURL: URL
    let session: URLSession

    init(server: String, session: URLSession = .shared) throws {
        guard var parts = URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", parts.url != nil else {
            throw SchoolError.message("HTTPS 서버 주소를 확인해 주세요. 경로나 계정 정보가 없는 주소가 필요합니다.")
        }
        parts.host = host.lowercased()
        if parts.port == 443 { parts.port = nil }
        parts.path = ""
        baseURL = parts.url!
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

    private func request(path: String, query: [URLQueryItem] = [], text: Bool = false) async throws -> (data: Data, response: HTTPURLResponse) {
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
            let usableMessage = message.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            let isPlainText = response.mimeType == "text/plain"
            throw SchoolError.message((text && !isPlainText ? nil : usableMessage) ?? "학교 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.")
        }
        return (data, response)
    }

    private func json<Value: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> Value {
        let result = try await request(path: path, query: query)
        do { return try JSONDecoder().decode(Value.self, from: result.data) }
        catch is DecodingError {
            throw SchoolError.message("학교 자료를 읽지 못했어요. 잠시 뒤 다시 시도해 주세요.")
        }
    }

    func health() async throws -> Health {
        try await json(path: "/api/health")
    }
    func schools(name: String) async throws -> [School] {
        struct Result: Decodable { let schools: [School] }
        let result: Result = try await json(path: "/api/schools", query: [URLQueryItem(name: "name", value: name)])
        return result.schools
    }
    func classes(school: School) async throws -> [SchoolClass] {
        struct Result: Decodable { let classes: [SchoolClass] }
        let query = [URLQueryItem(name: "officeCode", value: school.officeCode), URLQueryItem(name: "schoolCode", value: school.schoolCode)]
        let result: Result = try await json(path: "/api/classes", query: query)
        return result.classes
    }
    func timetable(settings: SchoolSettings) async throws -> Timetable {
        let result: Timetable = try await json(path: "/api/timetable/today", query: settings.timetableQuery)
        // Match the server's 1...20, one-row-per-period contract before UI IDs or missing-period ranges use it.
        guard result.lessons.allSatisfy({ (1...20).contains($0.period) }),
              Set(result.lessons.map(\.period)).count == result.lessons.count else {
            throw SchoolError.message("시간표 자료가 올바르지 않아요. 잠시 뒤 다시 시도해 주세요.")
        }
        return result
    }
    func meals(settings: SchoolSettings) async throws -> Meals {
        try await json(path: "/api/meal/today", query: settings.schoolQuery)
    }
    func speech(settings: SchoolSettings, meal: Bool) async throws -> String {
        let result = try await request(path: meal ? "/api/voice/meal" : "/api/voice/timetable", query: meal ? settings.schoolQuery : settings.timetableQuery, text: true)
        guard result.response.mimeType == "text/plain",
              let text = String(data: result.data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchoolError.message("음성 안내를 읽을 수 없습니다. 잠시 뒤 다시 실행해 주세요.")
        }
        let mode: String
        if let responseMode = result.response.value(forHTTPHeaderField: "X-School-Data-Mode") {
            mode = responseMode
        } else {
            // Older servers don't yet include data provenance in the voice response.
            mode = try await health().neis.mode
        }
        guard mode == "live" || mode == "mock" else {
            throw SchoolError.message("학교 자료의 출처를 확인하지 못했어요. 잠시 뒤 다시 실행해 주세요.")
        }
        return (mode == "mock" ? "실제 학교 자료가 아닌 예제 데이터입니다. " : "") + text
    }
}
