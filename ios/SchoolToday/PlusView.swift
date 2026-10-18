import SwiftUI
import StoreKit

@MainActor
struct PlusView: View {
    @ObservedObject private var store = PlusStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var continued = false
    var onActivated: (() -> Void)? = nil

    private var selected: Product? {
        store.products.first { $0.id == selectedID } ?? store.products.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("오늘의 학교 Plus", systemImage: "sparkles").font(.headline)
                        Text("준비는 차근차근,\n등교는 가볍게.")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("수업에 맞춰 준비물과 마감을 한곳에서 챙겨요.")
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    .foregroundStyle(.white)
                    .background(SchoolDesign.hero, in: RoundedRectangle(cornerRadius: 24))

                    VStack(alignment: .leading, spacing: 18) {
                        feature("books.vertical.fill", "여러 과목 준비", "과목마다 필요한 준비물을 함께 관리해요.")
                        feature("checklist", "마감일까지 단계별로", "준비 단계를 나눠 하나씩 완료해요.")
                        feature("bell.badge.fill", "내가 고른 알림", "요약·재확인 알림을 원하는 대로 선택해요.")
                        feature("rectangle.3.group.fill", "나만의 준비 위젯", "원할 때만 개인 준비 내용을 위젯에 표시해요.")
                    }.modifier(SchoolCard())

                    if store.isPlus {
                        Label("Plus 이용 중", systemImage: "checkmark.seal.fill")
                            .font(.title2.bold()).foregroundStyle(SchoolDesign.blue)
                        Button("계속하기", action: activate).buttonStyle(SchoolPrimaryButtonStyle())
                    } else {
                        pricing
                    }

                    if let message = store.message {
                        Text(message).font(.callout).foregroundStyle(.secondary)
                            .accessibilityIdentifier("plus-status")
                    }
                    VStack(spacing: 14) {
                        Button("구입 복원") { Task { await store.restore() } }
                            .disabled(store.purchasing)
                        Link("구독 관리 및 취소", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                        Link("이용 약관 (Apple 표준 EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }.font(.footnote).frame(maxWidth: .infinity)
                    SchoolPrivacyNotice().modifier(SchoolCard())
                    Text("구독 요금은 구입 확인 시 Apple 계정으로 청구됩니다. 구독은 취소하지 않으면 선택한 기간마다 자동 갱신됩니다. 다음 갱신을 원하지 않으면 현재 기간 종료 최소 24시간 전에 Apple 계정의 구독 관리에서 취소해 주세요. 갱신 요금은 기간 종료 전 24시간 이내에 청구되며, 취소 후에도 결제한 기간까지 이용할 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }
            .background(SchoolDesign.canvas)
            .foregroundStyle(SchoolDesign.ink)
            .navigationTitle("Plus").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
            .task { await store.load() }
            .onChange(of: store.isPlus) { _, active in
                if active { activate() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.refresh() } }
            }
        }
    }

    private var pricing: some View {
        VStack(spacing: 12) {
            if store.loading { ProgressView("구독 가격을 확인하고 있어요…") }
            ForEach(store.products, id: \.id) { product in
                Button { selectedID = product.id } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected?.id == product.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(SchoolDesign.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.displayName).font(.headline)
                            Text("\(product.displayPrice) / \(period(product)) 결제")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.modifier(SchoolCard())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected?.id == product.id ? [.isSelected] : [])
                .disabled(store.purchasing)
            }
            if let selected {
                if store.eligibleTrials.contains(selected.id), let trial = selected.subscription?.introductoryOffer {
                    Text("이 Apple 계정은 \(periodLabel(trial.period)) 무료 체험 대상이에요. 체험 후 \(selected.displayPrice) / \(period(selected))으로 자동 갱신됩니다. 정확한 종료일과 첫 청구일은 Apple 구입 확인 화면에서 확인해 주세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button {
                    Task { await store.purchase(selected) }
                } label: {
                    Text(store.purchasing ? "처리 중…" : "\(selected.displayPrice) · \(period(selected)) 구독하기")
                }
                .buttonStyle(SchoolPrimaryButtonStyle())
                .disabled(store.purchasing || store.loading)
            }
            Button(store.products.isEmpty ? "가격 다시 불러오기" : "가격 새로고침") {
                Task { await store.load() }
            }.font(.footnote).disabled(store.loading || store.purchasing)
        }
    }

    private func period(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "구독 기간" }
        return periodLabel(period)
    }

    private func periodLabel(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: return "\(period.value)일"
        case .week: return "\(period.value)주"
        case .month: return "\(period.value)개월"
        case .year: return "\(period.value)년"
        @unknown default: return "구독 기간"
        }
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(SchoolDesign.blue)
                .frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func activate() {
        guard store.isPlus, !continued else { return }
        continued = true
        dismiss()
        onActivated?()
    }
}
