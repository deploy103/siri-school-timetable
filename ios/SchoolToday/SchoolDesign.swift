import SwiftUI
import AppIntents

enum SchoolDesign {
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .label : UIColor(red: 0.09, green: 0.13, blue: 0.20, alpha: 1)
    })
    static let blue = Color(red: 0.23, green: 0.38, blue: 0.94)
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGroupedBackground : UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1)
    })
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct SchoolPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(SchoolDesign.blue, in: RoundedRectangle(cornerRadius: 18))
            .opacity(!enabled ? 0.4 : (configuration.isPressed ? 0.75 : 1))
    }
}

struct SchoolCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(SchoolDesign.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct SchoolBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "house.fill").foregroundStyle(SchoolDesign.blue)
            Text("오늘의 학교")
        }.font(.headline)
    }
}

struct WelcomeView: View {
    let start: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SchoolBrand()
                Text("학교생활,\n말 한마디로.")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .padding(.top, 40)
                Text("시간표와 급식은 Siri에게 물어보세요.\n먼저 내 학교부터 연결할게요.")
                    .font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    Image(systemName: "calendar").foregroundStyle(SchoolDesign.blue)
                    Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(.primary)
                }
                .font(.system(size: 58, weight: .light))
                .frame(maxWidth: .infinity).padding(.vertical, 60)
                Text("회원가입 없이 시작할 수 있어요.").font(.footnote).foregroundStyle(.secondary)
            }.padding(28)
        }
        .background(SchoolDesign.canvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: start) { Label("시작하기", systemImage: "arrow.right") }
                .buttonStyle(SchoolPrimaryButtonStyle()).accessibilityIdentifier("start-onboarding")
                .padding(24).background(SchoolDesign.canvas)
        }
    }
}

struct GuideInstruction: View {
    let number: Int
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(.headline).foregroundStyle(SchoolDesign.blue)
                .frame(width: 30, height: 30)
                .background(SchoolDesign.blue.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.modifier(SchoolCard())
    }
}

struct SiriGuideView: View {
    @EnvironmentObject private var store: SchoolStore
    @Environment(\.dismiss) private var dismiss
    let onboarding: Bool
    @State private var page = 0
    private let titles = ["Siri를 켜볼까요?", "이제 Siri를\n불러보세요", "학교 단축어를\n열어볼까요?", "이 문구로\n물어보세요", "내 단축어 이름으로\n부를 수도 있어요"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page > 0 {
                    Button { page -= 1 } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("이전 단계").frame(minWidth: 44, minHeight: 44)
                } else if !onboarding {
                    Button("닫기") { dismiss() }
                }
                Spacer()
                if page < 5 {
                    ProgressView(value: Double(page + 3), total: 7).frame(maxWidth: 140)
                    Text("\(page + 3) / 7").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if page < 5 {
                        Text(titles[page]).font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .accessibilityIdentifier("siri-guide-title")
                    }
                    switch page {
                    case 0:
                        Text("설정 앱에서 한 번만 준비하면 돼요.").foregroundStyle(.secondary)
                        GuideInstruction(number: 1, title: "iPhone의 설정 앱을 열어요", detail: "이 앱을 잠시 나가서 회색 톱니바퀴 모양의 ‘설정’을 여세요. 앱에서 Siri를 대신 켤 수는 없어요.")
                        GuideInstruction(number: 2, title: "Siri 메뉴를 찾아요", detail: "‘Siri’ 또는 ‘Apple Intelligence 및 Siri’를 누르세요. 찾기 어렵다면 설정의 검색창에 Siri를 입력하세요.")
                        GuideInstruction(number: 3, title: "Siri를 켜고 안내를 따라요", detail: "‘Siri 켜기’가 보이면 누르고 음성 설정을 마치세요. 이전 iOS에서는 ‘Siri에게 말하기’ 또는 ‘Siri에게 말하기 및 타이핑’에서 음성 호출을 설정할 수 있어요.")
                        Link("Apple의 Siri 설정 안내", destination: URL(string: "https://support.apple.com/ko-kr/guide/iphone/iph83aad8922/ios")!)
                        Text("메뉴 이름은 iOS 버전에 따라 달라요. 이미 사용 중이라면 다음으로 넘어가세요.").font(.footnote).foregroundStyle(.secondary)
                    case 1:
                        GuideInstruction(number: 1, title: "목소리로 부르기", detail: "설정에서 ‘Siri야’ 음성 호출을 켠 뒤, ‘시리야’라고 불러보세요. 기기·언어에 따라 ‘Siri’만으로 부르는 옵션도 있어요.")
                        GuideInstruction(number: 2, title: "버튼으로 부르기", detail: "Face ID가 있는 iPhone은 측면 버튼을 길게 누르세요. 홈 버튼이 있는 iPhone은 홈 버튼을 길게 누르세요. 짧게 누르는 것이 아니라 길게 누르는 거예요.")
                        GuideInstruction(number: 3, title: "응답이 없다면", detail: "설정의 Siri 메뉴에서 음성 호출 또는 버튼으로 Siri 사용이 켜져 있는지 확인하세요. 소리가 안 들리면 무음 모드와 Siri 응답 설정도 확인하세요. 이제 이 앱으로 돌아오세요.")
                    case 2:
                        Text("앱이 제공하는 ‘오늘 시간표’와 ‘오늘 급식’을 먼저 직접 실행해 보세요.").foregroundStyle(.secondary)
                        ShortcutsLink().accessibilityIdentifier("open-school-shortcuts")
                            .accessibilityLabel("오늘의 학교 단축어 페이지 열기")
                        GuideInstruction(number: 1, title: "단축어 페이지 열기", detail: "위 버튼으로 단축어 앱의 오늘의 학교 페이지를 열어요. ‘오늘 시간표’ 또는 ‘오늘 급식’을 눌러 실행해 보세요.")
                        GuideInstruction(number: 2, title: "내 단축어로 추가하기", detail: "원하는 앱 단축어의 메뉴를 열고 ‘새로운 단축어에서 사용’을 누르세요. 편집 화면에서 이름을 정하고 완료하면 내 단축어에 저장돼요. 메뉴 위치는 iOS 버전에 따라 달라질 수 있어요.")
                        Link("Apple의 앱 단축어 추가 안내", destination: URL(string: "https://support.apple.com/ko-kr/guide/shortcuts/apd43295406d/ios")!)
                        Text("학교·학급은 이 앱에 저장한 설정을 사용해요. 단축어를 추가했는지는 앱이 확인할 수 없어요.").font(.footnote).foregroundStyle(.secondary)
                    case 3:
                        Text("앱 단축어는 앱 이름 ‘오늘의 학교’를 포함한 문구로 불러요. 먼저 Siri를 부르거나 버튼으로 실행한 뒤 말해보세요.").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 18) {
                            Label("시간표", systemImage: "calendar").foregroundStyle(SchoolDesign.blue)
                            Text(SchoolShortcuts.timetableExample).font(.title3.bold()).textSelection(.enabled)
                            SiriTipView(intent: TodayTimetableIntent())
                            Label("급식", systemImage: "fork.knife").foregroundStyle(SchoolDesign.blue)
                            Text(SchoolShortcuts.mealExample).font(.title3.bold()).textSelection(.enabled)
                            SiriTipView(intent: TodayMealIntent())
                        }.modifier(SchoolCard())
                        Text("예: ‘시리야’ → ‘오늘의 학교 시간표 알려줘’").font(.headline)
                        GuideInstruction(number: 1, title: "웹 검색으로 넘어가면", detail: "먼저 단축어 앱에서 직접 실행되는지 확인하고, 위 문구를 그대로 말해보세요. 앱 이름을 빼거나 말을 임의로 덧붙이면 다른 요청으로 인식될 수 있어요. 표현 변형이 인식될 수는 있지만 모든 문장을 보장하지는 않아요.")
                    case 4:
                        Text("개인 단축어는 저장한 이름을 말하는 게 가장 확실해요. 앱의 호출 문구와 개인 단축어 이름은 서로 다른 방식이에요.").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("단축어 이름").font(.caption).foregroundStyle(.secondary)
                            Text("학교 시간표").font(.title2.bold())
                            Divider()
                            Text("말할 문구").font(.caption).foregroundStyle(.secondary)
                            Text("시리야, 학교 시간표").font(.title3.bold())
                        }.modifier(SchoolCard())
                        Text("‘오늘 학교 시간표’로 부르고 싶나요?").font(.headline)
                        Text("개인 단축어 이름도 ‘오늘 학교 시간표’로 바꿔주세요. ‘학교 시간표’라는 이름에 ‘오늘’을 덧붙이면 웹 검색으로 넘어갈 수 있어요. 실제 인식 결과는 기기에서 확인해야 해요.").foregroundStyle(.secondary)
                        GuideInstruction(number: 1, title: "이름 바꾸기", detail: "개인 단축어의 편집 화면을 열고, 위쪽 이름 옆 화살표 → ‘이름 변경’에서 원하는 문구를 입력한 뒤 완료하세요. 메뉴 위치는 iOS 버전에 따라 다를 수 있어요.")
                        Link("Apple의 단축어 이름 변경 안내", destination: URL(string: "https://support.apple.com/ko-kr/guide/shortcuts/apdd57094696/ios")!)
                    default:
                        Image(systemName: "checkmark.circle").font(.system(size: 72, weight: .light))
                            .foregroundStyle(SchoolDesign.blue).frame(maxWidth: .infinity).padding(.vertical, 24)
                        Text("학교 설정이\n완료됐어요").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("이제 내 학교의 시간표와 급식을 만날 수 있어요.").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.school?.school.name ?? "").font(.headline)
                            Text(store.school?.schoolClass.label ?? "").foregroundStyle(.secondary)
                            DemoNotice()
                        }.modifier(SchoolCard())
                        Text("Siri 실행은 단축어에서 확인해 보세요. 이 화면은 학교 설정과 안내가 끝났다는 뜻이며, Siri 설정이나 단축어 추가 성공을 확인한 것은 아니에요.").font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(28)
            }.id(page)
        }
        .background(SchoolDesign.canvas)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button {
                    if page < 5 { page += 1 }
                    else if onboarding { store.finishOnboarding() }
                    else { dismiss() }
                } label: {
                    Label(page < 5 ? "다음" : (onboarding ? "오늘의 학교 시작하기" : "안내 닫기"), systemImage: "arrow.right")
                }.buttonStyle(SchoolPrimaryButtonStyle())
                    .accessibilityIdentifier(page < 5 ? "guide-next" : "finish-onboarding")
                if page == 0 {
                    Button("Siri 설정은 나중에 하기") { page = 2 }.font(.footnote)
                        .accessibilityIdentifier("skip-siri-setup")
                }
            }.padding(24).background(SchoolDesign.canvas)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct SchoolHomeView: View {
    @EnvironmentObject private var store: SchoolStore
    @Binding var tab: Int
    @State private var help = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    SchoolBrand()
                    Spacer()
                    Button { help = true } label: { Image(systemName: "questionmark.circle").font(.title2) }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Siri 사용 방법").accessibilityIdentifier("siri-help")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.school?.school.name ?? "").font(.headline)
                    Text(store.school?.schoolClass.label ?? "").foregroundStyle(.secondary)
                    DemoNotice()
                }.modifier(SchoolCard())
                Text("“\(SchoolShortcuts.timetableExample)”")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .padding(.top, 12)
                Text("Siri를 부른 다음, 이렇게 말해보세요.").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 12) {
                    ShortcutsLink().accessibilityIdentifier("open-school-shortcuts")
                        .accessibilityLabel("오늘의 학교 단축어 페이지 열기")
                    Text("시간표·급식 단축어 페이지로 이동해요.").font(.footnote).foregroundStyle(.secondary)
                }.modifier(SchoolCard())
                HStack(spacing: 16) {
                    Button { tab = 1 } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "calendar").font(.title)
                            Text("시간표 보기").font(.headline)
                        }.modifier(SchoolCard())
                    }
                    Button { tab = 2 } label: {
                        VStack(alignment: .leading, spacing: 16) {
                            Image(systemName: "fork.knife").font(.title)
                            Text("급식 보기").font(.headline)
                        }.modifier(SchoolCard())
                    }
                }.buttonStyle(.plain).foregroundStyle(SchoolDesign.blue)
            }.padding(24)
        }
        .background(SchoolDesign.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $help) { SiriGuideView(onboarding: false) }
    }
}
