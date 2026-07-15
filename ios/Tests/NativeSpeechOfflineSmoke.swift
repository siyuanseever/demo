import Foundation

@main
struct NativeSpeechOfflineSmoke {
    @MainActor
    static func main() async {
        let speech = SpeechService()
        speech.speak(messageID: "offline-smoke", text: "这是一条离线降级测试。")

        let deadline = ContinuousClock.now + .seconds(5)
        while speech.lastError == nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }

        guard speech.lastError != nil else {
            fputs("SpeechService did not expose an offline error\n", stderr)
            exit(1)
        }
        guard speech.activeMessageID == nil, !speech.isPreparing, !speech.isSpeaking else {
            fputs("SpeechService did not reset playback state after offline failure\n", stderr)
            exit(1)
        }

        speech.speak(messageID: "cancel-smoke", text: "这条语音应当立即停止。")
        speech.stop()
        try? await Task.sleep(for: .milliseconds(200))
        guard speech.activeMessageID == nil, !speech.isPreparing, !speech.isSpeaking else {
            fputs("SpeechService stop did not leave a clean state\n", stderr)
            exit(1)
        }

        print("Native SpeechService offline and stop smoke passed")
    }
}
