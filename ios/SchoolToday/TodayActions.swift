import SwiftUI
import AVFAudio
import Combine

@MainActor
final class SchoolReader: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var preparing = false
    @Published private(set) var speaking = false
    @Published private(set) var error: String?
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func prepare() {
        stop()
        error = nil
        preparing = true
    }

    func speak(_ text: String) {
        guard let voice = AVSpeechSynthesisVoice(language: "ko-KR") else {
            fail("한국어 음성을 사용할 수 없어요. iPhone의 음성 설정을 확인해 주세요.")
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try audio.setActive(true)
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            activeUtterance = utterance
            preparing = false
            speaking = true
            synthesizer.speak(utterance)
        } catch {
            fail("음성을 재생하지 못했어요. 잠시 뒤 다시 시도해 주세요.")
        }
    }

    func fail(_ message: String) {
        stop()
        error = message
    }

    func stop() {
        preparing = false
        speaking = false
        let wasPlaying = activeUtterance != nil
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        if wasPlaying {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            // A delayed callback from an older utterance must not stop a new one.
            guard let self, self.activeUtterance === utterance else { return }
            self.stop()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance === utterance else { return }
            self.stop()
        }
    }
}

struct TodayActions: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var reader = SchoolReader()
    @State private var attempt = 0
    let kind: TodayKind
    let settings: SchoolSettings
    let api: SchoolAPI
    let shareText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                if reader.preparing || reader.speaking { reader.stop() }
                else { reader.prepare() }
                attempt += 1
            } label: {
                Label(reader.preparing ? "읽기 취소" : reader.speaking ? "읽기 중지" : "소리내어 읽기",
                      systemImage: reader.preparing || reader.speaking ? "stop.fill" : "speaker.wave.2")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.accessibilityIdentifier("read-today")
            if reader.preparing { ProgressView("음성 안내를 준비하는 중") }
            if let error = reader.error {
                Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("read-today-error")
            }
            ShareLink(item: shareText) {
                Label(kind == .timetable ? "시간표 공유" : "급식 공유", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.accessibilityIdentifier("share-today")
            Text("서버 결과를 읽어요. Siri 설정은 바뀌지 않아요.")
                .font(.footnote).foregroundStyle(.secondary)
            if kind == .meals {
                Text("음성은 알레르기 번호를 읽지 않아요. 식단·학교 안내를 확인해요.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.modifier(SchoolCard())
        .task(id: attempt) {
            guard reader.preparing else { return }
            do {
                let text = try await api.speech(settings: settings, meal: kind == .meals)
                guard !Task.isCancelled, reader.preparing else { return }
                reader.speak(text)
            } catch {
                if !Task.isCancelled, reader.preparing { reader.fail(error.localizedDescription) }
            }
        }
        .onDisappear { reader.stop(); attempt += 1 }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { reader.stop(); attempt += 1 }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { _ in
            reader.stop(); attempt += 1
        }
    }
}
