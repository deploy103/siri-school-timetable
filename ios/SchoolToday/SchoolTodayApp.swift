import SwiftUI
import Network
import AppIntents

@main
struct SchoolTodayApp: App {
    @StateObject private var store: SchoolStore
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let defaults = UserDefaults(suiteName: "schooltoday.ui-tests")!
            if ProcessInfo.processInfo.arguments.contains("--reset-settings") {
                defaults.removePersistentDomain(forName: "schooltoday.ui-tests")
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
        school = SchoolPreferences.readSchool(defaults: defaults)
        onboardingComplete = defaults.bool(forKey: "schooltoday.onboarding.v2")
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
        if defaults.string(forKey: SchoolPreferences.serverKey) != candidate.baseURL.absoluteString { try saveSchool(nil) }
        defaults.set(candidate.baseURL.absoluteString, forKey: SchoolPreferences.serverKey)
        mode = health.neis.mode
        api = candidate
    }
    func saveSchool(_ settings: SchoolSettings?) throws {
        try SchoolPreferences.writeSchool(settings, defaults: defaults)
        school = settings
        if settings == nil {
            onboardingComplete = false
            defaults.removeObject(forKey: "schooltoday.onboarding.v2")
        }
    }
    func finishOnboarding() {
        defaults.set(true, forKey: "schooltoday.onboarding.v2")
        onboardingComplete = true
    }
}

struct RootView: View {
    @EnvironmentObject private var store: SchoolStore
    @State private var started = false
    @State private var tab = 0
    var body: some View {
        Group {
            if !store.onboardingComplete && !started {
                WelcomeView { started = true }
            } else if let api = store.api {
                if let school = store.school {
                    if !store.onboardingComplete {
                        NavigationStack { SiriGuideView(onboarding: true) }
                    } else {
                        TabView(selection: $tab) {
                            NavigationStack { SchoolHomeView(tab: $tab) }
                                .tabItem { Label("홈", systemImage: "house") }.tag(0)
                            NavigationStack { TodayView(kind: .timetable, settings: school, api: api) }
                                .tabItem { Label("시간표", systemImage: "calendar") }.tag(1)
                            NavigationStack { TodayView(kind: .meals, settings: school, api: api) }
                                .tabItem { Label("급식", systemImage: "fork.knife") }.tag(2)
                            NavigationStack { SettingsView() }
                                .tabItem { Label("설정", systemImage: "gearshape") }.tag(3)
                        }
                    }
                } else {
                    NavigationStack { SchoolSearchView(api: api) }
                }
            } else {
                NavigationStack { ConnectionView() }
            }
        }
        .tint(SchoolDesign.blue)
        .foregroundStyle(SchoolDesign.ink)
        .onChange(of: store.school) { _, school in
            tab = 0
            if school == nil { started = false }
        }
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
                Text("학교 정보를 확인하려면 인터넷 연결이 필요합니다.")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("1 / 7 · 학교 선택").font(.caption).foregroundStyle(SchoolDesign.blue)
                Text("어느 학교에\n다니고 있나요?").font(.largeTitle.bold())
                Text("학교 이름을 검색한 뒤 내 학교를 선택하세요.").foregroundStyle(.secondary)
                DemoNotice()
                TextField("학교 이름 (두 글자 이상)", text: $name)
                    .padding(18).background(SchoolDesign.card, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("school-search")
                    .focused($searchFocused).submitLabel(.search).onSubmit(search)
                Button("학교 검색", action: search)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || loading)
                    .buttonStyle(SchoolPrimaryButtonStyle())
                if loading { ProgressView("학교를 찾고 있어요") }
                if let error { Text(error).foregroundStyle(.red) }
                ForEach(schools) { school in
                    Button { selectedSchool = school } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(school.name).font(.headline)
                                Text("\(school.kind) · \(school.address)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedSchool == school ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(SchoolDesign.blue)
                        }.modifier(SchoolCard())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(school.name)
                        .accessibilityValue(selectedSchool == school ? "선택됨" : "선택 안 됨")
                }
                if !submitted.isEmpty && !loading && error == nil && schools.isEmpty { Text("검색된 학교가 없습니다.") }
            }.padding(28)
        }
        .background(SchoolDesign.canvas)
        .navigationTitle("내 학교").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !searchFocused {
                NavigationLink {
                    if let selectedSchool { ClassSelectionView(api: api, school: selectedSchool) }
                } label: { Label("다음", systemImage: "arrow.right") }
                    .buttonStyle(SchoolPrimaryButtonStyle()).disabled(selectedSchool == nil)
                    .accessibilityIdentifier("school-next")
                    .padding(24).background(SchoolDesign.canvas)
            }
        }
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

struct ClassSelectionView: View {
    @EnvironmentObject private var store: SchoolStore
    let api: SchoolAPI
    let school: School
    @State private var classes: [SchoolClass] = []
    @State private var error: String?
    @State private var loading = true
    @State private var attempt = 0
    @State private var selectedClass: SchoolClass?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("2 / 7 · 학급 선택").font(.caption).foregroundStyle(SchoolDesign.blue)
                Text("내 학급을\n알려주세요").font(.largeTitle.bold())
                Text(school.name).font(.headline)
                Text("학과·학년·반을 확인하고 다음으로 넘어가세요.").foregroundStyle(.secondary)
                DemoNotice()
                if loading { ProgressView("학급을 불러오는 중") }
                if let error { Text(error).foregroundStyle(.red); Button("다시 시도") { attempt += 1 } }
                ForEach(classes) { schoolClass in
                    Button { selectedClass = schoolClass } label: {
                        HStack {
                            Text(schoolClass.label).font(.headline)
                            Spacer()
                            Image(systemName: selectedClass == schoolClass ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(SchoolDesign.blue)
                        }.modifier(SchoolCard())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(schoolClass.label)
                        .accessibilityValue(selectedClass == schoolClass ? "선택됨" : "선택 안 됨")
                }
                if !loading && error == nil && classes.isEmpty { Text("학교에서 제공한 학급이 없습니다. 학교에 문의해 주세요.") }
            }.padding(28)
        }
        .background(SchoolDesign.canvas)
        .navigationTitle("내 학급").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                if let selectedClass {
                    do { try store.saveSchool(SchoolSettings(school: school, schoolClass: selectedClass)) }
                    catch { self.error = error.localizedDescription }
                }
            } label: { Label("다음", systemImage: "arrow.right") }
                .buttonStyle(SchoolPrimaryButtonStyle()).disabled(selectedClass == nil)
                .accessibilityIdentifier("class-next")
                .padding(24).background(SchoolDesign.canvas)
        }
        .task(id: attempt) {
            loading = true; error = nil
            defer { if !Task.isCancelled { loading = false } }
            do { classes = try await api.classes(school: school) }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
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
                    Text(store.school?.schoolClass.label ?? "").foregroundStyle(.secondary)
                    Button("학교 변경") {
                        do { try store.saveSchool(nil) } catch { self.error = error.localizedDescription }
                    }
                }.modifier(SchoolCard())
                VStack(alignment: .leading, spacing: 16) {
                    NavigationLink("Siri 설정 안내 다시 보기") { SiriGuideView(onboarding: false) }
                    ShortcutsLink().accessibilityIdentifier("open-school-shortcuts")
                        .accessibilityLabel("오늘의 학교 단축어 페이지 열기")
                    Text("앱 호출 문구와 개인 단축어 이름은 달라요. 안내에서 Siri 설정, 이름 변경과 웹 검색이 나올 때의 확인 방법을 볼 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.modifier(SchoolCard())
                VStack(alignment: .leading, spacing: 16) {
                    Text("데이터와 개인정보").font(.headline)
                    DemoNotice()
                    Text("인터넷 연결이 필요합니다. 학교 설정은 이 기기에 저장됩니다. NEIS 키와 Apple 로그인 정보는 앱에 저장하지 않습니다.")
                        .font(.footnote).foregroundStyle(.secondary)
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
