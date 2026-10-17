#if DEBUG
import Foundation

/// Deterministic native UI-test data. This code is excluded from Release builds.
final class PreviewTransport: URLProtocol {
    private static var failedVoice = false
    private static var returnedEmptyClasses = false
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewTransport.self]
        return URLSession(configuration: configuration)
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "Asia/Seoul")
        day.dateFormat = "yyyy-MM-dd"
        let path = request.url!.path
        let arguments = ProcessInfo.processInfo.arguments
        let date = arguments.contains("--wrong-day") ? "2000-01-01" : day.string(from: Date())
        if path.hasPrefix("/api/voice/"), arguments.contains("--fail-first-voice"), !Self.failedVoice {
            Self.failedVoice = true
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let body: String
        var status = 200
        switch path {
        case "/api/health":
            if arguments.contains("--fail-connection") {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            body = #"{"status":"ok","neis":{"mode":"mock"}}"#
        case "/api/schools":
            let kind = arguments.contains("--middle-school") ? "중학교" : "고등학교"
            let name = arguments.contains("--middle-school") ? "테스트중학교" : "테스트고등학교"
            body = "{\"schools\":[{\"officeCode\":\"B10\",\"schoolCode\":\"7010911\",\"name\":\"\(name)\",\"kind\":\"\(kind)\",\"address\":\"서울특별시 마포구\",\"region\":\"서울\"}]}"
        case "/api/classes":
            if arguments.contains("--empty-first-classes"), !Self.returnedEmptyClasses {
                Self.returnedEmptyClasses = true
                body = #"{"classes":[]}"#
            } else if arguments.contains("--middle-school") {
                body = #"{"classes":[{"grade":1,"className":"2"},{"grade":2,"className":"3"},{"grade":2,"className":"7"}]}"#
            } else if arguments.contains("--general-school") {
                body = #"{"classes":[{"grade":1,"className":"2","department":"7차일반"},{"grade":2,"className":"3","department":"7차일반"},{"grade":2,"className":"7","department":"7차일반"}]}"#
            } else {
                body = #"{"classes":[{"grade":2,"className":"3","department":"콘텐츠과"},{"grade":2,"className":"3","department":"클라우드보안과"}]}"#
            }
        case "/api/timetable/today":
            if arguments.contains("--fail-timetable") {
                status = 503
                body = #"{"error":{"code":"NEIS_UNAVAILABLE","message":"학교 서비스에 연결할 수 없습니다."}}"#
            } else if arguments.contains("--empty-timetable") {
                body = "{\"date\":\"\(date)\",\"lessons\":[]}"
            } else {
                body = "{\"date\":\"\(date)\",\"lessons\":[{\"period\":3,\"subject\":\"생명과학\"},{\"period\":1,\"subject\":\"수학\"}]}"
            }
        case "/api/meal/today":
            body = "{\"date\":\"\(date)\",\"meals\":[{\"code\":\"2\",\"name\":\"중식\",\"dishes\":[\"쌀밥\",\"계란국 (1)\"],\"calories\":\"701 Kcal\",\"nutrition\":\"단백질: 25g\",\"origin\":\"쌀: 국내산\"}]}"
        case "/api/timetable/range", "/api/meal/range":
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let from = query.first { $0.name == "from" }?.value ?? ""
            let to = query.first { $0.name == "to" }?.value ?? ""
            let dates = SchoolCalendar.range(from: from, to: to) ?? []
            if path == "/api/timetable/range", arguments.contains("--fail-timetable") {
                status = 503
                body = #"{"error":{"message":"학교 서비스에 연결할 수 없습니다."}}"#
            } else if path == "/api/timetable/range" {
                let days = dates.enumerated().map { index, key in
                    Timetable(date: arguments.contains("--wrong-day") ? "2000-01-01" : key, lessons: arguments.contains("--empty-timetable") ? [] : [
                        Timetable.Lesson(period: 1, subject: "수학", ambiguous: nil),
                        Timetable.Lesson(period: 3, subject: index % 2 == 0 ? "체육" : "생명과학", ambiguous: nil),
                        Timetable.Lesson(period: 4, subject: "수학", ambiguous: nil),
                    ])
                }
                body = String(data: try! JSONEncoder().encode(SchoolRange(from: from, to: to, days: days)), encoding: .utf8)!
            } else {
                let days = dates.map { key in
                    Meals(date: arguments.contains("--wrong-day") ? "2000-01-01" : key, meals: [Meals.Meal(code: "2", name: "중식", dishes: ["쌀밥", "계란국 (1)"], calories: "701 Kcal", nutrition: "단백질: 25g", origin: "쌀: 국내산")])
                }
                body = String(data: try! JSONEncoder().encode(SchoolRange(from: from, to: to, days: days)), encoding: .utf8)!
            }
        case "/api/voice/timetable": body = "오늘 시간표는 1교시 수학, 3교시 생명과학입니다."
        case "/api/voice/meal": body = "오늘 급식은 쌀밥, 계란국입니다."
        default:
            status = 404
            body = #"{"error":{"message":"지원하지 않는 시험 경로입니다."}}"#
        }
        let contentType = path.hasPrefix("/api/voice/") ? "text/plain; charset=utf-8" : "application/json"
        var headers = ["Content-Type": contentType]
        if path.hasPrefix("/api/voice/"), status == 200 { headers["X-School-Data-Mode"] = "mock" }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
