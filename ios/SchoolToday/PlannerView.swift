import SwiftUI
import Combine

struct SchoolDashboard: View {
    @EnvironmentObject private var schoolStore: SchoolStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var planner: PlannerStore
    @State private var tab = 0
    @State private var day = SchoolCalendar.key()
    @State private var currentDay = SchoolCalendar.key()
    @State private var refresh = 0
    @State private var siri = false
    @State private var editor: PreparationDraft?
    @State private var deletingTask: PreparationTask?
    @State private var correctingLesson: LessonCorrection?
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(settings: SchoolSettings, api: SchoolAPI, mode: String, directory: URL? = nil) {
        _planner = StateObject(wrappedValue: PlannerStore(settings: settings, api: api, mode: mode, directory: directory))
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                page("planner-today") {
                    datePicker
                    HStack {
                        Button { siri = true } label: { Label("Siri로 듣기", systemImage: "mic") }
                            .accessibilityIdentifier("siri-help")
                        Spacer()
                        NavigationLink { ShortcutCheckView() } label: { Text("실행 점검") }
                            .accessibilityIdentifier("shortcut-check")
                    }.font(.subheadline).frame(minHeight: 44)
                    preparationSummary
                    timetableCard
                    mealCard
                }
                .navigationTitle("오늘")
                .toolbar { settingsButton }
            }.tabItem { Label("오늘", systemImage: "sun.max") }.tag(0)
            NavigationStack {
                page("planner-week") {
                    weekNavigation
                    Text("수업을 누르면 준비물을 연결할 수 있어요.").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(SchoolCalendar.week(containing: day), id: \.self) { date in
                        VStack(alignment: .leading, spacing: 14) {
                            Button { day = date; tab = 0 } label: {
                                HStack {
                                    Text(SchoolCalendar.label(date, format: "M.d EEEE")).font(.headline)
                                    if date == SchoolCalendar.key() { Text("오늘").font(.caption.bold()) }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }.frame(minHeight: 44)
                            }.buttonStyle(.plain)
                            if let timetable = planner.timetable(on: date), !timetable.lessons.isEmpty {
                                ForEach(timetable.lessons.sorted { $0.period < $1.period }) { lesson in
                                    lessonButton(lesson, on: date)
                                }
                            } else {
                                Text("시간표 확인 필요 · 휴업일 또는 미게시일 수 있어요.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }.modifier(SchoolCard())
                    }
                }.navigationTitle("주간").toolbar { settingsButton }
            }.tabItem { Label("주간", systemImage: "calendar") }.tag(1)
            NavigationStack {
                page("planner-preparation") {
                    datePicker
                    preparationList
                    Button { editor = PreparationDraft(date: day) } label: {
                        Label("준비물·마감 추가", systemImage: "plus")
                    }.buttonStyle(SchoolPrimaryButtonStyle()).accessibilityIdentifier("add-preparation")
                    linkedSubjects
                    if !planner.tasks.isEmpty { savedTasks }
                }.navigationTitle("준비").toolbar { settingsButton }
            }.tabItem { Label("준비", systemImage: "checklist") }.tag(2)
        }
        .tint(SchoolDesign.blue)
        .environment(\.timeZone, SchoolCalendar.calendar.timeZone)
        .task(id: "\(SchoolCalendar.week(containing: day).first ?? day):\(refresh)") {
            await planner.refresh(containing: day)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { openNotificationDate(); refresh += 1 } }
        .onAppear(perform: openNotificationDate)
        .onReceive(NotificationCenter.default.publisher(for: .showSchoolPreparation)) { _ in openNotificationDate() }
        .onChange(of: schoolStore.online) { _, online in if online && scenePhase == .active { refresh += 1 } }
        .onReceive(timer) { now in
            guard scenePhase == .active else { return }
            let nextDay = SchoolCalendar.key(now)
            if nextDay != currentDay {
                if day == currentDay { day = nextDay }
                currentDay = nextDay
                if schoolStore.online { refresh += 1 }
            }
        }
        .onOpenURL { url in
            if url.scheme == "schooltoday", url.host == "today" { day = SchoolCalendar.key(); tab = 0 }
        }
        .sheet(isPresented: $siri) { NavigationStack { SiriGuideView(onboarding: false) } }
        .sheet(item: $editor) { draft in
            PreparationEditor(planner: planner, draft: draft)
        }
        .sheet(item: $correctingLesson) { correction in
            LessonCorrectionEditor(planner: planner, correction: correction, fixedPeriod: !correction.subject.isEmpty)
        }
        .confirmationDialog("이 일정을 삭제할까요?", isPresented: Binding(get: { deletingTask != nil }, set: { if !$0 { deletingTask = nil } }), titleVisibility: .visible) {
            if let task = deletingTask {
                Button("일정 삭제", role: .destructive) { try? planner.deleteTask(task); deletingTask = nil }
            }
        }
    }

    private func page<Content: View>(_ identifier: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(planner.settings.school.name).font(.headline)
                        Text(planner.settings.classLabel).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button { refresh += 1 } label: { Image(systemName: "arrow.clockwise") }
                        .frame(minWidth: 44, minHeight: 44).accessibilityLabel("새로고침").disabled(planner.loading)
                }
                DemoNotice()
                if planner.loading { ProgressView("학교 자료 확인 중") }
                if let error = planner.recordError { Text(error).font(.footnote).foregroundStyle(.red) }
                if let error = planner.reminderError { Text(error).font(.footnote).foregroundStyle(.red) }
                if let error = planner.timetableError {
                    Label(error, systemImage: "wifi.exclamationmark").font(.footnote).foregroundStyle(.secondary)
                    Button("다시 시도") { refresh += 1 }.frame(minHeight: 44)
                }
                content()
                Text("출처 NEIS · 학교에서 받은 자료를 기준으로 표시해요.")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: 600, alignment: .leading).padding(20).frame(maxWidth: .infinity)
        }
        .background(SchoolDesign.canvas)
        .accessibilityIdentifier(identifier)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await planner.refresh(containing: day) }
    }

    @ToolbarContentBuilder private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("설정").accessibilityIdentifier("open-settings")
        }
    }

    private var datePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Text(SchoolCalendar.label(day)).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 4) }
                DatePicker("날짜 선택", selection: Binding(get: { SchoolCalendar.date(day) ?? Date() }, set: { day = SchoolCalendar.key($0) }), displayedComponents: .date)
                    .labelsHidden().fixedSize().accessibilityIdentifier("planner-date")
            }
            HStack(spacing: 12) {
                Button("오늘") { day = SchoolCalendar.key() }
                    .accessibilityIdentifier("select-today")
                Button("내일") { day = SchoolCalendar.adding(1, to: SchoolCalendar.key())! }
                    .accessibilityIdentifier("select-tomorrow")
                Spacer()
                if !dynamicTypeSize.isAccessibilitySize { dayArrows }
            }.buttonStyle(.bordered).controlSize(.regular)
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) { dayArrows }.buttonStyle(.bordered)
            }
        }
    }
    @ViewBuilder private var dayArrows: some View {
        Button { day = SchoolCalendar.adding(-1, to: day)! } label: { Image(systemName: "chevron.left") }
            .accessibilityLabel("이전 날").frame(minWidth: 44, minHeight: 44)
        Button { day = SchoolCalendar.adding(1, to: day)! } label: { Image(systemName: "chevron.right") }
            .accessibilityLabel("다음 날").frame(minWidth: 44, minHeight: 44)
    }
    private var weekNavigation: some View {
        HStack {
            Button { day = SchoolCalendar.adding(-7, to: day)! } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("이전 주").frame(minWidth: 44, minHeight: 44)
            Spacer()
            Text("\(SchoolCalendar.label(SchoolCalendar.week(containing: day).first!, format: "M.d")) – \(SchoolCalendar.label(SchoolCalendar.week(containing: day).last!, format: "M.d"))")
                .font(.headline)
            Spacer()
            Button { day = SchoolCalendar.adding(7, to: day)! } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("다음 주").frame(minWidth: 44, minHeight: 44)
        }
    }
    private var preparationSummary: some View {
        let items = planner.occurrences(on: day)
        let remaining = items.filter { !$0.completed }.count
        return Button { tab = 2 } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("등교 준비", systemImage: "bag")
                    Spacer()
                    Image(systemName: "arrow.right")
                }.font(.headline)
                Text(items.isEmpty ? "준비물을 한 번 연결해 보세요" : (remaining == 0 ? "등록한 준비를 모두 마쳤어요" : "아직 \(remaining)개를 챙겨야 해요"))
                    .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                if !items.isEmpty {
                    Text("\(items.count - remaining)/\(items.count) 완료").font(.subheadline)
                }
                if planner.needsTimetableConfirmation(on: day) {
                    Text("시간표 확인 필요 · 자동 준비를 확정할 수 없어요").font(.footnote)
                }
            }.foregroundStyle(.white).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(SchoolDesign.hero, in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain).accessibilityIdentifier("preparation-summary")
    }
    private var timetableCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("시간표").font(.title3.bold())
            if let timetable = planner.timetable(on: day) {
                if timetable.lessons.isEmpty {
                    Text("등록된 시간표가 없어요.").font(.headline)
                    Text("휴업일이거나 아직 게시되지 않았을 수 있어요. 학교·반을 확인하거나 다시 불러와 주세요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(timetable.lessons.sorted { $0.period < $1.period }) { lesson in lessonButton(lesson, on: day) }
                if !timetable.missingPeriods.isEmpty {
                    Text("\(timetable.missingPeriods.map(String.init).joined(separator: ", "))교시 자료가 없어요. 수업 여부는 학교에 확인해요.")
                        .font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("missing-periods")
                }
            } else { Text("시간표 확인 필요").foregroundStyle(.secondary) }
            Text("수업을 길게 누르면 선택과목·교실을 수정해요.").font(.caption).foregroundStyle(.secondary)
            Button("수업 직접 추가") {
                correctingLesson = LessonCorrection(selection: planner.settings.planningKey, date: day, period: 1, subject: "", room: "")
            }.frame(minHeight: 44)
            if day == SchoolCalendar.key() {
                NavigationLink("시간표 읽기·공유") { TodayView(kind: .timetable, settings: planner.settings, api: planner.api) }
                    .frame(minHeight: 44)
            }
            checkedAt(planner.cache.timetableCheckedAt, failed: planner.timetableError != nil)
        }.modifier(SchoolCard())
    }
    private func lessonButton(_ lesson: Timetable.Lesson, on date: String) -> some View {
        Button { editor = PreparationDraft(date: date, subject: lesson.subject, automatic: lesson.ambiguous != true) } label: {
            HStack(alignment: .center, spacing: 14) {
                Text("\(lesson.period)").font(.headline).monospacedDigit().foregroundStyle(SchoolDesign.blue)
                    .frame(minWidth: 30, minHeight: 38)
                    .background(SchoolDesign.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.subject).font(.body.weight(.medium))
                    if let correction = planner.correction(on: date, period: lesson.period) {
                        Text("내 수정\(correction.room.isEmpty ? "" : " · \(correction.room)")").font(.caption).foregroundStyle(.secondary)
                    }
                    if lesson.ambiguous == true { Text("선택 수업 · 학교 확인 필요").font(.caption).foregroundStyle(.secondary) }
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "plus.circle").foregroundStyle(SchoolDesign.blue)
            }.frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(lesson.period)교시 \(lesson.subject), 준비물 추가")
            .contextMenu {
                Button("선택과목·교실 수정") {
                    correctingLesson = planner.correction(on: date, period: lesson.period) ?? LessonCorrection(selection: planner.settings.planningKey, date: date, period: lesson.period, subject: lesson.subject, room: "")
                }
            }
    }
    private var mealCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("급식", systemImage: "fork.knife").font(.title3.bold())
            if let error = planner.mealError { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if let meals = planner.meals(on: day) {
                if meals.meals.isEmpty { Text("등록된 급식이 없어요. 급식이 없는 날이거나 미게시일 수 있어요.").foregroundStyle(.secondary) }
                ForEach(meals.meals) { meal in
                    DisclosureGroup {
                        ForEach(Array(meal.dishes.enumerated()), id: \.offset) { _, dish in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(dish)
                                if let allergens = MealAllergens.description(for: dish) {
                                    Text("알레르기: \(allergens)").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 4)
                        }
                        if !meal.calories.isEmpty { Text(meal.calories).font(.caption) }
                        if let nutrition = meal.nutrition { Text(nutrition).font(.footnote) }
                        if let origin = meal.origin { Text(origin).font(.footnote) }
                        Text("표시가 없어도 알레르기 성분이 있을 수 있어요. 식사 전 영양 선생님께 확인해요.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meal.name).font(.headline)
                            Text(meal.dishes.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.padding(.vertical, 6)
                    }
                }
            } else { Text("급식 자료 확인 필요").foregroundStyle(.secondary) }
            if day == SchoolCalendar.key() {
                NavigationLink("급식 읽기·공유·알레르기 안내") { TodayView(kind: .meals, settings: planner.settings, api: planner.api) }
                    .frame(minHeight: 44)
            }
            checkedAt(planner.cache.mealCheckedAt, failed: planner.mealError != nil)
        }.modifier(SchoolCard())
    }
    private func checkedAt(_ date: Date?, failed: Bool) -> some View {
        Group {
            if let date {
                Text("\(failed || !schoolStore.online ? "마지막으로 받은 자료" : "마지막 확인") \(SchoolCalendar.label(SchoolCalendar.key(date), format: "M.d")) \(date.formatted(date: .omitted, time: .shortened))\(failed ? " · 최신 여부 확인 필요" : "")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var preparationList: some View {
        let items = planner.occurrences(on: day)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("챙길 것").font(.title3.bold())
                Spacer()
                Text("\(items.filter(\.completed).count)/\(items.count)").font(.subheadline).foregroundStyle(.secondary)
            }
            if planner.needsTimetableConfirmation(on: day) {
                Label("시간표 확인 필요 · 자동 준비를 확정할 수 없어요. 직접 적은 항목은 아래에 표시합니다.", systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text("아직 등록한 준비가 없어요.").font(.headline)
                Text("수업에서 준비물을 한 번 연결하거나, 날짜를 골라 직접 적어 보세요.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                Button { planner.toggle(item) } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(item.completed ? SchoolDesign.blue : .secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).strikethrough(item.completed)
                            if !item.subject.isEmpty {
                                Text("\(item.subject)\(item.automatic ? " · 수업에 자동 연결" : "")").font(.caption).foregroundStyle(.secondary)
                            }
                        }.fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(item.title)
                    .accessibilityValue(item.completed ? "완료" : "미완료")
            }
        }.modifier(SchoolCard())
    }
    private var linkedSubjects: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("수업에 연결한 준비").font(.headline)
            Text("한 과목은 계속 무료 · 받은 시간표 기준").font(.footnote).foregroundStyle(.secondary)
            ForEach(planner.rules) { rule in
                Button { editor = PreparationDraft(date: day, subject: rule.subject, automatic: true, items: rule.items.joined(separator: ", ")) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(rule.subject).font(.headline)
                            Text(rule.items.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "pencil")
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
            Text("여러 과목 자동 연결과 마감 준비 단계는 Plus로 준비 중이에요. 아직 결제를 받지 않습니다.")
                .font(.footnote).foregroundStyle(.secondary)
        }.modifier(SchoolCard())
    }
    private var savedTasks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("직접 등록한 일정").font(.headline)
            ForEach(planner.tasks.sorted { $0.date < $1.date }) { task in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                        if let reminder = task.reminder { Text("알림 \(reminder.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        Text("\(SchoolCalendar.label(task.date, format: "M.d E")) · \(task.kind == .deadline ? "마감" : "준비물")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) { deletingTask = task } label: { Image(systemName: "trash") }
                        .frame(minWidth: 44, minHeight: 44).accessibilityLabel("\(task.title) 삭제")
                }
            }
        }.modifier(SchoolCard())
    }
    private func openNotificationDate() {
        guard let value = UserDefaults.standard.string(forKey: "schooltoday.pending-preparation-date") else { return }
        UserDefaults.standard.removeObject(forKey: "schooltoday.pending-preparation-date")
        if SchoolCalendar.date(value) != nil { day = value; tab = 2 }
    }
}

private struct PreparationDraft: Identifiable {
    let id = UUID()
    var date: String
    var subject = ""
    var automatic = false
    var items = ""
}

private struct PreparationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var planner: PlannerStore
    @State var draft: PreparationDraft
    @State private var title = ""
    @State private var kind: PreparationTask.Kind = .item
    @State private var error: String?
    @State private var delete = false
    @State private var remind = false
    @State private var reminder = Date().addingTimeInterval(60 * 60)
    @State private var saving = false

    private var existingRule: PreparationRule? { planner.rules.first { $0.subject == draft.subject } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("과목 (선택)", text: $draft.subject).accessibilityIdentifier("preparation-subject")
                    Toggle("수업이 있는 날마다 자동 준비", isOn: $draft.automatic)
                        .accessibilityIdentifier("preparation-automatic")
                } footer: {
                    Text("자동 연결 한 과목은 계속 무료예요. 자료가 없는 날짜는 시간표 확인이 필요합니다.")
                }
                if draft.automatic {
                    Section("준비물") {
                        TextField("체육복, 교재, 충전기", text: $draft.items, axis: .vertical)
                            .accessibilityIdentifier("preparation-items")
                        Text("쉼표로 나눠 입력해요.").font(.footnote).foregroundStyle(.secondary)
                        quickItems
                    }
                    let dates = planner.cache.timetables.compactMap { planner.timetable(on: $0.date) }.filter { day in day.lessons.contains { PreparationPlan.subjectKey($0.subject) == PreparationPlan.subjectKey(draft.subject) && $0.ambiguous != true } }.map(\.date).sorted()
                    Section("받은 시간표에 적용되는 날짜") {
                        if dates.isEmpty { Text("아직 적용 날짜를 확인하지 못했어요. 시간표를 새로 받으면 다시 계산해요.") }
                        ForEach(dates, id: \.self) { date in Text(SchoolCalendar.label(date)) }
                    }
                } else {
                    Section {
                        Picker("종류", selection: $kind) {
                            Text("준비물").tag(PreparationTask.Kind.item)
                            Text("과제·시험 마감").tag(PreparationTask.Kind.deadline)
                        }
                        TextField("챙길 것 또는 마감 제목", text: $title).accessibilityIdentifier("preparation-title")
                        DatePicker("날짜", selection: Binding(get: { SchoolCalendar.date(draft.date) ?? Date() }, set: { draft.date = SchoolCalendar.key($0) }), displayedComponents: .date)
                    }
                    Section {
                        Toggle("이 일정 알림 받기", isOn: $remind)
                        if remind { DatePicker("알림 시각", selection: $reminder, in: Date()...) }
                    } footer: {
                        Text("일정당 한 번, 선택한 시각에 알려요. 잠금 화면에 제목이 보일 수 있으며 실제 전달은 iPhone 알림·집중 모드 설정에 따라 달라져요.")
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("preparation-error") } }
                if let rule = existingRule, draft.automatic {
                    Section { Button("자동 연결 삭제", role: .destructive) { delete = true } }
                        .confirmationDialog("연결을 삭제할까요? 직접 적은 일정은 유지돼요.", isPresented: $delete, titleVisibility: .visible) {
                            Button("연결 삭제", role: .destructive) {
                                do { try planner.deleteRule(rule); dismiss() } catch { self.error = error.localizedDescription }
                            }
                        }
                }
                Section {
                    Text("기록은 이 기기에 저장됩니다. 앱 삭제·기기 변경 시 자동 복원되지 않아요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("준비 추가").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("저장") { Task { await save() } }.bold().disabled(saving || planner.storageBlocked).accessibilityIdentifier("save-preparation") }
            }
            .onAppear { if let rule = existingRule, draft.items.isEmpty { draft.items = rule.items.joined(separator: ", ") } }
        }
    }
    private var quickItems: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
            ForEach(["체육복", "교재", "노트북", "충전기", "랜선"], id: \.self) { item in
                Button {
                    let values = draft.items.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    if !values.contains(item) { draft.items += draft.items.trimmingCharacters(in: .whitespaces).isEmpty ? item : ", \(item)" }
                } label: {
                    Text(item).frame(maxWidth: .infinity, minHeight: 44)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.bordered)
            }
        }
    }
    private func save() async {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            if draft.automatic { try planner.addRule(subject: draft.subject, items: draft.items.components(separatedBy: ",")) }
            else {
                let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { throw SchoolError.message("챙길 것 또는 마감 제목을 입력해 주세요.") }
                if remind {
                    guard try await PreparationNotifications.shared.authorize() else {
                        throw SchoolError.message("알림이 꺼져 있어요. iPhone 설정에서 허용하거나 알림을 끄고 저장해 주세요.")
                    }
                }
                try planner.addTask(PreparationTask(selection: planner.settings.planningKey, title: title, date: draft.date, subject: draft.subject, kind: kind, reminder: remind ? reminder : nil))
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct LessonCorrectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var planner: PlannerStore
    @State var correction: LessonCorrection
    let fixedPeriod: Bool
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(SchoolCalendar.label(correction.date))
                    if fixedPeriod { Text("\(correction.period)교시") }
                    else {
                        Stepper("\(correction.period)교시", value: Binding(get: { correction.period }, set: {
                            correction = LessonCorrection(selection: correction.selection, date: correction.date, period: $0, subject: correction.subject, room: correction.room)
                        }), in: 1...20)
                    }
                    TextField("실제 수업 과목", text: $correction.subject)
                    TextField("교실 (선택)", text: $correction.room)
                } footer: {
                    Text("이 날짜·교시에만 적용합니다. 학교의 원본 자료는 바꾸지 않아요. 직접 수정한 과목으로 준비물을 연결할 수 있습니다.\n\n내 수정은 앱과 위젯에 적용해요. Siri·읽기·공유는 학교 원본 자료를 사용합니다.")
                }
                if planner.correction(on: correction.date, period: correction.period) != nil {
                    Section {
                        Button("학교 자료로 되돌리기", role: .destructive) {
                            do { try planner.removeCorrection(correction); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("내 수업 수정").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        correction.subject = PreparationPlan.subjectKey(correction.subject)
                        do { try planner.correct(correction); dismiss() } catch { self.error = error.localizedDescription }
                    }.disabled(planner.storageBlocked)
                }
            }
        }
    }
}
