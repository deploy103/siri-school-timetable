import SwiftUI

struct SiriGuideView: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onboarding: Bool
    @State private var step: Step = .enable
    @State private var history: [Step] = []
    @State private var forward = true
    @State private var timetableName = SchoolShortcuts.timetableExample
    @State private var mealName = SchoolShortcuts.mealExample
    @State private var loadedNames = false
    @State private var copied = false
    @State private var help = false
    @State private var check = false
    @FocusState private var nameFocused: Bool

    private enum Step: Hashable {
        case enable, activate, name(SchoolShortcut), tryDefault(SchoolShortcut)
        case create(SchoolShortcut), editor(SchoolShortcut), rename(SchoolShortcut), saveName(SchoolShortcut), speak(SchoolShortcut), mealOffer, finish
        var title: String {
            switch self {
            case .enable: return "Siri 켜기"
            case .activate: return "Siri 부르기"
            case .name(let shortcut): return "\(shortcut == .timetable ? "시간표를" : "급식을") 뭐라고 부를까요?"
            case .tryDefault: return "단축어 실행해 보기"
            case .create: return "내 단축어 만들기"
            case .editor: return "이름 메뉴 열기"
            case .rename: return "이름 바꾸기"
            case .saveName: return "이름을 저장해요"
            case .speak: return "이렇게 불러보세요"
            case .mealOffer: return "급식도 불러볼까요?"
            case .finish: return "이제 써볼까요?"
            }
        }
    }
    private var photo: GuideScreenshot? {
        let apple = URL(string: "https://support.apple.com/ko-kr/105037")!
        let shortcuts = URL(string: "https://support.apple.com/ko-kr/guide/shortcuts/apd43295406d/ios")!
        switch step {
        case .enable:
            return GuideScreenshot(asset: "SiriSettingsGuide", description: "설정 → Siri → ‘Siri 켜기’", sourceLabel: "Apple 지원 · iOS 27 설정", source: apple)
        case .activate:
            return GuideScreenshot(asset: "SiriActivationGuide", description: "설정 → Siri → 요청", sourceLabel: "Apple 지원 · iOS 27 요청 설정", source: apple)
        case .tryDefault(let shortcut):
            return GuideScreenshot(asset: "AppShortcutsGuide", description: "‘오늘 \(shortcut.title)’를 눌러 한 번 실행해요.", sourceLabel: "iOS 27 Simulator · 실제 단축어 앱", source: shortcuts)
        case .create(let shortcut):
            return GuideScreenshot(asset: shortcut == .timetable ? "ShortcutMenuGuide" : "AppShortcutsGuide", description: "‘오늘 \(shortcut.title)’를 길게 눌러 ‘새로운 단축어’를 골라요.", sourceLabel: "iOS 27 Simulator · 실제 단축어 앱", source: shortcuts)
        case .editor:
            return GuideScreenshot(asset: "ShortcutEditorGuide", description: "만든 단축어 → ‘편집기’에서 이름 옆 화살표를 눌러요.", sourceLabel: "iOS 27 Simulator · 실제 단축어 앱", source: URL(string: "https://support.apple.com/ko-kr/guide/shortcuts/apdd57094696/ios")!)
        case .rename:
            return GuideScreenshot(asset: "ShortcutRenameGuide", description: "‘이름 변경’을 눌러요.", sourceLabel: "iOS 27 Simulator · 실제 단축어 앱", source: URL(string: "https://support.apple.com/ko-kr/guide/shortcuts/apdd57094696/ios")!)
        case .saveName:
            return GuideScreenshot(asset: "ShortcutNameGuide", description: "사진은 예시예요. 여기에 내 이름을 붙여넣어요.", sourceLabel: "iOS 27 Simulator · 실제 단축어 앱", source: URL(string: "https://support.apple.com/ko-kr/guide/shortcuts/apdd57094696/ios")!)
        default: return nil
        }
    }
    var body: some View {
        ZStack {
            SetupPage(title: nameFocused ? "" : step.title, titleIdentifier: "siri-guide-title", pinnedActions: !nameFocused) {
                stepContent
                if let photo {
                    Button("도움이 필요해요?") { help = true }.frame(minHeight: 44)
                        .accessibilityIdentifier("siri-step-help")
                    GuidePhotoSource(label: photo.sourceLabel, url: photo.source).padding(.top, 32)
                }
            } actions: {
                VStack(spacing: 8) {
                    Button(primaryTitle, action: next)
                        .buttonStyle(SchoolPrimaryButtonStyle())
                        .disabled(nameError != nil)
                        .accessibilityIdentifier(step == .finish ? "finish-onboarding" : "guide-next")
                    if step == .mealOffer {
                        Button("여기까지 할게요") { advance(.finish) }.frame(minHeight: 44)
                            .accessibilityIdentifier("skip-meal-setup")
                    } else if onboarding && step != .finish {
                        Button("Siri는 나중에") { store.finishOnboarding() }.frame(minHeight: 44)
                            .accessibilityIdentifier("skip-siri-setup")
                    }
                }
            }
            .id(step)
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .background(SchoolDesign.canvas)
        .navigationTitle(nameFocused ? "호출 이름" : "Siri 설정").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !history.isEmpty {
                    Button(action: back) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("이전 단계").frame(minWidth: 44, minHeight: 44)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !onboarding {
                    Button("닫기") { dismiss() }.accessibilityIdentifier("close-siri-guide")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("입력 완료") { nameFocused = false }
            }
        }
        .onAppear {
            if !loadedNames {
                timetableName = SchoolPreferences.shortcutName(for: .timetable, defaults: store.defaults)
                mealName = SchoolPreferences.shortcutName(for: .meal, defaults: store.defaults)
                loadedNames = true
            }
        }
        .sheet(isPresented: $help) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        helpContent
                    }.padding(24)
                }
                .background(SchoolDesign.canvas)
                .navigationTitle(step.title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { help = false } } }
            }
        }
        .sheet(isPresented: $check) { NavigationStack { ShortcutCheckView() } }
    }
    @ViewBuilder private var stepContent: some View {
        switch step {
        case .enable:
            if let photo { photo }
            Text("이미 켰다면 다음으로 넘어가요.").font(.subheadline).foregroundStyle(.secondary)
        case .activate:
            SiriCallHint()
            if let photo { photo }
        case .name(let shortcut):
            TextField("예: 학교 \(shortcut.title)", text: nameBinding(for: shortcut), axis: .vertical)
                .font(.title3.weight(.semibold)).lineLimit(1...3)
                .padding(18).background(SchoolDesign.card, in: RoundedRectangle(cornerRadius: 18))
                .focused($nameFocused).submitLabel(.done)
                .onSubmit { nameFocused = false }
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .accessibilityLabel("\(shortcut.title) 호출 이름")
                .accessibilityIdentifier("shortcut-name-\(shortcut.rawValue)")
            Text(isCustom(shortcut) ? "단축어 앱에도 같은 이름을 써요." : "기본 문구는 바로 쓸 수 있어요.")
                .font(.subheadline).foregroundStyle(.secondary)
            if isCustom(shortcut) {
                Button("이미 이 이름으로 저장했어요") { useExisting(shortcut) }
                    .frame(minHeight: 44).disabled(nameError != nil)
                    .accessibilityHint("단축어 앱에 같은 이름으로 저장한 경우에만 만들기 안내를 건너뛰어요.")
                    .accessibilityIdentifier("use-existing-shortcut")
                Button("기본 문구로 돌아가기") { nameBinding(for: shortcut).wrappedValue = shortcut.defaultPhrase }
                    .frame(minHeight: 44)
            }
            if let nameError { Text(nameError).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("shortcut-name-error") }
        case .tryDefault:
            if let photo { photo }
            SchoolShortcutsEntry()
        case .create:
            if let photo { photo }
            SchoolShortcutsEntry()
        case .editor(let shortcut):
            if let photo { photo }
            if shortcut == .meal {
                Text("시간표 사진이에요. 급식도 같은 방법이에요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            SchoolShortcutsEntry(appPage: false)
        case .rename:
            if let photo { photo }
            SchoolShortcutsEntry(appPage: false)
        case .saveName(let shortcut):
            VStack(alignment: .leading, spacing: 12) {
                Text(name(for: shortcut)).font(.title3.bold()).textSelection(.enabled)
                    .accessibilityIdentifier("chosen-shortcut-name")
                Button(copied ? "복사했어요" : "이 이름 복사") {
                    UIPasteboard.general.string = name(for: shortcut)
                    copied = true
                }.frame(minHeight: 44).accessibilityIdentifier("copy-shortcut-name")
            }
            if let photo { photo }
            SchoolShortcutsEntry(appPage: false)
            Text("키보드의 ‘완료’(✓)를 누르고 뒤로 나가요.")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("앱으로 돌아온 것만으로 저장되지는 않아요.")
                .font(.footnote).foregroundStyle(.secondary)
        case .speak(let shortcut):
            SiriCallHint()
            Text(name(for: shortcut)).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled).modifier(SchoolCard()).accessibilityIdentifier("siri-call-phrase")
            SchoolShortcutsEntry(personalName: isCustom(shortcut) ? name(for: shortcut) : nil)
            Button("잘 안 되나요?") { check = true }.frame(minHeight: 44)
                .accessibilityIdentifier("shortcut-check")
        case .mealOffer:
            Text("급식도 기본 문구를 쓰거나 원하는 이름으로 바꿀 수 있어요.").foregroundStyle(.secondary)
        case .finish:
            VStack(alignment: .leading, spacing: 8) {
                Text(store.school?.school.name ?? "").font(.headline)
                Text(store.school?.classLabel ?? "").foregroundStyle(.secondary)
                DemoNotice()
            }
            Text("호출 이름은 Siri 사용법에서 다시 바꿀 수 있어요.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var helpContent: some View {
        switch step {
        case .enable:
            Text("설정에서 Siri를 검색해요.").font(.headline)
            Text("기기에 따라 ‘Apple Intelligence 및 Siri’ 또는 ‘Siri 및 검색’으로 보여요. 음성 호출이나 버튼 사용을 직접 켜요.")
        case .activate:
            Text("‘시리야’라고 말해도 돼요.").font(.headline)
            Text("설정 → Siri → 요청에서 음성 호출을 켜요. 홈 버튼이 있는 iPhone은 홈 버튼을 길게 눌러요.")
        case .editor, .rename, .saveName:
            Text("같은 이름으로 저장해요.").font(.headline)
            Text("‘시리야’는 이름에 넣지 않아요. 다른 단축어와 같은 이름도 피해주세요. 편집 화면에 ‘완료’가 있다면 눌러요.")
            SchoolShortcutsEntry(appPage: false)
        default:
            Text("단축어 앱 → 오늘의 학교").font(.headline)
            Text("‘오늘 시간표’ 또는 ‘오늘 급식’을 길게 눌러 ‘새로운 단축어’를 골라요. ‘새로운 단축어에서 사용’으로 보일 수도 있어요.")
            Text("이미 만든 단축어가 있다면 그 단축어의 이름을 확인해요.")
        }
    }
    private func name(for shortcut: SchoolShortcut) -> String {
        (shortcut == .timetable ? timetableName : mealName).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func nameBinding(for shortcut: SchoolShortcut) -> Binding<String> {
        Binding {
            shortcut == .timetable ? timetableName : mealName
        } set: { value in
            if shortcut == .timetable { timetableName = value } else { mealName = value }
            copied = false
        }
    }
    private func isCustom(_ shortcut: SchoolShortcut) -> Bool { name(for: shortcut) != shortcut.defaultPhrase }
    private var nameError: String? {
        guard case .name(let shortcut) = step else { return nil }
        if name(for: shortcut).isEmpty { return "호출할 이름을 입력해요." }
        if name(for: shortcut) == name(for: shortcut.other) || name(for: shortcut) == shortcut.other.defaultPhrase {
            return "시간표와 급식은 다른 이름으로 정해요."
        }
        return nil
    }
    private var primaryTitle: String {
        switch step {
        case .name(let shortcut): return isCustom(shortcut) ? "이 이름 설정하기" : "이 문구 사용하기"
        case .tryDefault: return "Siri로 불러보기"
        case .create: return "만들었어요"
        case .editor: return "메뉴를 열었어요"
        case .rename: return "이름 입력하기"
        case .saveName: return "이 이름으로 저장했어요"
        case .speak: return "확인했어요"
        case .mealOffer: return "급식 이름도 정하기"
        case .finish: return onboarding ? "시작하기" : "안내 닫기"
        default: return "다음"
        }
    }
    private func useExisting(_ shortcut: SchoolShortcut) {
        guard nameError == nil else { return }
        nameFocused = false
        SchoolPreferences.writeShortcutName(name(for: shortcut), for: shortcut, defaults: store.defaults)
        advance(.speak(shortcut))
    }
    private func next() {
        nameFocused = false
        switch step {
        case .enable: advance(.activate)
        case .activate: advance(.name(.timetable))
        case .name(let shortcut):
            guard nameError == nil else { return }
            SchoolPreferences.writeShortcutName(name(for: shortcut), for: shortcut, defaults: store.defaults)
            advance(isCustom(shortcut) ? .create(shortcut) : .tryDefault(shortcut))
        case .tryDefault(let shortcut): advance(.speak(shortcut))
        case .create(let shortcut): advance(.editor(shortcut))
        case .editor(let shortcut): advance(.rename(shortcut))
        case .rename(let shortcut): advance(.saveName(shortcut))
        case .saveName(let shortcut): advance(.speak(shortcut))
        case .speak(let shortcut): advance(shortcut == .timetable ? .mealOffer : .finish)
        case .mealOffer: advance(.name(.meal))
        case .finish:
            if onboarding { store.finishOnboarding() } else { dismiss() }
        }
    }
    private func advance(_ next: Step) {
        history.append(step)
        forward = true; copied = false
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28)) { step = next }
    }
    private func back() {
        guard let previous = history.popLast() else { return }
        nameFocused = false; forward = false; copied = false
        withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.28)) { step = previous }
    }
}
