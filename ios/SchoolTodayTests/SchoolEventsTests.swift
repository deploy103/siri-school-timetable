import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SchoolToday

final class SchoolEventsTests: XCTestCase {
    private let settings = SchoolSettings(
        school: School(officeCode: "B10", schoolCode: "123", name: "학교", kind: "고등학교", address: "", region: ""),
        schoolClass: SchoolClass(grade: 2, className: "3", department: nil))

    private func api(_ body: String, status: Int = 200) throws -> SchoolAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SchoolEventsTransport.self]
        let host = UUID().uuidString.lowercased() + ".invalid"
        SchoolEventsTransport.register(host: host, body: body, status: status)
        return try SchoolAPI(server: "https://\(host)", session: URLSession(configuration: configuration))
    }

    private let event = #"{"name":"같은 행사","content":"첫째","lessonDayType":"원문","dayNightCourse":"주야","schoolCourse":"과정","gradeFlags":["*","N","Y","","0","미정"]}"#

    private func body(from: String = "2026-10-19", to: String = "2026-10-20", dates: [String] = ["2026-10-19", "2026-10-20"], events: String = "") -> String {
        let days = dates.map { "{\"date\":\"\($0)\",\"school\":{\"name\":\"학교\"},\"events\":[\(events)]}" }.joined(separator: ",")
        return "{\"from\":\"\(from)\",\"to\":\"\(to)\",\"days\":[\(days)]}"
    }

    func testDecodePreservesRawFieldsAndDuplicateNamePositions() async throws {
        let client = try api(body(events: event + "," + event.replacingOccurrences(of: "첫째", with: "둘째")))
        defer { client.session.invalidateAndCancel() }
        let days = try await client.schoolEvents(settings: settings, from: "2026-10-19", to: "2026-10-20")
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].school.name, "학교")
        XCTAssertEqual(days[0].positionedEvents.map(\.id), [0, 1])
        XCTAssertEqual(days[0].events.map(\.name), ["같은 행사", "같은 행사"])
        XCTAssertEqual(days[0].events.map(\.content), ["첫째", "둘째"])
        XCTAssertEqual(days[0].events[0].gradeFlags, ["*", "N", "Y", "", "0", "미정"])
        XCTAssertEqual(days[0].events[0].lessonDayType, "원문")
        XCTAssertEqual(days[0].events[0].dayNightCourse, "주야")
        XCTAssertEqual(days[0].events[0].schoolCourse, "과정")
    }

    func testRejectsInvalidRequestsAndIncompleteOrWrongRanges() async throws {
        let client = try api(body())
        defer { client.session.invalidateAndCancel() }
        for (from, to) in [("2026-02-30", "2026-03-01"), ("2026-10-20", "2026-10-19"), ("2026-10-19", "2026-10-26")] {
            do {
                _ = try await client.schoolEvents(settings: settings, from: from, to: to)
                XCTFail("Invalid request accepted")
            } catch { XCTAssertTrue(error is SchoolError) }
        }
        for payload in [
            body(from: "2026-10-18"), body(to: "2026-10-21"),
            body(dates: ["2026-10-19"]), body(dates: ["2026-10-20", "2026-10-19"]),
            body(dates: ["2026-10-19", "2026-10-19"]),
            body(dates: ["2026-10-19", "2026-10-20", "2026-10-21"]),
            body(events: event.replacingOccurrences(of: #""*","N","Y","","0","미정""#, with: #""Y""#)),
            "not JSON",
        ] {
            let invalid = try api(payload)
            defer { invalid.session.invalidateAndCancel() }
            do {
                _ = try await invalid.schoolEvents(settings: settings, from: "2026-10-19", to: "2026-10-20")
                XCTFail("Invalid response accepted: \(payload)")
            } catch { XCTAssertTrue(error is SchoolError) }
        }
    }

    func testEmptyWeekAndServiceError() async throws {
        let dates = SchoolCalendar.week(containing: "2026-10-21")
        let client = try api(body(from: dates.first!, to: dates.last!, dates: dates))
        defer { client.session.invalidateAndCancel() }
        let days = try await client.schoolEvents(settings: settings, from: dates.first!, to: dates.last!)
        XCTAssertEqual(days.map(\.date), dates)
        XCTAssertTrue(days.allSatisfy { $0.events.isEmpty })
        let failed = try api(#"{"error":{"message":"다시 시도"}}"#, status: 503)
        defer { failed.session.invalidateAndCancel() }
        do {
            _ = try await failed.schoolEvents(settings: settings, from: "2026-10-19", to: "2026-10-20")
            XCTFail("Service error accepted")
        } catch { XCTAssertEqual(error.localizedDescription, "다시 시도") }
    }
}

private final class SchoolEventsTransport: URLProtocol {
    private static let lock = NSLock()
    private static var fixtures: [String: (String, Int)] = [:]
    static func register(host: String, body: String, status: Int) {
        lock.lock()
        defer { lock.unlock() }
        fixtures[host] = (body, status)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let fixture = Self.fixtures.removeValue(forKey: request.url!.host!)
        Self.lock.unlock()
        guard let (body, status) = fixture else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/calendar/range")
        XCTAssertEqual(Set(query.map(\.name)), Set(["officeCode", "schoolCode", "from", "to"]))
        XCTAssertEqual(query.first { $0.name == "officeCode" }?.value, "B10")
        XCTAssertEqual(query.first { $0.name == "schoolCode" }?.value, "123")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
