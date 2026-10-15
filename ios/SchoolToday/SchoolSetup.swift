import SwiftUI

/// One layout for setup questions: shared alignment, scrolling, and accessible actions.
struct SetupPage<Content: View, Actions: View>: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @AccessibilityFocusState private var headingFocused: Bool
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    var titleIdentifier = "setup-title"
    var pinnedActions = true
    var compactHeading = false
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions

    private var pinActions: Bool { pinnedActions && !textSize.isAccessibilitySize }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let symbol, !textSize.isAccessibilitySize && !compactHeading {
                    Image(systemName: symbol).font(.title2)
                        .foregroundStyle(SchoolDesign.blue).padding(16)
                        .background(SchoolDesign.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityHidden(true)
                }
                if !title.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title).font(.system(compactHeading ? .headline : .largeTitle, design: .rounded, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(titleIdentifier)
                            .accessibilityFocused($headingFocused)
                        if let detail {
                            Text(detail).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                content()
                if !pinActions { actions().padding(.top, 12) }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(24).frame(maxWidth: .infinity)
        }
        .background(SchoolDesign.canvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if pinActions {
                actions().frame(maxWidth: 520).padding(24)
                    .frame(maxWidth: .infinity).background(SchoolDesign.canvas)
            }
        }
        .onAppear { headingFocused = true }
    }
}

struct SetupChoice: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 16) {
                if let symbol, !textSize.isAccessibilitySize {
                    Image(systemName: symbol).font(.title2)
                        .foregroundStyle(SchoolDesign.blue).frame(width: 36)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline)
                    if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(selected ? SchoolDesign.blue : .secondary)
                    .accessibilityHidden(true)
            }
            .padding(20).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(selected ? SchoolDesign.blue.opacity(0.07) : SchoolDesign.card,
                        in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(
                selected ? SchoolDesign.blue : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
        .accessibilityHint(detail ?? "")
    }
}

struct ClassSelectionView: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let api: SchoolAPI
    let school: School
    @State private var classes: [SchoolClass] = []
    @State private var error: String?
    @State private var loading = true
    @State private var attempt = 0
    @State private var page: Page = .type
    @State private var schoolType: HighSchoolType?
    @State private var grade: Int?
    @State private var department: String?
    @State private var selectedClass: SchoolClass?
    @State private var forward = true
    private enum Page { case type, grade, department, schoolClass }
    private var isHighSchool: Bool { school.kind == "고등학교" }
    private var needsDepartment: Bool {
        schoolType == .vocational && classes.contains { $0.grade == grade && $0.department != nil }
    }
    private var title: String {
        switch page {
        case .type: return "어떤 고등학교인가요?"
        case .grade: return "몇 학년인가요?"
        case .department: return "어느 학과인가요?"
        case .schoolClass: return "몇 반인가요?"
        }
    }
    private var gradeClasses: [SchoolClass] { classes.filter { $0.grade == grade } }
    private var departments: [String] {
        Array(Set(gradeClasses.map { $0.department ?? "" })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private var availableClasses: [SchoolClass] {
        gradeClasses.filter { !needsDepartment || ($0.department ?? "") == department }
            .sorted { $0.className.localizedStandardCompare($1.className) == .orderedAscending }
    }
    // Never silently select one of two different departments with the same class number.
    private var ambiguousGeneralClass: Bool {
        !needsDepartment && Dictionary(grouping: gradeClasses, by: \.className).values.contains {
            Set($0.map(\.department)).count > 1
        }
    }
    private var canContinue: Bool {
        if page == .type { return schoolType != nil }
        guard !loading, error == nil else { return false }
        switch page {
        case .type: return schoolType != nil
        case .grade: return grade != nil
        case .department: return department != nil
        case .schoolClass: return selectedClass != nil && !ambiguousGeneralClass
        }
    }
    var body: some View {
        ZStack {
            SetupPage(title: title, detail: school.name, symbol: "building.2") {
                DemoNotice()
                if loading && page != .type { ProgressView("학급을 불러오고 있어요") }
                if let error, page != .type {
                    Text(error).foregroundStyle(.red)
                    Button("다시 시도") { attempt += 1 }.frame(minHeight: 44)
                }
                if page == .type || (!loading && error == nil) {
                    choices
                    if page != .type && classes.isEmpty {
                        Text("학급 자료가 아직 없어요. 다시 불러오거나 다른 학교를 선택해요.")
                            .foregroundStyle(.secondary)
                        Button("학급 다시 불러오기") { attempt += 1 }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("reload-empty-classes")
                    }
                }
            } actions: {
                Button(page == .schoolClass ? "학교 설정 저장" : "다음", action: next)
                    .buttonStyle(SchoolPrimaryButtonStyle()).disabled(!canContinue)
                    .accessibilityIdentifier(page == .schoolClass ? "class-next" : "class-step-next")
            }
            .id(page)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .background(SchoolDesign.canvas)
        .navigationTitle("내 학교").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(page != (isHighSchool ? .type : .grade))
        .toolbar {
            if page != (isHighSchool ? .type : .grade) {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: back) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("이전 선택").frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .onAppear { if !isHighSchool && page == .type { page = .grade } }
        .task(id: attempt) {
            loading = true; error = nil
            defer { if !Task.isCancelled { loading = false } }
            do {
                let result = try await api.classes(school: school)
                guard !Task.isCancelled else { return }
                classes = result
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    @ViewBuilder private var choices: some View {
        VStack(spacing: 12) {
            switch page {
            case .type:
                ForEach(HighSchoolType.allCases, id: \.self) { type in
                    SetupChoice(title: type.title, detail: type == .general ? "학년과 반을 골라요" : "학과도 함께 골라요",
                                symbol: type == .general ? "building.2.fill" : "book.closed.fill", selected: schoolType == type) {
                        if schoolType != type { schoolType = type; department = nil; selectedClass = nil }
                    }
                }
            case .grade:
                ForEach(Array(Set(classes.map(\.grade))).sorted(), id: \.self) { value in
                    SetupChoice(title: "\(value)학년", selected: grade == value) {
                        if grade != value { grade = value; department = nil; selectedClass = nil }
                    }
                }
            case .department:
                ForEach(departments, id: \.self) { value in
                    SetupChoice(title: value.isEmpty ? "학과 정보 없음" : value, selected: department == value) {
                        if department != value { department = value; selectedClass = nil }
                    }
                }
            case .schoolClass:
                Text([department, grade.map { "\($0)학년" }].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if ambiguousGeneralClass {
                    Text("같은 반 번호가 여러 학과에 있어요. 학과를 골라야 정확히 연결돼요.")
                        .accessibilityIdentifier("class-department-required")
                    Button("학과 선택으로 바꾸기") { schoolType = .vocational; move(to: .department) }
                        .frame(minHeight: 44)
                } else {
                    ForEach(availableClasses) { value in
                        SetupChoice(title: "\(value.className)반", selected: selectedClass == value) { selectedClass = value }
                    }
                }
            }
        }
    }
    private func move(to next: Page, forward: Bool = true) {
        self.forward = forward
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28)) { page = next }
    }
    private func next() {
        switch page {
        case .type: move(to: .grade)
        case .grade: move(to: needsDepartment ? .department : .schoolClass)
        case .department: move(to: .schoolClass)
        case .schoolClass:
            if let selectedClass {
                do { try store.saveSchool(SchoolSettings(school: school, schoolClass: selectedClass, highSchoolType: schoolType)) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
    private func back() {
        switch page {
        case .type: break
        case .grade: move(to: .type, forward: false)
        case .department: move(to: .grade, forward: false)
        case .schoolClass: move(to: needsDepartment ? .department : .grade, forward: false)
        }
    }
}
