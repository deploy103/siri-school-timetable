import XCTest

final class SchoolTodayUITests: XCTestCase {
    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-settings"] + extra
        app.launch()
        return app
    }

    private func selectSchool(_ app: XCUIApplication) {
        let search = app.textFields["school-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["server-address"].exists)
        search.tap(); search.typeText("테스트")
        app.buttons["학교 검색"].tap()
        let school = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "테스트고등학교")).firstMatch
        XCTAssertTrue(school.waitForExistence(timeout: 10)); school.tap()
        let selected = app.buttons["콘텐츠과 · 2학년 3반"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["클라우드보안과 · 2학년 3반"].exists)
        selected.tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNativeSetupTimetableMealsSettingsAndRelaunch() {
        let app = launch()
        XCTAssertTrue(app.textFields["school-search"].waitForExistence(timeout: 10))
        capture("native-start", app: app)
        selectSchool(app)
        XCTAssertTrue(app.staticTexts["수학"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["예제 데이터 · 실제 학교 자료가 아닙니다"].exists)
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertLessThan(labels.firstIndex(of: "수학")!, labels.firstIndex(of: "생명과학")!)
        capture("native-timetable", app: app)
        app.tabBars.buttons["급식"].tap()
        XCTAssertTrue(app.staticTexts["계란국 (1)"].waitForExistence(timeout: 10))
        capture("native-meals", app: app)
        app.tabBars.buttons["설정"].tap()
        XCTAssertTrue(app.buttons["open-school-shortcuts"].isHittable)
        XCTAssertTrue(app.staticTexts["오늘 시간표 듣기"].exists)
        capture("native-settings", app: app)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.staticTexts["수학"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["콘텐츠과 · 2학년 3반"].exists)
        app.tabBars.buttons["설정"].tap()
        let reset = app.buttons["학교 설정 초기화"]
        for _ in 0..<3 where !reset.isHittable { app.swipeUp() }
        XCTAssertTrue(reset.isHittable)
        capture("native-settings-scrolled", app: app)
        reset.tap()
        let delete = app.buttons["설정 삭제"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(app.textFields["school-search"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["school-search"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["수학"].exists)
    }

    func testEmptyTimetableIsNotAnError() {
        let app = launch(extra: ["--empty-timetable"])
        selectSchool(app)
        XCTAssertTrue(app.staticTexts["오늘 등록된 시간표가 없습니다."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["학교 정보를 확인하지 못했어요"].exists)
        capture("native-empty", app: app)
    }

    func testFailedLookupOffersRetryWithoutOldLessons() {
        let app = launch(extra: ["--fail-timetable"])
        selectSchool(app)
        XCTAssertTrue(app.staticTexts["학교 서비스에 연결할 수 없습니다."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["다시 시도"].exists)
        XCTAssertFalse(app.staticTexts["수학"].exists)
        capture("native-error", app: app)
    }

    func testMissingBackendDoesNotAskUserForAnAddress() {
        let app = launch(extra: ["--missing-server"])
        XCTAssertTrue(app.staticTexts["서비스 연결이 아직 준비되지 않았습니다."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["server-address"].exists)
        XCTAssertFalse(app.textFields["school-search"].exists)
        capture("native-service-unconfigured", app: app)
    }

    func testBackendConnectionFailureOffersRetryWithoutAddressInput() {
        let app = launch(extra: ["--fail-connection"])
        XCTAssertTrue(app.staticTexts["connection-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["다시 시도"].isHittable)
        XCTAssertFalse(app.textFields["server-address"].exists)
        XCTAssertFalse(app.textFields["school-search"].exists)
        capture("native-connection-error", app: app)
    }
}
