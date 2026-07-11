import AVFoundation
import Combine
import Foundation

@MainActor
final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var activeMessageID: String?
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPreparing = false
    @Published private(set) var voiceName = "Qwen3-TTS · Serena"
    @Published private(set) var lastError: String?
    @Published var automaticallyReadsReplies: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyReadsReplies, forKey: Self.autoReadKey)
        }
    }

    private struct LocalSpeechRequest: Encodable {
        let model: String
        let input: String
        let voice: String
        let instruct: String
    }

    private static let autoReadKey = "speech.automaticallyReadsReplies"
    private static let endpoint = URL(string: "http://127.0.0.1:8768/v1/audio/speech")!
    private static let voiceInstruction = "温柔、自然、安静地说，像一位年轻女孩在夜晚陪伴亲近的朋友。语速稍慢，不要播音腔，不要夸张卖萌。"

    private var audioPlayer: AVAudioPlayer?
    private var generationTask: Task<Void, Never>?
    private var requestID: UUID?

    override init() {
        automaticallyReadsReplies = UserDefaults.standard.bool(forKey: Self.autoReadKey)
        super.init()
    }

    var isActive: Bool {
        activeMessageID != nil && (isPreparing || isSpeaking)
    }

    func toggle(messageID: String, text: String) {
        if activeMessageID == messageID, isActive {
            stop()
        } else {
            speak(messageID: messageID, text: text)
        }
    }

    func speak(messageID: String, text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        stop()
        let currentRequestID = UUID()
        requestID = currentRequestID
        activeMessageID = messageID
        isPreparing = true
        lastError = nil

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let audioData = try await requestLocalAudio(text: cleanText)
                try Task.checkCancellation()
                guard requestID == currentRequestID else { return }

                let player = try AVAudioPlayer(data: audioData)
                player.delegate = self
                player.prepareToPlay()
                audioPlayer = player
                isPreparing = false
                isSpeaking = player.play()
                if !isSpeaking {
                    throw SpeechServiceError.playbackFailed
                }
            } catch is CancellationError {
                return
            } catch {
                guard requestID == currentRequestID else { return }
                resetPlaybackState()
                lastError = "本地自然语音暂时不可用。请用 scripts/run_mac.sh 启动应用，或查看 logs/tts.log。"
            }
        }
    }

    func previewVoice() {
        speak(
            messageID: "speech-preview",
            text: "晚上好呀，我是忧忧兔。你可以慢慢说，我会安静地听着。"
        )
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        requestID = nil
        audioPlayer?.stop()
        audioPlayer = nil
        resetPlaybackState()
    }

    private func requestLocalAudio(text: String) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            LocalSpeechRequest(
                model: "qwen3-tts-0.6b-customvoice-8bit",
                input: text,
                voice: "Serena",
                instruct: Self.voiceInstruction
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              !data.isEmpty else {
            throw SpeechServiceError.invalidResponse
        }
        return data
    }

    private func resetPlaybackState() {
        activeMessageID = nil
        isPreparing = false
        isSpeaking = false
    }
}

extension SpeechService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, player === self.audioPlayer else { return }
            self.audioPlayer = nil
            self.requestID = nil
            self.resetPlaybackState()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, player === self.audioPlayer else { return }
            self.audioPlayer = nil
            self.requestID = nil
            self.resetPlaybackState()
            self.lastError = "语音已经生成，但播放失败了。"
        }
    }
}

private enum SpeechServiceError: Error {
    case invalidResponse
    case playbackFailed
}
