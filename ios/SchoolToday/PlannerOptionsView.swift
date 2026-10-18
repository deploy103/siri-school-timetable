import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct PlannerOptionsView: View {
    @ObservedObject var planner: PlannerStore
    @ObservedObject private var plus = PlusStore.shared
    @ObservedObject private var cloud = PlannerCloud.shared
    @State private var showingPlus = false
    @State private var evening = false
    @State private var morning = false
    @State private var eveningMinute = 20 * 60
    @State private var morningMinute = 7 * 60
    @State private var paused = false
    @State private var pauseDay = SchoolCalendar.key()
    @State private var saving = false
    @State private var message: String?
    @State private var document: PlannerBackupDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var preview: ImportPreview?
    @State private var confirmImport = false
    @State private var conflict: PlannerCloud.Conflict?
    @State private var reset: BaselineReset?
    @State private var confirmReset = false
    @State private var syncing = false
    @State private var showingTransfer = false
    @State private var bellTimes: [SchoolBellTime] = []

    private var blocked: Bool { planner.storageBlocked || syncing || saving }

    var body: some View {
        SchoolEditorPage {
            Text("준비 설정").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("알림은 현재 선택한 학교·학년·반에만 적용돼요.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14) {
                Label("오늘의 학교 Plus", systemImage: "sparkles").font(.title2.bold())
                Text(plus.isPlus ? "확인된 Plus 구독을 이용 중이에요." : "요약 알림과 나만의 준비 위젯을 만나 보세요.")
                Button("Plus 보기 · 구입 복원") { showingPlus = true }
                    .buttonStyle(SchoolSecondaryButtonStyle())
                Text("구입 복원은 구독 이용 권한만 복원해요. 개인 준비 기록은 아래 JSON 백업이나 iCloud 동기화로 별도로 복원해야 해요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.modifier(SchoolCard())
            alertsCard
            bellTimesCard
            widgetCard
            backupCard
            cloudCard
            VStack(alignment: .leading, spacing: 14) {
                Label("이전 학교의 과목 규칙", systemImage: "arrow.triangle.branch").font(.headline)
                Text("가져올 규칙을 고르고 새 과목명을 직접 연결해요. 기존 규칙과 현재 학교 선택은 바뀌지 않아요.")
                Button("규칙 선택하기") { showingTransfer = true }
                    .buttonStyle(SchoolSecondaryButtonStyle()).disabled(blocked)
            }.modifier(SchoolCard())
            if planner.storageBlocked {
                Text("저장된 원본을 읽지 못해 보호 중이에요. 백업 복원과 동기화로도 원본을 덮어쓰지 않습니다.")
                    .foregroundStyle(.red)
            }
            if let message { Text(message).font(.callout).accessibilityIdentifier("planner-options-status") }
        }
        .navigationTitle("준비 설정")
        .onAppear { loadPreference(); planner.updateAccess(plus.isPlus, until: plus.validUntil) }
        .onChange(of: plus.isPlus) { _, value in planner.updateAccess(value, until: plus.validUntil) }
        .onChange(of: planner.settings.planningKey) { _, _ in loadPreference() }
        .sheet(isPresented: $showingPlus) { PlusView() }
        .sheet(isPresented: $showingTransfer) { PlannerRuleTransferView(planner: planner) }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "school-preparation-backup") { result in
            switch result {
            case .success: message = "JSON 백업을 내보냈어요. 개인 기록이므로 안전한 곳에 보관해 주세요."
            case .failure: message = "백업을 내보내지 못했어요. 저장 위치를 확인해 주세요."
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            readImport(result)
        }
        .confirmationDialog("현재 기록을 백업 파일로 교체할까요?", isPresented: $confirmImport,
                            titleVisibility: .visible) {
            Button("현재 기록을 교체", role: .destructive) { applyImport() }
        } message: {
            Text("모든 학교의 준비 기록이 교체됩니다. 교체 직전 원본은 기기 안에 별도로 백업됩니다.")
        }
        .confirmationDialog("동기화 기준을 초기화할까요?", isPresented: $confirmReset,
                            titleVisibility: .visible) {
            Button("기준만 초기화", role: .destructive) { clearBaseline() }
        } message: {
            Text("개인 기록은 지금 변경하지 않아요. 초기화 후 자동 재시도하지 않으며, 다시 동기화 버튼을 눌러야 합니다.")
        }
    }

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("등교 준비 알림", systemImage: "bell.badge").font(.title2.bold())
            Toggle("저녁 준비 요약", isOn: gated($evening))
            if evening { PlannerMinuteControl(title: "저녁 시각", minute: $eveningMinute) }
            Toggle("아침에 한 번 더 확인", isOn: gated($morning))
            if morning { PlannerMinuteControl(title: "아침 시각", minute: $morningMinute) }
            Toggle("잠시 쉬기", isOn: $paused)
            if paused {
                SchoolDateButton(day: $pauseDay, label: "이 날짜까지 알림 쉬기",
                                 accessibilityIdentifier: "preparation-pause-date")
            }
            Text("선택한 시각은 한국 시간 기준이며, 쉬는 날짜까지 요약·재확인 알림을 보내지 않아요.")
                .font(.footnote).foregroundStyle(.secondary)
            Button(saving ? "저장 중…" : "알림 설정 저장") { Task { await saveAlerts() } }
                .buttonStyle(SchoolPrimaryButtonStyle()).disabled(blocked)
        }.modifier(SchoolCard())
    }

    private var widgetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("나만의 준비 위젯", systemImage: "rectangle.3.group").font(.headline)
            Toggle("개인 준비 내용 표시", isOn: Binding(
                get: { planner.preference.privateWidget },
                set: { enabled in
                    guard !enabled || plus.isPlus else { showingPlus = true; return }
                    var preference = planner.preference
                    preference.privateWidget = enabled
                    do { try planner.setPreference(preference) }
                    catch { message = "위젯 설정을 저장하지 못했어요. 원본과 저장 공간을 확인해 주세요." }
                }))
                .disabled(blocked)
            Text("켜면 준비물·과제 등 개인 내용이 홈 화면 위젯에 나타나 주변 사람에게 보일 수 있어요. 기본은 꺼짐이며 언제든 끌 수 있어요. 위젯 내용은 현재 학교 기록에서 만들어집니다.")
                .font(.footnote).foregroundStyle(.secondary)
        }.modifier(SchoolCard())
    }

    private var bellTimesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("우리 반 종 시간", systemImage: "clock").font(.title2.bold())
            Text("직접 확인한 한국 시각을 입력하면 오늘 시간표에 현재·다음 수업을 표시해요. 학교 종 시간을 자동으로 추측하지 않습니다. 무료로 이용할 수 있어요.")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach($bellTimes) { $time in
                VStack(alignment: .leading, spacing: 12) {
                    Stepper("\(time.period)교시", value: $time.period, in: 1...20)
                    PlannerMinuteControl(title: "수업 시작", minute: $time.startMinute)
                    PlannerMinuteControl(title: "수업 종료", minute: $time.endMinute)
                    Button("이 교시 삭제", role: .destructive) { bellTimes.removeAll { $0.id == time.id } }
                        .frame(minHeight: 44)
                }.padding(14).background(SchoolDesign.canvas, in: RoundedRectangle(cornerRadius: 16))
            }
            Button("교시 추가") {
                let period = (1...20).first { number in !bellTimes.contains { $0.period == number } } ?? 20
                let start = min(23 * 60, (bellTimes.last?.endMinute ?? (9 * 60 - 10)) + 10)
                bellTimes.append(SchoolBellTime(period: period, startMinute: start, endMinute: min(1439, start + 50)))
            }.buttonStyle(SchoolSecondaryButtonStyle()).disabled(blocked || bellTimes.count >= 20)
            Button("종 시간 저장") {
                do {
                    var value = planner.preference
                    value.bellTimes = bellTimes.sorted { $0.period < $1.period }
                    guard PreparationPlan.validBellTimes(bellTimes) else {
                        message = "교시는 중복 없이, 시작은 종료보다 빠르게 입력해 주세요. 앞 수업이 끝나기 전에 다음 수업을 시작할 수 없어요."; return
                    }
                    try planner.setPreference(value)
                    message = "종 시간을 저장했어요. 오늘 시간표에 적용됩니다."
                } catch { message = "종 시간을 저장하지 못했어요. 기록과 저장 공간을 확인해 주세요." }
            }.buttonStyle(SchoolPrimaryButtonStyle()).disabled(blocked)
        }.modifier(SchoolCard())
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("무료 JSON 백업", systemImage: "externaldrive").font(.title2.bold())
            Text("모든 학교의 규칙·과제·단계·완료 기록을 포함하는 schema 2 파일이에요. 최대 256 KiB이며 구독 없이 이용할 수 있어요.")
            Button("백업 내보내기") {
                do { document = try PlannerBackupDocument(plan: planner.plan); exporting = true }
                catch { message = "백업을 만들지 못했어요. 기록 형식과 256 KiB 크기 제한을 확인해 주세요." }
            }.buttonStyle(SchoolSecondaryButtonStyle()).disabled(blocked)
            Button("백업 파일 선택") { importing = true }
                .buttonStyle(SchoolSecondaryButtonStyle()).disabled(blocked)
            if let preview {
                Text("선택한 파일: \(counts(preview.plan))").font(.headline)
                Text("현재 기기: \(counts(planner.plan))").font(.subheadline)
                Button("내용 확인 완료 · 교체하기", role: .destructive) { confirmImport = true }
                    .buttonStyle(SchoolSecondaryButtonStyle()).disabled(blocked)
                Button("선택 취소") { self.preview = nil }
            }
        }.modifier(SchoolCard())
    }

    private var cloudCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("iCloud 개인 기록", systemImage: "icloud").font(.title2.bold())
            Text("이 버튼을 누를 때만 iCloud 비공개 데이터베이스와 통신해요. 자동 동기화나 자동 병합은 하지 않아요.")
            Button(syncing ? "동기화 중…" : "지금 동기화") { Task { await synchronize() } }
                .buttonStyle(SchoolPrimaryButtonStyle()).disabled(blocked || cloud.busy)
            if let conflict {
                Text("양쪽 기록이 달라요. 한쪽 전체를 직접 선택해 주세요.").font(.headline)
                Text("이 기기: \(counts(conflict.local))\niCloud: \(counts(conflict.remote))")
                Text("선택하지 않은 쪽은 교체됩니다. 기기 원본은 적용 전에 로컬 백업됩니다. 이 기기를 선택하면 iCloud 기록도 교체됩니다.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("이 기기 기록 유지", role: .destructive) { Task { await resolve(conflict, choice: .local) } }
                    .buttonStyle(SchoolSecondaryButtonStyle()).disabled(blocked || cloud.busy)
                Button("iCloud 기록 사용", role: .destructive) { Task { await resolve(conflict, choice: .remote) } }
                    .buttonStyle(SchoolSecondaryButtonStyle()).disabled(blocked || cloud.busy)
                Button("선택 취소") { self.conflict = nil }
            }
            if let reset {
                Text(reset == .account ? "iCloud 계정이 바뀌었어요. 새 계정 사용을 확인하려면 기준을 초기화해 주세요." : "이전 iCloud 기록이 없어졌어요. 기록을 다시 만들려면 먼저 기준 초기화를 확인해 주세요.")
                Button("기준 초기화 확인") { confirmReset = true }
                    .buttonStyle(SchoolSecondaryButtonStyle()).disabled(blocked)
            }
        }.modifier(SchoolCard())
    }

    private func gated(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue }, set: { value in
            if value && !plus.isPlus { showingPlus = true } else { binding.wrappedValue = value }
        })
    }

    private func loadPreference() {
        let value = planner.preference
        evening = value.eveningMinute != nil; morning = value.morningMinute != nil
        eveningMinute = value.eveningMinute ?? 1200; morningMinute = value.morningMinute ?? 420
        paused = value.pausedUntil != nil; pauseDay = value.pausedUntil ?? SchoolCalendar.key()
        bellTimes = value.bellTimes ?? []
    }

    private func saveAlerts() async {
        guard !blocked else { return }
        guard !(evening || morning) || plus.isPlus else { showingPlus = true; return }
        let original = planner.preference
        var value = original
        value.eveningMinute = evening ? eveningMinute : nil
        value.morningMinute = morning ? morningMinute : nil
        value.pausedUntil = paused ? pauseDay : nil
        saving = true
        defer { saving = false }
        do {
            if evening || morning {
                guard try await PreparationNotifications.shared.authorize() else {
                    message = "알림 권한이 꺼져 있어요. iPhone 설정에서 허용한 뒤 다시 저장해 주세요."; return
                }
            }
            guard planner.preference == original, value.selection == planner.settings.planningKey else {
                message = "설정이 변경됐어요. 다시 확인하고 저장해 주세요."; return
            }
            guard !(evening || morning) || plus.isPlus else { showingPlus = true; return }
            try planner.setPreference(value)
            message = "알림 설정을 저장했어요."
        } catch { message = "알림 설정을 저장하지 못했어요. 권한과 저장 공간을 확인해 주세요." }
    }

    private func readImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: PlannerBackupDocument.limit + 1) ?? Data()
            let plan = try PlannerBackupDocument.decode(data)
            preview = ImportPreview(plan: plan, original: planner.plan)
            message = "파일을 검증했어요. 개수를 확인한 뒤 교체를 직접 승인해 주세요."
        } catch { message = "백업을 읽지 못했어요. schema 2 JSON 파일과 256 KiB 제한을 확인해 주세요. 기록은 변경하지 않았어요." }
    }

    private func applyImport() {
        guard let preview, !blocked else { return }
        do {
            try planner.replacePlan(preview.plan, expected: preview.original)
            self.preview = nil; loadPreference(); message = "원본을 기기에 백업하고 기록을 복원했어요."
        } catch { message = "복원하지 못했어요. 파일 선택 이후 기록이 바뀌었거나 원본을 보호 중일 수 있어요. 다시 선택해 주세요." }
    }

    private func synchronize() async {
        guard !blocked, !cloud.busy else { return }
        syncing = true; conflict = nil; reset = nil
        defer { syncing = false }
        let original = planner.plan
        do {
            let baseline = try planner.cloudBaseline()
            let result = try await cloud.synchronize(local: original, base: baseline.data, expectedAccount: baseline.account)
            try apply(result, expected: original)
        } catch { handleCloud(error) }
    }

    private func resolve(_ conflict: PlannerCloud.Conflict, choice: PlannerCloud.Choice) async {
        guard !blocked, !cloud.busy else { return }
        guard planner.plan == conflict.local else {
            self.conflict = nil; message = "선택을 기다리는 동안 기기 기록이 바뀌었어요. 다시 동기화해 주세요."; return
        }
        syncing = true
        defer { syncing = false }
        do {
            let result = try await cloud.resolve(conflict, choosing: choice)
            try apply(result, expected: conflict.local)
            self.conflict = nil
        } catch { self.conflict = nil; handleCloud(error) }
    }

    private func apply(_ result: PlannerCloud.SyncResult, expected: PreparationPlan) throws {
        try planner.replacePlan(result.plan, expected: expected)
        try planner.saveCloudBaseline(data: result.base, account: result.account)
        loadPreference(); message = "준비 기록을 동기화했어요."
    }

    private func handleCloud(_ error: Error) {
        if let value = error as? PlannerCloud.Conflict {
            guard planner.plan == value.local else { message = "기기 기록이 바뀌었어요. 다시 동기화해 주세요."; return }
            conflict = value; message = "두 기록의 개수를 확인하고 사용할 쪽을 선택해 주세요."
        } else if let failure = error as? PlannerCloud.Failure {
            switch failure {
            case .accountChanged: reset = .account
            case .remoteMissing: reset = .missing
            default: break
            }
            message = failure.errorDescription
        } else {
            message = "동기화를 완료하지 못했어요. 기기 기록이 바뀌었거나 연결·저장에 문제가 있을 수 있어요. 현재 기록을 확인한 뒤 다시 시도해 주세요."
        }
    }

    private func clearBaseline() {
        guard let reset, !blocked else { return }
        do {
            let account: String?
            if reset == .account { account = nil } else { account = try planner.cloudBaseline().account }
            try planner.saveCloudBaseline(data: nil, account: account)
            self.reset = nil; conflict = nil
            message = "기준만 초기화했어요. 원할 때 지금 동기화를 다시 눌러 주세요."
        } catch { message = "동기화 기준을 저장하지 못했어요. 저장 공간을 확인해 주세요." }
    }

    private func counts(_ plan: PreparationPlan) -> String {
        "규칙 \(plan.rules.count) · 과제 \(plan.tasks.count) · 단계 \(plan.stages.count)"
    }

    private struct ImportPreview { let plan: PreparationPlan; let original: PreparationPlan }
    private enum BaselineReset { case account, missing }
}

private struct PlannerMinuteControl: View {
    let title: String
    @Binding var minute: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            HStack {
                Menu {
                    ForEach(0..<24, id: \.self) { hour in
                        Button("\(hour)시") { minute = hour * 60 + minute % 60 }
                    }
                } label: { Text("\(minute / 60)시").frame(maxWidth: .infinity, minHeight: 48) }
                Menu {
                    ForEach(0..<60, id: \.self) { value in
                        Button("\(value)분") { minute = minute / 60 * 60 + value }
                    }
                } label: { Text(String(format: "%02d분", minute % 60)).frame(maxWidth: .infinity, minHeight: 48) }
            }
            .font(.headline).foregroundStyle(SchoolDesign.blue)
            .background(SchoolDesign.blue.opacity(0.08), in: Capsule())
        }
    }
}

private struct PlannerBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static let limit = 256 * 1024
    var data: Data

    init(plan: PreparationPlan) throws {
        try plan.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = try encoder.encode(plan)
        guard data.count <= Self.limit else { throw CocoaError(.fileReadTooLarge) }
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        _ = try Self.decode(data)
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    static func decode(_ data: Data) throws -> PreparationPlan {
        guard data.count <= limit,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int, version == 2 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let plan = try JSONDecoder().decode(PreparationPlan.self, from: data)
        try plan.validate()
        let known = Set(["version", "rules", "tasks", "completed", "corrections", "stages", "preferences"])
        guard Set(object.keys).isSubset(of: known) else { throw CocoaError(.fileReadCorruptFile) }
        return plan
    }
}

@MainActor
private struct PlannerRuleTransferView: View {
    @ObservedObject var planner: PlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var selected: Set<UUID> = []
    @State private var subjects: [UUID: String] = [:]
    @State private var message: String?
    private var sources: [String] {
        Set(planner.plan.rules.map(\.selection).filter { $0 != planner.settings.planningKey }).sorted()
    }
    private var rules: [PreparationRule] { planner.plan.rules.filter { $0.selection == source } }

    var body: some View {
        NavigationStack {
            SchoolEditorPage {
                Text("과목 규칙 가져오기").font(.title.bold())
                Text("원본은 그대로 두고 현재 학교에 복사해요. 같은 새 과목의 규칙이 이미 있으면 건너뜁니다. 과목명은 자동으로 연결하지 않아요.")
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sources, id: \.self) { value in
                        Button {
                            source = value; selected = []; subjects = [:]
                        } label: {
                            Label(selectionLabel(value), systemImage: source == value ? "checkmark.circle.fill" : "circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(SchoolSecondaryButtonStyle())
                    }
                    if sources.isEmpty { Text("다른 학교·반의 규칙이 아직 없어요.") }
                }.modifier(SchoolCard())
                ForEach(rules) { rule in
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("\(rule.subject) · 준비물 \(rule.items.count)개", isOn: Binding(
                            get: { selected.contains(rule.id) },
                            set: { if $0 { selected.insert(rule.id) } else { selected.remove(rule.id) } }))
                        TextField("연결할 새 과목명 직접 입력", text: Binding(
                            get: { subjects[rule.id] ?? "" }, set: { subjects[rule.id] = $0 }))
                            .modifier(SchoolField())
                    }.modifier(SchoolCard())
                }
                Button("선택한 규칙 복사 확정") {
                    let mapping = subjects.filter { selected.contains($0.key) }
                    do {
                        try planner.transferRules(from: source, subjects: mapping)
                        dismiss()
                    } catch { message = "규칙을 복사하지 못했어요. 원본과 저장 공간을 확인해 주세요." }
                }
                .buttonStyle(SchoolPrimaryButtonStyle())
                .disabled(planner.storageBlocked || selected.isEmpty || selected.contains {
                    PreparationPlan.subjectKey(subjects[$0] ?? "").isEmpty
                })
                if let message { Text(message) }
            }
            .navigationTitle("규칙 연결")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("취소") { dismiss() } } }
        }
    }
    private func selectionLabel(_ key: String) -> String {
        guard let data = Data(base64Encoded: key), let values = try? JSONDecoder().decode([String].self, from: data), values.count == 5 else { return "이전 학급" }
        return "학교 \(values[1]) · \(values[2])학년 \(values[3])반\(values[4].isEmpty ? "" : " · \(values[4])")"
    }
}
