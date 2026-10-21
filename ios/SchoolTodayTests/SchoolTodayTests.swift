import XCTest
@testable import SchoolToday

final class SchoolTodayTests: XCTestCase {
    private var settings: SchoolSettings {
        SchoolSettings(
            school: School(officeCode: "B10", schoolCode: "7010911", name: "테스트고등학교", kind: "고등학교", address: "서울", region: "서울"),
            schoolClass: SchoolClass(grade: 2, className: "3+과정", department: "콘텐츠 & 보안과")
        )
    }

    func testV1ArchiveMigrationPreservesIdentityAndCompletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = #"{"version":1,"rules":[{"id":"11111111-1111-1111-1111-111111111111","selection":"class-a","subject":"미술","items":["붓"],"enabled":true}],"tasks":[{"id":"22222222-2222-2222-2222-222222222222","selection":"class-a","title":"동의서","date":"2026-10-19","subject":"","kind":"item"}],"completed":["rule:11111111-1111-1111-1111-111111111111:2026-10-19:붓","task:22222222-2222-2222-2222-222222222222"],"corrections":[]}"#
        let url = directory.appendingPathComponent("preparation-v1.json")
        try Data(fixture.utf8).write(to: url)
        let archive = PlannerArchive(directory: directory)
        let migrated = try archive.load()
        XCTAssertEqual(migrated.version, 3)
        XCTAssertEqual(migrated.rules.map(\.id.uuidString), ["11111111-1111-1111-1111-111111111111"])
        XCTAssertEqual(migrated.tasks.map(\.id.uuidString), ["22222222-2222-2222-2222-222222222222"])
        XCTAssertTrue(migrated.stages.isEmpty)
        XCTAssertTrue(migrated.preferences.isEmpty)
        let items = migrated.occurrences(on: "2026-10-19", selection: "class-a", lessons: [Timetable.Lesson(period: 1, subject: "미술", ambiguous: false)])
        XCTAssertEqual(items.map(\.title), ["붓", "동의서"])
        XCTAssertEqual(items.map(\.completed), [true, true])
        XCTAssertEqual(try Data(contentsOf: url), Data(fixture.utf8), "Reading must not rewrite the v1 source")
        try archive.save(migrated)
        XCTAssertEqual(try archive.load(), migrated)
    }

    @MainActor
    func testAssessmentsRemainFreePersistAndPreserveLegacyDeadlines() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("preparation-v1.json")
        let legacy = Data(#"{"version":2,"rules":[],"tasks":[{"id":"22222222-2222-2222-2222-222222222222","selection":"old-class","title":"기존 마감","date":"2026-10-20","subject":"영어","kind":"deadline"}],"completed":["task:22222222-2222-2222-2222-222222222222"],"corrections":[],"stages":[],"preferences":[]}"#.utf8)
        try legacy.write(to: url)
        let api = try SchoolAPI(server: "https://fixture.invalid", session: PreviewTransport.session)
        let store = PlannerStore(settings: settings, api: api, mode: "mock", directory: directory)
        XCTAssertFalse(store.plusEnabled)
        let old = try XCTUnwrap(store.plan.tasks.first)
        XCTAssertNil(old.category)
        XCTAssertNil(old.notes)
        XCTAssertEqual(old.kindLabel, "마감")
        XCTAssertEqual(try Data(contentsOf: url), legacy, "Reading must not rewrite old archives")
        for category in PreparationTask.Category.allCases {
            let task = PreparationTask(selection: settings.planningKey, title: category.label, date: "2026-10-22", subject: "과학", kind: .deadline, category: category, notes: "2장 · 파일 제출")
            try store.addTask(task)
        }
        let saved = try PlannerArchive(directory: directory).load()
        XCTAssertEqual(saved.version, 3)
        XCTAssertEqual(saved.tasks.first, old)
        XCTAssertTrue(saved.completed.contains(old.completionID))
        XCTAssertEqual(saved.tasks.compactMap(\.category), [.assessment, .exam, .homework])
        XCTAssertEqual(saved.tasks.dropFirst().map(\.notes), Array(repeating: "2장 · 파일 제출", count: 3))
        var edited = try XCTUnwrap(store.tasks.first)
        store.toggle(try XCTUnwrap(store.occurrences(on: edited.date).first { $0.id == edited.completionID }))
        edited.date = "2026-10-23"
        edited.notes = String(repeating: "가", count: 2000)
        try store.addTask(edited)
        let bytes = try Data(contentsOf: url)
        var invalid = edited
        invalid.notes = String(repeating: "가", count: 2001)
        XCTAssertThrowsError(try store.addTask(invalid))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let reopened = PlannerStore(settings: settings, api: api, mode: "mock", directory: directory)
        XCTAssertEqual(reopened.tasks.first { $0.id == edited.id }, edited)
        XCTAssertTrue(reopened.plan.completed.contains(edited.completionID))
        reopened.toggle(try XCTUnwrap(reopened.occurrences(on: edited.date).first { $0.id == edited.completionID }))
        XCTAssertFalse(reopened.plan.completed.contains(edited.completionID))
        let restored = try JSONDecoder().decode(PreparationPlan.self, from: JSONEncoder().encode(reopened.plan))
        XCTAssertEqual(restored, reopened.plan, "Backup/sync payloads must retain new metadata")
        try reopened.deleteTask(edited)
        XCTAssertFalse(try PlannerArchive(directory: directory).load().tasks.contains { $0.id == edited.id })
        XCTAssertEqual(reopened.plan.tasks.first { $0.id == old.id }, old)
    }

    func testUpcomingAgendaUsesSeoulMidnightAndRetainsOverdueAndCompletedRecords() throws {
        let before = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-21T14:59:59Z"))
        let dates = ["2026-10-29", "2026-10-20", "2026-10-28", "2026-10-21", "2026-10-22"]
        let tasks = dates.map { PreparationTask(selection: "a", title: $0, date: $0, kind: .deadline, category: .assessment) }
        let finished = PreparationTask(selection: "a", title: "완료한 숙제", date: "2026-10-19", kind: .deadline, category: .homework)
        let foreign = PreparationTask(selection: "b", title: "다른 반 비공개", date: "2026-10-18")
        let plan = PreparationPlan(tasks: tasks + [finished, foreign], completed: [finished.completionID])
        let agenda = plan.scheduledTasks(selection: "a")
        XCTAssertEqual(agenda.map(\.date), ["2026-10-20", "2026-10-21", "2026-10-22", "2026-10-28", "2026-10-29"])
        XCTAssertEqual(agenda.map { $0.scheduleGroup(relativeTo: before) }, [.overdue, .today, .week, .week, .later])
        XCTAssertEqual(agenda.map { $0.relativeDate(to: before) }, ["1일 지남", "오늘", "내일", "7일 남음", "8일 남음"])
        let after = before.addingTimeInterval(1)
        XCTAssertEqual(agenda.map { $0.scheduleGroup(relativeTo: after) }, [.overdue, .overdue, .today, .week, .week])
        XCTAssertEqual(agenda.map { $0.relativeDate(to: after) }, ["2일 지남", "1일 지남", "오늘", "6일 남음", "7일 남음"])
        XCTAssertEqual(plan.scheduledTasks(selection: "a", completed: true), [finished])
        XCTAssertEqual(plan.scheduledTasks(selection: "b"), [foreign])
    }

    func testNoticesRespectExpiryDeduplicationAndStageCompletion() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-18T00:00:00Z"))
        let before = now.addingTimeInterval(60)
        let expiry = now.addingTimeInterval(120)
        let after = now.addingTimeInterval(180)
        let task = PreparationTask(selection: "a", title: "보고서", date: "2026-10-19", kind: .deadline, reminder: after, extraReminders: [now, before, before, expiry, after])
        let stage = PreparationStage(taskID: task.id, title: "초안", date: "2026-10-18", reminder: before)
        let boundaryStage = PreparationStage(taskID: task.id, title: "제출", date: "2026-10-19", reminder: expiry)
        let foreign = PreparationTask(selection: "b", title: "비공개 다른 반", date: "2026-10-19", reminder: before)
        var plan = PreparationPlan(tasks: [task, foreign], stages: [stage, boundaryStage])
        let basic = plan.notices(selection: "a", cache: nil, plus: false, after: now, plusUntil: expiry)
        XCTAssertEqual(basic.map(\.body), ["보고서"])
        XCTAssertEqual(basic.map(\.fireDate), [after], "The basic reminder survives premium expiry")
        let premium = plan.notices(selection: "a", cache: nil, plus: true, after: now, plusUntil: expiry)
        XCTAssertEqual(premium.map(\.fireDate), [before, before, after])
        XCTAssertEqual(Set(premium.map(\.body)), ["보고서", "보고서 · 초안"])
        XCTAssertEqual(Set(premium.map(\.id)).count, 3)
        XCTAssertEqual(plan.notices(selection: "a", cache: nil, plus: true, after: now).map(\.fireDate), [before, before, expiry, expiry, after])
        let occurrence = try XCTUnwrap(plan.occurrences(on: "2026-10-18", selection: "a", lessons: nil, includeStages: true).first)
        plan.toggle(occurrence)
        XCTAssertEqual(plan.notices(selection: "a", cache: nil, plus: true, after: now, plusUntil: expiry).map(\.body), ["보고서", "보고서"])
        XCTAssertTrue(plan.occurrences(on: "2026-10-18", selection: "a", lessons: nil, includeStages: true)[0].completed)
        let parent = try XCTUnwrap(plan.occurrences(on: "2026-10-19", selection: "a", lessons: nil).first)
        plan.toggle(parent)
        XCTAssertTrue(plan.notices(selection: "a", cache: nil, plus: true, after: now).isEmpty)
        XCTAssertEqual(plan.occurrences(on: "2026-10-19", selection: "a", lessons: nil, includeStages: true).map(\.title), ["보고서"])
    }

    @MainActor
    func testDowngradeRetainsRecordsAndPersistsChosenFreeRule() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = try SchoolAPI(server: "https://fixture.invalid", session: PreviewTransport.session)
        let store = PlannerStore(settings: settings, api: api, mode: "mock", directory: directory)
        store.updateAccess(true)
        try store.addRule(subject: "미술", items: ["붓"])
        try store.addRule(subject: "체육", items: ["운동화"])
        let day = "2026-10-19"
        try store.correct(LessonCorrection(selection: settings.planningKey, date: day, period: 1, subject: "미술", room: "101"))
        try store.correct(LessonCorrection(selection: settings.planningKey, date: day, period: 2, subject: "체육", room: "운동장"))
        let task = PreparationTask(selection: settings.planningKey, title: "개인 보고서", date: day, kind: .deadline)
        try store.addTask(task, stages: [PreparationStage(taskID: task.id, title: "개인 초안", date: day)])
        let art = try XCTUnwrap(store.occurrences(on: day).first { $0.title == "붓" })
        store.toggle(art)
        let original = store.plan
        store.updateAccess(false)
        XCTAssertEqual(store.plan, original)
        XCTAssertEqual(store.occurrences(on: day).map(\.title), ["붓", "개인 보고서"])
        XCTAssertTrue(store.occurrences(on: day)[0].completed)
        var renamed = task
        renamed.title = "수정한 개인 보고서"
        renamed.category = .assessment
        renamed.notes = "기본 내용 수정은 만료 후에도 무료"
        try store.addTask(renamed, stages: original.stages)
        XCTAssertEqual(store.tasks.first?.title, "수정한 개인 보고서", "Expiration must not prevent basic editing of retained records")
        XCTAssertEqual(try PlannerArchive(directory: directory).load().tasks, [renamed])
        try store.addTask(task, stages: original.stages)
        XCTAssertThrowsError(try store.addRule(subject: "음악", items: ["악보"]))
        try store.useFreeRule(try XCTUnwrap(store.rules.first { $0.subject == "체육" }))
        XCTAssertEqual(store.occurrences(on: day).map(\.title), ["운동화", "개인 보고서"])
        let reopened = PlannerStore(settings: settings, api: api, mode: "mock", directory: directory)
        XCTAssertEqual(reopened.occurrences(on: day).map(\.title), ["운동화", "개인 보고서"])
        XCTAssertEqual(reopened.plan.tasks, original.tasks)
        XCTAssertEqual(reopened.plan.stages, original.stages)
        XCTAssertEqual(reopened.plan.completed, original.completed)
        reopened.updateAccess(true)
        XCTAssertEqual(reopened.occurrences(on: day).map(\.title), ["운동화", "붓", "개인 보고서", "개인 초안"])
        XCTAssertEqual(reopened.occurrences(on: day).map(\.completed), [false, true, false, false])
        let link = try XCTUnwrap(SchoolSelectionLink.url(settings))
        XCTAssertEqual(try SchoolSelectionLink.read(link), settings)
        let query = try XCTUnwrap(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.map(\.name), ["school"])
        let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(query.first?.value)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["school", "schoolClass"])
        XCTAssertFalse(String(decoding: payload, as: UTF8.self).contains("개인"))
        XCTAssertEqual(store.plan.tasks.count, 1, "Sharing must not remove local private records")
    }

    @MainActor
    func testExpiredPlusAllowsPartialRemovalButNotNewPremiumConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = try SchoolAPI(server: "https://fixture.invalid", session: PreviewTransport.session)
        let store = PlannerStore(settings: settings, api: api, mode: "mock", directory: directory)
        let firstReminder = Date().addingTimeInterval(3600)
        let task = PreparationTask(selection: settings.planningKey, title: "과학 숙제", date: "2026-11-20", kind: .deadline,
                                   extraReminders: [firstReminder, firstReminder.addingTimeInterval(3600)], category: .homework)
        let retained = PreparationStage(taskID: task.id, title: "초안", date: "2026-11-17")
        let removed = PreparationStage(taskID: task.id, title: "제출 확인", date: "2026-11-19")
        store.updateAccess(true)
        try store.addTask(task, stages: [retained, removed])
        store.updateAccess(false)

        var earlier = task
        earlier.date = "2026-11-18"
        earlier.extraReminders = [firstReminder]
        try store.addTask(earlier, stages: [retained])
        let saved = try PlannerArchive(directory: directory).load()
        XCTAssertEqual(saved.tasks, [earlier])
        XCTAssertEqual(saved.stages, [retained], "Removing one invalidated stage must not require deleting every stage")

        var added = earlier
        added.extraReminders?.append(firstReminder.addingTimeInterval(7200))
        XCTAssertThrowsError(try store.addTask(added, stages: [retained])) { XCTAssertTrue($0 is PlannerAccessError) }
        var changed = retained
        changed.date = "2026-11-16"
        XCTAssertThrowsError(try store.addTask(earlier, stages: [changed])) { XCTAssertTrue($0 is PlannerAccessError) }
        XCTAssertThrowsError(try store.addTask(earlier, stages: [retained, removed])) { XCTAssertTrue($0 is PlannerAccessError) }
        XCTAssertEqual(try PlannerArchive(directory: directory).load(), saved, "Rejected additions/edits must preserve saved records")
    }

    @MainActor
    func testReplacePlanRejectsStaleAndInvalidInputAndBacksUpBeforeRestore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = try SchoolAPI(server: "https://fixture.invalid", session: PreviewTransport.session)
        let store = PlannerStore(settings: settings, api: api, mode: "mock", directory: directory)
        let stale = store.plan
        try store.addTask(PreparationTask(selection: settings.planningKey, title: "원본", date: "2026-10-19"))
        let current = store.plan
        let source = directory.appendingPathComponent("preparation-v1.json")
        let bytes = try Data(contentsOf: source)
        let replacement = PreparationPlan(tasks: [PreparationTask(selection: settings.planningKey, title: "복원본", date: "2026-10-20")])
        XCTAssertThrowsError(try store.replacePlan(replacement, expected: stale))
        var invalid = replacement
        invalid.tasks[0].date = "2026-02-30"
        XCTAssertThrowsError(try store.replacePlan(invalid, expected: current))
        XCTAssertEqual(store.plan, current)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.hasPrefix("before-restore-") })
        try store.replacePlan(replacement, expected: current)
        XCTAssertEqual(store.plan, replacement)
        XCTAssertEqual(try PlannerArchive(directory: directory).load(), replacement)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("before-restore-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), bytes)
    }

    func testBellTimesRespectKoreanLessonBoundariesAndRejectOverlaps() throws {
        let first = SchoolBellTime(period: 1, startMinute: 9 * 60, endMinute: 9 * 60 + 45)
        let second = SchoolBellTime(period: 3, startMinute: 10 * 60 + 5, endMinute: 10 * 60 + 55)
        let preference = PreparationPreference(selection: "a", bellTimes: [second, first])
        let plan = PreparationPlan(preferences: [preference])
        try plan.validate()
        let timetable = Timetable(date: "2026-10-19", lessons: [.init(period: 1, subject: "수학", ambiguous: false), .init(period: 3, subject: "실습", ambiguous: false)])
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-19T00:00:00Z"))
        XCTAssertEqual(plan.lessonStatus(selection: "a", timetable: timetable, now: start.addingTimeInterval(-1)), "다음 1교시 수학 · 09:00 시작")
        XCTAssertEqual(plan.lessonStatus(selection: "a", timetable: timetable, now: start), "지금 1교시 수학 · 다음 3교시 실습")
        XCTAssertEqual(plan.lessonStatus(selection: "a", timetable: timetable, now: start.addingTimeInterval(45 * 60)), "다음 3교시 실습 · 10:05 시작")
        XCTAssertNil(plan.lessonStatus(selection: "a", timetable: timetable, now: start.addingTimeInterval(115 * 60)))
        XCTAssertNil(plan.lessonStatus(selection: "other", timetable: timetable, now: start))
        XCTAssertNil(plan.lessonStatus(selection: "a", timetable: timetable, now: start.addingTimeInterval(86400)))
        XCTAssertFalse(PreparationPlan.validBellTimes([first, .init(period: 2, startMinute: 584, endMinute: 620)]))
        XCTAssertFalse(PreparationPlan.validBellTimes([first, .init(period: 1, startMinute: 620, endMinute: 670)]))
        XCTAssertFalse(PreparationPlan.validBellTimes([.init(period: 1, startMinute: 600, endMinute: 600)]))
    }

    func testSummaryIncludesDeadlineStagesOnKnownNonSchoolDaysAndHonorsPause() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-18T00:00:00Z"))
        let task = PreparationTask(selection: settings.planningKey, title: "보고서", date: "2026-10-19", kind: .deadline)
        let stage = PreparationStage(taskID: task.id, title: "초안 확인", date: "2026-10-18")
        var plan = PreparationPlan(tasks: [task], stages: [stage], preferences: [.init(selection: settings.planningKey, morningMinute: 10 * 60)])
        let cache = SchoolWeekCache(selection: settings, origin: "https://fixture.invalid", timetables: [.init(date: "2026-10-18", lessons: [])])
        let notices = plan.notices(selection: settings.planningKey, cache: cache, plus: true, after: now, plusUntil: now.addingTimeInterval(7200))
        XCTAssertEqual(notices.map(\.body), ["초안 확인"])
        XCTAssertEqual(notices.map(\.preparationDate), ["2026-10-18"])
        plan.preferences[0].pausedUntil = "2026-10-18"
        XCTAssertTrue(plan.notices(selection: settings.planningKey, cache: cache, plus: true, after: now, plusUntil: now.addingTimeInterval(7200)).isEmpty)
    }

    func testCalendarRangesUseKoreanDaysAndMondayWeeks() throws {
        let beforeMidnight = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-02-29T14:59:59Z"))
        XCTAssertEqual(SchoolCalendar.key(beforeMidnight), "2024-02-29")
        XCTAssertEqual(SchoolCalendar.key(beforeMidnight.addingTimeInterval(1)), "2024-03-01")
        XCTAssertEqual(SchoolCalendar.week(containing: "2024-03-03"), ["2024-02-26", "2024-02-27", "2024-02-28", "2024-02-29", "2024-03-01", "2024-03-02", "2024-03-03"])
        XCTAssertEqual(SchoolCalendar.range(from: "2024-12-31", to: "2025-01-01"), ["2024-12-31", "2025-01-01"])
        XCTAssertEqual(SchoolCalendar.range(from: "2024-02-29", to: "2024-03-06")?.count, 7)
        for invalid in ["2023-02-29", "2024-04-31", "2024-00-10", "2024-1-1", "2024-13-01", "not-a-date"] { XCTAssertNil(SchoolCalendar.date(invalid), invalid) }
        XCTAssertNil(SchoolCalendar.range(from: "2024-02-29", to: "2024-03-07"))
        XCTAssertNil(SchoolCalendar.range(from: "2024-03-01", to: "2024-02-29"))
    }

    func testAutomaticPreparationRecomputesWithoutDuplicatingOrCompletingOtherDates() throws {
        let selection = settings.planningKey
        let rule = PreparationRule(selection: selection, subject: "체육", items: ["체육복", " 물통 ", "체육복"])
        let other = PreparationRule(selection: selection, subject: "실습", items: ["노트북"])
        var plan = PreparationPlan(rules: [rule, other], tasks: [PreparationTask(selection: selection, title: "동의서", date: "2024-03-05")])
        let lessons = [Timetable.Lesson(period: 2, subject: "체육", ambiguous: nil), Timetable.Lesson(period: 6, subject: "체육", ambiguous: nil), Timetable.Lesson(period: 7, subject: "실습", ambiguous: nil)]
        let first = plan.occurrences(on: "2024-03-05", selection: selection, lessons: lessons)
        XCTAssertEqual(first.map(\.title), ["체육복", "물통", "동의서"])
        plan.toggle(first[0])
        XCTAssertTrue(plan.occurrences(on: "2024-03-05", selection: selection, lessons: lessons)[0].completed)
        XCTAssertFalse(plan.occurrences(on: "2024-03-12", selection: selection, lessons: lessons)[0].completed)
        XCTAssertEqual(plan.occurrences(on: "2024-03-05", selection: selection, lessons: []).map(\.title), ["동의서"])
        XCTAssertEqual(plan.occurrences(on: "2024-03-05", selection: selection, lessons: nil).map(\.title), ["동의서"])
        XCTAssertEqual(plan.occurrences(on: "2024-03-05", selection: "other class", lessons: lessons), [])
        XCTAssertEqual(plan.occurrences(on: "2024-03-05", selection: selection, lessons: [Timetable.Lesson(period: 1, subject: "체육", ambiguous: true)]).map(\.title), ["동의서"])
        XCTAssertEqual(plan.occurrences(on: "2024-03-05", selection: selection, lessons: lessons, automaticLimit: 2).map(\.title), ["체육복", "물통", "노트북", "동의서"])
        XCTAssertEqual(plan.rules.count, 2, "Losing extra automation must not erase records")
    }

    @MainActor
    func testPlannerPersistsRulesAndDatedCompletionAndKeepsFailedRefreshSeparate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = try SchoolAPI(server: "https://fixture.invalid", session: PreviewTransport.session)
        let planner = PlannerStore(settings: settings, api: api, mode: "mock", directory: directory)
        await planner.refresh(containing: "2024-03-05")
        XCTAssertNil(planner.timetableError)
        XCTAssertEqual(planner.timetable(on: "2024-03-05")?.date, "2024-03-05")
        XCTAssertEqual(planner.meals(on: "2024-03-05")?.meals.first?.dishes, ["쌀밥", "계란국 (1)"])
        try planner.addRule(subject: "수학", items: ["교재", "교재"])
        XCTAssertThrowsError(try planner.addRule(subject: "체육", items: ["체육복"]))
        try planner.addTask(PreparationTask(selection: settings.planningKey, title: "동의서", date: "2024-03-05"))
        XCTAssertEqual(planner.occurrences(on: "2024-03-05").map(\.title), ["교재", "동의서"])
        planner.toggle(planner.occurrences(on: "2024-03-05")[0])
        let restored = PlannerStore(settings: settings, api: api, mode: "mock", directory: directory)
        XCTAssertTrue(restored.occurrences(on: "2024-03-05")[0].completed)
        XCTAssertFalse(restored.occurrences(on: "2024-03-06")[0].completed)
        try restored.addRule(subject: "수학", items: ["교재", "연필"])
        XCTAssertEqual(restored.rules.count, 1)
        XCTAssertEqual(restored.occurrences(on: "2024-03-05").map(\.title), ["교재", "연필", "동의서"])
        let otherSettings = SchoolSettings(school: settings.school, schoolClass: SchoolClass(grade: 2, className: "9", department: nil))
        let otherClass = PlannerStore(settings: otherSettings, api: api, mode: "mock", directory: directory)
        XCTAssertTrue(otherClass.tasks.isEmpty)
        XCTAssertNil(otherClass.timetable(on: "2024-03-05"))
        let wrongOrigin = PlannerStore(settings: settings, api: try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session), mode: "mock", directory: directory)
        XCTAssertNil(wrongOrigin.timetable(on: "2024-03-05"))
        var failTimetable = false
        ControlledTransport.onStart = { transport in
            let dates = ["2024-03-04", "2024-03-05", "2024-03-06", "2024-03-07", "2024-03-08", "2024-03-09", "2024-03-10"]
            if transport.request.url?.path == "/api/timetable/range", failTimetable {
                transport.respond(body: Data(#"{"error":{"message":"학교 서비스 점검 중"}}"#.utf8), contentType: "application/json", status: 503)
            } else if transport.request.url?.path == "/api/timetable/range" {
                let value = SchoolRange(from: "2024-03-04", to: "2024-03-10", days: dates.map { Timetable(date: $0, lessons: [Timetable.Lesson(period: 2, subject: "음악", ambiguous: nil)]) })
                transport.respond(body: try! JSONEncoder().encode(value), contentType: "application/json")
            } else {
                let value = SchoolRange(from: "2024-03-04", to: "2024-03-10", days: dates.map { Meals(date: $0, meals: []) })
                transport.respond(body: try! JSONEncoder().encode(value), contentType: "application/json")
            }
        }
        defer { ControlledTransport.onStart = nil }
        let failedAPI = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        let offline = PlannerStore(settings: settings, api: failedAPI, mode: "mock", directory: directory)
        await offline.refresh(containing: "2024-03-05")
        let oldChecked = offline.cache.timetableCheckedAt
        XCTAssertEqual(offline.timetable(on: "2024-03-05")?.lessons.first?.subject, "음악")
        failTimetable = true
        await offline.refresh(containing: "2024-03-05")
        XCTAssertEqual(offline.timetableError, "학교 서비스 점검 중")
        XCTAssertNil(offline.mealError)
        XCTAssertEqual(offline.cache.timetableCheckedAt, oldChecked)
        XCTAssertEqual(offline.timetable(on: "2024-03-05")?.lessons.first?.subject, "음악")
        XCTAssertNil(offline.timetable(on: "2024-03-11"))
        let correction = LessonCorrection(selection: settings.planningKey, date: "2024-03-05", period: 2, subject: "수학", room: "실습실 A")
        try offline.correct(correction)
        XCTAssertEqual(offline.timetable(on: "2024-03-05")?.lessons.first?.subject, "수학")
        XCTAssertEqual(offline.correction(on: "2024-03-05", period: 2)?.room, "실습실 A")
        XCTAssertEqual(offline.occurrences(on: "2024-03-05").map(\.title), ["교재", "연필", "동의서"])
        XCTAssertEqual(offline.timetable(on: "2024-03-06")?.lessons.first?.subject, "음악")
        try offline.removeCorrection(correction)
        XCTAssertEqual(offline.timetable(on: "2024-03-05")?.lessons.first?.subject, "음악")
        XCTAssertEqual(try PlannerArchive(directory: directory).load().rules.first?.items, ["교재", "연필"])
        try restored.deleteRule(restored.rules[0])
        XCTAssertEqual(restored.occurrences(on: "2024-03-05").map(\.title), ["동의서"])
    }

    @MainActor
    func testPlannerDisplaysReadyDataWhileTheOtherSchoolServiceIsPending() async throws {
        let dates = ["2024-03-04", "2024-03-05", "2024-03-06", "2024-03-07", "2024-03-08", "2024-03-09", "2024-03-10"]
        let timetable = try JSONEncoder().encode(SchoolRange(from: dates[0], to: dates[6], days: dates.map {
            Timetable(date: $0, lessons: [Timetable.Lesson(period: 1, subject: "수학", ambiguous: nil)])
        }))
        let meals = try JSONEncoder().encode(SchoolRange(from: dates[0], to: dates[6], days: dates.map {
            Meals(date: $0, meals: [Meals.Meal(code: "2", name: "중식", dishes: ["쌀밥"], calories: "", nutrition: nil, origin: nil)])
        }))
        for slowTimetable in [true, false] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
            let planner = PlannerStore(settings: settings, api: api, mode: "live", directory: directory)
            var slow: ControlledTransport?
            ControlledTransport.onStart = { transport in
                Task { @MainActor in
                    let isTimetable = transport.request.url?.path == "/api/timetable/range"
                    if isTimetable == slowTimetable { slow = transport }
                    else { transport.respond(body: isTimetable ? timetable : meals, contentType: "application/json") }
                }
            }
            defer { ControlledTransport.onStart = nil }
            let lookup = Task { await planner.refresh(containing: dates[1]) }
            for _ in 0..<100 {
                let ready = slowTimetable ? planner.meals(on: dates[1]) != nil : planner.timetable(on: dates[1]) != nil
                if ready && slow != nil { break }
                try await Task.sleep(nanoseconds: 30_000_000)
            }
            if slowTimetable {
                XCTAssertEqual(planner.meals(on: dates[1])?.meals.first?.dishes, ["쌀밥"])
                XCTAssertNil(planner.timetable(on: dates[1]))
            } else {
                XCTAssertEqual(planner.timetable(on: dates[1])?.lessons.first?.subject, "수학")
                XCTAssertNil(planner.meals(on: dates[1]))
            }
            XCTAssertTrue(planner.loading)
            if let slow { slow.fail(.timedOut) } else { lookup.cancel() }
            await lookup.value
            XCTAssertFalse(planner.loading)
            XCTAssertNotNil(slowTimetable ? planner.timetableError : planner.mealError)
            XCTAssertNil(slowTimetable ? planner.mealError : planner.timetableError)
        }
    }

    @MainActor
    func testUnreadablePreparationArchiveIsPreservedAndCannotBeOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("preparation-v1.json")
        let original = Data("unreadable but potentially recoverable".utf8)
        try original.write(to: url)
        let planner = PlannerStore(settings: settings, api: try SchoolAPI(server: "https://fixture.invalid"), mode: "mock", directory: directory)
        XCTAssertTrue(planner.storageBlocked)
        XCTAssertNotNil(planner.recordError)
        XCTAssertThrowsError(try planner.addTask(PreparationTask(selection: settings.planningKey, title: "체육복", date: "2024-03-05")))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testBasicRemindersExcludeCompletedPastAndOtherClassRecords() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-03-04T10:00:00Z"))
        let later = PreparationTask(selection: "my-class", title: "보고서", date: "2024-03-06", kind: .deadline, reminder: now.addingTimeInterval(7200))
        let earlier = PreparationTask(selection: "my-class", title: "동의서", date: "2024-03-05", reminder: now.addingTimeInterval(3600))
        let past = PreparationTask(selection: "my-class", title: "지난 알림", date: "2024-03-04", reminder: now)
        let other = PreparationTask(selection: "other-class", title: "다른 반", date: "2024-03-05", reminder: now.addingTimeInterval(1800))
        var plan = PreparationPlan(tasks: [later, past, other, earlier])
        XCTAssertEqual(plan.reminders(selection: "my-class", after: now).map(\.title), ["동의서", "보고서"])
        let occurrence = try XCTUnwrap(plan.occurrences(on: "2024-03-05", selection: "my-class", lessons: nil).first)
        plan.toggle(occurrence)
        XCTAssertEqual(plan.reminders(selection: "my-class", after: now).map(\.title), ["보고서"])
        XCTAssertEqual(plan.tasks.count, 4)
        XCTAssertEqual(try JSONDecoder().decode(PreparationPlan.self, from: JSONEncoder().encode(plan)), plan)
    }

    func testRangeAPIRejectsMissingReorderedDuplicateAndWrongDayResponses() async throws {
        let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        defer { ControlledTransport.onStart = nil }
        let days = ["2024-03-04", "2024-03-05"]
        for returned in [[], ["2024-03-04"], days.reversed().map { $0 }, ["2024-03-04", "2024-03-04"], ["2024-03-04", "2000-01-01"]] {
            ControlledTransport.onStart = { transport in
                if transport.request.url?.path == "/api/timetable/range" {
                    let result = SchoolRange(from: days[0], to: days[1], days: returned.map { Timetable(date: $0, lessons: []) })
                    transport.respond(body: try! JSONEncoder().encode(result), contentType: "application/json")
                } else {
                    let result = SchoolRange(from: days[0], to: days[1], days: returned.map { Meals(date: $0, meals: []) })
                    transport.respond(body: try! JSONEncoder().encode(result), contentType: "application/json")
                }
            }
            do { _ = try await api.timetables(settings: settings, from: days[0], to: days[1]); XCTFail("Incomplete/wrong range accepted") }
            catch { XCTAssertTrue(error.localizedDescription.contains("요청한 날짜")) }
            do { _ = try await api.meals(settings: settings, from: days[0], to: days[1]); XCTFail("Incomplete/wrong range accepted") }
            catch { XCTAssertTrue(error.localizedDescription.contains("요청한 날짜")) }
        }
    }

    func testHTTPSOriginValidation() throws {
        for invalid in ["http://example.com", "https://user:password@example.com", "https://example.com/api", "https://example.com?token=secret", "https://example.com#fragment", ""] {
            XCTAssertThrowsError(try SchoolAPI(server: invalid), invalid)
        }
        let api = try SchoolAPI(server: "https://example.com:8443/")
        XCTAssertEqual(api.baseURL.host, "example.com")
        XCTAssertEqual(api.baseURL.port, 8443)
        let canonical = try SchoolAPI(server: "https://example.com").baseURL
        for equivalent in ["https://example.com/", "https://EXAMPLE.COM", "https://example.com:443/"] {
            XCTAssertEqual(try SchoolAPI(server: equivalent).baseURL, canonical, equivalent)
        }
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

    func testPersonalShortcutURLsKeepNamesAsOneParameterWithoutClipboardInput() throws {
        for name in ["학교 시간표", "점심 & 급식 + 간식?#", "시간표&input=clipboard&name=다른단축어", "🔔 학교/시간표 % 점심"] {
            let url = SchoolShortcut.runURL(named: name)
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(parts.scheme, "shortcuts")
            XCTAssertEqual(parts.host, "run-shortcut")
            XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "name", value: name)])
            XCTAssertNil(parts.fragment)
            if name.contains("+") { XCTAssertTrue(url.absoluteString.contains("%2B")) }
        }
    }

    func testPreferencesPersistTheCompleteSelectionAndReset() throws {
        let suite = "SchoolTodayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(SchoolPreferences.shortcutName(for: .timetable, defaults: defaults), "오늘의 학교 시간표 알려줘")
        XCTAssertEqual(SchoolPreferences.shortcutName(for: .meal, defaults: defaults), "오늘의 학교 급식 알려줘")
        SchoolPreferences.writeShortcutName("학교 시간표", for: .timetable, defaults: defaults)
        SchoolPreferences.writeShortcutName("점심 뭐야", for: .meal, defaults: defaults)
        XCTAssertEqual(SchoolPreferences.shortcutName(for: .timetable, defaults: defaults), "학교 시간표")
        XCTAssertEqual(SchoolPreferences.shortcutName(for: .meal, defaults: defaults), "점심 뭐야")
        try SchoolPreferences.writeSchool(settings, defaults: defaults)
        XCTAssertEqual(SchoolPreferences.readSchool(defaults: defaults), settings)
        try SchoolPreferences.writeSchool(nil, defaults: defaults)
        XCTAssertNil(SchoolPreferences.readSchool(defaults: defaults))
        defaults.set(Data("not JSON".utf8), forKey: SchoolPreferences.schoolKey)
        XCTAssertNil(SchoolPreferences.readSchool(defaults: defaults))
    }

    func testSchoolTypePreservesLegacySelectionAndBackendDepartmentIdentity() throws {
        let legacy = Data(#"{"school":{"officeCode":"B10","schoolCode":"7010911","name":"테스트고등학교","kind":"고등학교","address":"서울","region":"서울"},"schoolClass":{"grade":2,"className":"7","department":"7차일반"}}"#.utf8)
        let previous = try JSONDecoder().decode(SchoolSettings.self, from: legacy)
        XCTAssertNil(previous.highSchoolType)
        XCTAssertEqual(previous.schoolClass.department, "7차일반")
        let general = SchoolSettings(school: previous.school, schoolClass: previous.schoolClass, highSchoolType: .general)
        XCTAssertEqual(general.classLabel, "2학년 7반")
        XCTAssertEqual(general.timetableQuery.first { $0.name == "department" }?.value, "7차일반")
        let decoded = try JSONDecoder().decode(SchoolSettings.self, from: JSONEncoder().encode(general))
        XCTAssertEqual(decoded, general)
        let vocational = SchoolSettings(school: settings.school, schoolClass: settings.schoolClass, highSchoolType: .vocational)
        XCTAssertEqual(vocational.classLabel, "콘텐츠 & 보안과 · 2학년 3+과정반")
    }

    @MainActor
    func testMissingOrUnreadableSchoolCannotSkipSetupAfterRelaunch() async throws {
        let suite = "SchoolTodayTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for data: Data? in [nil, Data("not JSON".utf8), Data("{}".utf8)] {
            if let data { defaults.set(data, forKey: SchoolPreferences.schoolKey) }
            else { defaults.removeObject(forKey: SchoolPreferences.schoolKey) }
            defaults.set(true, forKey: "schooltoday.onboarding.v2")
            SchoolPreferences.writeShortcutName("학교 시간표", for: .timetable, defaults: defaults)

            let store = SchoolStore(defaults: defaults)
            XCTAssertNil(store.school)
            XCTAssertFalse(store.onboardingComplete)
            try store.saveSchool(settings)
            let relaunched = SchoolStore(defaults: defaults)
            XCTAssertEqual(relaunched.school, settings)
            XCTAssertFalse(relaunched.onboardingComplete)
            XCTAssertEqual(SchoolPreferences.shortcutName(for: .timetable, defaults: defaults), "학교 시간표")
        }
        defaults.set(true, forKey: "schooltoday.onboarding.v2")
        let completed = SchoolStore(defaults: defaults)
        XCTAssertEqual(completed.school, settings)
        XCTAssertTrue(completed.onboardingComplete)
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
        XCTAssertEqual(meals.meals.first?.nutrition, "단백질: 25g")
        XCTAssertEqual(meals.meals.first?.origin, "쌀: 국내산")
        let speech = try await api.speech(settings: settings, meal: false)
        XCTAssertTrue(speech.hasPrefix("실제 학교 자료가 아닌 예제 데이터입니다. "))
        XCTAssertTrue(speech.contains("1교시 수학"))
    }

    func testMealAllergenAnnotationsAreDecodedWithoutGuessingFromDishNames() {
        XCTAssertEqual(MealAllergens.description(for: "계란국 (1)"), "난류")
        XCTAssertEqual(MealAllergens.description(for: "파스타 ( 6.2.6.18.19. )"), "우유 · 밀 · 조개류(굴·전복·홍합 포함) · 잣")
        XCTAssertEqual(MealAllergens.description(for: "볶음밥1.5.10."), "난류 · 대두 · 돼지고기")
        XCTAssertEqual(MealAllergens.description(for: "면 (1\n.\t6)"), "난류 · 밀")
        XCTAssertEqual(MealAllergens.description(for: "반찬 (0.1.20)"), "난류")
        for dish in ["쌀밥", "비타민 B12", "3.14 파이", "우유 200ml", "주스 (100ml)", "빵 (20)", "2.5"] {
            XCTAssertNil(MealAllergens.description(for: dish), dish)
        }
    }

    func testShareSummariesPreserveMealAnnotationsAndOrderLessonsAndMeals() throws {
        let timetable = try JSONDecoder().decode(Timetable.self, from: Data(#"{"date":"2026-10-10","lessons":[{"period":5,"subject":"체육"},{"period":2,"subject":"미술 또는 음악","ambiguous":true},{"period":3,"subject":"영어"}]}"#.utf8))
        XCTAssertEqual(timetable.missingPeriods, [1, 4])
        XCTAssertEqual(timetable.summary, "2교시 미술 또는 음악 (선택 수업)\n3교시 영어\n5교시 체육")
        let meals = try JSONDecoder().decode(Meals.self, from: Data(#"{"date":"2026-10-10","meals":[{"code":"3","name":"석식","dishes":["볶음밥 (1.5.10)"],"calories":""},{"code":"1","name":"조식","dishes":["우유 (2)","빵 (1.6)"],"calories":""}]}"#.utf8))
        XCTAssertEqual(meals.summary, "[조식]\n우유 (2)\n빵 (1.6)\n\n[석식]\n볶음밥 (1.5.10)")
        XCTAssertNil(meals.meals.first?.nutrition)
        XCTAssertNil(meals.meals.first?.origin)
        XCTAssertEqual(Timetable(date: "2026-10-10", lessons: []).missingPeriods, [])
        XCTAssertEqual(Timetable(date: "2026-10-10", lessons: []).summary, "등록된 시간표가 없습니다.")
        XCTAssertEqual(Meals(date: "2026-10-10", meals: []).summary, "등록된 급식이 없습니다.")
    }

    func testAppIntentsFailWithSetupGuidanceWhenSchoolIsMissing() async throws {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: SchoolPreferences.schoolKey)
        defer {
            if let original { defaults.set(original, forKey: SchoolPreferences.schoolKey) }
            else { defaults.removeObject(forKey: SchoolPreferences.schoolKey) }
        }
        defaults.removeObject(forKey: SchoolPreferences.schoolKey)
        for meal in [false, true] {
            do {
                if meal { _ = try await TodayMealIntent().perform() }
                else { _ = try await TodayTimetableIntent().perform() }
                XCTFail("Missing school must not become a successful Shortcuts value")
            } catch let error as SchoolError {
                XCTAssertEqual(error.localizedDescription, "오늘의 학교 앱에서 학교와 학급을 먼저 설정해 주세요.")
                XCTAssertEqual(String(localized: error.localizedStringResource), error.localizedDescription)
            }
        }
    }

    func testSpeechProvenanceSupportsNewAndLegacyServers() async throws {
        let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        defer { ControlledTransport.onStart = nil }
        for meal in [false, true] {
            let speech = meal ? "오늘 등록된 급식이 없습니다." : "오늘 시간표는 2교시 영어입니다."
            for mode in ["live", "mock"] {
                for legacy in [false, true] {
                    ControlledTransport.onStart = { transport in
                        if transport.request.url?.path == "/api/health" {
                            if legacy {
                                transport.respond(body: Data("{\"neis\":{\"mode\":\"\(mode)\"}}".utf8), contentType: "application/json")
                            } else {
                                // A failed health endpoint must not block a valid modern response.
                                transport.fail(.notConnectedToInternet)
                            }
                        } else {
                            let path = meal ? "/api/voice/meal" : "/api/voice/timetable"
                            XCTAssertEqual(transport.request.url?.path, path)
                            transport.respond(body: Data(speech.utf8), mode: legacy ? nil : mode)
                        }
                    }
                    let result = try await api.speech(settings: settings, meal: meal)
                    XCTAssertEqual(result, (mode == "mock" ? "실제 학교 자료가 아닌 예제 데이터입니다. " : "") + speech)
                }
            }
        }
    }

    func testSpeechRejectsInvalidBodiesAndUnknownProvenanceAndPreservesServerErrors() async throws {
        let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        defer { ControlledTransport.onStart = nil }
        let invalidResponse = "음성 안내를 읽을 수 없습니다. 잠시 뒤 다시 실행해 주세요."
        let genericFailure = "학교 정보를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요."
        let cases: [(Data, String, String, Int, String)] = [
            (Data("<html>Proxy error</html>".utf8), "text/html", "live", 200, invalidResponse),
            (Data("{\"error\":\"upstream\"}".utf8), "application/json", "live", 200, invalidResponse),
            (Data(" \n\t".utf8), "text/plain", "mock", 200, invalidResponse),
            (Data([0xff]), "text/plain", "live", 200, invalidResponse),
            (Data("오늘 등록된 급식이 없습니다.".utf8), "text/plain", "unconfigured", 200, "학교 자료의 출처를 확인하지 못했어요. 잠시 뒤 다시 실행해 주세요."),
            (Data("<html>Proxy secret</html>".utf8), "text/html", "live", 502, genericFailure),
            (Data(" \n".utf8), "text/plain", "live", 503, genericFailure),
            (Data("요청이 너무 많습니다. 잠시 후 다시 물어봐 주세요.".utf8), "text/plain", "live", 429, "요청이 너무 많습니다. 잠시 후 다시 물어봐 주세요."),
        ]
        for meal in [false, true] {
            for (body, type, mode, status, expected) in cases {
                ControlledTransport.onStart = { transport in
                    if transport.request.url?.path == "/api/health" {
                        transport.respond(body: Data(#"{"neis":{"mode":"live"}}"#.utf8), contentType: "application/json")
                    } else {
                        transport.respond(body: body, contentType: type, mode: mode, status: status)
                    }
                }
                do {
                    _ = try await api.speech(settings: settings, meal: meal)
                    XCTFail("Invalid voice response must not become spoken data")
                } catch {
                    XCTAssertEqual(error.localizedDescription, expected)
                }
            }
        }
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

    func testMalformedJSONResponsesGiveRetryGuidanceAndAllowRecovery() async throws {
        let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        defer { ControlledTransport.onStart = nil }
        let calls: [() async throws -> Void] = [
            { _ = try await api.health() },
            { _ = try await api.schools(name: "테스트") },
            { _ = try await api.classes(school: self.settings.school) },
            { _ = try await api.timetable(settings: self.settings) },
            { _ = try await api.meals(settings: self.settings) },
        ]
        for body in [Data(), Data("<html>Proxy failure</html>".utf8), Data("{\"date\":".utf8), Data("{}".utf8), Data("[]".utf8), Data([0xff])] {
            ControlledTransport.onStart = { $0.respond(body: body, contentType: "application/json") }
            for call in calls {
                do {
                    try await call()
                    XCTFail("Malformed data must not be accepted as school information")
                } catch let error as SchoolError {
                    XCTAssertEqual(error.localizedDescription, "학교 자료를 읽지 못했어요. 잠시 뒤 다시 시도해 주세요.")
                } catch {
                    XCTFail("Expected retry guidance, not a raw decoding error: \(error)")
                }
            }
        }
        ControlledTransport.onStart = {
            $0.respond(body: Data(#"{"error":{"message":"학교 서비스 점검 중입니다."}}"#.utf8), contentType: "application/json", status: 503)
        }
        for call in calls {
            do { try await call(); XCTFail("Expected the server failure") }
            catch { XCTAssertEqual(error.localizedDescription, "학교 서비스 점검 중입니다.") }
        }
        ControlledTransport.onStart = { transport in
            let body: String
            switch transport.request.url?.path {
            case "/api/health": body = #"{"neis":{"mode":"live"}}"#
            case "/api/schools": body = #"{"schools":[]}"#
            case "/api/classes": body = #"{"classes":[]}"#
            case "/api/timetable/today": body = #"{"date":"2026-10-15","lessons":[]}"#
            default: body = #"{"date":"2026-10-15","meals":[]}"#
            }
            transport.respond(body: Data(body.utf8), contentType: "application/json")
        }
        let health = try await api.health()
        let schools = try await api.schools(name: "테스트")
        let classes = try await api.classes(school: settings.school)
        let timetable = try await api.timetable(settings: settings)
        let meals = try await api.meals(settings: settings)
        XCTAssertEqual(health.neis.mode, "live")
        XCTAssertTrue(schools.isEmpty)
        XCTAssertTrue(classes.isEmpty)
        XCTAssertTrue(timetable.lessons.isEmpty)
        XCTAssertTrue(meals.meals.isEmpty)
    }

    func testTimetableRejectsInvalidPeriodsAndDuplicateRows() async throws {
        let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        defer { ControlledTransport.onStart = nil }
        let invalidLessons = [0, -1, 21, Int.max].map {
            "[{\"period\":\($0),\"subject\":\"수학\"}]"
        } + [#"[{"period":2,"subject":"국어"},{"period":2,"subject":"수학"}]"#]
        for lessons in invalidLessons {
            ControlledTransport.onStart = {
                $0.respond(body: Data("{\"date\":\"2026-10-15\",\"lessons\":\(lessons)}".utf8), contentType: "application/json")
            }
            do {
                _ = try await api.timetable(settings: settings)
                XCTFail("Invalid periods or duplicate rows must not reach the timetable screen")
            } catch let error as SchoolError {
                XCTAssertEqual(error.localizedDescription, "시간표 자료가 올바르지 않아요. 잠시 뒤 다시 시도해 주세요.")
            }
        }
        ControlledTransport.onStart = {
            $0.respond(body: Data(#"{"date":"2026-10-15","lessons":[{"period":20,"subject":"자율활동"},{"period":1,"subject":"미술 또는 음악","ambiguous":true}]}"#.utf8), contentType: "application/json")
        }
        let valid = try await api.timetable(settings: settings)
        XCTAssertEqual(Set(valid.lessons.map(\.period)), [1, 20])
        XCTAssertEqual(valid.missingPeriods, Array(2..<20))
        XCTAssertEqual(valid.lessons.first { $0.period == 1 }?.ambiguous, true)
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
        XCTAssertNotNil(model.fetchedAt)
        model.clearYesterday()
        XCTAssertNil(model.timetable)
        XCTAssertNil(model.meals)
        XCTAssertNil(model.fetchedAt)
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
        for previous in ["https://fixture.invalid/", "https://FIXTURE.INVALID", "https://fixture.invalid:443/"] {
            try store.saveSchool(settings)
            store.finishOnboarding()
            defaults.set(previous, forKey: SchoolPreferences.serverKey)
            let relaunched = SchoolStore(defaults: defaults, session: PreviewTransport.session, server: "https://fixture.invalid")
            try await relaunched.connect()
            XCTAssertEqual(relaunched.school, settings, previous)
            XCTAssertTrue(relaunched.onboardingComplete, previous)
            XCTAssertEqual(SchoolPreferences.readSchool(defaults: defaults), settings, previous)
        }
        let previousServer = defaults.string(forKey: SchoolPreferences.serverKey)
        ControlledTransport.onStart = { $0.fail(.notConnectedToInternet) }
        defer { ControlledTransport.onStart = nil }
        let unavailable = SchoolStore(defaults: defaults, session: ControlledTransport.session, server: "https://controlled.invalid")
        do { try await unavailable.connect(); XCTFail("Expected connection failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("인터넷 연결")) }
        XCTAssertEqual(unavailable.school, settings)
        XCTAssertTrue(unavailable.onboardingComplete)
        XCTAssertEqual(SchoolPreferences.readSchool(defaults: defaults), settings)
        XCTAssertEqual(defaults.string(forKey: SchoolPreferences.serverKey), previousServer)
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
    func testWrongDayResultsAndRefreshFailuresCannotLookLikeCurrentData() async throws {
        let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        defer { ControlledTransport.onStart = nil }
        for kind in [TodayKind.timetable, .meals] {
            let model = TodayModel()
            ControlledTransport.onStart = { $0.finish(subject: "current") }
            await model.load(kind: kind, settings: settings, api: api)
            XCTAssertNotNil(model.fetchedAt)
            XCTAssertNil(model.error)
            let shared = try XCTUnwrap(model.shareText(settings: settings, mock: true))
            XCTAssertTrue(shared.hasPrefix("예제 데이터 · 실제 학교 자료가 아닙니다\n테스트고등학교\n콘텐츠 & 보안과 · 2학년 3+과정반\n"))
            XCTAssertTrue(shared.contains("current"))
            XCTAssertTrue(shared.hasSuffix("출처: NEIS · 오늘의 학교"))
            XCTAssertFalse(model.shareText(settings: settings, mock: false)?.contains("예제 데이터") == true)
            ControlledTransport.onStart = {
                $0.respond(body: Data("{}".utf8), contentType: "application/json")
            }
            await model.load(kind: kind, settings: settings, api: api)
            XCTAssertEqual(model.error, "학교 자료를 읽지 못했어요. 잠시 뒤 다시 시도해 주세요.")
            XCTAssertNil(model.timetable)
            XCTAssertNil(model.meals)
            XCTAssertNil(model.fetchedAt)
            XCTAssertFalse(model.loading)
            XCTAssertNil(model.shareText(settings: settings, mock: false))
            ControlledTransport.onStart = { $0.finish(subject: "recovered") }
            await model.load(kind: kind, settings: settings, api: api)
            XCTAssertNil(model.error)
            XCTAssertTrue(model.shareText(settings: settings, mock: false)?.contains("recovered") == true)
            ControlledTransport.onStart = { $0.finish(subject: "wrong day", date: "2000-01-01") }
            await model.load(kind: kind, settings: settings, api: api)
            XCTAssertTrue(model.error?.contains("오늘 날짜") == true)
            XCTAssertNil(model.timetable)
            XCTAssertNil(model.meals)
            XCTAssertNil(model.fetchedAt)
            XCTAssertFalse(model.loading)
            XCTAssertNil(model.shareText(settings: settings, mock: false))
            ControlledTransport.onStart = { $0.finish(subject: "current") }
            await model.load(kind: kind, settings: settings, api: api)
            XCTAssertNotNil(model.fetchedAt)
            ControlledTransport.onStart = { $0.fail(.notConnectedToInternet) }
            await model.load(kind: kind, settings: settings, api: api)
            XCTAssertNotNil(model.error)
            XCTAssertNil(model.timetable)
            XCTAssertNil(model.meals)
            XCTAssertNil(model.fetchedAt)
            XCTAssertNil(model.shareText(settings: settings, mock: false))
        }
    }

    @MainActor
    func testCancelledLookupStopsLoadingAndCanBeRetriedWithoutStaleData() async throws {
        let api = try SchoolAPI(server: "https://controlled.invalid", session: ControlledTransport.session)
        defer { ControlledTransport.onStart = nil }
        for kind in [TodayKind.timetable, .meals] {
            let model = TodayModel()
            let started = expectation(description: "lookup started")
            ControlledTransport.onStart = { _ in started.fulfill() }
            let lookup = Task { await model.load(kind: kind, settings: settings, api: api) }
            await fulfillment(of: [started], timeout: 3)
            XCTAssertTrue(model.loading)
            lookup.cancel()
            await lookup.value
            XCTAssertFalse(model.loading)
            XCTAssertNil(model.error)
            XCTAssertNil(model.timetable)
            XCTAssertNil(model.meals)
            XCTAssertNil(model.fetchedAt)
            XCTAssertNil(model.shareText(settings: settings, mock: false))
            ControlledTransport.onStart = { $0.finish(subject: "retry result") }
            await model.load(kind: kind, settings: settings, api: api)
            XCTAssertFalse(model.loading)
            XCTAssertNil(model.error)
            XCTAssertNotNil(model.fetchedAt)
            XCTAssertTrue(model.shareText(settings: settings, mock: false)?.contains("retry result") == true)
        }
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
                    XCTAssertNil(model.shareText(settings: settings, mock: false))
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
    func finish(subject: String, status: Int = 200, date: String? = nil) {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = date ?? formatter.string(from: Date())
        let body: String
        if status != 200 {
            body = #"{"error":{"message":"older request failed"}}"#
        } else if request.url?.path == "/api/meal/today" {
            body = "{\"date\":\"\(day)\",\"meals\":[{\"code\":\"2\",\"name\":\"중식\",\"dishes\":[\"\(subject)\"],\"calories\":\"\"}]}"
        } else {
            body = "{\"date\":\"\(day)\",\"lessons\":[{\"period\":1,\"subject\":\"\(subject)\"}]}"
        }
        respond(body: Data(body.utf8), contentType: "application/json", status: status)
    }
    func respond(body: Data, contentType: String = "text/plain; charset=utf-8", mode: String? = nil, status: Int = 200) {
        var headers = ["Content-Type": contentType]
        if let mode { headers["X-School-Data-Mode"] = mode }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}
