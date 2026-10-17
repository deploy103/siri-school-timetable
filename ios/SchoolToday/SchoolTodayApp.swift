import SwiftUI
import Network
import AppIntents
import UserNotifications
import WidgetKit

@main
struct SchoolTodayApp: App {
    @UIApplicationDelegateAdaptor(SchoolAppDelegate.self) private var appDelegate
    @StateObject private var store: SchoolStore
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let defaults = UserDefaults(suiteName: "schooltoday.ui-tests")!
            if ProcessInfo.processInfo.arguments.contains("--reset-settings") {
                defaults.removePersistentDomain(forName: "schooltoday.ui-tests")
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlannerUITests", isDirectory: true)
                try? FileManager.default.removeItem(at: directory)
            }
            let server = ProcessInfo.processInfo.arguments.contains("--missing-server") ? "" : "https://fixture.invalid"
            _store = StateObject(wrappedValue: SchoolStore(defaults: defaults, session: PreviewTransport.session, server: server))
            return
        }
        #endif
        _store = StateObject(wrappedValue: SchoolStore())
    }
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
        }
    }
}

@MainActor
final class SchoolAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let day = info["preparationDate"] as? String, SchoolCalendar.date(day) != nil,
              let selection = info["selection"] as? String else { return }
        await MainActor.run {
            guard SchoolPreferences.readSchool()?.planningKey == selection else { return }
            UserDefaults.standard.set(day, forKey: "schooltoday.pending-preparation-date")
            NotificationCenter.default.post(name: .showSchoolPreparation, object: nil)
        }
    }
}

@MainActor
final class SchoolStore: ObservableObject {
    @Published private(set) var school: SchoolSettings?
    @Published private(set) var onboardingComplete: Bool
    @Published private(set) var api: SchoolAPI?
    @Published private(set) var mode = ""
    @Published private(set) var online = true
    let defaults: UserDefaults
    let session: URLSession
    private let monitor = NWPathMonitor()
    let server: String

    init(defaults: UserDefaults = .standard, session: URLSession = .shared, server: String = SchoolPreferences.server()) {
        self.defaults = defaults
        self.session = session
        self.server = server
        let storedSchool = SchoolPreferences.readSchool(defaults: defaults)
        school = storedSchool
        onboardingComplete = storedSchool != nil && defaults.bool(forKey: "schooltoday.onboarding.v2")
        if storedSchool == nil { defaults.removeObject(forKey: "schooltoday.onboarding.v2") }
        // A previously verified origin can open dated local data without a new network handshake.
        if storedSchool != nil,
           let candidate = try? SchoolAPI(server: server, session: session),
           let previous = defaults.string(forKey: SchoolPreferences.serverKey).flatMap({ try? SchoolAPI(server: $0).baseURL }),
           previous == candidate.baseURL,
           let previousMode = defaults.string(forKey: "schooltoday.data-mode.v1"), ["live", "mock"].contains(previousMode) {
            api = candidate
            mode = previousMode
        }
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.online = path.status == .satisfied }
        }
        monitor.start(queue: DispatchQueue(label: "SchoolToday.Network"))
    }
    deinit { monitor.cancel() }

    func connect() async throws {
        let candidate = try SchoolAPI(server: server, session: session)
        let health = try await candidate.health()
        guard ["live", "mock"].contains(health.neis.mode) else {
            throw SchoolError.message("서버의 학교 데이터 연결이 준비되지 않았습니다.")
        }
        let previous = defaults.string(forKey: SchoolPreferences.serverKey)
            .flatMap { try? SchoolAPI(server: $0).baseURL }
        if previous != candidate.baseURL { try saveSchool(nil) }
        defaults.set(candidate.baseURL.absoluteString, forKey: SchoolPreferences.serverKey)
        defaults.set(health.neis.mode, forKey: "schooltoday.data-mode.v1")
        mode = health.neis.mode
        api = candidate
    }
    func saveSchool(_ settings: SchoolSettings?) throws {
        try SchoolPreferences.writeSchool(settings, defaults: defaults)
        school = settings
        if settings == nil {
            onboardingComplete = false
            defaults.removeObject(forKey: "schooltoday.onboarding.v2")
            SchoolWidgetCache.write(nil)
            WidgetCenter.shared.reloadAllTimelines()
            UserDefaults.standard.removeObject(forKey: "schooltoday.pending-preparation-date")
            Task { _ = await PreparationNotifications.shared.synchronize(plan: PreparationPlan(), selection: "") }
        }
    }
    func finishOnboarding() {
        defaults.set(true, forKey: "schooltoday.onboarding.v2")
        onboardingComplete = true
    }
}

struct RootView: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = false
    var body: some View {
        Group {
            if !store.onboardingComplete && !started {
                WelcomeView { started = true }
            } else if let api = store.api {
                if let school = store.school {
                    SchoolDashboard(settings: school, api: api, mode: store.mode, directory: plannerDirectory)
                        .id("\(school.planningKey):\(api.baseURL):\(store.mode)")
                        .onAppear { if !store.onboardingComplete { store.finishOnboarding() } }
                } else {
                    NavigationStack { SchoolSearchView(api: api) }
                }
            } else {
                NavigationStack { ConnectionView() }
            }
        }
        .tint(SchoolDesign.blue)
        .foregroundStyle(SchoolDesign.ink)
        .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28), value: started)
        .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28), value: store.school)
        .task {
            if store.api != nil { try? await store.connect() }
        }
        .onChange(of: store.school) { _, school in
            if school == nil { started = false }
        }
    }
    private var plannerDirectory: URL? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PlannerUITests", isDirectory: true)
        }
        #endif
        return nil
    }
}

struct DemoNotice: View {
    @EnvironmentObject private var store: SchoolStore
    var body: some View {
        if store.mode == "mock" {
            Label("예제 데이터 · 실제 학교 자료가 아닙니다", systemImage: "exclamationmark.triangle")
                .font(.footnote).foregroundStyle(.orange)
        }
    }
}

struct ConnectionView: View {
    @EnvironmentObject private var store: SchoolStore
    @State private var error: String?
    @State private var loading = false
    @State private var attempt = 0
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SchoolBrand()
                Text(store.server.isEmpty || error != nil ? "학교 연결을\n확인해 주세요" : "내 학교를\n연결하고 있어요").font(.largeTitle.bold())
                if loading { ProgressView("학교 정보를 준비하고 있어요") }
                if store.server.isEmpty {
                    Text("서비스 연결이 아직 준비되지 않았습니다.")
                } else if error != nil {
                    Button("다시 시도") { attempt += 1 }.disabled(loading)
                        .buttonStyle(SchoolPrimaryButtonStyle())
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("connection-error") }
                Text("인터넷 연결을 확인해요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(28)
        }
        .background(SchoolDesign.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: attempt) {
            guard !store.server.isEmpty else { return }
            loading = true; error = nil
            defer { loading = false }
            do { try await store.connect() }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}

struct SchoolSearchView: View {
    let api: SchoolAPI
    @State private var name = ""
    @State private var submitted = ""
    @State private var searchAttempt = 0
    @State private var schools: [School] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selectedSchool: School?
    @FocusState private var searchFocused: Bool
    var body: some View {
        SetupPage(title: "어느 학교에 다니나요?", symbol: "magnifyingglass", pinnedActions: !searchFocused, compactHeading: searchFocused) {
            HStack(spacing: 8) {
                TextField("학교 이름 (두 글자 이상)", text: $name)
                    .accessibilityIdentifier("school-search")
                    .focused($searchFocused).submitLabel(.search).onSubmit(search)
                Button(action: search) { Image(systemName: "arrow.right.circle.fill").font(.title2) }
                    .frame(minWidth: 44, minHeight: 44).accessibilityLabel("학교 검색")
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || loading)
            }.padding(14).background(SchoolDesign.card, in: RoundedRectangle(cornerRadius: 16))
            DemoNotice()
            if loading { ProgressView("학교를 찾고 있어요") }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(schools) { school in
                SetupChoice(title: school.name, detail: "\(school.kind) · \(school.address)", selected: selectedSchool == school) {
                    selectedSchool = school
                }
            }
            if !submitted.isEmpty && !loading && error == nil && schools.isEmpty { Text("검색된 학교가 없습니다.") }
        } actions: {
            NavigationLink {
                if let selectedSchool { ClassSelectionView(api: api, school: selectedSchool) }
            } label: { Text("이 학교로 계속") }
                .buttonStyle(SchoolPrimaryButtonStyle()).disabled(selectedSchool == nil)
                .accessibilityIdentifier("school-next")
        }
        .navigationTitle("내 학교").navigationBarTitleDisplayMode(.inline)
        .onChange(of: name) { _, _ in submitted = ""; schools = []; selectedSchool = nil; loading = false; error = nil; searchAttempt += 1 }
        .task(id: searchAttempt) {
            guard submitted.count >= 2 else { return }
            loading = true; error = nil; schools = []; selectedSchool = nil
            defer { if !Task.isCancelled { loading = false } }
            do {
                let result = try await api.schools(name: submitted)
                guard !Task.isCancelled else { return }
                schools = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }

    private func search() {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 && !loading else { return }
        searchFocused = false
        submitted = query
        searchAttempt += 1
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: SchoolStore
    @State private var reset = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("내 학교와\n사용 방법").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 12) {
                    Text(store.school?.school.name ?? "학교 미설정").font(.headline)
                    Text(store.school?.classLabel ?? "").foregroundStyle(.secondary)
                    Button("학교 변경") {
                        do { try store.saveSchool(nil) } catch { self.error = error.localizedDescription }
                    }
                }.modifier(SchoolCard())
                VStack(alignment: .leading, spacing: 16) {
                    NavigationLink("Siri 사용법") { SiriGuideView(onboarding: false) }
                    NavigationLink("단축어 실행 점검") { ShortcutCheckView() }
                        .accessibilityIdentifier("shortcut-check")
                    SchoolShortcutsEntry()
                }.modifier(SchoolCard())
                VStack(alignment: .leading, spacing: 16) {
                    Text("데이터와 개인정보").font(.headline)
                    DemoNotice()
                    Text("학교 설정과 개인 준비 기록은 이 기기에 저장해요. 학교를 바꿔도 이전 준비 기록은 지우지 않습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("구매 복원은 개인 기록 복원이 아닙니다. 앱 삭제·기기 변경에 대비한 동기화는 아직 제공하지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    DisclosureGroup("개인정보 안내") {
                        Text("인터넷 연결이 필요해요. NEIS 키·Apple 로그인 정보는 앱에 저장하지 않아요.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    Button("학교 설정 초기화", role: .destructive) { reset = true }
                    if let error { Text(error).foregroundStyle(.red) }
                }.modifier(SchoolCard())
            }.padding(24)
        }
        .background(SchoolDesign.canvas)
        .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("저장된 학교 설정을 삭제할까요?", isPresented: $reset, titleVisibility: .visible) {
            Button("설정 삭제", role: .destructive) {
                do { try store.saveSchool(nil) } catch { self.error = error.localizedDescription }
            }
        }
    }
}
