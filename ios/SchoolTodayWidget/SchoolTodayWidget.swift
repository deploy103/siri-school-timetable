import SwiftUI
import WidgetKit

private struct SchoolEntry: TimelineEntry {
    let date: Date
    let cache: SchoolWeekCache?
}

private struct SchoolProvider: TimelineProvider {
    func placeholder(in context: Context) -> SchoolEntry { SchoolEntry(date: Date(), cache: nil) }
    func getSnapshot(in context: Context, completion: @escaping (SchoolEntry) -> Void) {
        completion(SchoolEntry(date: Date(), cache: SchoolWidgetCache.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SchoolEntry>) -> Void) {
        let now = Date()
        let cache = SchoolWidgetCache.read()
        var entries = [SchoolEntry(date: now, cache: cache)]
        // Midnight entries select the correct stored day even when the OS delays a refresh.
        for offset in 1...7 {
            if let key = SchoolCalendar.adding(offset, to: SchoolCalendar.key(now)), let date = SchoolCalendar.date(key) {
                entries.append(SchoolEntry(date: date, cache: cache))
            }
        }
        if let end = cache?.preparationUntil, end > now, !entries.contains(where: { $0.date == end }) {
            entries.append(SchoolEntry(date: end, cache: cache))
        }
        completion(Timeline(entries: entries.sorted { $0.date < $1.date }, policy: .after(now.addingTimeInterval(60 * 60))))
    }
}

private struct SchoolWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SchoolEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(SchoolCalendar.label(SchoolCalendar.key(entry.date), format: "M.d E"), systemImage: "calendar")
                    .font(.caption.bold())
                Spacer(minLength: 0)
                if entry.cache?.mode == "mock" { Text("예제").font(.caption2) }
            }
            if let cache = entry.cache {
                if family == .systemMedium {
                    HStack(alignment: .top, spacing: 18) {
                        timetable(cache).frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                        VStack(alignment: .leading, spacing: 6) {
                            Text("급식").font(.headline)
                            if let meals = cache.meals.first(where: { $0.date == SchoolCalendar.key(entry.date) }), !meals.meals.isEmpty {
                                Text(meals.meals.map { $0.dishes.joined(separator: " · ") }.joined(separator: "\n"))
                                    .font(.caption).lineLimit(4)
                            } else { Text("급식 확인 필요").font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else { timetable(cache) }
                Spacer(minLength: 0)
                if family == .systemMedium {
                    Text("확인 · 시간표 \(cache.timetableCheckedAt.map { SchoolCalendar.label(SchoolCalendar.key($0), format: "M.d") } ?? "미확인") · 급식 \(cache.mealCheckedAt.map { SchoolCalendar.label(SchoolCalendar.key($0), format: "M.d") } ?? "미확인")")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("받은 자료 · \(cache.timetableCheckedAt.map { SchoolCalendar.label(SchoolCalendar.key($0), format: "M.d") } ?? "미확인")")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("내 학교를 연결해 주세요").font(.headline)
                Text("앱에서 시간표·급식을 받으면 여기에 표시돼요.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .containerBackground(for: .widget) { Color(uiColor: .secondarySystemGroupedBackground) }
        .widgetURL(URL(string: "schooltoday://today"))
        .accessibilityElement(children: .combine)
    }
    private func timetable(_ cache: SchoolWeekCache) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(cache.correctedDates.contains(SchoolCalendar.key(entry.date)) ? "시간표 · 내 수정" : "시간표").font(.headline)
            if let timetable = cache.timetables.first(where: { $0.date == SchoolCalendar.key(entry.date) }), !timetable.lessons.isEmpty {
                ForEach(timetable.lessons.sorted { $0.period < $1.period }.prefix(3)) { lesson in
                    HStack(spacing: 6) {
                        Text("\(lesson.period)").fontWeight(.bold)
                        Text(lesson.subject).lineLimit(1)
                    }.font(.caption)
                }
                if timetable.lessons.count > 3 { Text("외 \(timetable.lessons.count - 3)개 수업").font(.caption2).foregroundStyle(.secondary) }
            } else { Text("시간표 확인 필요").font(.caption) }
        }
    }
}

struct SchoolTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SchoolDayWidget", provider: SchoolProvider()) { SchoolWidgetView(entry: $0) }
            .configurationDisplayName("학교 시간표·급식")
            .description("마지막으로 받은 오늘 자료를 봅니다. 갱신 시점은 시스템과 앱 사용에 따라 달라져요.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SchoolPreparationWidgetView: View {
    let entry: SchoolEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("등교 준비", systemImage: "bag").font(.headline)
            Text(SchoolCalendar.label(SchoolCalendar.key(entry.date), format: "M.d EEEE")).font(.caption).foregroundStyle(.secondary)
            if let cache = entry.cache, cache.preparationUntil.map({ entry.date < $0 }) ?? true,
               let preparation = cache.preparation {
                let items = preparation[SchoolCalendar.key(entry.date)] ?? []
                Text("\(items.filter(\.completed).count)/\(items.count) 완료").font(.headline)
                ForEach(items.prefix(3)) { item in
                    Label(item.title, systemImage: item.completed ? "checkmark.circle.fill" : "circle")
                        .font(.caption).lineLimit(1)
                }
                if items.isEmpty { Text("앱에서 시간표와 준비를 확인해요.").font(.caption) }
            } else {
                Text("앱의 준비 설정에서 Plus와 개인 내용 표시를 확인해 주세요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .containerBackground(for: .widget) { Color(uiColor: .secondarySystemGroupedBackground) }
        .widgetURL(URL(string: "schooltoday://preparation"))
    }
}

private struct SchoolPreparationWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SchoolPreparationWidget", provider: SchoolProvider()) { SchoolPreparationWidgetView(entry: $0) }
            .configurationDisplayName("나만의 등교 준비")
            .description("Plus에서 개인 내용 표시를 켠 경우에만 준비물·마감을 표시합니다.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct SchoolWidgets: WidgetBundle {
    var body: some Widget {
        SchoolTodayWidget()
        SchoolPreparationWidget()
    }
}
