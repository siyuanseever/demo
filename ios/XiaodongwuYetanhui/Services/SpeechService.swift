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
    @Published private(set) var queuedMessageID: String?
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

    private struct QueuedItem {
        let messageID: String
        let text: String
    }

    private static let autoReadKey = "speech.automaticallyReadsReplies"
    private static var serviceBaseURL: URL {
#if DEBUG
        if let rawValue = ProcessInfo.processInfo.environment["SENSEN_TTS_BASE_URL"],
           let overriddenURL = URL(string: rawValue),
           ["http", "https"].contains(overriddenURL.scheme?.lowercased() ?? "") {
            return overriddenURL
        }
#endif
        return URL(string: "http://127.0.0.1:8768")!
    }
    private static var streamEndpoint: URL {
        serviceBaseURL.appendingPathComponent("v1/audio/speech/stream")
    }
    private static var fallbackEndpoint: URL {
        serviceBaseURL.appendingPathComponent("v1/audio/speech")
    }
    private static var cancelEndpoint: URL {
        serviceBaseURL.appendingPathComponent("v1/audio/speech/cancel")
    }
    private static let voiceInstruction = "平静、克制、自然地说，像一位年轻女孩在安静地陪伴朋友。保持稳定音量和清晰发音，情绪起伏小，不使用哭腔、气声、播音腔或撒娇语气。"

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var generationTask: Task<Void, Never>?
    private var requestID: UUID?
    private var pendingBuffers: Int = 0
    private var playbackContinuation: CheckedContinuation<Void, Never>?
    private var queuedItem: QueuedItem?
    private var queuedPrefetchTask: Task<Data, Error>?

    override init() {
        automaticallyReadsReplies = UserDefaults.standard.bool(forKey: Self.autoReadKey)
        super.init()
    }

    var isActive: Bool {
        activeMessageID != nil && (isPreparing || isSpeaking)
    }

    var hasQueued: Bool {
        queuedItem != nil
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

        stop(cancelRemote: false)
        startPlayback(messageID: messageID, text: cleanText)
    }

    func enqueue(messageID: String, text: String) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        if !isActive {
            startPlayback(messageID: messageID, text: cleanText)
            return
        }

        queuedItem = QueuedItem(messageID: messageID, text: cleanText)
        queuedMessageID = messageID
        queuedPrefetchTask?.cancel()
        queuedPrefetchTask = Task {
            try await Self.fetchCompleteAudio(text: cleanText)
        }
    }

    func previewVoice() {
        speak(
            messageID: "speech-preview",
            text: "晚上好呀，我是忧忧兔。你可以慢慢说，我会安静地听着。"
        )
    }

    func stop() {
        stop(cancelRemote: true)
    }

    private func stop(cancelRemote: Bool) {
        let shouldCancelRemote = isActive || queuedItem != nil || queuedPrefetchTask != nil
        queuedItem = nil
        queuedMessageID = nil
        queuedPrefetchTask?.cancel()
        queuedPrefetchTask = nil
        generationTask?.cancel()
        generationTask = nil
        requestID = nil
        stopEngine()
        resetPlaybackState()
        if cancelRemote, shouldCancelRemote {
            Task {
                await Self.cancelRemoteGeneration()
            }
        }
    }

    private func startPlayback(
        messageID: String,
        text: String,
        preparedAudioTask: Task<Data, Error>? = nil
    ) {
        let currentRequestID = UUID()
        requestID = currentRequestID
        activeMessageID = messageID
        isPreparing = true
        lastError = nil

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let preparedAudioTask {
                    let audio = try await preparedAudioTask.value
                    try await self.playCompleteAudio(audio, requestID: currentRequestID)
                } else {
                    try await self.streamAndPlay(text: text, requestID: currentRequestID)
                }
                await self.handlePlaybackFinished(requestID: currentRequestID)
            } catch is CancellationError {
                return
            } catch {
                guard requestID == currentRequestID else { return }
                self.resetPlaybackState()
                self.lastError = "本地自然语音暂时不可用。请用 scripts/run_mac.sh 启动应用，或查看 logs/tts.log。"
                self.checkAndPlayQueued()
            }
        }
    }

    private func handlePlaybackFinished(requestID finishedRequestID: UUID) async {
        guard requestID == finishedRequestID else { return }
        resetPlaybackState()
        checkAndPlayQueued()
    }

    private func checkAndPlayQueued() {
        guard let item = queuedItem else { return }
        let preparedAudioTask = queuedPrefetchTask
        queuedItem = nil
        queuedMessageID = nil
        queuedPrefetchTask = nil
        startPlayback(
            messageID: item.messageID,
            text: item.text,
            preparedAudioTask: preparedAudioTask
        )
    }

    // MARK: - Streaming playback

    private func streamAndPlay(text: String, requestID: UUID) async throws {
        var request = try Self.makeRequest(url: Self.streamEndpoint, text: text)
        request.timeoutInterval = 300

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpeechServiceError.invalidResponse
        }

        var iterator = bytes.makeAsyncIterator()
        var headerData = Data()
        while headerData.count < 44 {
            guard let byte = try? await iterator.next() else { break }
            headerData.append(byte)
        }
        guard headerData.count >= 44 else {
            throw SpeechServiceError.invalidResponse
        }

        let sampleRate = readUInt32(headerData, offset: 24)
        let numChannels = readUInt16(headerData, offset: 22)
        let bitsPerSample = readUInt16(headerData, offset: 34)

        guard sampleRate > 0, numChannels > 0, bitsPerSample == 16 else {
            throw SpeechServiceError.invalidResponse
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(numChannels),
            interleaved: true
        ) else {
            throw SpeechServiceError.playbackFailed
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        try engine.start()
        playerNode.play()

        self.audioEngine = engine
        self.playerNode = playerNode
        self.isPreparing = false
        self.isSpeaking = true

        var buffer = Data()
        let bytesPerFrame = Int(numChannels) * Int(bitsPerSample) / 8
        let targetChunkBytes = 16384

        while let byte = try await iterator.next() {
            try Task.checkCancellation()
            guard requestID == self.requestID else { return }

            buffer.append(byte)
            if buffer.count >= targetChunkBytes {
                schedulePCMBuffer(buffer, format: format, bytesPerFrame: bytesPerFrame)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !buffer.isEmpty {
            schedulePCMBuffer(buffer, format: format, bytesPerFrame: bytesPerFrame)
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.playbackContinuation = continuation
            self.checkPlaybackComplete()
        }
    }

    private static func fetchCompleteAudio(text: String) async throws -> Data {
        var request = try makeRequest(url: fallbackEndpoint, text: text)
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              data.count > 44 else {
            throw SpeechServiceError.invalidResponse
        }
        return data
    }

    private static func cancelRemoteGeneration() async {
        var request = URLRequest(url: cancelEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func makeRequest(url: URL, text: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            LocalSpeechRequest(
                model: "qwen3-tts-0.6b-customvoice-4bit",
                input: text,
                voice: "Serena",
                instruct: voiceInstruction
            )
        )
        return request
    }

    private func playCompleteAudio(_ wavData: Data, requestID: UUID) async throws {
        guard wavData.count > 44 else { throw SpeechServiceError.invalidResponse }
        let sampleRate = readUInt32(wavData, offset: 24)
        let numChannels = readUInt16(wavData, offset: 22)
        let bitsPerSample = readUInt16(wavData, offset: 34)
        guard sampleRate > 0, numChannels > 0, bitsPerSample == 16,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(sampleRate),
                channels: AVAudioChannelCount(numChannels),
                interleaved: true
              ) else {
            throw SpeechServiceError.invalidResponse
        }

        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try engine.start()
        playerNode.play()

        guard requestID == self.requestID else { return }
        self.audioEngine = engine
        self.playerNode = playerNode
        self.isPreparing = false
        self.isSpeaking = true

        let pcmData = Data(wavData.dropFirst(44))
        let bytesPerFrame = Int(numChannels) * Int(bitsPerSample) / 8
        schedulePCMBuffer(pcmData, format: format, bytesPerFrame: bytesPerFrame)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.playbackContinuation = continuation
            self.checkPlaybackComplete()
        }
    }

    private func schedulePCMBuffer(_ data: Data, format: AVAudioFormat, bytesPerFrame: Int) {
        guard let playerNode = playerNode else { return }

        let frameCount = AVAudioFrameCount(data.count / bytesPerFrame)
        guard frameCount > 0 else { return }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        data.withUnsafeBytes { rawBufferPointer in
            let dest = pcmBuffer.audioBufferList.pointee.mBuffers.mData!
            let src = rawBufferPointer.baseAddress!
            memcpy(dest, src, data.count)
        }

        pendingBuffers += 1
        playerNode.scheduleBuffer(pcmBuffer) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pendingBuffers -= 1
                self.checkPlaybackComplete()
            }
        }
    }

    private func checkPlaybackComplete() {
        if pendingBuffers == 0 && playbackContinuation != nil {
            let continuation = playbackContinuation
            playbackContinuation = nil
            continuation?.resume()
        }
    }

    // MARK: - Engine management

    private func stopEngine() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        pendingBuffers = 0
        let continuation = playbackContinuation
        playbackContinuation = nil
        continuation?.resume()
    }

    // MARK: - Helpers

    private func resetPlaybackState() {
        activeMessageID = nil
        isPreparing = false
        isSpeaking = false
    }

    private func readUInt32(_ data: Data, offset: Int) -> UInt32 {
        data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }
    }

    private func readUInt16(_ data: Data, offset: Int) -> UInt16 {
        data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }
    }
}

private enum SpeechServiceError: Error {
    case invalidResponse
    case playbackFailed
}
