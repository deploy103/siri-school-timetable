import SwiftUI
import Combine

enum TodayKind: String { case timetable, meals }

@MainActor
final class TodayModel: ObservableObject {
    @Published private(set) var timetable: Timetable?
    @Published private(set) var meals: Meals?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var requestID = UUID()
    private(set) var fetchedAt: Date?
    private(set) var requestedDay = ""

    static func day(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func clearYesterday() {
        requestID = UUID()
        timetable = nil; meals = nil; loading = false
        error = "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
        requestedDay = Self.day()
    }

    func load(kind: TodayKind, settings: SchoolSettings, api: SchoolAPI) async {
        let id = UUID()
        requestID = id
        let day = Self.day()
        requestedDay = day
        loading = true; error = nil; timetable = nil; meals = nil
        do {
            switch kind {
            case .timetable:
                let data = try await api.timetable(settings: settings)
                guard requestID == id, !Task.isCancelled else { return }
                if day != Self.day() { await load(kind: kind, settings: settings, api: api); return }
                timetable = data
            case .meals:
                let data = try await api.meals(settings: settings)
                guard requestID == id, !Task.isCancelled else { return }
                if day != Self.day() { await load(kind: kind, settings: settings, api: api); return }
                meals = data
            }
            fetchedAt = Date()
            loading = false
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            self.error = (error as? URLError)?.code == .notConnectedToInternet
                ? "인터넷 연결을 확인한 뒤 다시 시도해 주세요." : error.localizedDescription
            loading = false
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = TodayModel()
    @State private var refresh = 0
    let kind: TodayKind
    let settings: SchoolSettings
    let api: SchoolAPI
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            Section {
                Text(settings.school.name).font(.title2.bold())
                Text(settings.schoolClass.label).foregroundStyle(.secondary)
                DemoNotice()
                if let date = model.timetable?.date ?? model.meals?.date { Text(date).font(.caption) }
            }
            if model.loading { Section { ProgressView("학교 정보를 불러오는 중") } }
            if let error = model.error {
                Section {
                    Label("학교 정보를 확인하지 못했어요", systemImage: "wifi.exclamationmark")
                    Text(error).foregroundStyle(.secondary)
                    Button("다시 시도") { refresh += 1 }
                }
            }
            if let timetable = model.timetable {
                Section("오늘 수업") {
                    if timetable.lessons.isEmpty {
                        Text("오늘 등록된 시간표가 없습니다.")
                        Text("주말·휴업일이거나 학교에서 아직 자료를 제공하지 않았을 수 있습니다.").font(.footnote)
                    }
                    ForEach(timetable.lessons.sorted { $0.period < $1.period }) { lesson in
                        HStack(spacing: 16) {
                            Text("\(lesson.period)").font(.title2.bold()).foregroundStyle(.indigo).frame(width: 28)
                            VStack(alignment: .leading) {
                                Text("\(lesson.period)교시").font(.caption).foregroundStyle(.secondary)
                                Text(lesson.subject).font(.headline)
                                if lesson.ambiguous == true { Text("선택 수업 · 학교 안내를 확인하세요").font(.caption) }
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
            if let meals = model.meals {
                if meals.meals.isEmpty {
                    Section("오늘 급식") { Text("오늘 등록된 급식이 없습니다."); Text("주말·공휴일·방학이거나 급식을 제공하지 않는 날일 수 있습니다.").font(.footnote) }
                }
                ForEach(meals.meals.sorted { (Int($0.code) ?? 0) < (Int($1.code) ?? 0) }) { meal in
                    Section(meal.name) {
                        ForEach(Array(meal.dishes.enumerated()), id: \.offset) { _, dish in Text(dish) }
                        if !meal.calories.isEmpty { Text(meal.calories).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle(kind == .timetable ? "오늘 시간표" : "오늘 급식")
        .toolbar { Button { refresh += 1 } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("새로고침").disabled(model.loading) }
        .refreshable { await model.load(kind: kind, settings: settings, api: api) }
        .task(id: refresh) { await model.load(kind: kind, settings: settings, api: api) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh += 1 } }
        .onChange(of: store.online) { _, online in if online && scenePhase == .active { refresh += 1 } }
        .onReceive(timer) { now in
            guard scenePhase == .active else { return }
            if model.requestedDay != TodayModel.day(now) {
                if store.online { refresh += 1 } else { model.clearYesterday() }
            } else if store.online, let fetchedAt = model.fetchedAt, now.timeIntervalSince(fetchedAt) >= 30 * 60 {
                refresh += 1
            }
        }
    }
}
