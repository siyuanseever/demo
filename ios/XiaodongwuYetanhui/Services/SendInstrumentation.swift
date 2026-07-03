import Foundation
import OSLog

final class SendInstrumentation {
    static let shared = SendInstrumentation()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SensenStory",
        category: "SendInstrumentation"
    )

    private let queue = DispatchQueue(label: "xiaodongwu.send.instrumentation")

    private var activeSends: [String: SendTrackingState] = [:]
    private var recentEvents: [SendPhaseEvent] = []
    private let maxRecentEvents = 50

    private var heartbeatTimer: DispatchSourceTimer?
    private var lastMainThreadTick: Date = Date()
    private var heartbeatCount: Int64 = 0
    private var heartbeatTickPending = false

    private var hangDetectionTimer: DispatchSourceTimer?
    private let hangThreshold: TimeInterval = 1.0
    private let hangCaptureCooldown: TimeInterval = 30.0
    private var lastHangCapturedAt: Date?

    private init() {
        startHeartbeat()
        startHangDetection()
    }

    func beginSend(messageLength: Int, isGroupMode: Bool) -> String {
        let correlationID = "send-\(UUID().uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970))"
        let state = SendTrackingState(
            correlationID: correlationID,
            messageLength: messageLength,
            isGroupMode: isGroupMode,
            startedAt: Date()
        )
        queue.async { [weak self] in
            self?.activeSends[correlationID] = state
        }
        recordPhase(.sendTapped, correlationID: correlationID, metadata: [
            "message_length": String(messageLength),
            "group_mode": isGroupMode ? "true" : "false"
        ])
        logger.info("[\(correlationID, privacy: .public)] send_tapped length=\(messageLength, privacy: .public) group=\(isGroupMode ? "yes" : "no", privacy: .public)")
        return correlationID
    }

    func recordPhase(_ phase: SendPhase, correlationID: String, metadata: [String: String] = [:]) {
        let event = SendPhaseEvent(
            correlationID: correlationID,
            phase: phase,
            timestamp: Date(),
            metadata: metadata
        )
        queue.async { [weak self] in
            guard let self else { return }
            self.recentEvents.append(event)
            if self.recentEvents.count > self.maxRecentEvents {
                self.recentEvents.removeFirst(self.recentEvents.count - self.maxRecentEvents)
            }
            if self.activeSends[correlationID] != nil {
                self.activeSends[correlationID]?.lastPhase = phase
                self.activeSends[correlationID]?.lastPhaseAt = Date()
            }
        }
        logger.info("[\(correlationID, privacy: .public)] phase=\(phase.rawValue, privacy: .public)")
    }

    func endSend(_ correlationID: String, success: Bool, error: String? = nil) {
        recordPhase(success ? .storeApplyFinished : .error, correlationID: correlationID, metadata: [
            "success": success ? "true" : "false",
            "error": error ?? ""
        ])
        queue.async { [weak self] in
            guard let self else { return }
            if let state = self.activeSends[correlationID] {
                let duration = Date().timeIntervalSince(state.startedAt)
                self.logger.info("[\(correlationID, privacy: .public)] completed duration_ms=\(Int(duration * 1000), privacy: .public) success=\(success ? "yes" : "no", privacy: .public)")
            }
            self.activeSends.removeValue(forKey: correlationID)
        }
    }

    func currentActiveSends() -> [SendTrackingState] {
        queue.sync {
            Array(activeSends.values)
        }
    }

    func recentEvents(limit: Int = 30) -> [SendPhaseEvent] {
        queue.sync {
            Array(recentEvents.suffix(limit))
        }
    }

    var heartbeatInfo: HeartbeatInfo {
        queue.sync {
            HeartbeatInfo(
                lastMainThreadTick: lastMainThreadTick,
                heartbeatCount: heartbeatCount,
                currentGap: Date().timeIntervalSince(lastMainThreadTick),
                pendingTickCount: heartbeatTickPending ? 1 : 0
            )
        }
    }

    var hasHangRisk: Bool {
        let gap = Date().timeIntervalSince(heartbeatInfo.lastMainThreadTick)
        return gap > hangThreshold
    }

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: .milliseconds(200), leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let shouldScheduleTick = self.queue.sync {
                guard !self.heartbeatTickPending else { return false }
                self.heartbeatTickPending = true
                return true
            }
            guard shouldScheduleTick else { return }
            DispatchQueue.main.async {
                let now = Date()
                self.queue.async {
                    self.lastMainThreadTick = now
                    self.heartbeatCount += 1
                    self.heartbeatTickPending = false
                }
            }
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func startHangDetection() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 1.0, repeating: .milliseconds(500), leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            let gap = now.timeIntervalSince(self.heartbeatInfo.lastMainThreadTick)
            if gap > self.hangThreshold, self.shouldCaptureHang(at: now) {
                self.captureHangSample(mainThreadGap: gap)
            }
        }
        timer.resume()
        hangDetectionTimer = timer
    }

    private func shouldCaptureHang(at now: Date) -> Bool {
        queue.sync {
            if let lastCapture = lastHangCapturedAt,
               now.timeIntervalSince(lastCapture) < hangCaptureCooldown {
                return false
            }
            lastHangCapturedAt = now
            return true
        }
    }

    private func captureHangSample(mainThreadGap: TimeInterval) {
        let activeSends = currentActiveSends()
        let events = recentEvents(limit: 30)
        let sample = HangSample(
            capturedAt: Date(),
            mainThreadGap: mainThreadGap,
            activeSendCount: activeSends.count,
            lastPhase: activeSends.first?.lastPhase,
            lastPhaseAt: activeSends.first?.lastPhaseAt,
            recentEventCount: events.count,
            memoryUsage: Self.memoryUsage(),
            cpuUsage: Self.cpuUsage()
        )
        let gapText = String(format: "%.1f", mainThreadGap)
        let activeSendCount = activeSends.count
        let lastPhase = activeSends.first?.lastPhase.rawValue ?? "none"
        let memoryUsageMB = sample.memoryUsageMB
        logger.error(
            "HANG_DETECTED gap=\(gapText, privacy: .public)s active_sends=\(activeSendCount, privacy: .public) last_phase=\(lastPhase, privacy: .public) memory_mb=\(memoryUsageMB, privacy: .public)"
        )
        var eventDescriptions: [String] = []
        for event in events.suffix(10) {
            let ts = ISO8601DateFormatter().string(from: event.timestamp)
            eventDescriptions.append("[\(ts)] \(event.correlationID): \(event.phase.rawValue)")
        }
        logger.error("Recent events:\n\(eventDescriptions.joined(separator: "\n"), privacy: .public)")
    }

    private static func memoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return info.resident_size
        }
        return 0
    }

    private static func cpuUsage() -> Double {
        var kr: kern_return_t
        var task_info_count: mach_msg_type_number_t = mach_msg_type_number_t(TASK_INFO_MAX)
        var tinfo = [integer_t](repeating: 0, count: Int(task_info_count))
        kr = task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), &tinfo, &task_info_count)
        if kr != KERN_SUCCESS { return -1 }

        var thread_array: thread_act_array_t? = nil
        var thread_count: mach_msg_type_number_t = 0
        defer {
            if let thread_array = thread_array {
                let address = vm_address_t(UInt(bitPattern: thread_array))
                let size = vm_size_t(thread_count) * vm_size_t(MemoryLayout<thread_t>.stride)
                vm_deallocate(mach_task_self_, address, size)
            }
        }
        kr = task_threads(mach_task_self_, &thread_array, &thread_count)
        if kr != KERN_SUCCESS { return -1 }

        var tot_cpu: Double = 0
        if let thread_array = thread_array {
            for j in 0..<Int(thread_count) {
                var thread_info_count = mach_msg_type_number_t(THREAD_INFO_MAX)
                var thinfo = [integer_t](repeating: 0, count: Int(thread_info_count))
                kr = thread_info(thread_array[j], thread_flavor_t(THREAD_BASIC_INFO), &thinfo, &thread_info_count)
                if kr != KERN_SUCCESS { continue }
                let threadBasicInfo = thinfo.withUnsafeBytes {
                    $0.load(as: thread_basic_info.self)
                }
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    tot_cpu += Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }
        }
        return tot_cpu
    }
}

struct SendTrackingState {
    let correlationID: String
    let messageLength: Int
    let isGroupMode: Bool
    let startedAt: Date
    var lastPhase: SendPhase = .sendTapped
    var lastPhaseAt: Date = Date()
}

enum SendPhase: String, Codable {
    case sendTapped = "send_tapped"
    case sendTaskStarted = "send_task_started"
    case requestEncodeStarted = "request_encode_started"
    case requestResumed = "request_resumed"
    case backendReceived = "backend_received"
    case firstResponseReceived = "first_response_received"
    case storeApplyStarted = "store_apply_started"
    case storeApplyFinished = "store_apply_finished"
    case error = "error"
}

struct SendPhaseEvent {
    let correlationID: String
    let phase: SendPhase
    let timestamp: Date
    let metadata: [String: String]
}

struct HeartbeatInfo {
    let lastMainThreadTick: Date
    let heartbeatCount: Int64
    let currentGap: TimeInterval
    let pendingTickCount: Int
}

struct HangSample {
    let capturedAt: Date
    let mainThreadGap: TimeInterval
    let activeSendCount: Int
    let lastPhase: SendPhase?
    let lastPhaseAt: Date?
    let recentEventCount: Int
    let memoryUsage: UInt64
    let cpuUsage: Double

    var memoryUsageMB: Int {
        Int(Double(memoryUsage) / 1024.0 / 1024.0)
    }
}
