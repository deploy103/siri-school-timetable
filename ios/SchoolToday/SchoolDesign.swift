import SwiftUI
import AppIntents

enum SchoolDesign {
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .label : UIColor(red: 0.09, green: 0.13, blue: 0.20, alpha: 1)
    })
    static let hero = Color(red: 8.0 / 255, green: 34.0 / 255, blue: 64.0 / 255)
    static let blue = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemBlue : UIColor(red: 0.23, green: 0.38, blue: 0.94, alpha: 1)
    })
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
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20).padding(.vertical, 14)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var appeared = false
    let start: () -> Void
    var body: some View {
        SetupPage(title: "") {
            SchoolBrand()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("반가워요!").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("시간표와 급식을 간편하게.")
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                if !textSize.isAccessibilitySize {
                    Image("WelcomeVoice").resizable().scaledToFit()
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.white)
            .background(SchoolDesign.hero, in: RoundedRectangle(cornerRadius: 24))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .opacity(appeared || reduceMotion ? 1 : 0)
            .offset(y: appeared || reduceMotion ? 0 : 10)
        } actions: {
            VStack(spacing: 12) {
                Button("내 학교 찾기", action: start)
                    .buttonStyle(SchoolPrimaryButtonStyle()).accessibilityIdentifier("start-onboarding")
                Text("가입 없이 시작해요").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.35)) { appeared = true } }
    }
}
