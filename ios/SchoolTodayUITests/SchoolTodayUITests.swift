import XCTest

final class SchoolTodayUITests: XCTestCase {
    private func launch(extra: [String] = [], start: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-settings"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["start-onboarding"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["school-search"].exists)
        XCTAssertFalse(app.staticTexts["connection-error"].exists)
        capture("native-welcome", app: app)
        if start { app.buttons["start-onboarding"].tap() }
        return app
    }

    private func chooseClass(_ app: XCUIApplication) {
        let search = app.textFields["school-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["server-address"].exists)
        XCTAssertFalse(app.buttons["school-next"].isEnabled)
        search.tap(); search.typeText("테스트")
        capture("native-school-keyboard", app: app)
        app.buttons["학교 검색"].tap()
        let school = app.buttons["테스트고등학교"]
        XCTAssertTrue(school.waitForExistence(timeout: 10)); school.tap()
        XCTAssertTrue(app.buttons["school-next"].isEnabled)
        capture("native-school-selected", app: app)
        app.buttons["school-next"].tap()
        let selected = app.buttons["콘텐츠과 · 2학년 3반"]
        XCTAssertTrue(selected.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["클라우드보안과 · 2학년 3반"].exists)
        XCTAssertFalse(app.buttons["class-next"].isEnabled)
        selected.tap()
        XCTAssertTrue(app.buttons["class-next"].isEnabled)
        capture("native-class-selected", app: app)
        app.buttons["class-next"].tap()
        XCTAssertTrue(app.staticTexts["siri-guide-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["시간표"].exists)
    }

    private func finishGuide(_ app: XCUIApplication, from page: Int = 0) {
        let titles = ["Siri를 켜볼까요?", "불러보세요", "열어볼까요?", "물어보세요", "부를 수도 있어요"]
        let names = ["siri-settings", "siri-activation", "shortcuts", "app-phrases", "personal-name"]
        for step in page..<5 {
            XCTAssertTrue(app.staticTexts["siri-guide-title"].label.contains(titles[step]))
            XCTAssertTrue(app.staticTexts["siri-guide-title"].isHittable)
            capture("native-guide-\(names[step])", app: app)
            if step == 2 {
                let entry = app.buttons["open-school-shortcuts"]
                for _ in 0..<3 where !entry.isHittable { app.swipeUp() }
                XCTAssertTrue(entry.isHittable)
            }
            app.swipeUp()
            capture("native-guide-\(names[step])-scrolled", app: app)
            XCTAssertTrue(app.buttons["guide-next"].isHittable)
            app.buttons["guide-next"].tap()
        }
        let finish = app.buttons["finish-onboarding"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["홈"].exists)
        capture("native-setup-complete", app: app)
        finish.tap()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["홈"].isSelected)
        capture("native-home", app: app)
    }

    private func selectSchool(_ app: XCUIApplication) {
        chooseClass(app)
        finishGuide(app)
        app.tabBars.buttons["시간표"].tap()
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
        XCTAssertTrue(app.buttons["Siri 설정 안내 다시 보기"].exists)
        capture("native-settings", app: app)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["홈"].isSelected)
        XCTAssertFalse(app.buttons["start-onboarding"].exists)
        app.tabBars.buttons["시간표"].tap()
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
        XCTAssertTrue(app.buttons["start-onboarding"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["start-onboarding"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["수학"].exists)
        app.buttons["start-onboarding"].tap()
        selectSchool(app)
    }

    func testInterruptedSetupBackSkipAndHomeHelp() {
        let app = launch()
        chooseClass(app)
        app.buttons["guide-next"].tap()
        app.buttons["이전 단계"].tap()
        XCTAssertTrue(app.staticTexts["siri-guide-title"].label.contains("Siri를 켜볼까요?"))
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["start-onboarding"].waitForExistence(timeout: 10))
        app.buttons["start-onboarding"].tap()
        XCTAssertTrue(app.buttons["skip-siri-setup"].waitForExistence(timeout: 10))
        app.buttons["skip-siri-setup"].tap()
        finishGuide(app, from: 2)
        app.buttons["siri-help"].tap()
        XCTAssertTrue(app.staticTexts["siri-guide-title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["siri-guide-title"].label.contains("Siri를 켜볼까요?"))
        app.buttons["닫기"].tap()
        app.swipeUp()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "급식 보기")).firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["급식"].isSelected)
        XCTAssertTrue(app.staticTexts["계란국 (1)"].waitForExistence(timeout: 10))
        app.tabBars.buttons["홈"].tap()
        app.swipeUp()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "시간표 보기")).firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["시간표"].isSelected)
        XCTAssertTrue(app.staticTexts["수학"].waitForExistence(timeout: 10))
    }

    func testEmptyTimetableIsNotAnError() {
        let app = launch(extra: ["--empty-timetable"])
        selectSchool(app)
        XCTAssertTrue(app.staticTexts["오늘 등록된 시간표가 없습니다."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["학교 정보를 확인하지 못했어요"].exists)
        capture("native-empty", app: app)
    }

    func testShortcutCheckFailureRetryAndBothResults() {
        let app = launch(extra: ["--fail-first-voice"])
        selectSchool(app)
        app.tabBars.buttons["홈"].tap()
        let check = app.buttons["shortcut-check"]
        for _ in 0..<3 where !check.isHittable { app.swipeUp() }
        XCTAssertTrue(check.isHittable)
        check.tap()
        XCTAssertTrue(app.buttons["check-timetable"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["닫기"].isHittable)
        capture("native-shortcut-check", app: app)
        app.buttons["check-timetable"].tap()
        let error = app.staticTexts["shortcut-check-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("잠시 뒤 다시 실행"))
        XCTAssertFalse(app.staticTexts["shortcut-check-result"].exists)
        capture("native-shortcut-check-error", app: app)
        app.buttons["check-timetable"].tap()
        let result = app.staticTexts["shortcut-check-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertEqual(result.label, "실제 학교 자료가 아닌 예제 데이터입니다. 오늘 시간표는 1교시 수학, 3교시 생명과학입니다.")
        XCTAssertFalse(error.exists)
        capture("native-shortcut-check-timetable", app: app)
        app.buttons["check-meal"].tap()
        let meal = NSPredicate(format: "label == %@", "실제 학교 자료가 아닌 예제 데이터입니다. 오늘 급식은 쌀밥, 계란국입니다.")
        expectation(for: meal, evaluatedWith: result)
        waitForExpectations(timeout: 10)
        capture("native-shortcut-check-meal", app: app)
        app.swipeUp()
        capture("native-shortcut-check-instructions", app: app)
        app.buttons["닫기"].tap()
        XCTAssertTrue(app.tabBars.buttons["홈"].isSelected)
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
        let app = launch(extra: ["--fail-connection"], start: false)
        XCTAssertFalse(app.buttons["다시 시도"].exists)
        app.buttons["start-onboarding"].tap()
        XCTAssertTrue(app.staticTexts["connection-error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["connection-error"].label.contains("인터넷 연결을 확인"))
        XCTAssertTrue(app.buttons["다시 시도"].isHittable)
        XCTAssertFalse(app.textFields["server-address"].exists)
        XCTAssertFalse(app.textFields["school-search"].exists)
        capture("native-connection-error", app: app)
    }
}
