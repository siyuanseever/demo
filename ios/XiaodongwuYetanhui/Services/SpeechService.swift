import AVFoundation
import Combine
import Foundation

final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var activeMessageID: String?
    @Published private(set) var isSpeaking = false
    @Published private(set) var voiceName = "中文女性声线"
    @Published var automaticallyReadsReplies: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyReadsReplies, forKey: Self.autoReadKey)
        }
    }

    private static let autoReadKey = "speech.automaticallyReadsReplies"
    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterance: AVSpeechUtterance?
    private lazy var preferredVoice: AVSpeechSynthesisVoice? = selectPreferredVoice()

    override init() {
        automaticallyReadsReplies = UserDefaults.standard.bool(forKey: Self.autoReadKey)
        super.init()
        synthesizer.delegate = self
        voiceName = preferredVoice?.name ?? "系统中文声线"
    }

    func toggle(messageID: String, text: String) {
        if activeMessageID == messageID, isSpeaking {
            stop()
        } else {
            speak(messageID: messageID, text: text)
        }
    }

    func speak(messageID: String, text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        stop()

        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = preferredVoice
        utterance.rate = 0.43
        utterance.pitchMultiplier = 1.08
        utterance.volume = 0.96
        utterance.preUtteranceDelay = 0.08
        utterance.postUtteranceDelay = 0.12

        activeMessageID = messageID
        activeUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func previewVoice() {
        speak(
            messageID: "speech-preview",
            text: "晚上好呀，我是忧忧兔。你可以慢慢说，我会安静地听着。"
        )
    }

    func stop() {
        activeUtterance = nil
        activeMessageID = nil
        isSpeaking = false
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func selectPreferredVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let chineseVoices = voices.filter { $0.language.lowercased().hasPrefix("zh") }
        if let tingting = chineseVoices.first(where: {
            "\($0.name) \($0.identifier)".lowercased().contains("tingting")
        }) {
            return tingting
        }
        let femaleChineseVoices = chineseVoices.filter { $0.gender == .female }
        let candidates = femaleChineseVoices.isEmpty ? chineseVoices : femaleChineseVoices

        return candidates.max { voiceScore($0) < voiceScore($1) }
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }

    private func voiceScore(_ voice: AVSpeechSynthesisVoice) -> Int {
        let searchableName = "\(voice.name) \(voice.identifier)".lowercased()
        var score = 0

        if searchableName.contains("tingting") || searchableName.contains("婷婷") {
            score += 500
        }
        if voice.language.lowercased() == "zh-cn" {
            score += 180
        } else if voice.language.lowercased().hasPrefix("zh") {
            score += 100
        }
        if voice.gender == .female {
            score += 120
        }
        score += voice.quality.rawValue * 10
        return score
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishIfCurrent(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishIfCurrent(utterance)
    }

    private func finishIfCurrent(_ utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, utterance === self.activeUtterance else { return }
            self.activeUtterance = nil
            self.activeMessageID = nil
            self.isSpeaking = false
        }
    }
}
