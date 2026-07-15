import Foundation
import SwiftUI
#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
#endif

struct CompanionCharacter: Identifiable, Hashable {
    let id: String
    let name: String
    let animal: String
    let systemImageName: String
    let avatarName: String
    let tagline: String
    let voice: String
    let bubbleColor: Color
    let defaultExpressionID: String
    let expressions: [CompanionExpression]
}

struct CompanionExpression: Identifiable, Hashable {
    let id: String
    let label: String
    let assetName: String
}

extension CompanionCharacter {
    func expression(id: String?) -> CompanionExpression? {
        if let id, let expression = expressions.first(where: { $0.id == id }) {
            return expression
        }
        return expressions.first { $0.id == defaultExpressionID } ?? expressions.first
    }
}

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let role: MessageRole
    let content: String
    let characterID: String?
    let createdAt: String
    var groupRole: String = ""
    var action: String = ""
    var expressionID: String = ""
    var replyStage: String = ""
    var routeSummary: String?
    var knowledgeCards: [KnowledgeCard] = []
    var retrievedMemories: [MemoryEntry] = []
}

struct UserConversationAssessment: Hashable {
    let userState: String
    let coreNeed: String
    let riskLevel: String
    let responseMode: String
    let reason: String
    let nextAction: String
}

enum MessageRole: String {
    case user
    case assistant
    case system
}

struct KnowledgeCard: Identifiable, Hashable {
    let id: String
    let title: String
    let concept: String
}

struct SessionSummary: Identifiable, Hashable {
    let id: String
    let createdAt: String
    let endedAt: String
    let messageCount: Int
    let preview: String
}

struct MemoryEntry: Identifiable, Hashable {
    let id: String
    let category: String
    let subcategory: String
    let content: String
    let evidence: String
    let keywords: [String]
    let sourceSessionID: String
    let importance: Int
    let updatedAt: String
}

struct JournalEntry: Identifiable, Hashable {
    let id: String
    let sessionID: String
    let summary: String
    let emotionCurve: [String]
    let keywords: [String]
    let insights: [String]
    let dominantEmotion: String
    let moodScore: Int
    let suggestedNextStep: String
    let createdAt: String
}

struct StateProfile: Identifiable, Hashable {
    let id: String
    let domain: String
    let stage: String
    let summary: String
    let intensity: Int
    let trend: String
    let confidence: Double
    let evidence: String
    let supportStrategy: String
    let sourceSessionID: String
    let updatedAt: String
}

struct StarMapInsight: Identifiable, Codable, Hashable {
    let id: String
    let generatedAt: Date
    let periodStart: Date
    let periodEnd: Date
    let primaryGoalTitle: String
    let primaryGoalReason: String
    let primaryGoalNextStep: String
    let primaryGoalChallenge: String
    let secondaryGoalTitle: String
    let secondaryGoalReason: String
    let secondaryGoalNextStep: String
    let secondaryGoalChallenge: String
    let recentEmotionSummary: String
    let recentEmotionTags: [String]
    let flowSupport: String
    let memoryCues: [String]
    let coreInsight: String
    let coreInsightDetail: String
    let recentPatternTitle: String
    let recentPatternItems: [String]
    let recentPatternDetail: String
    let flowConditionTitle: String
    let flowConditionItems: [String]
    let flowConditionDetail: String
    let gentleReminderTitle: String
    let gentleReminder: String
    let gentleReminderDetail: String
    let sourceSummary: String

    var recentPattern: [String] {
        recentPatternItems
    }

    var flowConditions: [String] {
        flowConditionItems
    }

    var periodLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return "\(formatter.string(from: periodStart)) - \(formatter.string(from: periodEnd))"
    }

    var isMockInsight: Bool {
        id == StarMapInsight.mock.id
            || primaryGoalTitle == StarMapInsight.mock.primaryGoalTitle
            || sourceSummary.contains("mock 数据")
            || sourceSummary.contains("fake 模式")
    }

    var hasSecondaryGoal: Bool {
        !secondaryGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let mock = StarMapInsight(
        id: "mock-star-map-insight",
        generatedAt: Date(),
        periodStart: Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date(),
        periodEnd: Date(),
        primaryGoalTitle: "先连接真实数据，再生成你的主要目标",
        primaryGoalReason: "目前还没有读取到后端生成的心流导航。这一页暂时只展示结构，不代表对你的真实判断。",
        primaryGoalNextStep: "检查后端连接并重新生成心流导航。",
        primaryGoalChallenge: "轻量",
        secondaryGoalTitle: "",
        secondaryGoalReason: "",
        secondaryGoalNextStep: "",
        secondaryGoalChallenge: "",
        recentEmotionSummary: "还没有足够的真实总结和情绪记录可供分析。",
        recentEmotionTags: ["等待数据"],
        flowSupport: "真实数据连接后，这里会根据目标、情绪和长期记忆给出更具体的进入方式。",
        memoryCues: ["这里将显示与当前目标有关的跨会话记忆提醒。"],
        coreInsight: "过去两个月里，\n你最有生命力的时刻，\n都发生在探索未知的时候。",
        coreInsightDetail: "这是一版本地 mock 的云朵观察。后续会根据最近 30-60 天的夜谈、总结、长期状态和记忆，让这里变成真正按月更新的生命力摘要。",
        recentPatternTitle: "最近的模式",
        recentPatternItems: ["阅读", "思考", "创造"],
        recentPatternDetail: "最近的节奏更像是：先被一个问题牵住，随后独自反复琢磨，最后在表达或创造里慢慢把它变清楚。",
        flowConditionTitle: "容易进入心流的时候",
        flowConditionItems: ["夜晚", "独处", "没有明确答案的问题"],
        flowConditionDetail: "当你不需要立刻给出正确答案，而是可以把注意力放在探索、连接和表达上时，更容易进入一种持续而专注的流动状态。",
        gentleReminderTitle: "一个温柔提醒",
        gentleReminder: "最近你已经很久\n没有探索新的问题了。",
        gentleReminderDetail: "如果最近总在处理压力和必须完成的事情，也许可以给自己留一点没有结果压力的空间，让好奇心慢慢回来。",
        sourceSummary: "基于最近的夜谈、日记和长期状态，暂时用本地 mock 数据呈现第一版星图。"
    )
}

struct DashboardSnapshot {
    var sessionCount: Int = 0
    var messageCount: Int = 0
    var memoryCount: Int = 0
    var journalCount: Int = 0
}

enum BackendConnectionState: String {
    case unknown = "未检查"
    case checking = "检查中"
    case online = "已连接"
    case fallback = "原型接住"
}

struct BackendConnectionStatus {
    var state: BackendConnectionState = .unknown
    var baseURL: String = ""
    var detail: String = "还没有检查本地后端连接。"
    var lastCheckedAt: Date?

    var isOnline: Bool {
        state == .online
    }
}

struct EmotionMonster: Identifiable, Hashable {
    let id: String
    let name: String
    let colorName: String
    let systemImageName: String
    let colorHex: UInt
    let prompt: String

    var color: Color {
        Color(hex: colorHex)
    }
}

struct EmotionCheckIn: Hashable {
    let monster: EmotionMonster
    let intensity: Double
    let note: String
    let createdAt: Date

    var intensityLabel: String {
        switch intensity {
        case 0..<0.34:
            return "轻轻的"
        case 0.34..<0.67:
            return "有一点明显"
        default:
            return "很强烈"
        }
    }
}

enum CompanionInteractionKind: String, Hashable {
    case checkIn
    case grounding
    case reflection
    case recommendation
    case tinyGame
}

struct CompanionInteractionOffer: Identifiable, Hashable {
    let id: String
    let kind: CompanionInteractionKind
    let title: String
    let subtitle: String
    let systemImageName: String
    let tint: Color
    let prompt: String
    let fallbackReply: String
}

extension CompanionInteractionKind {
    var displayName: String {
        switch self {
        case .checkIn:
            return "识别"
        case .grounding:
            return "安定"
        case .reflection:
            return "整理"
        case .recommendation:
            return "推荐"
        case .tinyGame:
            return "游戏"
        }
    }
}

extension CompanionInteractionOffer {
    var actionTitle: String {
        switch kind {
        case .checkIn:
            return "开始选择"
        case .grounding:
            return "做锚点"
        case .reflection:
            return "写小卡"
        case .recommendation:
            return "请它推荐"
        case .tinyGame:
            return "开始照顾"
        }
    }
}

struct MonsterCareAction: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImageName: String
    let message: String
    let reflectionPrompt: String
}

struct MonsterSafePlace: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImageName: String
    let detail: String
    let reflectionHint: String
}

struct CareMoment: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let detail: String
    let systemImageName: String
    let tintHex: UInt
    let createdAt: Date

    var tint: Color {
        Color(hex: tintHex)
    }
}

struct FlowMoment: Identifiable, Hashable, Codable {
    let id: String
    let intention: String
    let ending: String
    let createdAt: Date
}

struct BailanDiaryEntry: Identifiable, Hashable, Codable {
    let id: String
    let content: String
    let response: String
    let createdAt: Date
}

struct PlanItem: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var isDone: Bool
}

struct FlowContext: Identifiable, Hashable {
    let id: String
    var primaryGoal: String
    var emotionWeather: String
    var recentPattern: String
    var gentleReminder: String
    var dontCareItems: [String]
    var todayPlanItems: [PlanItem]
    var latestBailanDiary: BailanDiaryEntry?
    var latestFlowMoment: FlowMoment?

    static var empty: FlowContext {
        FlowContext(
            id: UUID().uuidString,
            primaryGoal: "",
            emotionWeather: "",
            recentPattern: "",
            gentleReminder: "",
            dontCareItems: [],
            todayPlanItems: [],
            latestBailanDiary: nil,
            latestFlowMoment: nil
        )
    }
}

enum RecommendationMedium: String, Codable, CaseIterable {
    case book
    case music
    case movie

    var displayName: String {
        switch self {
        case .book:
            return "书"
        case .music:
            return "音乐"
        case .movie:
            return "电影"
        }
    }

    var systemImageName: String {
        switch self {
        case .book:
            return "book.closed.fill"
        case .music:
            return "music.note"
        case .movie:
            return "film.fill"
        }
    }
}

struct CompanionRecommendation: Identifiable, Hashable, Codable {
    let id: String
    let medium: RecommendationMedium
    let title: String
    let creator: String
    let reason: String
    let practice: String
    let tintHex: UInt
    let createdAt: Date

    var tint: Color {
        Color(hex: tintHex)
    }

    var displayTitle: String {
        creator.isEmpty ? title : "\(title) · \(creator)"
    }
}

enum CompanionFixtures {
    static let emotionMonsters: [EmotionMonster] = [
        EmotionMonster(
            id: "tired",
            name: "困困怪",
            colorName: "雾蓝",
            systemImageName: "bed.double.fill",
            colorHex: 0xcfe2ec,
            prompt: "它像一团软雾，提醒你身体可能需要被放过。"
        ),
        EmotionMonster(
            id: "sad",
            name: "雨雨怪",
            colorName: "淡紫",
            systemImageName: "cloud.rain.fill",
            colorHex: 0xded7ef,
            prompt: "它带着一点雨水，可能是在替难过找一个出口。"
        ),
        EmotionMonster(
            id: "anxious",
            name: "团团怪",
            colorName: "浅黄",
            systemImageName: "tornado",
            colorHex: 0xf6dda2,
            prompt: "它绕来绕去，像在说：我想确认自己是安全的。"
        ),
        EmotionMonster(
            id: "angry",
            name: "刺刺怪",
            colorName: "暖橘",
            systemImageName: "flame.fill",
            colorHex: 0xf0b18f,
            prompt: "它有小小的刺，可能在保护你的边界。"
        ),
        EmotionMonster(
            id: "clear",
            name: "亮亮怪",
            colorName: "嫩绿",
            systemImageName: "sparkle.magnifyingglass",
            colorHex: 0xcfe6bf,
            prompt: "它带来一点清亮，像是终于可以看见下一小步。"
        ),
    ]

    static let characters: [CompanionCharacter] = [
        CompanionCharacter(
            id: "yoyo",
            name: "忧忧兔",
            animal: "月亮兔",
            systemImageName: "moon.fill",
            avatarName: "sensen-emoji-yoyo-listening",
            tagline: "柔软、敏感、能停在痛苦旁边，先把情绪接住。",
            voice: "低声、共情、脆弱但真诚。",
            bubbleColor: Color.bubbleYoyo,
            defaultExpressionID: "listening",
            expressions: [
                CompanionExpression(id: "bashful", label: "害羞", assetName: "sensen-emoji-yoyo-bashful"),
                CompanionExpression(id: "concerned", label: "担心", assetName: "sensen-emoji-yoyo-concerned"),
                CompanionExpression(id: "gentlesmile", label: "轻轻笑", assetName: "sensen-emoji-yoyo-gentlesmile"),
                CompanionExpression(id: "hug", label: "抱抱", assetName: "sensen-emoji-yoyo-hug"),
                CompanionExpression(id: "listening", label: "倾听", assetName: "sensen-emoji-yoyo-listening"),
                CompanionExpression(id: "proud", label: "为你骄傲", assetName: "sensen-emoji-yoyo-proud"),
                CompanionExpression(id: "understanding", label: "理解", assetName: "sensen-emoji-yoyo-understanding"),
            ]
        ),
        CompanionCharacter(
            id: "momo",
            name: "默默兔",
            animal: "云朵兔",
            systemImageName: "shield.lefthalf.filled",
            avatarName: "sensen-emoji-momo-hi",
            tagline: "安静但有力量，帮你把混乱慢慢变成可以走的一小步。",
            voice: "稳定、具体、保护边界。",
            bubbleColor: Color.bubbleMomo,
            defaultExpressionID: "hi",
            expressions: [
                CompanionExpression(id: "celebrate", label: "庆祝一下", assetName: "sensen-emoji-momo-celebrate"),
                CompanionExpression(id: "curious", label: "好奇", assetName: "sensen-emoji-momo-curious"),
                CompanionExpression(id: "encouraging", label: "鼓励你", assetName: "sensen-emoji-momo-encouraging"),
                CompanionExpression(id: "hi", label: "打招呼", assetName: "sensen-emoji-momo-hi"),
                CompanionExpression(id: "ok", label: "没关系", assetName: "sensen-emoji-momo-ok"),
                CompanionExpression(id: "ready", label: "准备好了", assetName: "sensen-emoji-momo-ready"),
                CompanionExpression(id: "thinking", label: "想一想", assetName: "sensen-emoji-momo-thinking"),
                CompanionExpression(id: "wistful", label: "有点怅然", assetName: "sensen-emoji-momo-wistful"),
            ]
        ),
        CompanionCharacter(
            id: "yoran",
            name: "悠然兔",
            animal: "星月兔",
            systemImageName: "leaf.fill",
            avatarName: "sensen-emoji-yoran-serene",
            tagline: "清明、平衡、能把感受和现实放在同一个温柔空间里。",
            voice: "松弛、开阔、带一点安稳的看见。",
            bubbleColor: Color.bubbleYoran,
            defaultExpressionID: "serene",
            expressions: [
                CompanionExpression(id: "content", label: "满足", assetName: "sensen-emoji-yoran-content"),
                CompanionExpression(id: "ready", label: "准备好了", assetName: "sensen-emoji-yoran-ready"),
                CompanionExpression(id: "sad", label: "有点难过", assetName: "sensen-emoji-yoran-sad"),
                CompanionExpression(id: "serene", label: "平静", assetName: "sensen-emoji-yoran-serene"),
                CompanionExpression(id: "wistful", label: "怅然", assetName: "sensen-emoji-yoran-wistful"),
            ]
        ),
    ]

    static let legacyCharacterAliases: [String: String] = [
        "sensen_deer": "yoyo",
        "youyou_rabbit": "yoyo",
        "gugu_bear": "momo",
        "gangan_tiger": "momo",
        "huahua_fox": "yoran",
        "shanshan_butterfly": "yoran",
    ]

    static func character(id: String?) -> CompanionCharacter? {
        guard let id else { return nil }
        let normalizedID = legacyCharacterAliases[id] ?? id
        return characters.first { $0.id == normalizedID }
    }

    static let interactionOffers: [CompanionInteractionOffer] = [
        CompanionInteractionOffer(
            id: "monster-check-in",
            kind: .checkIn,
            title: "情绪小怪兽",
            subtitle: "把感受先变成能碰到的小东西。",
            systemImageName: "face.smiling.inverse",
            tint: Color(hex: 0xf0b18f),
            prompt: "我想做一个情绪小怪兽 check-in。请先温柔地引导我选一种情绪、强度和一句备注。",
            fallbackReply: "可以。先不急着解释，我们只做三个很小的动作：选一只最靠近此刻的小怪兽，给它一个强度，再给它留一句话。"
        ),
        CompanionInteractionOffer(
            id: "room-anchor",
            kind: .grounding,
            title: "房间锚点",
            subtitle: "用 30 秒确认此刻是安全的。",
            systemImageName: "smallcircle.filled.circle",
            tint: Color(hex: 0xcfe2ec),
            prompt: "我想做一个 30 秒房间锚点练习。请用很短的步骤带我看见当下、身体和环境。",
            fallbackReply: "我们做 30 秒就好：看见一个稳定的物体，感受脚底或坐垫，再慢慢呼一口气。你不需要马上变好，只需要确认自己此刻在这里。"
        ),
        CompanionInteractionOffer(
            id: "boundary-card",
            kind: .reflection,
            title: "边界小卡",
            subtitle: "把不舒服变成一句更清楚的话。",
            systemImageName: "shield.lefthalf.filled",
            tint: Color(hex: 0xe8f3de),
            prompt: "我想做一张边界小卡。请帮我把现在的不舒服整理成一句温和但清楚的边界表达。",
            fallbackReply: "可以先用这个句式：我注意到我在这里有点不舒服；我需要先慢一点；这件事我想之后再决定。"
        ),
        CompanionInteractionOffer(
            id: "soft-recommendation",
            kind: .recommendation,
            title: "今晚推荐",
            subtitle: "给此刻配一本书、一首歌或一部电影。",
            systemImageName: "sparkles.rectangle.stack.fill",
            tint: Color(hex: 0xded7ef),
            prompt: "请根据我现在的状态，推荐一本书、一首音乐或一部电影。不要太多，只给一个很贴近今晚的小推荐，并说明为什么。",
            fallbackReply: "今晚先只选一个很小的陪伴：一首慢一点的纯音乐，或者一段熟悉的电影片段。重点不是获得建议，而是让夜晚多一个柔软的支点。"
        ),
        CompanionInteractionOffer(
            id: "monster-care",
            kind: .tinyGame,
            title: "照顾小怪兽",
            subtitle: "给小怪兽一个动作，让情绪被轻轻处理。",
            systemImageName: "hands.sparkles.fill",
            tint: Color(hex: 0xcfe6bf),
            prompt: "我想玩一个很轻的情绪小怪兽照顾游戏。请带我选一只小怪兽，再给它一个照顾动作。",
            fallbackReply: "可以。我们不急着解决情绪，只先照顾它一下：选一只小怪兽，再选一个动作，比如盖毯子、点一盏灯、放一个边界圈。"
        ),
    ]

    static let monsterCareActions: [MonsterCareAction] = [
        MonsterCareAction(
            id: "blanket",
            title: "盖小毯子",
            systemImageName: "rectangle.fill.on.rectangle.angled.fill",
            message: "我给它盖了一条小毯子，让它先不用继续硬撑。",
            reflectionPrompt: "请根据这个动作回应我：它可能代表我需要一点休息、保暖或被允许停下来。"
        ),
        MonsterCareAction(
            id: "lamp",
            title: "点一盏灯",
            systemImageName: "lightbulb.fill",
            message: "我在它旁边点了一盏小灯，让这里稍微亮一点。",
            reflectionPrompt: "请根据这个动作回应我：它可能代表我想看清一点现实，或者给混乱留一个小光源。"
        ),
        MonsterCareAction(
            id: "fence",
            title: "放边界圈",
            systemImageName: "circle.dashed.inset.filled",
            message: "我给它放了一个柔软的边界圈，让它不用被外面的东西一直碰到。",
            reflectionPrompt: "请根据这个动作回应我：它可能代表我需要边界、距离和一点掌控感。"
        ),
    ]

    static let monsterSafePlaces: [MonsterSafePlace] = [
        MonsterSafePlace(
            id: "pillow-corner",
            title: "枕头角落",
            systemImageName: "bed.double.fill",
            detail: "让它靠在一个软软的角落里。",
            reflectionHint: "它可能需要休息、降低刺激和被允许暂时不用回应。"
        ),
        MonsterSafePlace(
            id: "warm-window",
            title: "暖灯窗边",
            systemImageName: "lamp.table.fill",
            detail: "给它留一小块有光的地方。",
            reflectionHint: "它可能需要一点可见度，知道自己不是独自待在黑暗里。"
        ),
        MonsterSafePlace(
            id: "quiet-box",
            title: "安静盒子",
            systemImageName: "shippingbox.fill",
            detail: "把外面的声音先隔远一点。",
            reflectionHint: "它可能需要边界、容器和更可控的空间。"
        ),
        MonsterSafePlace(
            id: "tiny-garden",
            title: "小小花园",
            systemImageName: "leaf.fill",
            detail: "让它旁边有一点正在生长的东西。",
            reflectionHint: "它可能需要慢慢恢复，不用马上开花。"
        ),
    ]
}

extension Color {
    // MARK: Legacy static colors (kept for backward compatibility)
    static let nightInk = Color(hex: 0x2f2823)
    static let warmBrown = Color(hex: 0x8b5f35)
    static let softPaper = Color(hex: 0xfffbf3)
    static let fieldGreen = Color(hex: 0xdfe8d5)
    static let duskRose = Color(hex: 0xe8b9a2)

    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    // MARK: Adaptive Color Factory

    static func adaptive(lightHex: UInt, darkHex: UInt, opacity: Double = 1) -> Color {
        #if os(macOS) && !targetEnvironment(macCatalyst)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? darkHex : lightHex
            return NSColor(
                calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: opacity
            )
        })
        #else
        Color(uiColor: UIColor { traitCollection in
            let hex = traitCollection.userInterfaceStyle == .dark ? darkHex : lightHex
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: opacity
            )
        })
        #endif
    }

    // MARK: Page Backgrounds
    static let pageBackground = Color.adaptive(lightHex: 0xFAF5EB, darkHex: 0x1C1A17)
    static let sidebarBackground = Color.adaptive(lightHex: 0xF5F0E6, darkHex: 0x22201C)
    static let conversationBgTop = Color.adaptive(lightHex: 0xFDFAF2, darkHex: 0x1E1D1A)
    static let conversationBgBottom = Color.adaptive(lightHex: 0xF2F7ED, darkHex: 0x1B1C19)
    static let warmBg1 = Color.adaptive(lightHex: 0xFFFBF3, darkHex: 0x1E1C19)
    static let warmBg2 = Color.adaptive(lightHex: 0xF8EFE2, darkHex: 0x201E1B)
    static let warmBg3 = Color.adaptive(lightHex: 0xEAF0DF, darkHex: 0x1C1D1A)

    // MARK: Card / Surface Colors
    static let cardBackground = Color.adaptive(lightHex: 0xFFFFFF, darkHex: 0x2A2723)
    static let cardGradientTop = Color.adaptive(lightHex: 0xF0F7E8, darkHex: 0x252321)
    static let cardGradientBottom = Color.adaptive(lightHex: 0xFAEDE6, darkHex: 0x23211E)
    static let cardGreenBackground = Color.adaptive(lightHex: 0xF0F5E6, darkHex: 0x232420)
    static let inputBackground = Color.adaptive(lightHex: 0xFFFFFF, darkHex: 0x2D2A27)
    static let cardBorder = Color.adaptive(lightHex: 0xFFFFFF, darkHex: 0x3A3530)

    // MARK: Overlay Colors
    static let overlaySubtle = Color.adaptive(lightHex: 0xFDF9F3, darkHex: 0x292623)
    static let overlayLight = Color.adaptive(lightHex: 0xFEFBF6, darkHex: 0x2E2B28)
    static let overlayMedium = Color.adaptive(lightHex: 0xFFFCF8, darkHex: 0x33302D)
    static let overlayHeavy = Color.adaptive(lightHex: 0xFFFDF9, darkHex: 0x383532)
    static let overlayMax = Color.adaptive(lightHex: 0xFFFDFA, darkHex: 0x3D3A37)

    // MARK: Accent Colors
    static let accentPurple = Color.adaptive(lightHex: 0x7563A8, darkHex: 0x9B8EC4)
    static let accentPurpleLight = Color.adaptive(lightHex: 0xEDE8F5, darkHex: 0x2D2838)
    static let accentPurpleLighter = Color.adaptive(lightHex: 0xF7F0E8, darkHex: 0x282420)
    static let accentGreen = Color.adaptive(lightHex: 0x618557, darkHex: 0x7BA67B)
    static let accentMutedGreen = Color.adaptive(lightHex: 0x576B4A, darkHex: 0x7D8F6A)

    // MARK: Mood / Status Colors
    static let moodPositive = Color.adaptive(lightHex: 0x598C59, darkHex: 0x6DA86D)
    static let moodNeutral = Color.adaptive(lightHex: 0x8C804D, darkHex: 0xA8995D)
    static let moodMildNegative = Color.adaptive(lightHex: 0x99664D, darkHex: 0xB38066)
    static let moodNegative = Color.adaptive(lightHex: 0x8C4D59, darkHex: 0xAD6B7A)

    // MARK: Text Colors
    static let textPrimary = Color.adaptive(lightHex: 0x4F475E, darkHex: 0xD8D0E0)
    static let textSecondary = Color.adaptive(lightHex: 0x736B80, darkHex: 0xB0A8B8)
    static let textTertiary = Color.adaptive(lightHex: 0x8C8296, darkHex: 0x908898)
    static let textGreenMuted = Color.adaptive(lightHex: 0x5C634F, darkHex: 0x9CA88A)

    // MARK: Flow-section Gradients
    static let flowGradientTop = Color.adaptive(lightHex: 0xE8F0D6, darkHex: 0x25281F)
    static let flowGradientBottom = Color.adaptive(lightHex: 0xF5E6DB, darkHex: 0x27221E)

    // MARK: Chart Colors
    static let chartFillLight = Color.adaptive(lightHex: 0xA68CCC, darkHex: 0x7B6B9E)
    static let chartStroke = Color.adaptive(lightHex: 0x8C73B3, darkHex: 0x9B89C2)

    // MARK: Character Bubble Colors
    static let bubbleYoyo = Color.adaptive(lightHex: 0xFDE7EF, darkHex: 0x3D2535)
    static let bubbleMomo = Color.adaptive(lightHex: 0xE5F5FF, darkHex: 0x1F2A35)
    static let bubbleYoran = Color.adaptive(lightHex: 0xEEE8FF, darkHex: 0x282538)

    // MARK: Avatar / Stroke
    static let avatarStroke = Color.adaptive(lightHex: 0xFFFFFF, darkHex: 0x4A4642)

    // MARK: Decorative Tints
    static let decorativeLavender = Color.adaptive(lightHex: 0xD6C9EB, darkHex: 0x3D3648)
    static let decorativeMint = Color.adaptive(lightHex: 0xC7E0D6, darkHex: 0x2A3D38)
    static let flowHeaderGradientTop = Color.adaptive(lightHex: 0xEBE0FA, darkHex: 0x2D2638)
    static let flowHeaderGradientBottom = Color.adaptive(lightHex: 0xFAEBDB, darkHex: 0x2A2420)
    static let moodWeekGradientTop = Color.adaptive(lightHex: 0xEDF2E0, darkHex: 0x252820)
    static let moodWeekGradientBottom = Color.adaptive(lightHex: 0xF5EBE6, darkHex: 0x27231E)
    static let chartLineAccent = Color.adaptive(lightHex: 0x6B599E, darkHex: 0x9B8EC4)

    // MARK: Toast
    static let toastBackground = Color.adaptive(lightHex: 0x000000, darkHex: 0xEEEEEE)
    static let toastText = Color.adaptive(lightHex: 0xFFFFFF, darkHex: 0x000000)
}
