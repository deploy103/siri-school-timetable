import Foundation

struct SchoolEvent: Codable, Sendable {
    let name: String
    let content: String
    let lessonDayType: String
    let dayNightCourse: String
    let schoolCourse: String
    let gradeFlags: [String]
}

struct SchoolEventsDay: Codable, Sendable {
    struct SchoolInfo: Codable, Sendable { let name: String }
    let date: String
    let school: SchoolInfo
    let events: [SchoolEvent]

    /// Identity is the source position within this date, never the event name.
    var positionedEvents: [PositionedEvent] {
        events.enumerated().map { PositionedEvent(id: $0.offset, event: $0.element) }
    }
    struct PositionedEvent: Identifiable, Sendable {
        let id: Int
        let event: SchoolEvent
    }
}

#if canImport(SwiftUI)
import SwiftUI

struct SchoolEventsView: View {
    let settings: SchoolSettings
    let api: SchoolAPI
    @State private var day = SchoolCalendar.key()
    @State private var days: [SchoolEventsDay] = []
    @State private var loading = true
    @State private var error: String?
    @State private var retry = 0

    private var week: [String] { SchoolCalendar.week(containing: day) }
    private var requestID: String {
        "\(settings.school.id)|\(api.baseURL)|\(week.first ?? day)|\(retry)"
    }

    var body: some View {
        SchoolEditorPage {
            DemoNotice()
            VStack(alignment: .leading, spacing: 8) {
                Label("학교 학사일정 · NEIS", systemImage: "building.2").font(.headline)
                Text(settings.school.name)
                Text("직접 적은 수행평가·시험은 ‘준비’에서 확인해요.")
                Text("등교 여부와 변경 사항은 학교 안내를 확인해 주세요.")
            }.font(.subheadline).modifier(SchoolCard())
            SchoolDayHeader(day: $day)
            Text("선택한 날짜가 포함된 한 주").font(.headline)
            if loading {
                ProgressView("학교 학사일정을 불러오는 중")
            } else if let error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error)
                    Button("다시 시도") { retry += 1 }
                        .buttonStyle(SchoolSecondaryButtonStyle())
                }.modifier(SchoolCard())
            } else {
                ForEach(days, id: \.date) { entry in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(SchoolCalendar.label(entry.date)).font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("제공 학교: \(entry.school.name)").font(.caption)
                        if entry.events.isEmpty {
                            Text("등록된 학교 일정이 없습니다. 휴일 여부는 학교 안내를 확인해 주세요.")
                        }
                        ForEach(entry.positionedEvents) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.event.name).font(.headline)
                                if !item.event.content.isEmpty { Text(item.event.content) }
                                DisclosureGroup("NEIS 원문 적용 정보") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("수업일 구분: \(item.event.lessonDayType)")
                                        Text("주야 과정: \(item.event.dayNightCourse)")
                                        Text("학교 과정: \(item.event.schoolCourse)")
                                        Text("1–6학년 원문 값: \(item.event.gradeFlags.joined(separator: " / "))")
                                        Text("원문 값으로 적용 대상이나 등교 여부를 판단하지 않으며, 모든 일정을 표시합니다.")
                                    }.font(.caption)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(SchoolCard())
                }
            }
        }
        .navigationTitle("학교 학사일정").navigationBarTitleDisplayMode(.inline)
        .task(id: requestID) { await load() }
    }

    @MainActor private func load() async {
        let identity = requestID
        loading = true
        error = nil
        days = []
        do {
            guard let from = week.first, let to = week.last else { return }
            let result = try await api.schoolEvents(settings: settings, from: from, to: to)
            try Task.checkCancellation()
            guard identity == requestID else { return }
            days = result
            loading = false
        } catch {
            guard !Task.isCancelled, identity == requestID else { return }
            self.error = error.localizedDescription
            loading = false
        }
    }
}
#endif
