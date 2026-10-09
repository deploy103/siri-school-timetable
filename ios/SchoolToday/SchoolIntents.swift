import AppIntents
import SwiftUI

struct TodayTimetableIntent: AppIntent {
    static var title: LocalizedStringResource = "오늘 시간표 듣기"
    static var description = IntentDescription("앱에서 저장한 학교와 학급의 오늘 시간표를 확인합니다.")
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> & ShowsSnippetView {
        guard let settings = SchoolPreferences.readSchool() else {
            let text = "오늘의 학교 앱에서 학교와 학급을 먼저 설정해 주세요."
            return .result(value: text, dialog: IntentDialog(stringLiteral: text), view: Text(text))
        }
        let api = try SchoolAPI(server: SchoolPreferences.server())
        let text = try await api.speech(settings: settings, meal: false)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text), view: Text(text))
    }
}

struct TodayMealIntent: AppIntent {
    static var title: LocalizedStringResource = "오늘 급식 듣기"
    static var description = IntentDescription("앱에서 저장한 학교의 오늘 급식을 확인합니다.")
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> & ShowsSnippetView {
        guard let settings = SchoolPreferences.readSchool() else {
            let text = "오늘의 학교 앱에서 학교와 학급을 먼저 설정해 주세요."
            return .result(value: text, dialog: IntentDialog(stringLiteral: text), view: Text(text))
        }
        let api = try SchoolAPI(server: SchoolPreferences.server())
        let text = try await api.speech(settings: settings, meal: true)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text), view: Text(text))
    }
}

struct SchoolShortcuts: AppShortcutsProvider {
    static let timetableExample = "오늘의 학교 시간표 알려줘"
    static let mealExample = "오늘의 학교 급식 알려줘"
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TodayTimetableIntent(), phrases: ["\(.applicationName) 시간표 알려줘", "\(.applicationName) 오늘 시간표 알려줘"], shortTitle: "오늘 시간표", systemImageName: "calendar")
        AppShortcut(intent: TodayMealIntent(), phrases: ["\(.applicationName) 급식 알려줘", "\(.applicationName) 오늘 급식 알려줘"], shortTitle: "오늘 급식", systemImageName: "fork.knife")
    }
}
