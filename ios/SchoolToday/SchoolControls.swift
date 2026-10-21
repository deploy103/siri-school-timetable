import SwiftUI

struct SchoolSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(SchoolDesign.blue)
            .background(SchoolDesign.blue.opacity(configuration.isPressed ? 0.18 : 0.08),
                        in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SchoolField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(SchoolDesign.ink)
            .padding(14)
            .frame(minHeight: 48)
            .background(SchoolDesign.canvas, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(SchoolDesign.blue.opacity(0.25), lineWidth: 1)
            }
    }
}

/// Place related fields in `VStack { ... }.modifier(SchoolCard())` inside this page.
struct SchoolEditorPage<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .frame(maxWidth: 600)
                .padding(20)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SchoolDesign.canvas.ignoresSafeArea())
        .foregroundStyle(SchoolDesign.ink)
        .tint(SchoolDesign.blue)
    }
}

struct SchoolDateButton: View {
    @Binding var day: String
    var label: String = "날짜 선택"
    var accessibilityIdentifier: String = "planner-date"
    @State private var showingCalendar = false

    var body: some View {
        Button { showingCalendar = true } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "calendar")
                    .font(.title2).foregroundStyle(SchoolDesign.blue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).font(.subheadline).foregroundStyle(.secondary)
                    Text(SchoolCalendar.label(day, format: "yyyy년 M월 d일 EEEE"))
                        .font(.headline).foregroundStyle(SchoolDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .foregroundStyle(SchoolDesign.blue).accessibilityHidden(true)
            }
            .modifier(SchoolCard())
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(SchoolCalendar.label(day, format: "yyyy년 M월 d일 EEEE"))
        .accessibilityIdentifier(accessibilityIdentifier)
        .sheet(isPresented: $showingCalendar) { SchoolCalendarSheet(day: $day) }
    }
}

struct SchoolDayHeader: View {
    @Binding var day: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var calendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(SchoolCalendar.label(day, format: "yyyy년"))
                        .font(.subheadline.bold()).foregroundStyle(SchoolDesign.blue)
                    Text(SchoolCalendar.label(day, format: "M월 d일 EEEE"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { calendar = true } label: {
                    Image(systemName: "calendar").font(.title3)
                        .frame(width: 48, height: 48)
                        .background(SchoolDesign.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                }.accessibilityLabel("날짜 선택").accessibilityIdentifier("planner-date")
            }
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    quickDay("오늘", key: SchoolCalendar.key(), identifier: "select-today")
                    quickDay("내일", key: SchoolCalendar.adding(1, to: SchoolCalendar.key())!, identifier: "select-tomorrow")
                    if !typeSize.isAccessibilitySize { arrows }
                }
                if typeSize.isAccessibilitySize { HStack { arrows } }
            }
        }
        .foregroundStyle(SchoolDesign.ink)
        .modifier(SchoolCard())
        .sheet(isPresented: $calendar) { SchoolCalendarSheet(day: $day) }
    }

    @ViewBuilder private var arrows: some View {
        Button { move(-1) } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 48) }
            .accessibilityLabel("이전 날")
        Button { move(1) } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 48) }
            .accessibilityLabel("다음 날")
    }

    private func move(_ amount: Int) {
        if let next = SchoolCalendar.adding(amount, to: day) { day = next }
    }

    private func quickDay(_ title: String, key: String, identifier: String) -> some View {
        Button { day = key } label: {
            Text(title).font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 48)
                .padding(.horizontal, 8)
                .foregroundStyle(day == key ? Color.white : SchoolDesign.blue)
                .background(day == key ? SchoolDesign.blue : Color.clear,
                            in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(day == key ? [.isSelected] : [])
    }
}

struct SchoolReminderEditor: View {
    @Binding var date: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SchoolDateButton(day: Binding(get: { SchoolCalendar.key(date) }, set: { key in
                if let day = SchoolCalendar.date(key) {
                    let time = SchoolCalendar.calendar.dateComponents([.hour, .minute], from: date)
                    date = SchoolCalendar.calendar.date(byAdding: .minute, value: (time.hour ?? 0) * 60 + (time.minute ?? 0), to: day)!
                }
            }), label: "알림 날짜", accessibilityIdentifier: "reminder-date")
            HStack {
                Image(systemName: "clock").foregroundStyle(SchoolDesign.blue)
                Text("알림 시각").font(.headline)
                Spacer()
                timeMenu(.hour, range: 0..<24, suffix: "시")
                timeMenu(.minute, range: 0..<60, suffix: "분")
            }.modifier(SchoolCard())
        }
    }
    private func timeMenu(_ component: Calendar.Component, range: Range<Int>, suffix: String) -> some View {
        Menu {
            ForEach(Array(range), id: \.self) { value in
                Button("\(value)\(suffix)") {
                    var parts = SchoolCalendar.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                    if component == .hour { parts.hour = value } else { parts.minute = value }
                    if let next = SchoolCalendar.calendar.date(from: parts) { date = next }
                }
            }
        } label: {
            Text(String(format: "%02d", SchoolCalendar.calendar.component(component, from: date)) + suffix)
                .font(.headline.monospacedDigit()).padding(12)
                .background(SchoolDesign.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }.accessibilityLabel(suffix == "시" ? "알림 시" : "알림 분")
    }
}

struct SchoolCalendarSheet: View {
    @Binding private var day: String
    @State private var selection: String
    @State private var month: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    init(day: Binding<String>) {
        _day = day
        let date = SchoolCalendar.date(day.wrappedValue) ?? Date()
        _selection = State(initialValue: SchoolCalendar.key(date))
        _month = State(initialValue: SchoolCalendar.calendar.dateInterval(of: .month, for: date)!.start)
    }

    private var monthDays: [String] {
        let calendar = SchoolCalendar.calendar
        return (calendar.range(of: .day, in: .month, for: month) ?? 1..<1).compactMap { number in
            calendar.date(byAdding: .day, value: number - 1, to: month).map(SchoolCalendar.key)
        }
    }

    private var leadingCells: Int { SchoolCalendar.calendar.component(.weekday, from: month) - 1 }

    var body: some View {
        SchoolEditorPage {
            Text("날짜 선택")
                .font(.system(.title, design: .rounded, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 18) {
                Text(SchoolCalendar.label(SchoolCalendar.key(month), format: "yyyy년 M월"))
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 12) {
                    Button { moveMonth(-1) } label: {
                        Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("이전 달")
                    Button { moveMonth(1) } label: {
                        Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("다음 달")
                }
                .buttonStyle(SchoolSecondaryButtonStyle())
                if typeSize.isAccessibilitySize {
                    // Full-width rows preserve readable dates and touch targets at large type.
                    LazyVStack(spacing: 8) {
                        ForEach(monthDays, id: \.self) { key in dateCell(key, expanded: true) }
                    }
                } else {
                    // Horizontal scrolling protects seven 44pt targets on narrow screens.
                    ScrollView(.horizontal) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 44), spacing: 2), count: 7), spacing: 8) {
                            ForEach(Array(["일", "월", "화", "수", "목", "금", "토"].enumerated()), id: \.offset) { index, title in
                                Text(title).font(.subheadline.bold())
                                    .foregroundStyle(index == 0 ? SchoolDesign.blue : SchoolDesign.ink)
                                    .frame(minHeight: 44).accessibilityHidden(true)
                            }
                            ForEach(0..<leadingCells, id: \.self) { _ in
                                Color.clear.frame(height: 44).accessibilityHidden(true)
                            }
                            ForEach(monthDays, id: \.self) { key in dateCell(key, expanded: false) }
                        }
                        .frame(minWidth: 320)
                    }
                }
            }
            .modifier(SchoolCard())
            Text("선택한 날짜: \(SchoolCalendar.label(selection, format: "yyyy년 M월 d일 EEEE"))")
                .font(.headline).fixedSize(horizontal: false, vertical: true)
            Button("이 날짜로 선택") {
                day = selection
                dismiss()
            }.buttonStyle(SchoolPrimaryButtonStyle())
            Button("취소") { dismiss() }.buttonStyle(SchoolSecondaryButtonStyle())
                .accessibilityIdentifier("calendar-cancel")
        }
    }

    private func moveMonth(_ amount: Int) {
        if let next = SchoolCalendar.calendar.date(byAdding: .month, value: amount, to: month) { month = next }
    }

    private func dateCell(_ key: String, expanded: Bool) -> some View {
        let selected = selection == key
        let today = key == SchoolCalendar.key()
        return Button { selection = key } label: {
            Text(SchoolCalendar.label(key, format: expanded ? "M월 d일 EEEE" : "d"))
                .font(.body.weight(selected ? .bold : .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, expanded ? 8 : 0)
                .foregroundStyle(selected ? Color.white : SchoolDesign.ink)
                .background(selected ? SchoolDesign.blue : SchoolDesign.canvas, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(today ? SchoolDesign.blue : Color.clear, lineWidth: 2)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SchoolCalendar.label(key, format: "yyyy년 M월 d일 EEEE"))
        .accessibilityValue(today ? "오늘" : "")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
