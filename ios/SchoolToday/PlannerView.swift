import SwiftUI
import Combine

struct SchoolDashboard: View {
    @EnvironmentObject private var schoolStore: SchoolStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var planner: PlannerStore
    @ObservedObject private var plus = PlusStore.shared
    @State private var tab = 0
    @State private var preparationMode = 0
    @State private var day = SchoolCalendar.key()
    @State private var currentDay = SchoolCalendar.key()
    @State private var now = Date()
    @State private var refresh = 0
    @State private var siri = false
    @State private var editor: PreparationDraft?
    @State private var deletingTask: PreparationTask?
    @State private var deletionError: String?
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
                    NavigationLink {
                        SchoolEventsView(settings: planner.settings, api: planner.api)
                    } label: {
                        Label("학교 학사일정", systemImage: "calendar.badge.clock")
                    }.buttonStyle(SchoolSecondaryButtonStyle()).accessibilityIdentifier("school-calendar")
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
                    Picker("준비 보기", selection: $preparationMode) {
                        Text("다가오는 일정").tag(0)
                        Text("날짜별 준비").tag(1)
                    }.pickerStyle(.segmented)
                    Button { editor = PreparationDraft(date: preparationMode == 0 ? SchoolCalendar.key(now) : day) } label: {
                        Label("일정 추가", systemImage: "plus")
                    }.buttonStyle(SchoolPrimaryButtonStyle()).accessibilityIdentifier("add-preparation")
                    if preparationMode == 0 { upcomingTasks }
                    else {
                        datePicker
                        preparationList
                    }
                    linkedSubjects
                }.navigationTitle("준비").toolbar { settingsButton }
            }.tabItem { Label("준비", systemImage: "checklist") }.tag(2)
        }
        .tint(SchoolDesign.blue)
        .task(id: "\(SchoolCalendar.week(containing: day).first ?? day):\(refresh)") {
            await planner.refresh(containing: day)
        }
        .task { await plus.refresh(); planner.updateAccess(plus.isPlus, until: plus.validUntil) }
        .onChange(of: plus.isPlus) { _, enabled in planner.updateAccess(enabled, until: plus.validUntil) }
        .onChange(of: plus.validUntil) { _, until in planner.updateAccess(plus.isPlus, until: until) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { openNotificationDate(); refresh += 1; Task { await plus.refresh() } }
        }
        .onAppear(perform: openNotificationDate)
        .onReceive(NotificationCenter.default.publisher(for: .showSchoolPreparation)) { _ in openNotificationDate() }
        .onChange(of: schoolStore.online) { _, online in if online && scenePhase == .active { refresh += 1 } }
        .onReceive(timer) { now in
            guard scenePhase == .active else { return }
            self.now = now
            Task { await plus.refresh() }
            let nextDay = SchoolCalendar.key(now)
            if nextDay != currentDay {
                if day == currentDay { day = nextDay }
                currentDay = nextDay
                if schoolStore.online { refresh += 1 }
            }
        }
        .onOpenURL { url in
            if url.scheme == "schooltoday", url.host == "today" { day = SchoolCalendar.key(); tab = 0 }
            if url.scheme == "schooltoday", url.host == "preparation" { day = SchoolCalendar.key(); tab = 2 }
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
                Button("일정 삭제", role: .destructive) {
                    do { try planner.deleteTask(task); deletingTask = nil }
                    catch { deletionError = error.localizedDescription }
                }
            }
        }
        .alert("일정을 삭제하지 못했어요", isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
            Button("확인") { deletionError = nil }
        } message: { Text(deletionError ?? "") }
        .environment(\.timeZone, SchoolCalendar.calendar.timeZone)
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
                Text("시간표·급식 출처 NEIS · 준비 일정·과목 수정은 직접 기록한 내용이에요.")
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
            NavigationLink { SettingsView(planner: planner) } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("설정").accessibilityIdentifier("open-settings")
        }
    }

    private var datePicker: some View {
        SchoolDayHeader(day: $day)
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
        }.modifier(SchoolCard())
    }
    private var preparationSummary: some View {
        let items = planner.occurrences(on: day)
        let remaining = items.filter { !$0.completed }.count
        return Button { preparationMode = 1; tab = 2 } label: {
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
            if let status = planner.plan.lessonStatus(selection: planner.settings.planningKey, timetable: planner.timetable(on: day), now: now) {
                Label(status, systemImage: "clock.fill")
                    .font(.headline).foregroundStyle(SchoolDesign.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            Text(planner.plusEnabled ? "Plus · 여러 과목 자동 준비" : "한 과목은 계속 무료 · 받은 시간표 기준").font(.footnote).foregroundStyle(.secondary)
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
                if !planner.plusEnabled, let first = planner.rules.first, first.id != rule.id {
                    Button("이 과목을 무료 자동 준비로 사용") { try? planner.useFreeRule(rule) }
                        .buttonStyle(SchoolSecondaryButtonStyle())
                    Text("기록은 보존되며 지금은 자동 연결이 일시 중지된 과목이에요.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !planner.plusEnabled { NavigationLink("Plus · 여러 과목과 마감 준비") { PlusView() } }
        }.modifier(SchoolCard())
    }
    private var upcomingTasks: some View {
        let incomplete = planner.plan.scheduledTasks(selection: planner.settings.planningKey)
        let completed = planner.plan.scheduledTasks(selection: planner.settings.planningKey, completed: true)
        return VStack(alignment: .leading, spacing: 16) {
            Text("직접 기록한 일정").font(.title3.bold())
            Text("수행평가·시험·숙제를 적어 두세요. 학교 자료를 받지 못해도 확인할 수 있어요.")
                .font(.footnote).foregroundStyle(.secondary)
            if incomplete.isEmpty {
                Text(completed.isEmpty ? "직접 적은 일정이 없어요." : "등록한 미완료 일정이 없어요.").font(.headline)
            } else {
                ForEach(PreparationTask.ScheduleGroup.allCases, id: \.self) { group in
                    let tasks = incomplete.filter { $0.scheduleGroup(relativeTo: now) == group }
                    if !tasks.isEmpty {
                        if group == .later {
                            DisclosureGroup("이후 일정 · \(tasks.count)개") { taskRows(tasks) }
                        } else {
                            Text("\(group.rawValue) · \(tasks.count)개").font(.headline).padding(.top, 8)
                            taskRows(tasks)
                        }
                    }
                }
                if !incomplete.contains(where: { $0.scheduleGroup(relativeTo: now) == .today || $0.scheduleGroup(relativeTo: now) == .week }) {
                    Text("오늘부터 앞으로 7일 안에 등록한 일정이 없어요.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !completed.isEmpty {
                DisclosureGroup("완료한 일정 · \(completed.count)개") { taskRows(completed) }
            }
        }.modifier(SchoolCard())
    }
    private func taskRows(_ tasks: [PreparationTask]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(tasks) { task in
                let completed = planner.plan.completed.contains(task.completionID)
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        planner.toggle(PreparationOccurrence(id: task.completionID, title: task.title, subject: task.subject, date: task.date, automatic: false, completed: completed))
                    } label: {
                        Image(systemName: completed ? "checkmark.circle.fill" : "circle").font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain).foregroundStyle(SchoolDesign.blue)
                        .accessibilityLabel("\(task.title) \(completed ? "완료 취소" : "완료로 표시")")
                    VStack(alignment: .leading, spacing: 4) {
                        Button { editor = PreparationDraft(date: task.date, subject: task.subject, task: task) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(task.title).font(.headline).strikethrough(completed)
                                Text([task.kindLabel, task.subject, completed ? "완료" : task.relativeDate(to: now)].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(SchoolCalendar.label(task.date)).font(.caption).foregroundStyle(.secondary)
                                if let notes = task.notes, !notes.isEmpty { Text(notes).font(.footnote).lineLimit(3) }
                            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(task.title) 일정 수정")
                            .accessibilityValue([task.kindLabel, task.subject, completed ? "완료" : task.relativeDate(to: now), SchoolCalendar.label(task.date), task.notes ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        if let reminder = task.reminder { Text("알림 \(reminder.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                        let stages = planner.plan.stages.filter { $0.taskID == task.id }
                        ForEach(stages) { stage in
                            Text("\(SchoolCalendar.label(stage.date, format: "M.d")) · \(stage.title)\(planner.plan.completed.contains("stage:\(stage.id.uuidString)") ? " · 완료" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button(role: .destructive) { deletingTask = task } label: { Image(systemName: "trash") }
                        .frame(minWidth: 44, minHeight: 44).accessibilityLabel("\(task.title) 삭제")
                }
            }
        }
    }
    private func openNotificationDate() {
        guard let value = UserDefaults.standard.string(forKey: "schooltoday.pending-preparation-date") else { return }
        UserDefaults.standard.removeObject(forKey: "schooltoday.pending-preparation-date")
        if SchoolCalendar.date(value) != nil { day = value; preparationMode = 1; tab = 2 }
    }
}

private struct PreparationDraft: Identifiable {
    let id = UUID()
    var date: String
    var subject = ""
    var automatic = false
    var items = ""
    var task: PreparationTask? = nil
}

private struct PreparationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var planner: PlannerStore
    @State var draft: PreparationDraft
    @State private var title = ""
    @State private var kind: PreparationTask.Kind = .item
    @State private var category: PreparationTask.Category?
    @State private var notes = ""
    @State private var error: String?
    @State private var delete = false
    @State private var remind = false
    @State private var reminder = Date().addingTimeInterval(60 * 60)
    @State private var saving = false
    @State private var extraReminders: [Date] = []
    @State private var stages: [PreparationStage] = []
    @State private var taskID = UUID()
    @State private var showingPlus = false
    @State private var initialized = false
    @State private var notificationDenied = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case title, subject, notes, items, stage(UUID) }

    private var existingRule: PreparationRule? { planner.rules.first { $0.subject == draft.subject } }
    var body: some View {
        NavigationStack {
            SchoolEditorPage {
                if draft.automatic {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("수업과 연결하기", systemImage: "books.vertical").font(.headline)
                        TextField("과목 (선택)", text: $draft.subject).modifier(SchoolField()).accessibilityIdentifier("preparation-subject")
                            .focused($focusedField, equals: .subject).submitLabel(.next)
                            .onSubmit { focusedField = .items }
                        Toggle("수업이 있는 날마다 자동 준비", isOn: $draft.automatic)
                            .accessibilityIdentifier("preparation-automatic")
                        Text("자동 연결 한 과목은 계속 무료예요. 자료가 없는 날짜는 시간표 확인이 필요합니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.modifier(SchoolCard())
                    VStack(alignment: .leading, spacing: 16) {
                        Text("무엇을 챙길까요?").font(.title3.bold())
                        TextField("체육복, 교재, 충전기", text: $draft.items, axis: .vertical)
                            .modifier(SchoolField()).accessibilityIdentifier("preparation-items")
                            .focused($focusedField, equals: .items)
                        Text("쉼표로 나눠 입력해요.").font(.footnote).foregroundStyle(.secondary)
                        quickItems
                    }.modifier(SchoolCard())
                    let dates = planner.cache.timetables.compactMap { planner.timetable(on: $0.date) }.filter { day in day.lessons.contains { PreparationPlan.subjectKey($0.subject) == PreparationPlan.subjectKey(draft.subject) && $0.ambiguous != true } }.map(\.date).sorted()
                    VStack(alignment: .leading, spacing: 14) {
                        Label("받은 시간표에 적용되는 날짜", systemImage: "calendar.badge.checkmark").font(.headline)
                        if dates.isEmpty { Text("아직 적용 날짜를 확인하지 못했어요. 시간표를 새로 받으면 다시 계산해요.") }
                        ForEach(dates, id: \.self) { date in Text(SchoolCalendar.label(date)) }
                    }.modifier(SchoolCard())
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("직접 챙길 일정").font(.title3.bold())
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                            kindButton("준비물", value: .item)
                            ForEach(PreparationTask.Category.allCases, id: \.self) { value in
                                kindButton(value.label, value: .deadline, category: value)
                            }
                            if draft.task?.kind == .deadline && draft.task?.category == nil {
                                kindButton("마감", value: .deadline)
                            }
                        }
                        TextField("제목 (예: 영어 발표)", text: $title).modifier(SchoolField()).accessibilityIdentifier("preparation-title")
                            .focused($focusedField, equals: .title).submitLabel(.next)
                            .onSubmit { focusedField = .subject }
                    }.modifier(SchoolCard())
                    SchoolDateButton(day: $draft.date, label: dateLabel, accessibilityIdentifier: "preparation-date")
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("과목 (선택)", text: $draft.subject).modifier(SchoolField()).accessibilityIdentifier("preparation-subject")
                            .focused($focusedField, equals: .subject).submitLabel(.next)
                            .onSubmit { focusedField = .notes }
                        TextField("메모 (범위·제출 방법·챙길 것, 2,000자까지)", text: $notes, axis: .vertical)
                            .lineLimit(3...8).modifier(SchoolField()).accessibilityIdentifier("preparation-notes")
                            .focused($focusedField, equals: .notes)
                        Text("직접 기록 · 학교가 제공한 공식 평가 일정이 아니에요.").font(.footnote).foregroundStyle(.secondary)
                    }.modifier(SchoolCard())
                    VStack(alignment: .leading, spacing: 14) {
                        Label("필요한 때만 알림", systemImage: "bell").font(.headline)
                        Toggle("이 일정 알림 받기", isOn: $remind)
                        Text("기본 알림은 한 번 무료예요. 알림 제목은 잠금 화면에 보일 수 있고 집중 모드에 따라 전달이 달라져요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.modifier(SchoolCard())
                    if remind {
                        SchoolReminderEditor(date: $reminder)
                        ForEach(extraReminders.indices, id: \.self) { index in
                            VStack(spacing: 8) {
                                SchoolReminderEditor(date: $extraReminders[index])
                                Button("추가 알림 삭제", role: .destructive) { extraReminders.remove(at: index) }.frame(minHeight: 44)
                            }
                        }
                        Button("사전 알림 추가 · Plus") {
                            extraReminders.append(Date().addingTimeInterval(7200))
                        }.buttonStyle(SchoolSecondaryButtonStyle())
                    }
                    if kind == .deadline {
                        DisclosureGroup("추가 준비 기능 · Plus") { deadlineStages }
                            .modifier(SchoolCard())
                    }
                    if draft.task == nil {
                        Button("준비물을 수업에 자동 연결") { draft.automatic = true }
                            .buttonStyle(SchoolSecondaryButtonStyle())
                    }
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("preparation-error") }
                if notificationDenied {
                    Button("알림 없이 저장") {
                        remind = false
                        extraReminders = []
                        for index in stages.indices { stages[index].reminder = nil }
                        Task { await save() }
                    }.buttonStyle(SchoolSecondaryButtonStyle()).disabled(saving || planner.storageBlocked)
                }
                if let rule = existingRule, draft.automatic {
                    Button("자동 연결 삭제", role: .destructive) { delete = true }.frame(minHeight: 44)
                        .confirmationDialog("연결을 삭제할까요? 직접 적은 일정은 유지돼요.", isPresented: $delete, titleVisibility: .visible) {
                            Button("연결 삭제", role: .destructive) {
                                do { try planner.deleteRule(rule); dismiss() } catch { self.error = error.localizedDescription }
                            }
                        }
                }
                Text("기록은 이 기기에 보관해요. 설정의 백업·iCloud 동기화로 직접 이전할 수 있으며 구입 복원은 개인 기록을 복원하지 않아요.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(saving ? "저장 중…" : "일정 저장") { Task { await save() } }
                    .buttonStyle(SchoolPrimaryButtonStyle()).disabled(saving || planner.storageBlocked)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil {
                    Button { focusedField = nil } label: {
                        Text("입력 완료")
                            .foregroundStyle(SchoolDesign.blue)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                            .padding(.horizontal, 24).padding(.vertical, 8)
                            .background(SchoolDesign.canvas)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("preparation-input-done")
                }
            }
            .navigationTitle(draft.task == nil ? "준비 추가" : "일정 수정").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) { Button("저장") { Task { await save() } }.bold().disabled(saving || planner.storageBlocked).accessibilityIdentifier("save-preparation") }
            }
            .interactiveDismissDisabled(saving)
            .onAppear {
                guard !initialized else { return }; initialized = true
                if let rule = existingRule, draft.items.isEmpty { draft.items = rule.items.joined(separator: ", ") }
                if let task = draft.task {
                    taskID = task.id; title = task.title; kind = task.kind
                    category = task.category; notes = task.notes ?? ""
                    remind = task.reminder != nil
                    if let date = task.reminder { reminder = date }
                    extraReminders = task.extraReminders ?? []
                    stages = planner.plan.stages.filter { $0.taskID == task.id }
                }
            }
            .sheet(isPresented: $showingPlus) {
                PlusView(onActivated: { planner.updateAccess(PlusStore.shared.isPlus, until: PlusStore.shared.validUntil); Task { await save() } })
            }
            .environment(\.timeZone, SchoolCalendar.calendar.timeZone)
        }
    }
    private var dateLabel: String {
        switch category {
        case .assessment: return "평가 날짜"
        case .exam: return "시험 날짜"
        case .homework: return "제출 날짜"
        case nil: return kind == .deadline ? "마감 날짜" : "준비 날짜"
        }
    }
    private func kindButton(_ text: String, value: PreparationTask.Kind, category choice: PreparationTask.Category? = nil) -> some View {
        let selected = kind == value && category == choice
        return Button { kind = value; category = choice } label: {
            Text(text).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(selected ? .white : SchoolDesign.blue)
                .background(selected ? SchoolDesign.blue : SchoolDesign.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private var deadlineStages: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("마감 준비 단계 · Plus", systemImage: "checklist").font(.headline)
            Text("제안을 넣은 뒤 필요한 단계와 날짜만 남겨요. 저장 전까지 알림을 예약하지 않습니다.").font(.footnote).foregroundStyle(.secondary)
            ForEach(DeadlineTemplate.allCases) { template in
                Button("\(template.rawValue) 단계 제안") {
                    let task = PreparationTask(id: taskID, selection: planner.settings.planningKey, title: title, date: draft.date, kind: .deadline)
                    stages = template.stages(for: task)
                }.buttonStyle(SchoolSecondaryButtonStyle())
            }
            ForEach($stages) { $stage in
                VStack(alignment: .leading, spacing: 12) {
                    TextField("준비 단계", text: $stage.title).modifier(SchoolField())
                        .focused($focusedField, equals: .stage(stage.id))
                    SchoolDateButton(day: $stage.date, label: "준비할 날짜", accessibilityIdentifier: "stage-date")
                    Toggle("이 단계 알림", isOn: Binding(get: { stage.reminder != nil }, set: { enabled in
                        stage.reminder = enabled ? Date().addingTimeInterval(3600) : nil
                    }))
                    if stage.reminder != nil {
                        SchoolReminderEditor(date: Binding(get: { stage.reminder ?? Date() }, set: { stage.reminder = $0 }))
                    }
                    Button("단계 삭제", role: .destructive) { stages.removeAll { $0.id == stage.id } }.frame(minHeight: 44)
                }.padding(12).background(SchoolDesign.canvas, in: RoundedRectangle(cornerRadius: 16))
            }
        }.modifier(SchoolCard())
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
                .buttonStyle(SchoolSecondaryButtonStyle())
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
                guard !title.isEmpty else { throw SchoolError.message("제목을 입력해 주세요.") }
                guard notes.count <= 2000 else { throw SchoolError.message("메모는 2,000자까지 입력해 주세요.") }
                let activeStages = kind == .deadline ? stages : []
                let oldStages = planner.plan.stages.filter { $0.taskID == taskID }
                if !planner.plusEnabled && ((!activeStages.isEmpty && activeStages != oldStages) || (remind && !extraReminders.isEmpty && extraReminders != (draft.task?.extraReminders ?? []))) { throw PlannerAccessError.plusRequired }
                let task = PreparationTask(id: taskID, selection: planner.settings.planningKey, title: title, date: draft.date, subject: draft.subject.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind, reminder: remind ? reminder : nil, extraReminders: remind ? extraReminders : [], category: kind == .deadline ? category : nil, notes: notes.isEmpty ? nil : notes)
                let pending = PreparationPlan(tasks: [task], completed: planner.plan.completed, stages: activeStages).notices(
                    selection: planner.settings.planningKey, cache: nil, plus: planner.plusEnabled,
                    after: Date(), plusUntil: PlusStore.shared.validUntil, limit: 1)
                if !pending.isEmpty {
                    guard try await PreparationNotifications.shared.authorize() else {
                        notificationDenied = true
                        throw SchoolError.message("알림이 꺼져 있어요. 입력한 내용은 그대로예요. 알림 없이 저장하거나 iPhone 설정에서 허용해 주세요.")
                    }
                }
                try planner.addTask(task, stages: activeStages)
            }
            dismiss()
        } catch is PlannerAccessError { showingPlus = true }
        catch { self.error = error.localizedDescription }
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
            SchoolEditorPage {
                VStack(alignment: .leading, spacing: 18) {
                    Label(SchoolCalendar.label(correction.date), systemImage: "calendar").font(.headline)
                    if fixedPeriod { Text("\(correction.period)교시") }
                    else {
                        Stepper("\(correction.period)교시", value: Binding(get: { correction.period }, set: {
                            correction = LessonCorrection(selection: correction.selection, date: correction.date, period: $0, subject: correction.subject, room: correction.room)
                        }), in: 1...20)
                    }
                    TextField("실제 수업 과목", text: $correction.subject).modifier(SchoolField())
                    TextField("교실 (선택)", text: $correction.room).modifier(SchoolField())
                }.modifier(SchoolCard())
                Text("이 날짜·교시에만 적용합니다. 학교의 원본 자료는 바꾸지 않아요. 직접 수정한 과목으로 준비물을 연결할 수 있습니다.\n\n내 수정은 앱과 위젯에 적용해요. Siri·읽기·공유는 학교 원본 자료를 사용합니다.")
                    .font(.footnote).foregroundStyle(.secondary).modifier(SchoolCard())
                if planner.correction(on: correction.date, period: correction.period) != nil {
                    Button("학교 자료로 되돌리기", role: .destructive) {
                        do { try planner.removeCorrection(correction); dismiss() } catch { self.error = error.localizedDescription }
                    }.frame(minHeight: 44)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("이 수업으로 적용", action: apply).buttonStyle(SchoolPrimaryButtonStyle()).disabled(planner.storageBlocked)
            }
            .navigationTitle("내 수업 수정").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용", action: apply).disabled(planner.storageBlocked)
                }
            }
        }
    }
    private func apply() {
        correction.subject = PreparationPlan.subjectKey(correction.subject)
        do { try planner.correct(correction); dismiss() } catch { self.error = error.localizedDescription }
    }
}
