import XCTest
@testable import SchoolToday

final class SchoolTodayTests: XCTestCase {
    private var settings: SchoolSettings {
        SchoolSettings(
            school: School(officeCode: "B10", schoolCode: "7010911", name: "테스트고등학교", kind: "고등학교", address: "서울", region: "서울"),
            schoolClass: SchoolClass(grade: 2, className: "3+과정", department: "콘텐츠 & 보안과")
        )
    }

    func testHTTPSOriginValidation() throws {
        for invalid in ["http://example.com", "https://user:password@example.com", "https://example.com/api", "https://example.com?token=secret", "https://example.com#fragment", ""] {
            XCTAssertThrowsError(try SchoolAPI(server: invalid), invalid)
        }
        let api = try SchoolAPI(server: "https://example.com:8443/")
        XCTAssertEqual(api.baseURL.host, "example.com")
        XCTAssertEqual(api.baseURL.port, 8443)
    }

    func testDepartmentAndNonNumericClassRoundTripWithoutQueryInjection() throws {
        let api = try SchoolAPI(server: "https://example.com")
        let url = api.url(path: "/api/timetable/today", query: settings.timetableQuery)
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "department" }?.value, "콘텐츠 & 보안과")
        XCTAssertEqual(items.first { $0.name == "className" }?.value, "3+과정")
        XCTAssertEqual(items.count, 6)
        // The Next.js URLSearchParams parser treats an unescaped + as a space.
        XCTAssertTrue(url.absoluteString.contains("className=3%2B"), url.absoluteString)
        XCTAssertEqual(url.path, "/api/timetable/today")
        XCTAssertEqual(settings.schoolQuery.map(\.name), ["officeCode", "schoolCode"])
        let other = SchoolClass(grade: 2, className: "3+과정", department: "다른 학과")
        XCTAssertNotEqual(other.id, settings.schoolClass.id)
    }

    func testPreferencesPersistTheCompleteSelectionAndReset() throws {
        let suite = "SchoolTodayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try SchoolPreferences.writeSchool(settings, defaults: defaults)
        XCTAssertEqual(SchoolPreferences.readSchool(defaults: defaults), settings)
        try SchoolPreferences.writeSchool(nil, defaults: defaults)
        XCTAssertNil(SchoolPreferences.readSchool(defaults: defaults))
        defaults.set(Data("not JSON".utf8), forKey: SchoolPreferences.schoolKey)
        XCTAssertNil(SchoolPreferences.readSchool(defaults: defaults))
    }

    func testAPIContractsAndAudibleMockDisclosure() async throws {
        let api = try SchoolAPI(server: "https://fixture.invalid", session: PreviewTransport.session)
        let schools = try await api.schools(name: "테스트")
        XCTAssertEqual(schools.first?.name, "테스트고등학교")
        let classes = try await api.classes(school: settings.school)
        XCTAssertEqual(classes.map(\.department), ["콘텐츠과", "클라우드보안과"])
        XCTAssertEqual(classes.map(\.className), ["3", "3"])
        let timetable = try await api.timetable(settings: settings)
        XCTAssertEqual(timetable.lessons.map(\.period), [3, 1])
        let meals = try await api.meals(settings: settings)
        XCTAssertEqual(meals.meals.first?.dishes, ["쌀밥", "계란국 (1)"])
        let speech = try await api.speech(settings: settings, meal: false)
        XCTAssertTrue(speech.hasPrefix("실제 학교 자료가 아닌 예제 데이터입니다. "))
        XCTAssertTrue(speech.contains("1교시 수학"))
    }

    func testAppIntentsReturnReusableSetupGuidanceWhenSchoolIsMissing() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: SchoolPreferences.schoolKey)
        defer {
            if let original { defaults.set(original, forKey: SchoolPreferences.schoolKey) }
            else { defaults.removeObject(forKey: SchoolPreferences.schoolKey) }
        }
        defaults.removeObject(forKey: SchoolPreferences.schoolKey)
        let timetable = try await TodayTimetableIntent().perform()
        let meal = try await TodayMealIntent().perform()
        XCTAssertEqual(timetable.value, "오늘의 학교 앱에서 학교와 학급을 먼저 설정해 주세요.")
        XCTAssertEqual(meal.value, "오늘의 학교 앱에서 학교와 학급을 먼저 설정해 주세요.")
    }

    func testNetworkFailuresAreActionableAndCancellationIsPreserved() async throws {
        let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        defer { ControlledTransport.onStart = nil }
        for code in [URLError.Code.notConnectedToInternet, .timedOut, .cancelled] {
            ControlledTransport.onStart = { $0.fail(code) }
            do {
                _ = try await api.health()
                XCTFail("Expected a failed request")
            } catch {
                if code == .cancelled { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
                else if code == .timedOut {
                    XCTAssertEqual(error.localizedDescription, "학교 서비스의 응답이 늦어지고 있어요. 잠시 뒤 다시 실행해 주세요.")
                } else {
                    XCTAssertEqual(error.localizedDescription, "학교 서비스에 연결하지 못했어요. 인터넷 연결을 확인한 뒤 다시 실행해 주세요.")
                }
            }
        }
    }

    @MainActor
    func testKoreanMidnightAndClearingYesterday() async throws {
        let before = ISO8601DateFormatter().date(from: "2026-10-08T14:59:59Z")!
        let after = ISO8601DateFormatter().date(from: "2026-10-08T15:00:00Z")!
        XCTAssertEqual(TodayModel.day(before), "2026-10-08")
        XCTAssertEqual(TodayModel.day(after), "2026-10-09")
        let model = TodayModel()
        let api = try SchoolAPI(server: "https://fixture.invalid", session: PreviewTransport.session)
        await model.load(kind: .timetable, settings: settings, api: api)
        XCTAssertEqual(model.timetable?.lessons.count, 2)
        model.clearYesterday()
        XCTAssertNil(model.timetable)
        XCTAssertNil(model.meals)
        XCTAssertFalse(model.loading)
        XCTAssertEqual(model.error, "인터넷 연결을 확인한 뒤 다시 시도해 주세요.")
    }

    @MainActor
    func testReconnectPreservesSchoolButChangingBackendAndResetClearIt() async throws {
        let suite = "SchoolTodayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SchoolStore(defaults: defaults, session: PreviewTransport.session, server: "https://fixture.invalid")
        try await store.connect()
        try store.saveSchool(settings)
        try await store.connect()
        XCTAssertEqual(store.school, settings)
        let updated = SchoolStore(defaults: defaults, session: PreviewTransport.session, server: "https://fixture.invalid:8443")
        try await updated.connect()
        XCTAssertNil(updated.school)
        XCTAssertNil(SchoolPreferences.readSchool(defaults: defaults))
        try updated.saveSchool(settings)
        try updated.saveSchool(nil)
        XCTAssertNotNil(updated.api)
        XCTAssertNil(updated.school)
        XCTAssertNil(SchoolPreferences.readSchool(defaults: defaults))
        XCTAssertEqual(updated.server, "https://fixture.invalid:8443")
        XCTAssertEqual(SchoolStore(defaults: defaults).server, SchoolPreferences.server())
    }

    @MainActor
    func testOlderResponseOrErrorCannotReplaceANewerLoad() async throws {
        let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        for oldStatus in [200, 503] {
            for finishOldFirst in [true, false] {
                let model = TodayModel()
                let firstStarted = expectation(description: "older request started")
                let secondStarted = expectation(description: "newer request started")
                var requests: [ControlledTransport] = []
                ControlledTransport.onStart = { transport in
                    Task { @MainActor in
                        requests.append(transport)
                        if requests.count == 1 { firstStarted.fulfill() }
                        else if requests.count == 2 { secondStarted.fulfill() }
                    }
                }
                defer { ControlledTransport.onStart = nil }
                let first = Task { await model.load(kind: .timetable, settings: settings, api: api) }
                await fulfillment(of: [firstStarted], timeout: 3)
                let second = Task { await model.load(kind: .timetable, settings: settings, api: api) }
                await fulfillment(of: [secondStarted], timeout: 3)
                guard requests.count == 2 else {
                    first.cancel(); second.cancel()
                    XCTFail("Expected two overlapping requests")
                    return
                }
                if finishOldFirst {
                    requests[0].finish(subject: "older", status: oldStatus)
                    await first.value
                    XCTAssertTrue(model.loading)
                    XCTAssertNil(model.timetable)
                    XCTAssertNil(model.error)
                }
                requests[1].finish(subject: "newer")
                await second.value
                if !finishOldFirst {
                    requests[0].finish(subject: "older", status: oldStatus)
                    await first.value
                }
                XCTAssertEqual(model.timetable?.lessons.first?.subject, "newer")
                XCTAssertFalse(model.loading)
                XCTAssertNil(model.error)
            }
        }
    }
}

private final class ControlledTransport: URLProtocol {
    static var onStart: ((ControlledTransport) -> Void)?
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ControlledTransport.self]
        return URLSession(configuration: configuration)
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "controlled.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.onStart?(self) }
    override func stopLoading() {}
    func fail(_ code: URLError.Code) {
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }
    func finish(subject: String, status: Int = 200) {
        let body = status == 200
            ? "{\"date\":\"2026-10-08\",\"lessons\":[{\"period\":1,\"subject\":\"\(subject)\"}]}"
            : "{\"error\":{\"message\":\"older request failed\"}}"
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}
