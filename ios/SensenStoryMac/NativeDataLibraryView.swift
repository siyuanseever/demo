import Charts
import SwiftUI

private enum NativeDataTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case sessions = "会话"
    case memories = "记忆"
    case journals = "日记"
    case states = "长期状态"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .sessions: "bubble.left.and.bubble.right.fill"
        case .memories: "books.vertical.fill"
        case .journals: "book.closed.fill"
        case .states: "person.text.rectangle.fill"
        }
    }
}

struct NativeDataLibraryView: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @State private var tab: NativeDataTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本地资料")
                        .font(.title.bold())
                    Text("看见系统保存了什么，也能从历史会话继续说下去。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新本地资料", systemImage: "arrow.clockwise") {
                    store.loadLocalCache()
                }
            }
            .padding(24)

            Picker("资料类型", selection: $tab) {
                ForEach(NativeDataTab.allCases) { item in
                    Label(item.rawValue, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview:
            NativeOverviewGrid(tab: $tab)
        case .sessions:
            NativeSessionList()
        case .memories:
            NativeMemoryBrowser()
        case .journals:
            NativeJournalTimeline()
        case .states:
            NativeStateProfileGrid()
        }
    }
}

private struct NativeOverviewGrid: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @Binding var tab: NativeDataTab
    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                NativeMetricCard(title: "会话", value: store.snapshot.sessionCount, icon: "bubble.left.and.bubble.right") { tab = .sessions }
                NativeMetricCard(title: "消息", value: store.snapshot.messageCount, icon: "text.bubble") { tab = .sessions }
                NativeMetricCard(title: "记忆", value: store.snapshot.memoryCount, icon: "books.vertical") { tab = .memories }
                NativeMetricCard(title: "日记", value: store.snapshot.journalCount, icon: "book.closed") { tab = .journals }
                NativeMetricCard(title: "长期状态", value: store.stateProfiles.count, icon: "person.text.rectangle") { tab = .states }
            }
            .padding(24)
        }
    }
}

private struct NativeSessionList: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @State private var sessionToDelete: SessionSummary?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.sessions) { session in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            if let journal = store.journals.first(where: { $0.sessionID == session.id }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("会后日记", systemImage: "book.closed.fill")
                                        .font(.caption.bold())
                                    Text(journal.summary)
                                    if !journal.insights.isEmpty {
                                        Text("洞察：\(journal.insights.joined(separator: "；"))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !journal.suggestedNextStep.isEmpty {
                                        Label(journal.suggestedNextStep, systemImage: "arrow.forward.circle.fill")
                                            .font(.caption)
                                    }
                                }
                                .padding(12)
                                .background(Color.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                            }

                            let linkedMemories = store.memories.filter { $0.sourceSessionID == session.id }
                            if !linkedMemories.isEmpty {
                                VStack(alignment: .leading, spacing: 7) {
                                    Label("关联记忆 · \(linkedMemories.count)", systemImage: "brain.head.profile")
                                        .font(.caption.bold())
                                    ForEach(linkedMemories) { memory in
                                        Text("• \(memory.content)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            HStack {
                                Button("继续这段夜谈", systemImage: "arrowshape.turn.up.left.fill") {
                                    store.openSession(session.id)
                                    NotificationCenter.default.post(name: .nativeOpenConversation, object: nil)
                                }
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    sessionToDelete = session
                                }
                            }
                        }
                        .padding(.top, 12)
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "moon.stars.fill")
                                .foregroundStyle(.indigo)
                                .frame(width: 32, height: 32)
                                .background(Color.indigo.opacity(0.1), in: Circle())
                            VStack(alignment: .leading, spacing: 5) {
                                Text(session.preview.isEmpty ? "一段夜谈" : session.preview)
                                    .lineLimit(2)
                                HStack {
                                    Text(session.createdAt)
                                    Text("\(session.messageCount) 条消息")
                                    if !session.endedAt.isEmpty { Text("已总结") }
                                    let memoryCount = store.memories.filter { $0.sourceSessionID == session.id }.count
                                    if memoryCount > 0 { Text("\(memoryCount) 条记忆") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
        .alert(
            "删除这段夜谈？",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            presenting: sessionToDelete
        ) { session in
            Button("删除", role: .destructive) {
                store.deleteSession(session.id)
                sessionToDelete = nil
            }
            Button("取消", role: .cancel) { sessionToDelete = nil }
        } message: { _ in
            Text("会同时删除这段夜谈关联的消息、日记和记忆，此操作无法撤销。")
        }
    }
}

private enum NativeMemoryViewMode: String, CaseIterable, Identifiable {
    case categories = "按分类"
    case recent = "最近更新"

    var id: String { rawValue }
}

private struct NativeMemoryBrowser: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @State private var mode: NativeMemoryViewMode = .categories

    private var categories: [(String, [MemoryEntry])] {
        Dictionary(grouping: store.memories, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { NativeDataTaxonomy.categoryOrder($0.0) < NativeDataTaxonomy.categoryOrder($1.0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("查看方式", selection: $mode) {
                ForEach(NativeMemoryViewMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .padding(.top, 18)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if mode == .categories {
                        ForEach(categories, id: \.0) { category, memories in
                            DisclosureGroup {
                                VStack(spacing: 9) {
                                    ForEach(subcategories(memories), id: \.0) { subcategory, items in
                                        DisclosureGroup {
                                            VStack(spacing: 8) {
                                                ForEach(items) { memory in
                                                    NativeMemoryCard(memory: memory)
                                                }
                                            }
                                            .padding(.top, 8)
                                        } label: {
                                            HStack {
                                                Text(NativeDataTaxonomy.subcategoryLabel(subcategory))
                                                Spacer()
                                                Text("\(items.count)").foregroundStyle(.secondary)
                                            }
                                            .font(.callout.bold())
                                        }
                                        .padding(10)
                                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                                .padding(.top, 10)
                            } label: {
                                HStack {
                                    Label(
                                        NativeDataTaxonomy.categoryLabel(category),
                                        systemImage: NativeDataTaxonomy.categoryIcon(category)
                                    )
                                    Spacer()
                                    Text("\(memories.count)").foregroundStyle(.secondary)
                                }
                                .font(.headline)
                            }
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        ForEach(store.memories.sorted { $0.updatedAt > $1.updatedAt }) { memory in
                            NativeMemoryCard(memory: memory)
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private func subcategories(_ memories: [MemoryEntry]) -> [(String, [MemoryEntry])] {
        Dictionary(grouping: memories, by: \.subcategory)
            .map { ($0.key, $0.value) }
            .sorted {
                NativeDataTaxonomy.subcategoryLabel($0.0)
                    < NativeDataTaxonomy.subcategoryLabel($1.0)
            }
    }
}

private struct NativeJournalTimeline: View {
    @EnvironmentObject private var store: NativeMacShellStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !store.journals.isEmpty {
                    NativeMoodChart(journals: store.journals)
                }
                ForEach(journalWeeks, id: \.0) { week, journals in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(week)
                            .font(.headline)
                        NativeWeeklyReportCard(weekLabel: week, journals: journals)
                        ForEach(journals) { journal in
                            NativeJournalCard(journal: journal)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var journalWeeks: [(String, [JournalEntry])] {
        Dictionary(grouping: store.journals) { NativeDateFormat.weekLabel($0.createdAt) }
            .map { ($0.key, $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { ($0.1.first?.createdAt ?? "") > ($1.1.first?.createdAt ?? "") }
    }
}

private struct NativeWeeklyReportCard: View {
    let weekLabel: String
    let journals: [JournalEntry]

    private var averageMood: Double {
        guard !journals.isEmpty else { return 0 }
        return Double(journals.reduce(0) { $0 + $1.moodScore }) / Double(journals.count)
    }

    private var dominantEmotion: String {
        let values = journals.map(\.dominantEmotion).filter { !$0.isEmpty }
        return Dictionary(grouping: values, by: { $0 })
            .max { $0.value.count < $1.value.count }?.key ?? "未标注"
    }

    private var keywords: [String] {
        let counts = Dictionary(grouping: journals.flatMap(\.keywords), by: { $0 })
            .mapValues(\.count)
        return counts.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }
        .prefix(8)
        .map(\.key)
    }

    private var reportText: String {
        let summaries = journals.map(\.summary).filter { !$0.isEmpty }.prefix(3)
        return summaries.isEmpty ? "这一周的记录还在形成。" : summaries.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本周小结")
                        .font(.title3.bold())
                    Text("\(weekLabel) · 根据 \(journals.count) 篇日记自动聚合")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(dominantEmotion).font(.subheadline.bold())
                    Text(String(format: "平均心情 %.1f", averageMood))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(reportText)
                .font(.callout)
                .lineLimit(8)
                .textSelection(.enabled)

            NativeMoodChart(journals: journals)

            if !keywords.isEmpty {
                NativeTagFlow(tags: keywords)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.flowGradientTop, Color.flowGradientBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }
}

private struct NativeStateProfileGrid: View {
    @EnvironmentObject private var store: NativeMacShellStore
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(store.stateProfiles) { profile in
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            if !profile.stage.isEmpty {
                                Text(profile.stage).font(.caption.bold()).foregroundStyle(.indigo)
                            }
                            Text(profile.summary).textSelection(.enabled)
                            ProgressView(value: Double(profile.intensity), total: 10)
                                .tint(profile.intensity >= 7 ? .orange : .green)
                            if !profile.supportStrategy.isEmpty {
                                Text("支持方式：\(profile.supportStrategy)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !profile.evidence.isEmpty {
                                Text("依据：\(profile.evidence)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("置信度 \(Int(profile.confidence * 100))% · 更新于 \(profile.updatedAt)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 10)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(
                                    NativeDataTaxonomy.stateDomainLabel(profile.domain),
                                    systemImage: NativeDataTaxonomy.stateDomainIcon(profile.domain)
                                )
                                .font(.headline)
                                Spacer()
                                Text(NativeDataTaxonomy.trendLabel(profile.trend))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(profile.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
    }
}

private struct NativeMemoryCard: View {
    let memory: MemoryEntry

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(memory.content).textSelection(.enabled)
                if !memory.keywords.isEmpty {
                    NativeTagFlow(tags: memory.keywords)
                }
                if !memory.evidence.isEmpty {
                    Text("依据：\(memory.evidence)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if !memory.updatedAt.isEmpty { Text("更新于 \(memory.updatedAt)") }
                    if !memory.sourceSessionID.isEmpty { Text("来源会话 \(memory.sourceSessionID.prefix(8))") }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(
                        "\(NativeDataTaxonomy.categoryLabel(memory.category)) / "
                            + NativeDataTaxonomy.subcategoryLabel(memory.subcategory)
                    )
                        .font(.caption.bold())
                    Spacer()
                    Text("重要度 \(memory.importance)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(memory.content)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NativeJournalCard: View {
    let journal: JournalEntry

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 9) {
                Text(journal.summary).textSelection(.enabled)
                if !journal.emotionCurve.isEmpty {
                    Text("情绪变化：\(journal.emotionCurve.joined(separator: " → "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !journal.insights.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("洞察").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(journal.insights, id: \.self) { insight in
                            Label(insight, systemImage: "lightbulb.fill").font(.callout)
                        }
                    }
                }
                if !journal.suggestedNextStep.isEmpty {
                    Label(journal.suggestedNextStep, systemImage: "arrow.forward.circle.fill")
                        .font(.callout)
                }
                if !journal.keywords.isEmpty {
                    NativeTagFlow(tags: journal.keywords)
                }
                Text("来源会话 · \(journal.sessionID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(.top, 8)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(journal.dominantEmotion.isEmpty ? "日记总结" : journal.dominantEmotion, systemImage: "book.closed.fill")
                        .font(.headline)
                    Text(journal.createdAt).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("心情 \(journal.moodScore)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NativeMoodColor.color(journal.moodScore).opacity(0.14), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct NativeTagFlow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentPurple.opacity(0.10), in: Capsule())
                }
            }
        }
    }
}

private struct NativeMoodChart: View {
    let journals: [JournalEntry]

    private var points: [NativeMoodPoint] {
        journals.reversed().enumerated().map { index, journal in
            NativeMoodPoint(index: index, journal: journal)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("心情轨迹", systemImage: "chart.xyaxis.line")
                .font(.headline)
            Chart(points) { point in
                LineMark(
                    x: .value("记录", point.index),
                    y: .value("心情", point.journal.moodScore)
                )
                .foregroundStyle(Color.chartLineAccent)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("记录", point.index),
                    y: .value("心情", point.journal.moodScore)
                )
                .foregroundStyle(NativeMoodColor.color(point.journal.moodScore))
            }
            .chartYScale(domain: -5...5)
            .chartXAxis(.hidden)
            .frame(height: 150)
        }
        .padding(16)
        .background(Color.cardBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct NativeMoodPoint: Identifiable {
    let index: Int
    let journal: JournalEntry

    var id: String { journal.id }
}

private enum NativeMoodColor {
    static func color(_ score: Int) -> Color {
        score >= 2 ? .moodPositive : score >= -1 ? .moodNeutral : .moodNegative
    }
}

private enum NativeDataTaxonomy {
    private static let categoryKeys = [
        "self_core",
        "emotion_pattern",
        "body_response",
        "relationship_pattern",
        "trauma_shadow",
        "resource_support",
        "life_habit",
        "goal_action",
    ]

    private static let categoryLabels = [
        "self_core": "自我核心",
        "emotion_pattern": "情绪模式",
        "body_response": "身体反应",
        "relationship_pattern": "关系模式",
        "trauma_shadow": "创伤影子",
        "resource_support": "支持资源",
        "life_habit": "生活习惯",
        "goal_action": "目标行动",
    ]

    private static let categoryIcons = [
        "self_core": "person.crop.circle.fill",
        "emotion_pattern": "heart.text.square.fill",
        "body_response": "waveform.path.ecg",
        "relationship_pattern": "person.2.fill",
        "trauma_shadow": "cloud.moon.fill",
        "resource_support": "hands.sparkles.fill",
        "life_habit": "cup.and.saucer.fill",
        "goal_action": "flag.checkered",
    ]

    private static let subcategoryLabels = [
        "identity": "身份与自我认同", "values": "价值观", "energy_source": "能量来源",
        "boundary": "个人边界", "self_image": "自我形象", "inner_critic": "内在批评",
        "self_compassion": "自我关怀", "anxiety": "焦虑", "freeze_response": "冻结反应",
        "shame": "羞耻", "grief": "悲伤与失落", "anger": "愤怒", "loneliness": "孤独",
        "numbness": "麻木", "fatigue": "疲惫", "tension": "紧绷", "sleep": "睡眠",
        "somatic_signal": "身体信号", "collapse": "耗竭与坍塌", "sensory_overload": "感官过载",
        "pain": "疼痛与不适", "family": "家庭关系", "intimacy": "亲密关系",
        "work_relation": "工作关系", "attachment_trigger": "依恋触发", "support_need": "支持需要",
        "rejection": "拒绝与疏离", "boundary_conflict": "边界冲突", "fear": "恐惧",
        "abandonment": "被抛弃感", "humiliation": "羞辱经历", "suppression": "压抑与控制",
        "dark_part": "阴影部分", "hypervigilance": "过度警觉", "trigger": "创伤触发",
        "person": "支持我的人", "place": "安全的地方", "activity": "有帮助的活动",
        "ritual": "安定仪式", "inner_strength": "内在力量", "professional_support": "专业支持",
        "creative_resource": "创作与文化资源", "routine": "日常节奏", "food": "饮食",
        "movement": "活动与运动", "work_rhythm": "工作节奏", "rest": "休息",
        "environment": "生活环境", "digital_habit": "数字习惯", "career": "职业方向",
        "project": "正在推进的项目", "small_step": "下一小步", "avoidance": "回避模式",
        "decision": "选择与决定", "uncertainty": "不确定性", "learning": "学习与探索",
        "general": "其他记录",
    ]

    private static let stateLabels = [
        "self_relation": "与自己的关系",
        "emotion_regulation": "情绪调节",
        "relationship": "关系与连接",
        "agency_boundary": "行动力与边界",
        "trauma_pattern": "创伤模式",
        "meaning_value": "意义与价值",
    ]

    private static let stateIcons = [
        "self_relation": "person.crop.circle",
        "emotion_regulation": "heart.circle",
        "relationship": "person.2.circle",
        "agency_boundary": "shield.lefthalf.filled",
        "trauma_pattern": "waveform.path.ecg.rectangle",
        "meaning_value": "sparkles",
    ]

    private static let trendLabels = [
        "unknown": "仍在观察", "stable": "相对稳定", "softening": "正在缓和",
        "intensifying": "有所增强", "fluctuating": "有所起伏", "integrating": "正在整合",
    ]

    static func categoryOrder(_ key: String) -> Int {
        categoryKeys.firstIndex(of: key) ?? categoryKeys.count
    }

    static func categoryLabel(_ key: String) -> String {
        categoryLabels[key] ?? readableFallback(key)
    }

    static func categoryIcon(_ key: String) -> String {
        categoryIcons[key] ?? "folder.fill"
    }

    static func subcategoryLabel(_ key: String) -> String {
        subcategoryLabels[key] ?? readableFallback(key)
    }

    static func stateDomainLabel(_ key: String) -> String {
        stateLabels[key] ?? readableFallback(key)
    }

    static func stateDomainIcon(_ key: String) -> String {
        stateIcons[key] ?? "person.text.rectangle"
    }

    static func trendLabel(_ key: String) -> String {
        trendLabels[key] ?? readableFallback(key)
    }

    private static func readableFallback(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
    }
}

private enum NativeDateFormat {
    static func weekLabel(_ value: String) -> String {
        guard let date = date(value) else { return "较早的日记" }
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return "较早的日记" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        let end = calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct NativeMetricCard: View {
    let title: String
    let value: Int
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(value)").font(.title2.bold())
                    Text(title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
