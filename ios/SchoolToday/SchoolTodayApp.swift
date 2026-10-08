import SwiftUI
import Network

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
    }
}

struct RootView: View {
    @EnvironmentObject private var store: SchoolStore
    var body: some View {
        Group {
            if let api = store.api {
                if let school = store.school {
                    TabView {
                        NavigationStack { TodayView(kind: .timetable, settings: school, api: api) }
                            .tabItem { Label("시간표", systemImage: "calendar") }
                        NavigationStack { TodayView(kind: .meals, settings: school, api: api) }
                            .tabItem { Label("급식", systemImage: "fork.knife") }
                        NavigationStack { SettingsView() }
                            .tabItem { Label("설정", systemImage: "gearshape") }
                    }
                } else {
                    NavigationStack { SchoolSearchView(api: api) }
                }
            } else {
                NavigationStack { ConnectionView() }
            }
        }
        .tint(.indigo)
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
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "graduationcap.fill").font(.title).foregroundStyle(.indigo).accessibilityHidden(true)
                    Text("오늘의 학교").font(.largeTitle.bold())
                }
                Text("학교 시간표와 급식을 확인하고 Siri로 바로 물어보세요.")
            }
            Section {
                if loading { ProgressView("학교 정보를 준비하고 있어요") }
                if store.server.isEmpty {
                    Text("서비스 연결이 아직 준비되지 않았습니다.")
                } else if error != nil {
                    Button("다시 시도") { attempt += 1 }.disabled(loading)
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("connection-error") }
            } header: {
                Text("학교 정보 연결")
            } footer: {
                Text("학교 정보를 확인하려면 인터넷 연결이 필요합니다.")
            }
        }
        .navigationTitle("시작하기")
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
    var body: some View {
        List {
            Section {
                DemoNotice()
                TextField("학교 이름 (두 글자 이상)", text: $name).accessibilityIdentifier("school-search")
                Button("학교 검색") { submitted = name.trimmingCharacters(in: .whitespacesAndNewlines); searchAttempt += 1 }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 || loading)
                if loading { ProgressView("학교를 찾고 있어요") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section("검색 결과") {
                ForEach(schools) { school in
                    NavigationLink {
                        ClassSelectionView(api: api, school: school)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(school.name).font(.headline)
                            Text("\(school.kind) · \(school.address)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !submitted.isEmpty && !loading && error == nil && schools.isEmpty { Text("검색된 학교가 없습니다.") }
            }
        }
        .navigationTitle("내 학교 선택")
        .onChange(of: name) { _, _ in submitted = ""; schools = []; loading = false; error = nil; searchAttempt += 1 }
        .task(id: searchAttempt) {
            guard submitted.count >= 2 else { return }
            loading = true; error = nil; schools = []
            defer { if !Task.isCancelled { loading = false } }
            do {
                let result = try await api.schools(name: submitted)
                guard !Task.isCancelled else { return }
                schools = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
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
    var body: some View {
        List {
            Section { Text(school.name).font(.headline); DemoNotice() }
            Section("학과·학년·반 선택") {
                if loading { ProgressView("학급을 불러오는 중") }
                if let error { Text(error).foregroundStyle(.red); Button("다시 시도") { attempt += 1 } }
                ForEach(classes) { schoolClass in
                    Button(schoolClass.label) {
                        do { try store.saveSchool(SchoolSettings(school: school, schoolClass: schoolClass)) }
                        catch { self.error = error.localizedDescription }
                    }
                }
                if !loading && error == nil && classes.isEmpty { Text("학교에서 제공한 학급이 없습니다. 학교에 문의해 주세요.") }
            }
        }
        .navigationTitle("학급 선택")
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
        Form {
            Section("내 학교") {
                Text(store.school?.school.name ?? "학교 미설정")
                Text(store.school?.schoolClass.label ?? "")
                Button("학교 변경") {
                    do { try store.saveSchool(nil) } catch { self.error = error.localizedDescription }
                }
            }
            Section("Siri와 단축어") {
                Label("오늘 시간표 듣기", systemImage: "calendar")
                Label("오늘 급식 듣기", systemImage: "fork.knife")
                Text("단축어 앱 → 앱 단축어 → 오늘의 학교에서 실행해 보세요. Siri에 ‘오늘의 학교 오늘 시간표 알려줘’ 또는 ‘오늘의 학교 오늘 급식 알려줘’라고 말할 수 있습니다. 실제 기기에서 인식 여부를 확인해야 합니다.")
                    .font(.footnote)
            }
            Section("데이터와 개인정보") {
                DemoNotice()
                Text("인터넷 연결이 필요합니다. 학교 설정은 이 기기에 저장됩니다. NEIS 키와 Apple 로그인 정보는 앱에 저장하지 않습니다.")
                Button("학교 설정 초기화", role: .destructive) { reset = true }
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("설정")
        .confirmationDialog("저장된 학교 설정을 삭제할까요?", isPresented: $reset, titleVisibility: .visible) {
            Button("설정 삭제", role: .destructive) {
                do { try store.saveSchool(nil) } catch { self.error = error.localizedDescription }
            }
        }
    }
}
