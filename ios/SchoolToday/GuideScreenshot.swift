import SwiftUI

/// Apple settings screenshots and a capture of the installed app in Simulator.
struct GuideScreenshot: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let asset: String
    let description: String
    let sourceLabel: String
    let source: URL
    @State private var expanded = false
    @State private var zoomed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(description).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            Button { zoomed = false; expanded = true } label: {
                Image(asset)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: textSize.isAccessibilitySize ? 220 : 300, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(description) · 화면 캡처 크게 보기")
            .accessibilityHint("누르면 사진이 커져요.")
            .accessibilityIdentifier("guide-screenshot-\(asset)")
            Text("사진을 누르면 커져요")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $expanded) {
            NavigationStack {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(description).font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(zoomed ? "전체 폭으로 보기" : "더 확대하기") { zoomed.toggle() }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("zoom-guide-screenshot")
                            if zoomed {
                                Text("사진을 밀어서 살펴봐요.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ScrollView(.horizontal) {
                                Image(asset).resizable().scaledToFit()
                                    .frame(width: max(0, geometry.size.width - 40) * (zoomed ? 2 : 1))
                                    .accessibilityLabel(description)
                            }
                            GuidePhotoSource(label: sourceLabel, url: source)
                        }
                        .padding(20)
                    }
                }
                .background(SchoolDesign.canvas)
                .navigationTitle("화면 캡처 크게 보기")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("닫기") { expanded = false }
                            .accessibilityIdentifier("close-guide-screenshot")
                    }
                }
            }
        }
    }
}

struct GuidePhotoSource: View {
    let label: String
    let url: URL
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(destination: url) {
                Text("사진 정보 · \(label)")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            Text("iOS 버전에 따라 화면이 달라요.")
        }
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}
