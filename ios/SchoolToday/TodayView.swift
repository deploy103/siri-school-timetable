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

    func shareText(settings: SchoolSettings, mock: Bool) -> String? {
        guard !loading, error == nil,
              let date = timetable?.date ?? meals?.date,
              let summary = timetable?.summary ?? meals?.summary else { return nil }
        let notice = mock ? "예제 데이터 · 실제 학교 자료가 아닙니다\n" : ""
        return "\(notice)\(settings.school.name)\n\(settings.classLabel)\n\(date)\n\n\(summary)\n\n출처: NEIS · 오늘의 학교"
    }

    func clearYesterday() {
        requestID = UUID()
        timetable = nil; meals = nil; loading = false
        fetchedAt = nil
        error = "인터넷 연결을 확인한 뒤 다시 시도해 주세요."
        requestedDay = Self.day()
    }

    func load(kind: TodayKind, settings: SchoolSettings, api: SchoolAPI) async {
        let id = UUID()
        requestID = id
        let day = Self.day()
        requestedDay = day
        loading = true; error = nil; timetable = nil; meals = nil
        fetchedAt = nil
        defer { if requestID == id { loading = false } }
        do {
            switch kind {
            case .timetable:
                let data = try await api.timetable(settings: settings)
                guard requestID == id, !Task.isCancelled else { return }
                if day != Self.day() { await load(kind: kind, settings: settings, api: api); return }
                guard data.date == day else {
                    throw SchoolError.message("오늘 날짜의 시간표가 아닙니다. 잠시 뒤 새로고침해 주세요.")
                }
                timetable = data
            case .meals:
                let data = try await api.meals(settings: settings)
                guard requestID == id, !Task.isCancelled else { return }
                if day != Self.day() { await load(kind: kind, settings: settings, api: api); return }
                guard data.date == day else {
                    throw SchoolError.message("오늘 날짜의 급식이 아닙니다. 잠시 뒤 새로고침해 주세요.")
                }
                meals = data
            }
            fetchedAt = Date()
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            self.error = (error as? URLError)?.code == .notConnectedToInternet
                ? "인터넷 연결을 확인한 뒤 다시 시도해 주세요." : error.localizedDescription
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = TodayModel()
    @State private var refresh = 0
    @State private var showAllergens = false
    let kind: TodayKind
    let settings: SchoolSettings
    let api: SchoolAPI
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(kind == .timetable ? "오늘의\n시간표" : "오늘의\n급식").font(.largeTitle.bold())
                VStack(alignment: .leading, spacing: 8) {
                    Text(settings.school.name).font(.headline)
                    Text(settings.classLabel).foregroundStyle(.secondary)
                    DemoNotice()
                    if let date = model.timetable?.date ?? model.meals?.date { Text(date).font(.caption) }
                    if let fetchedAt = model.fetchedAt {
                        Text("마지막 확인 \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.modifier(SchoolCard())
                if model.loading { ProgressView("학교 정보를 불러오는 중") }
                if let error = model.error {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("학교 정보를 확인하지 못했어요", systemImage: "wifi.exclamationmark").font(.headline)
                        Text(error).foregroundStyle(.secondary)
                        Button("다시 시도") { refresh += 1 }
                    }.modifier(SchoolCard())
                }
                if let timetable = model.timetable {
                    if timetable.lessons.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("오늘 등록된 시간표가 없습니다.").font(.headline)
                            Text("휴업일이거나 자료가 아직 없을 수 있어요.").font(.footnote).foregroundStyle(.secondary)
                        }.modifier(SchoolCard())
                    }
                    if !timetable.missingPeriods.isEmpty {
                        Text("\(timetable.missingPeriods.map(String.init).joined(separator: ", "))교시 자료가 없어요. 수업 여부는 학교에 확인해요.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("missing-periods")
                    }
                    ForEach(timetable.lessons.sorted { $0.period < $1.period }) { lesson in
                        HStack(spacing: 18) {
                            Text("\(lesson.period)").font(.title2.bold()).foregroundStyle(SchoolDesign.blue).frame(width: 32)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(lesson.period)교시").font(.caption).foregroundStyle(.secondary)
                                Text(lesson.subject).font(.headline)
                                if lesson.ambiguous == true { Text("선택 수업 · 학교 안내를 확인하세요").font(.caption) }
                            }
                        }.modifier(SchoolCard())
                    }
                }
                if let meals = model.meals {
                    if meals.meals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("오늘 등록된 급식이 없습니다.").font(.headline)
                            Text("급식이 없는 날이거나 자료가 아직 없을 수 있어요.").font(.footnote).foregroundStyle(.secondary)
                        }.modifier(SchoolCard())
                    }
                    if !meals.meals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Button("알레르기 번호 안내") { showAllergens = true }
                                .accessibilityIdentifier("meal-allergens")
                            Text("표시가 없어도 알레르기 성분이 있을 수 있어요. 식사 전 영양 선생님께 확인해요.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }.modifier(SchoolCard())
                    }
                    ForEach(meals.meals.sorted { (Int($0.code) ?? 0) < (Int($1.code) ?? 0) }) { meal in
                        VStack(alignment: .leading, spacing: 14) {
                            Text(meal.name).font(.title3.bold()).foregroundStyle(SchoolDesign.blue)
                            ForEach(Array(meal.dishes.enumerated()), id: \.offset) { _, dish in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(dish)
                                    if let allergens = MealAllergens.description(for: dish) {
                                        Text("알레르기: \(allergens)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            if !meal.calories.isEmpty { Text(meal.calories).font(.caption).foregroundStyle(.secondary) }
                            if let nutrition = meal.nutrition, !nutrition.isEmpty {
                                DisclosureGroup("영양 정보") { Text(nutrition).font(.footnote).padding(.top, 8) }
                            }
                            if let origin = meal.origin, !origin.isEmpty {
                                DisclosureGroup("원산지 정보") { Text(origin).font(.footnote).padding(.top, 8) }
                            }
                        }.modifier(SchoolCard())
                    }
                }
                if let shareText = model.shareText(settings: settings, mock: store.mode == "mock") {
                    TodayActions(kind: kind, settings: settings, api: api, shareText: shareText)
                }
            }.padding(24)
        }
        .background(SchoolDesign.canvas)
        .navigationTitle(kind == .timetable ? "오늘 시간표" : "오늘 급식")
        .navigationBarTitleDisplayMode(.inline)
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
        .sheet(isPresented: $showAllergens) {
            NavigationStack {
                List {
                    Section {
                        Text("학교가 표시한 번호의 뜻이에요. 표시가 없어도 안전한 건 아니에요. 식사 전 영양 선생님께 확인해요.")
                    }
                    Section("알레르기 유발 식품 19종") {
                        ForEach(Array(MealAllergens.names.enumerated()), id: \.offset) { index, name in
                            Text("\(index + 1). \(name)")
                        }
                    }
                }
                .navigationTitle("알레르기 번호 안내").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("닫기") { showAllergens = false } }
            }
        }
    }
}
