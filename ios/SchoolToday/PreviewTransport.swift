#if DEBUG
import Foundation

/// Deterministic native UI-test data. This code is excluded from Release builds.
final class PreviewTransport: URLProtocol {
    private static var failedVoice = false
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
        let date = day.string(from: Date())
        let path = request.url!.path
        let arguments = ProcessInfo.processInfo.arguments
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
            body = #"{"schools":[{"officeCode":"B10","schoolCode":"7010911","name":"테스트고등학교","kind":"고등학교","address":"서울특별시 마포구","region":"서울"}]}"#
        case "/api/classes":
            body = #"{"classes":[{"grade":2,"className":"3","department":"콘텐츠과"},{"grade":2,"className":"3","department":"클라우드보안과"}]}"#
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
            body = "{\"date\":\"\(date)\",\"meals\":[{\"code\":\"2\",\"name\":\"중식\",\"dishes\":[\"쌀밥\",\"계란국 (1)\"],\"calories\":\"701 Kcal\"}]}"
        case "/api/voice/timetable": body = "오늘 시간표는 1교시 수학, 3교시 생명과학입니다."
        case "/api/voice/meal": body = "오늘 급식은 쌀밥, 계란국입니다."
        default:
            status = 404
            body = #"{"error":{"message":"지원하지 않는 시험 경로입니다."}}"#
        }
        let contentType = path.hasPrefix("/api/voice/") ? "text/plain; charset=utf-8" : "application/json"
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
