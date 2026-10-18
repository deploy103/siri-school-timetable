import SwiftUI
import AppIntents

struct SchoolShortcutsEntry: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var available = false
    @State private var openFailed = false
    var appPage = true
    var personalName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if available {
                if let personalName {
                    Button { openShortcuts(SchoolShortcut.runURL(named: personalName)) } label: {
                        Label("저장한 단축어 실행", systemImage: "play.fill")
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("단축어 앱에서 이 이름으로 저장한 단축어를 실행해요.")
                    .accessibilityIdentifier("run-personal-shortcut")
                } else if appPage {
                    ShortcutsLink().accessibilityIdentifier("open-school-shortcuts")
                        .accessibilityLabel("오늘의 학교 단축어 페이지 열기")
                    Text("누르면 단축어 앱이 열려요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Button("단축어 앱 열기") { openShortcuts(URL(string: "shortcuts://")!) }
                        .frame(minHeight: 44).accessibilityIdentifier("open-school-shortcuts")
                }
            } else {
                Text("단축어 앱을 열 수 없어요.").font(.headline)
                    .accessibilityIdentifier("shortcuts-unavailable")
                Link("무료 단축어 앱 설치하기", destination: URL(string: "https://apps.apple.com/kr/app/shortcuts/id915249334")!)
                    .accessibilityIdentifier("open-school-shortcuts")
                Text("설치 후 돌아와요. 이미 있다면 직접 열어 ‘오늘의 학교’를 찾아요.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .onAppear { checkAvailability() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { checkAvailability() } }
        .alert("단축어 앱을 열지 못했어요", isPresented: $openFailed) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("단축어 앱을 직접 열어 ‘오늘의 학교’를 찾아요. 개인 단축어는 저장한 이름을 확인해요.")
        }
    }

    private func openShortcuts(_ url: URL) {
        openURL(url) { accepted in
            if !accepted { checkAvailability() }
            openFailed = !accepted
        }
    }

    private func checkAvailability() {
        available = UIApplication.shared.canOpenURL(URL(string: "shortcuts://")!)
    }
}

struct SiriCallHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("측면(전원) 버튼을 길게 눌러요.", systemImage: "hand.tap")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("홈 버튼이 있으면 홈 버튼을 길게 눌러요.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup {
                Text("Siri 설정에서 음성 호출을 켠 뒤 ‘시리야’라고 말해요.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
            } label: {
                Text("‘시리야’로 부르기").font(.subheadline)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
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
    @State private var requestID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("실행 확인").font(.largeTitle.bold())
                Text("앱 → 단축어 → Siri 순서로 확인해요.")
                VStack(alignment: .leading, spacing: 16) {
                    Text("1. 앱에서 확인").font(.headline)
                    Text(store.school?.classLabel ?? "학교·학급을 먼저 선택해 주세요.")
                    Button("시간표 결과 확인") { meal = false; attempt += 1 }
                        .buttonStyle(SchoolPrimaryButtonStyle())
                        .accessibilityIdentifier("check-timetable")
                    Button("급식 결과 확인") { meal = true; attempt += 1 }
                        .buttonStyle(SchoolPrimaryButtonStyle())
                        .accessibilityIdentifier("check-meal")
                    if loading { ProgressView("학교 정보를 확인하고 있어요") }
                    if let response { Text(response).textSelection(.enabled).accessibilityIdentifier("shortcut-check-result") }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("shortcut-check-error") }
                    Text("앱 결과만 확인해요. Siri 실행은 별도예요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.modifier(SchoolCard()).disabled(loading)
                VStack(alignment: .leading, spacing: 16) {
                    Text("2. 단축어에서 실행").font(.headline)
                    SchoolShortcutsEntry()
                    Text("목록에 없으면 이 앱을 한 번 켜고 다시 찾아요. 오류가 나면 화면을 캡처해요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.modifier(SchoolCard())
                VStack(alignment: .leading, spacing: 16) {
                    Text("3. Siri로 실행").font(.headline)
                    SiriCallHint()
                    Text(meal ? SchoolShortcuts.mealExample : SchoolShortcuts.timetableExample)
                        .font(.headline).textSelection(.enabled)
                        .accessibilityIdentifier("shortcut-check-phrase")
                }.modifier(SchoolCard())
                DisclosureGroup("내 단축어를 만들었다면") {
                    Text("저장한 이름 그대로 말해요. 웹 검색이 나오면 단축어 앱에서 직접 실행해요. 이름을 바꿨거나 삭제했다면 앱의 Siri 사용 방법에서 다시 설정해요.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                }
            }.padding(24)
        }
        .background(SchoolDesign.canvas)
        .navigationTitle("단축어 실행 점검").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { Button("닫기") { dismiss() } }
        .task(id: attempt) {
            guard attempt > 0, let settings = store.school, let api = store.api else { return }
            let id = UUID()
            requestID = id
            loading = true; response = nil; error = nil
            defer { if requestID == id { loading = false } }
            do {
                let result = try await api.speech(settings: settings, meal: meal)
                guard requestID == id, !Task.isCancelled else { return }
                response = result
            } catch {
                if requestID == id, !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }
}
