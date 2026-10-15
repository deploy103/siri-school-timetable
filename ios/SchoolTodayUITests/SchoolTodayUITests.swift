import XCTest

final class SchoolTodayUITests: XCTestCase {
    private func launch(extra: [String] = [], start: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-settings"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["start-onboarding"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["반가워요!"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["welcome-example-notice"].exists)
        XCTAssertFalse(app.staticTexts["오늘의 시간표"].exists)
        XCTAssertFalse(app.textFields["school-search"].exists)
        XCTAssertFalse(app.staticTexts["connection-error"].exists)
        capture("native-welcome", app: app)
        if start { tap(app.buttons["start-onboarding"], in: app) }
        return app
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        for _ in 0..<8 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }

    private func chooseSchool(_ app: XCUIApplication, name: String = "테스트고등학교") {
        let search = app.textFields["school-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["server-address"].exists)
        XCTAssertFalse(app.buttons["school-next"].isEnabled)
        search.tap(); search.typeText("테스트")
        capture("native-school-keyboard", app: app)
        app.buttons["학교 검색"].tap()
        let school = app.buttons[name]
        XCTAssertTrue(school.waitForExistence(timeout: 10)); school.tap()
        XCTAssertTrue(app.buttons["school-next"].isEnabled)
        capture("native-school-selected", app: app)
        tap(app.buttons["school-next"], in: app)
    }

    private func chooseClass(_ app: XCUIApplication) {
        chooseSchool(app)
        XCTAssertTrue(app.buttons["일반고"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["class-step-next"].isEnabled)
        tap(app.buttons["특성화고"], in: app)
        capture("native-school-type", app: app)
        tap(app.buttons["class-step-next"], in: app)
        tap(app.buttons["2학년"], in: app)
        capture("native-grade", app: app)
        tap(app.buttons["class-step-next"], in: app)
        XCTAssertTrue(app.buttons["클라우드보안과"].waitForExistence(timeout: 10))
        tap(app.buttons["콘텐츠과"], in: app)
        capture("native-department", app: app)
        tap(app.buttons["class-step-next"], in: app)
        XCTAssertFalse(app.buttons["class-next"].isEnabled)
        tap(app.buttons["3반"], in: app)
        XCTAssertTrue(app.buttons["class-next"].isEnabled)
        capture("native-class-selected", app: app)
        tap(app.buttons["class-next"], in: app)
        XCTAssertTrue(app.staticTexts["siri-guide-title"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["시간표"].exists)
    }

    private func finishGuide(_ app: XCUIApplication) {
        let titles = ["Siri 켜기", "Siri 부르기", "시간표를 뭐라고 부를까요?", "단축어 실행해 보기", "이렇게 불러보세요", "급식도 불러볼까요?", "급식을 뭐라고 부를까요?", "단축어 실행해 보기", "이렇게 불러보세요"]
        let names = ["siri-settings", "siri-activation", "timetable-name", "shortcuts", "timetable-phrase", "meal-offer", "meal-name", "meal-shortcut", "meal-phrase"]
        let screenshots = [0: "SiriSettingsGuide", 1: "SiriActivationGuide", 3: "AppShortcutsGuide"]
        for step in titles.indices {
            XCTAssertTrue(app.staticTexts["siri-guide-title"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["siri-guide-title"].label.contains(titles[step]))
            XCTAssertTrue(app.staticTexts["siri-guide-title"].isHittable)
            capture("native-guide-\(names[step])", app: app)
            if let asset = screenshots[step] {
                let image = app.buttons["guide-screenshot-\(asset)"]
                XCTAssertTrue(image.isHittable)
                image.tap()
                let closeImage = app.buttons["close-guide-screenshot"]
                XCTAssertTrue(closeImage.waitForExistence(timeout: 5))
                XCTAssertTrue(app.navigationBars["화면 캡처 크게 보기"].exists)
                capture("native-guide-\(names[step])-screenshot-expanded", app: app)
                let zoom = app.buttons["zoom-guide-screenshot"]
                XCTAssertTrue(zoom.isHittable)
                zoom.tap()
                XCTAssertEqual(zoom.label, "전체 폭으로 보기")
                capture("native-guide-\(names[step])-screenshot-zoomed", app: app)
                zoom.tap()
                XCTAssertEqual(zoom.label, "더 확대하기")
                closeImage.tap()
                XCTAssertTrue(app.staticTexts["siri-guide-title"].isHittable)
            }
            if step == 3 {
                let entry = app.buttons["open-school-shortcuts"]
                for _ in 0..<3 where !entry.isHittable { app.swipeUp() }
                XCTAssertTrue(entry.isHittable)
            }
            if step == 4 || step == 8 {
                XCTAssertFalse(app.descendants(matching: .any)["run-personal-shortcut"].exists)
                XCTAssertTrue(app.descendants(matching: .any)["open-school-shortcuts"].exists)
            }
            tap(app.buttons["guide-next"], in: app)
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

    private func selectSchool(_ app: XCUIApplication, guide: Bool = false) {
        chooseClass(app)
        if guide { finishGuide(app) }
        else { tap(app.buttons["skip-siri-setup"], in: app) }
        app.tabBars.buttons["시간표"].tap()
    }

    private func capture(_ name: String, app: XCUIApplication) {
        // Page transitions finish in at most 0.35 seconds; capture the settled layout.
        Thread.sleep(forTimeInterval: 0.45)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func callName(_ kind: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["shortcut-name-\(kind)"]
    }

    private func replaceCallName(_ name: String, kind: String = "timetable", in app: XCUIApplication) {
        let field = callName(kind, in: app)
        tap(field, in: app)
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.press(forDuration: 1.2)
            let selectAll = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", ["전체 선택", "Select All"])).firstMatch
            for _ in 0..<3 where !selectAll.exists {
                let nextPage = app.buttons.matching(NSPredicate(format: "label IN %@", ["다음 페이지", "Next Page"])).firstMatch
                guard nextPage.exists else { break }
                nextPage.tap()
            }
            XCTAssertTrue(selectAll.waitForExistence(timeout: 5), app.debugDescription)
            selectAll.tap()
            field.typeText(XCUIKeyboardKey.delete.rawValue)
        }
        if !name.isEmpty {
            field.typeText(name)
            XCTAssertEqual(field.value as? String, name)
        } else {
            XCTAssertTrue((field.value as? String ?? "").isEmpty || field.value as? String == field.placeholderValue)
        }
        capture("native-name-\(kind)-keyboard", app: app)
        tap(app.buttons["입력 완료"], in: app)
    }

    func testEmptyClassesCanReloadWithoutRestartingSchoolSetup() {
        let app = launch(extra: ["--general-school", "--empty-first-classes"])
        chooseSchool(app)
        tap(app.buttons["일반고"], in: app)
        tap(app.buttons["class-step-next"], in: app)
        let retry = app.buttons["reload-empty-classes"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["class-step-next"].isEnabled)
        capture("native-empty-classes", app: app)
        tap(retry, in: app)
        tap(app.buttons["2학년"], in: app)
        tap(app.buttons["class-step-next"], in: app)
        tap(app.buttons["3반"], in: app)
        tap(app.buttons["class-next"], in: app)
        XCTAssertTrue(app.buttons["skip-siri-setup"].waitForExistence(timeout: 10))
        tap(app.buttons["skip-siri-setup"], in: app)
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["2학년 3반"].exists)
    }

    func testGeneralAndMiddleSchoolBranchesInvalidateOnlyDependentChoices() {
        for middle in [false, true] {
            let app = launch(extra: [middle ? "--middle-school" : "--general-school"])
            chooseSchool(app, name: middle ? "테스트중학교" : "테스트고등학교")
            if !middle {
                tap(app.buttons["일반고"], in: app)
                tap(app.buttons["class-step-next"], in: app)
            } else {
                XCTAssertFalse(app.buttons["일반고"].exists)
                XCTAssertFalse(app.buttons["특성화고"].exists)
            }
            tap(app.buttons["2학년"], in: app)
            tap(app.buttons["class-step-next"], in: app)
            XCTAssertEqual(app.staticTexts["setup-title"].label, "몇 반인가요?")
            XCTAssertFalse(app.staticTexts["7차일반"].exists)
            XCTAssertFalse(app.buttons["콘텐츠과"].exists)
            tap(app.buttons["7반"], in: app)
            capture(middle ? "native-middle-class" : "native-general-class", app: app)
            tap(app.buttons["이전 선택"], in: app)
            XCTAssertEqual(app.buttons["2학년"].value as? String, "선택됨")
            tap(app.buttons["1학년"], in: app)
            tap(app.buttons["class-step-next"], in: app)
            XCTAssertFalse(app.buttons["7반"].exists)
            XCTAssertFalse(app.buttons["3반"].exists)
            XCTAssertFalse(app.buttons["class-next"].isEnabled)
            tap(app.buttons["2반"], in: app)
            tap(app.buttons["class-next"], in: app)
            tap(app.buttons["skip-siri-setup"], in: app)
            XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["1학년 2반"].exists)
            XCTAssertFalse(app.staticTexts["7차일반 · 1학년 2반"].exists)
            capture(middle ? "native-middle-selection-saved" : "native-general-selection-saved", app: app)
            app.terminate()
        }
    }

    func testGeneralSelectionDoesNotGuessADepartmentAndDepartmentChangesClearClass() {
        let app = launch()
        chooseSchool(app)
        tap(app.buttons["일반고"], in: app)
        tap(app.buttons["class-step-next"], in: app)
        tap(app.buttons["2학년"], in: app)
        tap(app.buttons["class-step-next"], in: app)
        XCTAssertTrue(app.staticTexts["class-department-required"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["class-next"].isEnabled)
        XCTAssertFalse(app.buttons["3반"].exists)
        capture("native-department-required", app: app)
        tap(app.buttons["학과 선택으로 바꾸기"], in: app)
        tap(app.buttons["콘텐츠과"], in: app)
        tap(app.buttons["class-step-next"], in: app)
        tap(app.buttons["3반"], in: app)
        tap(app.buttons["이전 선택"], in: app)
        XCTAssertEqual(app.buttons["콘텐츠과"].value as? String, "선택됨")
        tap(app.buttons["클라우드보안과"], in: app)
        tap(app.buttons["class-step-next"], in: app)
        XCTAssertFalse(app.buttons["class-next"].isEnabled)
        tap(app.buttons["3반"], in: app)
        tap(app.buttons["class-next"], in: app)
        tap(app.buttons["skip-siri-setup"], in: app)
        XCTAssertTrue(app.staticTexts["클라우드보안과 · 2학년 3반"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["콘텐츠과 · 2학년 3반"].exists)
    }

    func testCustomNamesRequireSavingGuidanceAndPersistIndependently() {
        let app = launch()
        chooseClass(app)
        tap(app.buttons["guide-next"], in: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(callName("timetable", in: app).value as? String, "오늘의 학교 시간표 알려줘")
        XCTAssertFalse(app.buttons["use-existing-shortcut"].exists)
        replaceCallName("", in: app)
        XCTAssertFalse(app.buttons["guide-next"].isEnabled)
        XCTAssertFalse(app.buttons["use-existing-shortcut"].isEnabled)
        replaceCallName("학교 시간표", in: app)
        capture("native-custom-timetable-name", app: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(app.staticTexts["siri-guide-title"].label, "내 단축어 만들기")
        capture("native-custom-create", app: app)
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        tap(app.buttons["start-onboarding"], in: app)
        tap(app.buttons["guide-next"], in: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(callName("timetable", in: app).value as? String, "학교 시간표")
        tap(app.buttons["guide-next"], in: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(app.staticTexts["siri-guide-title"].label, "이름 메뉴 열기")
        capture("native-custom-editor", app: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(app.staticTexts["siri-guide-title"].label, "이름 바꾸기")
        capture("native-custom-name-menu", app: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(app.staticTexts["chosen-shortcut-name"].label, "학교 시간표")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(app.staticTexts["siri-guide-title"].label, "이름을 저장해요")
        XCTAssertEqual(app.buttons["guide-next"].label, "이 이름으로 저장했어요")
        tap(app.buttons["copy-shortcut-name"], in: app)
        XCTAssertEqual(app.buttons["copy-shortcut-name"].label, "복사했어요")
        capture("native-custom-rename", app: app)
        XCTAssertFalse(app.descendants(matching: .any)["run-personal-shortcut"].exists)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(app.staticTexts["siri-call-phrase"].label, "학교 시간표")
        XCTAssertTrue(app.descendants(matching: .any)["run-personal-shortcut"].waitForExistence(timeout: 5))
        capture("native-custom-phrase", app: app)
        tap(app.buttons["guide-next"], in: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(callName("meal", in: app).value as? String, "오늘의 학교 급식 알려줘")
        replaceCallName("학교 시간표", kind: "meal", in: app)
        XCTAssertFalse(app.buttons["guide-next"].isEnabled)
        XCTAssertFalse(app.buttons["use-existing-shortcut"].isEnabled)
        XCTAssertEqual(app.staticTexts["shortcut-name-error"].label, "시간표와 급식은 다른 이름으로 정해요.")
        replaceCallName("점심 뭐야", kind: "meal", in: app)
        tap(app.buttons["guide-next"], in: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertTrue(app.staticTexts["시간표 사진이에요. 급식도 같은 방법이에요."].exists)
        tap(app.buttons["guide-next"], in: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(app.staticTexts["chosen-shortcut-name"].label, "점심 뭐야")
        capture("native-custom-meal-rename", app: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(app.staticTexts["siri-call-phrase"].label, "점심 뭐야")
        tap(app.buttons["guide-next"], in: app)
        tap(app.buttons["finish-onboarding"], in: app)
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
        tap(app.buttons["siri-help"], in: app)
        tap(app.buttons["guide-next"], in: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(callName("timetable", in: app).value as? String, "학교 시간표")
        tap(app.buttons["use-existing-shortcut"], in: app)
        XCTAssertEqual(app.staticTexts["siri-call-phrase"].label, "학교 시간표")
        XCTAssertTrue(app.buttons["run-personal-shortcut"].waitForExistence(timeout: 5))
        capture("native-reuse-shortcut", app: app)
        tap(app.buttons["이전 단계"], in: app)
        XCTAssertEqual(callName("timetable", in: app).value as? String, "학교 시간표")
    }

    func testLargeTextSetupKeepsChoicesAndNameActionsReachable() {
        let app = launch(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        chooseClass(app)
        tap(app.buttons["guide-next"], in: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertGreaterThan(app.staticTexts["siri-guide-title"].frame.height, 90)
        capture("native-large-text-name", app: app)
        replaceCallName("학교 시간표", in: app)
        tap(app.buttons["guide-next"], in: app)
        capture("native-large-text-create", app: app)
        tap(app.buttons["guide-screenshot-ShortcutMenuGuide"], in: app)
        XCTAssertTrue(app.buttons["close-guide-screenshot"].waitForExistence(timeout: 5))
        capture("native-large-text-photo", app: app)
        let photoScroll = app.scrollViews.containing(.button, identifier: "zoom-guide-screenshot").firstMatch
        let photoSource = photoScroll.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "사진 정보 · iOS 27 Simulator")).firstMatch
        XCTAssertTrue(photoSource.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<4 where !photoSource.isHittable { photoScroll.swipeUp() }
        XCTAssertTrue(photoSource.isHittable)
        capture("native-large-text-photo-bottom", app: app)
        tap(app.buttons["close-guide-screenshot"], in: app)
        tap(app.buttons["guide-next"], in: app)
        capture("native-large-text-editor", app: app)
        tap(app.buttons["guide-next"], in: app)
        capture("native-large-text-menu", app: app)
        tap(app.buttons["guide-next"], in: app)
        XCTAssertEqual(app.staticTexts["chosen-shortcut-name"].label, "학교 시간표")
        capture("native-large-text-save", app: app)
        tap(app.buttons["skip-siri-setup"], in: app)
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
    }

    func testNativeSetupTimetableMealsSettingsAndRelaunch() {
        let app = launch()
        XCTAssertTrue(app.textFields["school-search"].waitForExistence(timeout: 10))
        capture("native-start", app: app)
        selectSchool(app, guide: true)
        XCTAssertTrue(app.staticTexts["수학"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["예제 데이터 · 실제 학교 자료가 아닙니다"].exists)
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertLessThan(labels.firstIndex(of: "수학")!, labels.firstIndex(of: "생명과학")!)
        XCTAssertTrue(app.staticTexts["missing-periods"].label.contains("2교시"))
        XCTAssertTrue(app.buttons["share-today"].exists)
        capture("native-timetable", app: app)
        app.tabBars.buttons["급식"].tap()
        XCTAssertTrue(app.staticTexts["계란국 (1)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["알레르기: 난류"].exists)
        capture("native-meals", app: app)
        app.buttons["meal-allergens"].tap()
        XCTAssertTrue(app.staticTexts["1. 난류"].waitForExistence(timeout: 5))
        capture("native-meal-allergens", app: app)
        let pineNut = app.staticTexts["19. 잣"]
        for _ in 0..<4 where !pineNut.isHittable { app.swipeUp() }
        XCTAssertTrue(pineNut.isHittable)
        capture("native-meal-allergens-scrolled", app: app)
        app.buttons["닫기"].tap()
        let nutrition = app.buttons["영양 정보"]
        for _ in 0..<4 where !nutrition.isHittable { app.swipeUp() }
        XCTAssertTrue(nutrition.isHittable)
        nutrition.tap()
        XCTAssertTrue(app.staticTexts["단백질: 25g"].exists)
        let origin = app.buttons["원산지 정보"]
        for _ in 0..<3 where !origin.isHittable { app.swipeUp() }
        origin.tap()
        XCTAssertTrue(app.staticTexts["쌀: 국내산"].exists)
        XCTAssertTrue(app.buttons["share-today"].exists)
        capture("native-meal-details", app: app)
        app.tabBars.buttons["설정"].tap()
        XCTAssertTrue(app.buttons["open-school-shortcuts"].isHittable)
        XCTAssertTrue(app.buttons["Siri 사용법"].exists)
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
        XCTAssertFalse(app.staticTexts["테스트고등학교"].exists)
        XCTAssertFalse(app.staticTexts["콘텐츠과 · 2학년 3반"].exists)
        app.buttons["start-onboarding"].tap()
        selectSchool(app)
    }

    func testInterruptedSetupBackSkipAndHomeHelp() {
        let app = launch()
        chooseClass(app)
        app.buttons["guide-next"].tap()
        app.buttons["이전 단계"].tap()
        XCTAssertEqual(app.staticTexts["siri-guide-title"].label, "Siri 켜기")
        app.terminate()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["start-onboarding"].waitForExistence(timeout: 10))
        app.buttons["start-onboarding"].tap()
        XCTAssertTrue(app.buttons["skip-siri-setup"].waitForExistence(timeout: 10))
        app.buttons["skip-siri-setup"].tap()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["siri-guide-title"].exists)
        capture("native-siri-deferred-home", app: app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["홈"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["start-onboarding"].exists)
        app.buttons["siri-help"].tap()
        XCTAssertTrue(app.staticTexts["siri-guide-title"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["siri-guide-title"].label, "Siri 켜기")
        XCTAssertFalse(app.buttons["skip-siri-setup"].exists)
        XCTAssertFalse(app.buttons["사진 정보"].exists)
        let guideScroll = app.scrollViews.containing(.staticText, identifier: "siri-guide-title").firstMatch
        let source = guideScroll.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "사진 정보 · Apple 지원")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        let help = app.buttons["siri-step-help"]
        XCTAssertGreaterThan(source.frame.minY, help.frame.maxY)
        capture("native-photo-info-bottom", app: app)
        for _ in 0..<4 {
            if help.isHittable && help.frame.maxY < app.buttons["guide-next"].frame.minY { break }
            guideScroll.swipeUp()
        }
        help.tap()
        XCTAssertTrue(app.staticTexts["설정에서 Siri를 검색해요."].waitForExistence(timeout: 5))
        capture("native-siri-settings-help", app: app)
        app.navigationBars["Siri 켜기"].buttons["닫기"].tap()
        XCTAssertEqual(app.staticTexts["siri-guide-title"].label, "Siri 켜기")
        app.navigationBars["Siri 설정"].buttons["닫기"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "급식 보기")).firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["급식"].isSelected)
        XCTAssertTrue(app.staticTexts["계란국 (1)"].waitForExistence(timeout: 10))
        app.tabBars.buttons["홈"].tap()
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
        XCTAssertEqual(app.staticTexts["shortcut-check-phrase"].label, "오늘의 학교 시간표 알려줘")
        capture("native-shortcut-check-timetable", app: app)
        app.buttons["check-meal"].tap()
        let meal = NSPredicate(format: "label == %@", "실제 학교 자료가 아닌 예제 데이터입니다. 오늘 급식은 쌀밥, 계란국입니다.")
        expectation(for: meal, evaluatedWith: result)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.staticTexts["shortcut-check-phrase"].label, "오늘의 학교 급식 알려줘")
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

    func testReadingFailurePreservesTimetableAndOffersAnotherAttempt() {
        let app = launch(extra: ["--fail-first-voice"])
        selectSchool(app)
        let read = app.buttons["read-today"]
        for _ in 0..<4 where !read.isHittable { app.swipeUp() }
        XCTAssertTrue(read.isHittable)
        read.tap()
        let error = app.staticTexts["read-today-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertTrue(error.label.contains("잠시 뒤 다시 실행"))
        XCTAssertTrue(read.label.contains("소리내어 읽기"))
        XCTAssertTrue(app.staticTexts["수학"].exists)
        XCTAssertTrue(app.buttons["share-today"].exists)
        capture("native-read-error", app: app)
    }

    func testWrongDayDataDoesNotExposeLessonsMealsOrSharing() {
        let app = launch(extra: ["--wrong-day"])
        selectSchool(app)
        XCTAssertTrue(app.staticTexts["오늘 날짜의 시간표가 아닙니다. 잠시 뒤 새로고침해 주세요."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["수학"].exists)
        XCTAssertFalse(app.buttons["share-today"].exists)
        capture("native-wrong-day-timetable", app: app)
        app.tabBars.buttons["급식"].tap()
        XCTAssertTrue(app.staticTexts["오늘 날짜의 급식이 아닙니다. 잠시 뒤 새로고침해 주세요."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["계란국 (1)"].exists)
        XCTAssertFalse(app.buttons["read-today"].exists)
        capture("native-wrong-day-meals", app: app)
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
