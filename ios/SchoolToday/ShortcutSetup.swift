import SwiftUI
import AppIntents

struct SchoolShortcutsEntry: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var available = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if available {
                ShortcutsLink().accessibilityIdentifier("open-school-shortcuts")
                    .accessibilityLabel("오늘의 학교 단축어 페이지 열기")
                Text("단축어 앱으로 이동해요. ‘오늘 시간표’ 또는 ‘오늘 급식’을 눌러 실행해 보세요.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("이 기기에서 단축어 앱을 열 수 없어요.").font(.headline)
                    .accessibilityIdentifier("shortcuts-unavailable")
                Link("무료 단축어 앱 설치하기", destination: URL(string: "https://apps.apple.com/kr/app/shortcuts/id915249334")!)
                    .accessibilityIdentifier("open-school-shortcuts")
                Text("단축어 앱이 없다면 설치한 뒤 이 앱으로 돌아오세요. 설치되어 있는데 열리지 않으면 단축어 앱을 직접 열고 ‘앱 단축어’에서 ‘오늘의 학교’를 찾으세요.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .onAppear { checkAvailability() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { checkAvailability() } }
    }

    private func checkAvailability() {
        available = UIApplication.shared.canOpenURL(URL(string: "shortcuts://")!)
    }
}

struct ShortcutCheckView: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.dismiss) private var dismiss
    @State private var meal = false
    @State private var attempt = 0
    @State private var loading = false
    @State private var response: String?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("어디서 막혔는지\n같이 확인해요").font(.largeTitle.bold())
                Text("먼저 앱에서 결과가 나오는지, 그다음 단축어에서 실행되는지, 마지막으로 Siri가 알아듣는지 순서대로 확인해요.")
                VStack(alignment: .leading, spacing: 16) {
                    Text("1. 학교 정보가 나오는지 확인").font(.headline)
                    Text(store.school?.schoolClass.label ?? "학교·학급을 먼저 선택해 주세요.")
                    Button("시간표 결과 확인") { meal = false; attempt += 1 }
                        .buttonStyle(SchoolPrimaryButtonStyle())
                        .accessibilityIdentifier("check-timetable")
                    Button("급식 결과 확인") { meal = true; attempt += 1 }
                        .buttonStyle(SchoolPrimaryButtonStyle())
                        .accessibilityIdentifier("check-meal")
                    if loading { ProgressView("학교 정보를 확인하고 있어요") }
                    if let response { Text(response).textSelection(.enabled).accessibilityIdentifier("shortcut-check-result") }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("shortcut-check-error") }
                    Text("Siri와 같은 음성 API의 결과를 확인합니다. 이 검사가 성공해도 단축어 등록이나 Siri 음성 인식까지 확인된 것은 아니에요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.modifier(SchoolCard()).disabled(loading)
                VStack(alignment: .leading, spacing: 16) {
                    Text("2. 단축어 앱에서 직접 실행").font(.headline)
                    SchoolShortcutsEntry()
                    Text("학교 정보는 나오는데 여기서만 오류가 나면, 오류 화면을 캡처해 주세요. ‘오늘의 학교’가 목록에 없으면 앱을 한 번 실행한 뒤 단축어 앱을 다시 열어 확인하세요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.modifier(SchoolCard())
                GuideInstruction(number: 3, title: "버튼으로 Siri를 먼저 실행", detail: "측면 버튼(홈 버튼 기기는 홈 버튼)을 길게 누른 뒤 ‘오늘의 학교 시간표 알려줘’라고 말하세요. 이 방법은 ‘시리야’ 음성 호출 설정과 구분해서 확인할 수 있어요.")
                GuideInstruction(number: 4, title: "개인 단축어를 만들었다면", detail: "단축어 앱에 저장한 이름을 그대로 말하세요. 이름이 ‘학교 시간표’라면 ‘학교 시간표’, 이름이 ‘오늘 학교 시간표’라면 ‘오늘 학교 시간표’라고 말해요. 웹 검색이 나오면 먼저 이름과 단축어 앱의 직접 실행 결과를 확인하세요.")
            }.padding(24)
        }
        .background(SchoolDesign.canvas)
        .navigationTitle("단축어 실행 점검").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { Button("닫기") { dismiss() } }
        .task(id: attempt) {
            guard attempt > 0, let settings = store.school, let api = store.api else { return }
            loading = true; response = nil; error = nil
            defer { if !Task.isCancelled { loading = false } }
            do {
                let result = try await api.speech(settings: settings, meal: meal)
                guard !Task.isCancelled else { return }
                response = result
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
