import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif

struct MacPrototypeView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var selection: MacWorkspaceSection? = .conversation

    var body: some View {
        NavigationSplitView {
            MacWorkspaceSidebar(selection: $selection)
                .environmentObject(store)
                .navigationSplitViewColumnWidth(min: 210, ideal: 232, max: 270)
        } detail: {
            MacWorkspaceDetail(
                selection: selection ?? .conversation,
                openConversation: { selection = .conversation }
            )
                .environmentObject(store)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 1040, minHeight: 700)
        .background(Color.pageBackground)
        .sheet(isPresented: Binding(
            get: { store.flowRitualIntention != nil },
            set: { if !$0 { store.dismissFlowRitual() } }
        )) {
            if let intention = store.flowRitualIntention {
                MacFlowRitualSheet(intention: intention)
                    .environmentObject(store)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(false)
            }
        }
    }
}

private enum MacWorkspaceSection: String, CaseIterable, Identifiable {
    case conversation
    case flow
    case sessions
    case memories
    case journals
    case state
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversation: "夜谈"
        case .flow: "心流"
        case .sessions: "会话"
        case .memories: "记忆"
        case .journals: "日记"
        case .state: "长期状态"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .conversation: "bubble.left.and.bubble.right.fill"
        case .flow: "sparkles"
        case .sessions: "clock.arrow.circlepath"
        case .memories: "books.vertical.fill"
        case .journals: "book.closed.fill"
        case .state: "chart.line.uptrend.xyaxis"
        case .settings: "gearshape.fill"
        }
    }
}

private enum MacMemoryViewMode: String, CaseIterable, Identifiable {
    case categories = "分类地图"
    case recent = "最近更新"

    var id: String { rawValue }
}

private struct MacMemoryCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
}

private let macMemoryCategories = [
    MacMemoryCategory(id: "self_core", title: "自我核心", subtitle: "身份、价值与边界", systemImage: "person.crop.circle"),
    MacMemoryCategory(id: "emotion_pattern", title: "情绪模式", subtitle: "焦虑、羞耻与悲伤", systemImage: "waveform.path.ecg"),
    MacMemoryCategory(id: "body_response", title: "身体反应", subtitle: "疲惫、睡眠与紧绷", systemImage: "figure.mind.and.body"),
    MacMemoryCategory(id: "relationship_pattern", title: "关系模式", subtitle: "家庭、亲密与支持", systemImage: "person.2"),
    MacMemoryCategory(id: "trauma_shadow", title: "创伤阴影", subtitle: "恐惧、压抑与遗弃感", systemImage: "cloud.moon"),
    MacMemoryCategory(id: "resource_support", title: "支持资源", subtitle: "人、地方与内在力量", systemImage: "leaf"),
    MacMemoryCategory(id: "life_habit", title: "生活习惯", subtitle: "作息、饮食与休息", systemImage: "cup.and.saucer"),
    MacMemoryCategory(id: "goal_action", title: "目标行动", subtitle: "项目、选择与小步骤", systemImage: "arrow.up.right.circle"),
]

private struct MacStateDomain: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
}

private let macStateDomains = [
    MacStateDomain(id: "self_relation", title: "自我关系", subtitle: "怎样看待和对待自己", systemImage: "person.crop.circle.badge.heart"),
    MacStateDomain(id: "emotion_regulation", title: "情绪调节", subtitle: "识别、承受与恢复", systemImage: "waveform.path"),
    MacStateDomain(id: "relationship", title: "关系状态", subtitle: "连接、依恋与支持", systemImage: "person.2.fill"),
    MacStateDomain(id: "agency_boundary", title: "主体与边界", subtitle: "选择、行动和拒绝", systemImage: "shield.lefthalf.filled"),
    MacStateDomain(id: "trauma_pattern", title: "创伤模式", subtitle: "触发、保护与重复", systemImage: "cloud.rain"),
    MacStateDomain(id: "meaning_value", title: "意义价值", subtitle: "方向、价值与生命感", systemImage: "sparkles"),
]

private struct MacWorkspaceSidebar: View {
    @EnvironmentObject private var store: CompanionStore
    @Binding var selection: MacWorkspaceSection?

    var body: some View {
        List(selection: $selection) {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    CharacterAvatar(character: store.selectedCharacter, size: 54)
                    Text("森森物语")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("一个安静的心理陪伴工作台")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }

            Section("工作台") {
                ForEach(MacWorkspaceSection.allCases.filter { $0 != .settings }) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }

            Section {
                Label(MacWorkspaceSection.settings.title, systemImage: MacWorkspaceSection.settings.systemImage)
                    .tag(MacWorkspaceSection.settings)
            }

            Section("本周留痕") {
                MacWeeklyTraceRow(
                    title: "夜谈",
                    count: store.sessions.filter { macIsThisWeek($0.createdAt) }.count,
                    systemImage: "bubble.left.and.bubble.right",
                    tint: Color.accentPurple
                ) {
                    selection = .sessions
                }
                MacWeeklyTraceRow(
                    title: "日记",
                    count: store.journals.filter { macIsThisWeek($0.createdAt) }.count,
                    systemImage: "book.closed",
                    tint: Color.moodPositive
                ) {
                    selection = .journals
                }
                MacWeeklyTraceRow(
                    title: "记忆更新",
                    count: store.memories.filter { macIsThisWeek($0.updatedAt) }.count,
                    systemImage: "sparkles",
                    tint: Color.moodNeutral
                ) {
                    selection = .memories
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Circle()
                    .fill(store.backendStatus.isOnline ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(store.backendStatus.state.rawValue)
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(14)
            .background(.thinMaterial)
        }
    }
}

private struct MacWeeklyTraceRow: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(title)
                    .font(.callout)
                Spacer()
                Text("\(count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("本周\(title) \(count) 条")
    }
}

private struct MacWorkspaceDetail: View {
    @EnvironmentObject private var store: CompanionStore
    let selection: MacWorkspaceSection
    let openConversation: () -> Void

    @ViewBuilder
    var body: some View {
        switch selection {
        case .conversation:
            MacConversationWorkspace()
        case .flow:
            MacFlowWorkspace()
        case .sessions:
            MacSessionsWorkspace(openConversation: openConversation)
        case .memories:
            MacMemoriesWorkspace()
        case .journals:
            MacJournalsWorkspace()
        case .state:
            MacStateWorkspace()
        case .settings:
            SettingsView()
        }
    }
}

private struct MacConversationWorkspace: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var speech: SpeechService
    @State private var draft = ""
    @State private var hoveredTurnID: String?
    @State private var selectedTurnID: String?
    @State private var isTimelineHovered = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            MacConversationTopBar()
                .environmentObject(store)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ZStack(alignment: .leading) {
                            List {
                                ForEach(store.messages) { message in
                                    MacMessageRow(message: message)
                                        .id(message.id)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 32, bottom: 8, trailing: 32))
                                }

                                if let summary = store.latestCloseSummary {
                                    MacSessionCloseResultCard(summary: summary)
                                        .id(summary.id)
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 32, bottom: 8, trailing: 32))
                                }

                                if store.isSending {
                                    MacThinkingRow(
                                        character: store.selectedCharacter,
                                        status: store.chatOperationStatus
                                    )
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 8, leading: 32, bottom: 8, trailing: 32))
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color.conversationBgTop,
                                        Color.conversationBgBottom,
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .onChange(of: store.messages.count) {
                                guard let lastID = store.messages.last?.id else { return }
                                withAnimation(.easeOut(duration: 0.22)) {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                            .onChange(of: store.latestCloseSummary?.id) {
                                guard let summaryID = store.latestCloseSummary?.id else { return }
                                withAnimation(.easeOut(duration: 0.28)) {
                                    proxy.scrollTo(summaryID, anchor: .bottom)
                                }
                            }

                            if !conversationTurns.isEmpty {
                                MacConversationTimeline(
                                    turns: conversationTurns,
                                    hoveredTurnID: $hoveredTurnID,
                                    selectedTurnID: selectedTurnID,
                                    isVisible: $isTimelineHovered,
                                    selectTurn: { turn in
                                        selectedTurnID = turn.id
                                        withAnimation(.easeInOut(duration: 0.28)) {
                                            proxy.scrollTo(turn.questionMessageID, anchor: .center)
                                        }
                                    }
                                )
                                .padding(.vertical, 8)
                                .onHover { hovering in
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isTimelineHovered = hovering
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    MacComposer(draft: $draft, isFocused: $isComposerFocused)
                        .environmentObject(store)
                }
                .frame(maxWidth: .infinity)

                Divider()

                MacConversationSidebar()
                    .environmentObject(store)
                    .frame(width: 300)
            }
        }
        .task {
            isComposerFocused = true
        }
        .onChange(of: store.latestLiveAssistantMessage?.id) {
            guard speech.automaticallyReadsReplies,
                  let message = store.latestLiveAssistantMessage else { return }
            speech.enqueue(messageID: message.id, text: message.content)
        }
    }

    private var conversationTurns: [MacConversationTurn] {
        var turns: [MacConversationTurn] = []
        var activeQuestion: ChatMessage?
        var answers: [String] = []
        var knowledgeCount = 0

        func appendActiveTurn() {
            guard let question = activeQuestion else { return }
            turns.append(
                MacConversationTurn(
                    id: question.id,
                    questionMessageID: question.id,
                    question: Self.preview(question.content, limit: 300),
                    answer: answers.isEmpty
                        ? "正在等待小兔子的回应。"
                        : answers.prefix(3).joined(separator: "\n"),
                    knowledgeCount: knowledgeCount
                )
            )
        }

        for message in store.messages {
            if message.role == .user {
                appendActiveTurn()
                activeQuestion = message
                answers = []
                knowledgeCount = 0
            } else if activeQuestion != nil, message.role == .assistant {
                if answers.count < 3 {
                    answers.append(Self.preview(message.content, limit: 400))
                }
                knowledgeCount += message.knowledgeCards.count
            }
        }
        appendActiveTurn()
        return turns
    }

    private static func preview(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit)) + "…"
    }
}

private struct MacConversationTurn: Identifiable {
    let id: String
    let questionMessageID: String
    let question: String
    let answer: String
    let knowledgeCount: Int
}

private struct MacConversationTimeline: View {
    let turns: [MacConversationTurn]
    @Binding var hoveredTurnID: String?
    let selectedTurnID: String?
    @Binding var isVisible: Bool
    let selectTurn: (MacConversationTurn) -> Void

    private let shortTick: CGFloat = 14
    private let longTick: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentPurple.opacity(isVisible ? 0.5 : 0.1))
                .frame(height: 16)

            let visibleTurns = Array(turns.suffix(36))

            ForEach(Array(visibleTurns.enumerated()), id: \.element.id) { index, turn in
                turnRow(turn, visibleTurns: visibleTurns)
            }

            Spacer()
        }
        .padding(.vertical, 12)
        .opacity(isVisible ? 1 : 0.08)
    }

    private func turnRow(_ turn: MacConversationTurn, visibleTurns: [MacConversationTurn]) -> some View {
        let isHovered = hoveredTurnID == turn.id
        let tickLen = gradientTickLength(for: turn, visibleTurns: visibleTurns)

        return HStack(spacing: 0) {
            Capsule()
                .fill(tickColor(isHovered: isHovered, isSelected: selectedTurnID == turn.id))
                .frame(width: tickLen, height: 3)
                .padding(.vertical, 10.5)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
                .onHover { hovering in
                    hoveredTurnID = hovering ? turn.id : nil
                }
                .onTapGesture { selectTurn(turn) }

            if isHovered {
                previewCard(turn)
                    .padding(.leading, 10)
                    .allowsHitTesting(false)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 24)
        .padding(.leading, 6)
    }

    private func gradientTickLength(for turn: MacConversationTurn, visibleTurns: [MacConversationTurn]) -> CGFloat {
        guard let centerID = hoveredTurnID else { return shortTick }
        guard let currentIdx = visibleTurns.firstIndex(where: { $0.id == turn.id }),
              let centerIdx = visibleTurns.firstIndex(where: { $0.id == centerID }) else {
            return shortTick
        }
        let dist = abs(currentIdx - centerIdx)
        guard dist <= 3 else { return shortTick }
        let ratio = CGFloat(3 - dist) / 3
        return shortTick + (longTick - shortTick) * ratio
    }

    private func previewCard(_ turn: MacConversationTurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.question)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(turn.answer)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            if turn.knowledgeCount > 0 {
                HStack(spacing: 6) {
                    Label("\(turn.knowledgeCount) 篇知识参考", systemImage: "leaf")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(width: 330, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.1), radius: 14, y: 6)
    }

    private func tickColor(isHovered: Bool, isSelected: Bool) -> Color {
        if isSelected { return Color.primary.opacity(0.85) }
        if isHovered { return Color.primary.opacity(0.65) }
        return Color.primary.opacity(0.18)
    }
}

private struct MacConversationTopBar: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        HStack(spacing: 12) {
            CharacterAvatar(character: store.selectedCharacter, size: 28)
            Text("和 \(store.selectedCharacter.name) 夜谈")
                .font(.subheadline.weight(.semibold))

            Spacer()

            HStack(spacing: 8) {
                Button {
                    store.startNewSession()
                } label: {
                    Label("新会话", systemImage: "plus")
                }

                Button {
                    Task {
                        _ = await store.closeCurrentSession()
                    }
                } label: {
                    Label(
                        store.summarizingSessionID == nil ? "结束并总结" : "正在总结",
                        systemImage: "sparkles"
                    )
                }
                .disabled(store.summarizingSessionID != nil)
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(height: 46)
        .background(.regularMaterial)
    }
}

private struct MacFlowTopCarousel: View {
    let insight: StarMapInsight
    let startIntention: (String) -> Void
    @State private var selectedIndex = 0
    private let timer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    private struct Item: Identifiable {
        let id: String
        let icon: String
        let eyebrow: String
        let title: String
        let detail: String
        let tint: Color
        let intention: String?
    }

    private var items: [Item] {
        var result = [
            Item(
                id: "period",
                icon: "moon.stars.fill",
                eyebrow: insight.periodLabel.isEmpty ? "当前周期" : insight.periodLabel,
                title: insight.coreInsight.isEmpty ? "这一周，先照看真正重要的事" : insight.coreInsight,
                detail: insight.coreInsightDetail,
                tint: Color.flowHeaderGradientTop,
                intention: nil
            ),
            Item(
                id: "primary",
                icon: "scope",
                eyebrow: "主要目标",
                title: insight.primaryGoalTitle,
                detail: insight.primaryGoalNextStep,
                tint: Color.accentPurpleLight,
                intention: insight.primaryGoalNextStep
            ),
        ]
        if insight.hasSecondaryGoal {
            result.append(
                Item(
                    id: "secondary",
                    icon: "circle.dotted",
                    eyebrow: "次要目标",
                    title: insight.secondaryGoalTitle,
                    detail: insight.secondaryGoalNextStep,
                    tint: Color.decorativeMint.opacity(0.7),
                    intention: insight.secondaryGoalNextStep
                )
            )
        }
        result.append(
            Item(
                id: "emotion",
                icon: "cloud.sun.fill",
                eyebrow: "近期情绪天气",
                title: insight.recentEmotionTags.prefix(3).joined(separator: " · "),
                detail: insight.recentEmotionSummary,
                tint: Color.cardGreenBackground,
                intention: nil
            )
        )
        return result.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        let cards = items
        if let item = cards.indices.contains(selectedIndex) ? cards[selectedIndex] : cards.first {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: item.icon)
                        .foregroundStyle(Color.accentPurple)
                    Text(item.eyebrow)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { move(-1, count: cards.count) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(cards.count < 2)
                    Button { move(1, count: cards.count) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(cards.count < 2)
                }
                .buttonStyle(.plain)

                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)

                Text(item.detail.isEmpty ? "这一页暂时没有更多说明。" : item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: 45, alignment: .topLeading)

                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(cards.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == selectedIndex ? Color.accentPurple : Color.secondary.opacity(0.22))
                                .frame(width: index == selectedIndex ? 13 : 5, height: 5)
                        }
                    }
                    Spacer()
                    if let intention = item.intention, !intention.isEmpty {
                        Button("进入") {
                            startIntention(intention)
                        }
                        .font(.caption.bold())
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentPurple)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 178, maxHeight: 178, alignment: .topLeading)
            .background(item.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width < -24 {
                            move(1, count: cards.count)
                        } else if value.translation.width > 24 {
                            move(-1, count: cards.count)
                        }
                    }
            )
            .onReceive(timer) { _ in
                move(1, count: cards.count)
            }
            .onChange(of: cards.count) {
                selectedIndex = min(selectedIndex, max(cards.count - 1, 0))
            }
        }
    }

    private func move(_ offset: Int, count: Int) {
        guard count > 1 else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            selectedIndex = (selectedIndex + offset + count) % count
        }
    }
}

private struct MacMessageRow: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var speech: SpeechService
    @State private var selectedKnowledgeCard: KnowledgeCard?
    @State private var showCopyToast = false
    let message: ChatMessage

    var body: some View {
        if message.role == .system {
            Text(message.content)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .frame(maxWidth: .infinity)
                .contextMenu {
                    Button(action: {
                        copyMessage()
                    }) {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                }
        } else {
            HStack(alignment: .top, spacing: 10) {
                if message.role == .assistant {
                    CharacterAvatar(
                        character: store.character(id: message.characterID) ?? store.selectedCharacter,
                        size: 38,
                        expressionID: message.expressionID
                    )
                } else {
                    Spacer(minLength: 90)
                }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                    if message.role == .assistant {
                        Text(store.character(id: message.characterID)?.name ?? store.selectedCharacter.name)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        if let routeSummary = message.routeSummary, !routeSummary.isEmpty {
                            Label(routeSummary, systemImage: "wand.and.stars")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Text(message.content)
                            .font(.system(size: 17))
                            .foregroundStyle(message.role == .user ? Color.primary.opacity(0.72) : Color.primary)

                        if !message.knowledgeCards.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("本轮参考知识", systemImage: "leaf.fill")
                                    .font(.callout.bold())
                                    .foregroundStyle(.secondary)

                                ForEach(message.knowledgeCards) { card in
                                    Button {
                                        selectedKnowledgeCard = card
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(card.title)
                                                .lineLimit(1)
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                        }
                                        .font(.subheadline)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.overlaySubtle, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(
                        message.role == .user
                            ? Color.gray.opacity(0.10)
                            : (store.character(id: message.characterID)?.bubbleColor ?? store.selectedCharacter.bubbleColor),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                    if message.role == .assistant {
                        Button {
                            speech.toggle(messageID: message.id, text: message.content)
                        } label: {
                            Label(
                                speech.activeMessageID == message.id && speech.isPreparing
                                    ? "正在生成语音…"
                                    : (speech.activeMessageID == message.id && speech.isSpeaking ? "停止朗读" : "听\(characterName)说"),
                                systemImage: speech.activeMessageID == message.id && speech.isPreparing
                                    ? "waveform.badge.magnifyingglass"
                                    : (speech.activeMessageID == message.id && speech.isSpeaking
                                        ? "stop.circle.fill"
                                        : "speaker.wave.2.fill")
                            )
                            .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentPurple)
                        .accessibilityHint("使用本机 Qwen3-TTS Serena 女性声线朗读\(characterName)的这条回复")
                    }
                }
                .frame(maxWidth: 620, alignment: message.role == .user ? .trailing : .leading)

                if message.role == .assistant {
                    Spacer(minLength: 90)
                }
            }
            .frame(maxWidth: .infinity)
            .contextMenu {
                Button(action: {
                    copyMessage()
                }) {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }
            .popover(item: $selectedKnowledgeCard) { card in
                VStack(alignment: .leading, spacing: 12) {
                    Label("知识卡", systemImage: "leaf.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(card.title)
                        .font(.title3.bold())
                    Text(card.concept.isEmpty ? "当前本地记录只保存了知识卡标识：\(card.id)" : card.concept)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Text("ID · \(card.id)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
                .frame(width: 340)
            }
            .overlay(alignment: .center) {
                if showCopyToast {
                    Text("已复制")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.toastBackground.opacity(0.7))
                        .foregroundColor(Color.toastText)
                        .cornerRadius(8)
                        .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }

    private var characterName: String {
        store.character(id: message.characterID)?.name ?? store.selectedCharacter.name
    }

    private func copyMessage() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        #else
        UIPasteboard.general.string = message.content
        #endif
        showCopyToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopyToast = false
        }
    }
}

private struct MacSessionCloseResultCard: View {
    let summary: SessionCloseSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentGreen)

                VStack(alignment: .leading, spacing: 3) {
                    Text("本次夜谈已整理")
                        .font(.title3.bold())
                    Text("下面是这次总结实际写入或评估的内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Label("\(summary.memoryCount) 条记忆", systemImage: "books.vertical")
                    Label("\(summary.stateProfileCount) 项状态", systemImage: "chart.line.uptrend.xyaxis")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let journal = summary.journal {
                MacCloseJournalSection(journal: journal)
            } else {
                MacCloseSection(title: "总结日记", icon: "book.closed.fill") {
                    Text(summary.journalSummary)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }

            MacCloseSection(title: "记忆处理", icon: "books.vertical.fill") {
                if summary.memories.isEmpty {
                    Text("这次没有新增、合并或修改长期记忆。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.memories) { memory in
                        MacCloseMemoryRow(memory: memory)
                    }
                }
            }

            MacCloseSection(title: "长期状态评估", icon: "chart.line.uptrend.xyaxis") {
                if summary.stateProfiles.isEmpty {
                    Text("这次没有返回长期状态评估结果。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(summary.stateProfiles) { profile in
                        MacCloseStateRow(profile: profile)
                    }
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.cardGradientTop,
                    Color.cardGradientBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.overlayMax)
        }
    }
}

private struct MacCloseJournalSection: View {
    let journal: SessionCloseJournal

    var body: some View {
        MacCloseSection(title: "总结日记", icon: "book.closed.fill") {
            HStack(spacing: 9) {
                if !journal.dominantEmotion.isEmpty {
                    Text(journal.dominantEmotion)
                        .font(.caption.bold())
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.pink.opacity(0.12), in: Capsule())
                }
                Text("心情 \(journal.moodScore)")
                    .font(.caption.bold())
                    .foregroundStyle(macMoodColor(Double(journal.moodScore)))
            }

            Text(journal.summary)
                .font(.callout)
                .textSelection(.enabled)

            if !journal.emotionCurve.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("情绪变化")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    MacTagFlow(items: journal.emotionCurve)
                }
            }

            if !journal.insights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("洞察")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(journal.insights, id: \.self) { insight in
                        Label(insight, systemImage: "sparkle")
                            .font(.caption)
                    }
                }
            }

            if !journal.keywords.isEmpty {
                MacTagFlow(items: journal.keywords)
            }

            if !journal.suggestedNextStep.isEmpty {
                Label(journal.suggestedNextStep, systemImage: "arrow.right.circle.fill")
                    .font(.callout.weight(.semibold))
            }
        }
    }
}

private struct MacCloseMemoryRow: View {
    let memory: SessionCloseMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(macMemoryCategoryTitle(memory.category)) / \(memory.subcategory)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                MacCloseActionBadge(action: memory.action)
            }

            Text(memory.content)
                .font(.callout)
                .textSelection(.enabled)

            if !memory.reason.isEmpty {
                Text("处理依据：\(memory.reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !memory.keywords.isEmpty {
                MacTagFlow(items: memory.keywords)
            }
        }
        .padding(12)
        .background(Color.overlayMedium, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MacCloseStateRow: View {
    let profile: SessionCloseStateProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(macStateDomainTitle(profile.domain))
                        .font(.subheadline.bold())
                    Text(profile.stage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MacCloseActionBadge(action: profile.action)
            }

            if !profile.summary.isEmpty {
                Text(profile.summary)
                    .font(.callout)
                    .textSelection(.enabled)
            }

            HStack(spacing: 12) {
                Label("强度 \(profile.intensity)", systemImage: "gauge.with.dots.needle.50percent")
                Label(profile.trend, systemImage: "arrow.up.right")
                Text("置信度 \(Int(profile.confidence * 100))%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !profile.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本次依据")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(profile.evidence, id: \.self) { evidence in
                        Text("• \(evidence)")
                            .font(.caption)
                    }
                }
            }

            if !profile.supportStrategy.isEmpty {
                Label(profile.supportStrategy, systemImage: "heart.text.square.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !profile.reason.isEmpty {
                Text("判断说明：\(profile.reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.overlayMedium, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MacCloseActionBadge: View {
    let action: String

    var body: some View {
        Text(actionTitle)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(actionColor)
            .background(actionColor.opacity(0.12), in: Capsule())
    }

    private var actionTitle: String {
        switch action {
        case "create": "新增"
        case "merge": "合并"
        case "update": "更新"
        case "contradict": "矛盾修订"
        case "ignore": "忽略"
        case "no_change": "保持不变"
        default: action
        }
    }

    private var actionColor: Color {
        switch action {
        case "create": Color.green
        case "merge", "update": Color.blue
        case "contradict": Color.orange
        case "ignore", "no_change": Color.secondary
        default: Color.purple
        }
    }
}

private struct MacCloseSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.overlaySubtle, in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct MacThinkingRow: View {
    let character: CompanionCharacter
    let status: String?

    var body: some View {
        HStack(spacing: 10) {
            CharacterAvatar(character: character, size: 38)
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(character.bubbleColor, in: Capsule())
            if let status, !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct MacComposer: View {
    @EnvironmentObject private var store: CompanionStore
    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = store.chatNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("写下此刻最想说的话…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused(isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.overlayHeavy, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.secondary.opacity(0.16))
                    }

                Button {
                    send()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentPurple)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            Text("⌘ ↩ 发送")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !store.isSending else { return }
        draft = ""
        Task {
            await store.sendDraft(text)
        }
    }
}

private struct MacConversationSidebar: View {
    @EnvironmentObject private var store: CompanionStore

    private var latestDeepReply: ChatMessage? {
        store.messages.reversed().first { $0.replyStage == "deep" && $0.role == .assistant }
    }

    private var latestPlanMetadata: [String: Any]? {
        latestDeepReply?.routePlan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !store.starMapInsight.primaryGoalTitle.isEmpty {
                    MacSidebarSection(title: "本周心流") {
                        MacFlowTopCarousel(insight: store.starMapInsight) { intention in
                            store.triggerFlowRitual(intention: intention)
                        }
                    }

                    Divider()
                }

                VStack(spacing: 14) {
                    CharacterAvatar(character: store.selectedCharacter, cornerRadius: 12, isFixedSize: false)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                    Text(store.selectedCharacter.name)
                        .font(.title2.bold())
                    Text(store.selectedCharacter.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                Divider()

                MacSidebarSection(title: "此刻的你") {
                    MacUserAssessmentPanel(
                        assessment: store.latestUserAssessment,
                        isAnalyzing: store.isSending
                    )
                }

                MacSidebarSection(title: "这次夜谈") {
                    Label("\(store.messages.count) 条消息", systemImage: "text.bubble")
                        .font(.subheadline)
                    #if targetEnvironment(macCatalyst)
                    Label("本机后端双阶段模式", systemImage: "brain")
                        .font(.subheadline)
                    #else
                    Label(
                        store.isLocalAIConfigured ? "本机 API 模式" : "后端服务模式",
                        systemImage: "brain"
                    )
                    .font(.subheadline)
                    #endif
                }

                if let notice = store.sessionNotice {
                    Text(notice)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .background(Color.overlayLight, in: RoundedRectangle(cornerRadius: 12))
                }

                if let deepReply = latestDeepReply {
                    Divider()

                    if let planMetadata = latestPlanMetadata {
                        MacSidebarSection(title: "规划详情") {
                            VStack(alignment: .leading, spacing: 8) {
                                planInfoRow(label: "用户状态", value: planMetadata["user_state"] as? String)
                                planInfoRow(label: "核心需要", value: planMetadata["core_need"] as? String)
                                planInfoRow(label: "风险等级", value: planMetadata["risk_level"] as? String)
                                planInfoRow(label: "回复模式", value: planMetadata["response_mode"] as? String)
                                planInfoRow(label: "历史轮数", value: (planMetadata["history_turns_needed"] as? Int).map { "\($0)" })
                                planInfoRow(label: "需要状态画像", value: (planMetadata["need_state_profiles"] as? Bool).map { $0 ? "是" : "否" })
                                planInfoRow(label: "需要更多记忆", value: (planMetadata["need_more_memories"] as? Bool).map { $0 ? "是" : "否" })
                                planInfoRow(label: "上下文策略", value: planMetadata["context_strategy"] as? String)
                                planInfoRow(label: "选择理由", value: planMetadata["reason"] as? String)
                            }
                        }
                    }

                    if !deepReply.retrievedMemories.isEmpty {
                        MacSidebarSection(title: "检索到的记忆") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(deepReply.retrievedMemories.prefix(5)) { memory in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(memory.content)
                                            .font(.callout)
                                            .foregroundStyle(.primary)
                                        HStack(spacing: 8) {
                                            Text("[\(memory.category)/\(memory.subcategory)]")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            if !memory.keywords.isEmpty {
                                                Text(memory.keywords.joined(separator: "、"))
                                                    .font(.caption)
                                                    .foregroundStyle(.tertiary)
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.overlayLight, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }

                    if !deepReply.knowledgeCards.isEmpty {
                        MacSidebarSection(title: "参考知识卡") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(deepReply.knowledgeCards) { card in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(card.title)
                                            .font(.callout.bold())
                                            .foregroundStyle(.primary)
                                        Text(card.concept)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color.overlayLight, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 20)
            }
            .padding(22)
        }
        .background(Color.sidebarBackground)
    }

    @ViewBuilder
    private func planInfoRow(label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Text("\(label)：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 80, alignment: .trailing)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct MacUserAssessmentPanel: View {
    let assessment: UserConversationAssessment?
    let isAnalyzing: Bool

    var body: some View {
        if let assessment {
            VStack(alignment: .leading, spacing: 12) {
                assessmentRow(
                    icon: "heart.text.square.fill",
                    title: "状态与情绪",
                    value: assessment.userState,
                    fallback: "正在继续理解"
                )
                assessmentRow(
                    icon: "hand.raised.fingers.spread.fill",
                    title: "此刻需要",
                    value: assessment.coreNeed,
                    fallback: "陪伴与理解"
                )

                HStack(spacing: 8) {
                    assessmentPill(
                        title: "风险",
                        value: riskLabel(assessment.riskLevel),
                        color: riskColor(assessment.riskLevel)
                    )
                    assessmentPill(
                        title: "回应",
                        value: responseModeLabel(assessment.responseMode),
                        color: Color.accentPurple
                    )
                }

                if !assessment.reason.isEmpty {
                    Text(assessment.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isAnalyzing ? "waveform.badge.magnifyingglass" : "moon.stars")
                    .foregroundStyle(Color.accentPurple)
                Text(isAnalyzing ? "正在理解你此刻的情绪、需要和风险…" : "当你开始说话，这里会显示本轮对你的理解。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func assessmentRow(icon: String, title: String, value: String, fallback: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? fallback : value)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func assessmentPill(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.10), in: Capsule())
    }

    private func riskLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "medium", "moderate": "需留意"
        case "high": "较高"
        case "crisis", "critical": "紧急"
        default: "较低"
        }
    }

    private func riskColor(_ value: String) -> Color {
        switch value.lowercased() {
        case "high", "crisis", "critical": .red
        case "medium", "moderate": .orange
        default: .green
        }
    }

    private func responseModeLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "validate": "接住情绪"
        case "insight": "梳理洞察"
        case "action": "寻找行动"
        case "clarify": "继续澄清"
        case "stabilize": "稳定下来"
        default: value.isEmpty ? "温柔陪伴" : value
        }
    }
}

private struct MacStateProfileDetailSheet: View {
    let profile: StateProfile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(macStateDomainTitle(profile.domain))
                        .font(.title2.bold())
                    Spacer()
                    Button("关闭") {
                        dismiss()
                    }
                    .font(.subheadline)
                }

                if !profile.stage.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("当前阶段")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.stage)
                            .font(.body)
                    }
                }

                if !profile.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("总结")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.summary)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("趋势")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text(profile.trend.isEmpty ? "暂无数据" : profile.trend)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("强度")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text("\(profile.intensity)/10")
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("置信度")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%%", profile.confidence * 100))
                        .font(.body)
                }

                if !profile.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("证据")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.evidence)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                if !profile.supportStrategy.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("支持策略")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        Text(profile.supportStrategy)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: 400)
    }
}

private struct MacSidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct MacFlowWorkspace: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        let insight = store.starMapInsight
        MacCollectionWorkspace(
            title: "心流导航",
            subtitle: "把近期长期状态、记忆和日记压缩成当前最值得照看的目标。",
            isEmpty: false
        ) {
            VStack(alignment: .leading, spacing: 16) {
                MacFlowHeaderCard(insight: insight)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    MacFlowGoalCard(
                        role: "主要目标",
                        title: insight.primaryGoalTitle,
                        reason: insight.primaryGoalReason,
                        nextStep: insight.primaryGoalNextStep,
                        challenge: insight.primaryGoalChallenge,
                        tint: Color.decorativeLavender,
                        goalType: .primary
                    )

                    if insight.hasSecondaryGoal {
                        MacFlowGoalCard(
                            role: "次要目标",
                            title: insight.secondaryGoalTitle,
                            reason: insight.secondaryGoalReason,
                            nextStep: insight.secondaryGoalNextStep,
                            challenge: insight.secondaryGoalChallenge,
                            tint: Color.decorativeMint,
                            goalType: .secondary
                        )
                    } else {
                        MacFlowPlaceholderGoalCard()
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    MacFlowInfoCard(
                        icon: "cloud.sun.fill",
                        title: "近期情绪天气",
                        bodyText: insight.recentEmotionSummary,
                        tags: insight.recentEmotionTags
                    )

                    MacFlowInfoCard(
                        icon: "scope",
                        title: insight.flowConditionTitle,
                        bodyText: insight.flowConditionDetail.isEmpty ? insight.flowSupport : insight.flowConditionDetail,
                        tags: insight.flowConditions
                    )

                    MacFlowInfoCard(
                        icon: "sparkles",
                        title: insight.recentPatternTitle,
                        bodyText: insight.recentPatternDetail,
                        tags: insight.recentPattern
                    )

                    MacFlowInfoCard(
                        icon: "bookmark.fill",
                        title: "记忆在提醒你",
                        bodyText: insight.flowSupport,
                        tags: insight.memoryCues
                    )
                }

                MacFlowReminderCard(insight: insight)

                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Color.accentPurple)
                    Text("每周自动生成")
                        .font(.caption.bold())
                    Text(store.flowInsightNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .task {
            await store.loadStarMapInsightIfNeeded()
        }
    }
}

private struct MacFlowHeaderCard: View {
    let insight: StarMapInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("当前周期", systemImage: "moon.stars.fill")
                    .font(.headline)
                Spacer()
                Text(insight.periodLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            Text(insight.coreInsight)
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(insight.coreInsightDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if insight.isMockInsight {
                Label("当前可能是占位分析。连接后端并刷新后，会基于真实日记、记忆和长期状态生成。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.flowHeaderGradientTop,
                    Color.flowHeaderGradientBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct MacFlowGoalCard: View {
    @EnvironmentObject private var store: CompanionStore
    let role: String
    let title: String
    let reason: String
    let nextStep: String
    let challenge: String
    let tint: Color
    let goalType: GoalType

    enum GoalType {
        case primary
        case secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(role)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !challenge.isEmpty {
                    Text(challenge)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.overlayLight, in: Capsule())
                }
            }

            Text(title.isEmpty ? "还没有形成目标" : title)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("下一步", systemImage: "arrow.right.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(nextStep.isEmpty ? "先完成几次夜谈总结，再生成更具体的小步骤。" : nextStep)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task {
                        if store.starMapInsight.isMockInsight {
                            await store.refreshStarMapInsight(forceRefresh: true)
                        } else {
                            let intention = goalType == .primary
                                ? store.starMapInsight.primaryGoalNextStep
                                : store.starMapInsight.secondaryGoalNextStep
                            store.triggerFlowRitual(intention: intention)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("开始")
                        Image(systemName: "play.circle.fill")
                            .font(.caption)
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.overlayHeavy, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(store.starMapInsight.isMockInsight || nextStep.isEmpty)
                .opacity(store.starMapInsight.isMockInsight || nextStep.isEmpty ? 0.5 : 1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(tint.opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MacFlowPlaceholderGoalCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("次要目标", systemImage: "circle.dotted")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text("暂时不拆第二个目标")
                .font(.title3.bold())
            Text("当系统判断当前阶段只需要一个主线时，这里会保持空白，避免制造额外负担。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(Color.overlayLight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
    }
}

private struct MacFlowInfoCard: View {
    let icon: String
    let title: String
    let bodyText: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
            Text(bodyText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !tags.isEmpty {
                MacTagFlow(items: tags)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .background(Color.overlayMedium, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MacFlowReminderCard: View {
    let insight: StarMapInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(insight.gentleReminderTitle, systemImage: "leaf.fill")
                .font(.headline)
            Text(insight.gentleReminder)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(insight.gentleReminderDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardGreenBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct MacSessionsWorkspace: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var expandedSessionID: String?
    @State private var deletingSessionID: String?
    let openConversation: () -> Void

    var body: some View {
        MacCollectionWorkspace(
            title: "历史会话",
            subtitle: "继续过去的夜谈，或者查看最近发生了什么。",
            isEmpty: store.sessions.isEmpty
        ) {
            ForEach(store.sessions) { session in
                let journal = store.journals.first { $0.sessionID == session.id }
                let memories = store.memories.filter { $0.sourceSessionID == session.id }
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedSessionID == session.id },
                        set: { expandedSessionID = $0 ? session.id : nil }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Divider()

                        if let journal {
                            MacSessionJournalSummary(journal: journal)
                        } else {
                            Label("这次会话还没有总结日记", systemImage: "book.closed")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("关联记忆", systemImage: "books.vertical")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text("\(memories.count) 条")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if memories.isEmpty {
                                Text("这次会话暂时没有直接关联的长期记忆。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(memories) { memory in
                                    MacMemoryCompactRow(memory: memory)
                                }
                            }
                        }

                        Button {
                            store.openSession(session.id)
                            openConversation()
                        } label: {
                            Label("继续这次夜谈", systemImage: "arrow.right.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentPurple)
                    }
                    .padding(.top, 8)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(session.preview.isEmpty ? "一次安静的夜谈" : session.preview)
                                    .font(.headline)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Spacer()
                                Text(macShortDate(session.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 12) {
                                Label("\(session.messageCount) 条消息", systemImage: "bubble.left")
                                Label("\(journal == nil ? 0 : 1) 篇日记", systemImage: "book.closed")
                                Label("\(memories.count) 条记忆", systemImage: "books.vertical")
                                if let journal, !journal.dominantEmotion.isEmpty {
                                    Label(journal.dominantEmotion, systemImage: "heart.text.square")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Button(role: .destructive) {
                            deletingSessionID = session.id
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.red.opacity(0.7))
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 32, height: 32)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("删除会话")
                        .confirmationDialog("确认删除", isPresented: Binding(
                            get: { deletingSessionID == session.id },
                            set: { if !$0 { deletingSessionID = nil } }
                        )) {
                            Button("删除会话及关联数据", role: .destructive) {
                                if deletingSessionID == session.id {
                                    store.deleteSession(session.id)
                                    deletingSessionID = nil
                                }
                            }
                            Button("取消", role: .cancel) {
                                deletingSessionID = nil
                            }
                        } message: {
                            Text("删除后将无法恢复，包括关联的日记和记忆。")
                        }
                    }
                }
                .padding(16)
                .background(Color.overlayHeavy, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

private struct MacMemoriesWorkspace: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var viewMode: MacMemoryViewMode = .categories

    var body: some View {
        MacCollectionWorkspace(
            title: "长期记忆",
            subtitle: "既可以查看记忆地图，也可以追踪最近新增和修改的内容。",
            isEmpty: store.memories.isEmpty
        ) {
            Picker("记忆查看方式", selection: $viewMode) {
                ForEach(MacMemoryViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding(.bottom, 6)

            if viewMode == .categories {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(macMemoryCategories) { category in
                        MacMemoryCategoryCard(
                            category: category,
                            memories: store.memories.filter { $0.category == category.id }
                        )
                    }
                }
            } else {
                ForEach(store.memories.sorted { $0.updatedAt > $1.updatedAt }) { memory in
                    MacMemoryDetailCard(memory: memory)
                }
            }
        }
    }
}

private struct MacMemoryCategoryCard: View {
    let category: MacMemoryCategory
    let memories: [MemoryEntry]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                if memories.isEmpty {
                    Text("这个格子还没有形成记忆。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(memories.sorted { $0.updatedAt > $1.updatedAt }) { memory in
                        MacMemoryCompactRow(memory: memory)
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Image(systemName: category.systemImage)
                        .font(.title3)
                        .foregroundStyle(Color.accentMutedGreen)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(.headline)
                        Text(category.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(memories.count)")
                        .font(.title2.bold())
                        .monospacedDigit()
                }

                let subcategoryCounts = Dictionary(grouping: memories, by: \.subcategory)
                    .mapValues(\.count)
                    .sorted { $0.key < $1.key }
                if subcategoryCounts.isEmpty {
                    Text("暂无小类")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    MacTagFlow(items: subcategoryCounts.map { "\($0.key) \($0.value)" })
                }
            }
        }
        .padding(16)
        .background(Color.overlayHeavy, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.overlayHeavy)
        }
    }
}

private enum MacJournalViewMode: String, CaseIterable, Identifiable {
    case journalList = "日记列表"
    case moodTrack = "心情轨迹"

    var id: String { rawValue }
}

private struct MacJournalsWorkspace: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var viewMode: MacJournalViewMode = .journalList

    var body: some View {
        MacCollectionWorkspace(
            title: "总结日记",
            subtitle: "按周查看日记、情绪轨迹、关键词和阶段性小结。",
            isEmpty: store.journals.isEmpty
        ) {
            Picker("查看方式", selection: $viewMode) {
                ForEach(MacJournalViewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .padding(.bottom, 6)

            switch viewMode {
            case .journalList:
                journalListContent
            case .moodTrack:
                MacMoodTrackView()
                    .environmentObject(store)
            }
        }
        .task {
            await store.refreshMoodAnalytics()
        }
    }

    private var journalListContent: some View {
        ForEach(macJournalWeeks(store.journals)) { week in
            VStack(alignment: .leading, spacing: 12) {
                MacWeeklyReportCard(week: week)

                ForEach(week.journals) { journal in
                    MacJournalDetailCard(journal: journal)
                }
            }
        }
    }
}

private struct MacMoodTrackView: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        if store.isMoodRefreshing && store.moodAnalytics == nil {
            ProgressView("正在读取心情数据...")
                .frame(maxWidth: .infinity, minHeight: 200)
        } else if let analytics = store.moodAnalytics, !analytics.daily.isEmpty {
            LazyVStack(alignment: .leading, spacing: 18) {
                // 本周概览
                if let latestWeek = analytics.weekly.first {
                    MacMoodWeekOverviewCard(week: latestWeek)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("最近每日情绪")
                        .font(.headline)
                    Text("根据每次夜谈后生成的心情评分与主导情绪")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    let recentDaily = Array(analytics.daily.suffix(14))
                    MacMoodTrendChart(
                        points: recentDaily.map {
                            MacMoodChartPoint(
                                id: $0.date,
                                label: macMoodDayLabel($0.date),
                                score: $0.score,
                                detail: $0.dominantEmotion
                            )
                        },
                        title: "最近 14 天心情曲线",
                        subtitle: "0 是中性；越高越正向，越低越沉重。"
                    )

                    Text("每日记录")
                        .font(.subheadline.bold())
                        .padding(.top, 4)

                    ForEach(recentDaily, id: \.date) { day in
                        MacMoodDailyCard(day: day)
                    }
                }

                if !store.journals.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("单次夜谈情绪轨迹")
                            .font(.headline)
                        Text("每次夜谈中记录到的情绪变化序列")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(store.journals.prefix(6)) { journal in
                            MacSessionEmotionCurveCard(journal: journal)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "还没有足够的心情数据",
                systemImage: "chart.line.uptrend.xyaxis",
                description: Text("完成几次夜谈并生成总结后，这里会显示情绪变化轨迹。")
            )
            .frame(maxWidth: .infinity, minHeight: 360)
        }
    }
}

private struct MacMoodWeekOverviewCard: View {
    let week: RemoteMoodWeekly

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("本周概览")
                    .font(.title3.bold())
                Spacer()
                Text(week.week)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("平均心情")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f", week.score))
                        .font(.title2.bold())
                        .foregroundStyle(moodColor(week.score))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("主导情绪")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(week.dominantEmotion)
                        .font(.title3.bold())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("记录次数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(week.count)")
                        .font(.title3.bold())
                }

                Spacer()
            }

            if !week.keywords.isEmpty {
                MacTagFlow(items: week.keywords)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.moodWeekGradientTop,
                    Color.moodWeekGradientBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private func moodColor(_ score: Double) -> Color {
        if score >= 2 { return Color.moodPositive }
        if score >= 0 { return Color.moodNeutral }
        if score >= -2 { return Color.moodMildNegative }
        return Color.moodNegative
    }
}

private struct MacMoodChartPoint: Identifiable, Hashable {
    let id: String
    let label: String
    let score: Double
    let detail: String
}

private struct MacMoodTrendChart: View {
    let points: [MacMoodChartPoint]
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let averageScore {
                    Text(String(format: "均值 %.1f", averageScore))
                        .font(.caption.bold())
                        .foregroundStyle(macMoodColor(averageScore))
                }
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let leftInset: CGFloat = 34
                let rightInset: CGFloat = 14
                let topInset: CGFloat = 12
                let bottomInset: CGFloat = 28
                let plotWidth = max(1, width - leftInset - rightInset)
                let plotHeight = max(1, height - topInset - bottomInset)
                let baselineY = yPosition(for: 0, top: topInset, height: plotHeight)

                ZStack(alignment: .topLeading) {
                    chartGrid(
                        width: width,
                        plotWidth: plotWidth,
                        leftInset: leftInset,
                        rightInset: rightInset,
                        topInset: topInset,
                        plotHeight: plotHeight,
                        baselineY: baselineY
                    )

                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        let x = xPosition(index: index, count: points.count, left: leftInset, width: plotWidth)
                        let y = yPosition(for: point.score, top: topInset, height: plotHeight)
                        let barTop = min(y, baselineY)
                        let barHeight = max(3, abs(baselineY - y))

                        RoundedRectangle(cornerRadius: 4)
                            .fill(macMoodColor(point.score).opacity(0.28))
                            .frame(width: points.count > 8 ? 14 : 20, height: barHeight)
                            .position(x: x, y: barTop + barHeight / 2)

                        Circle()
                            .fill(macMoodColor(point.score))
                            .frame(width: 8, height: 8)
                            .position(x: x, y: y)

                        Text(point.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .position(x: x, y: height - 10)
                    }

                    Path { path in
                        for (index, point) in points.enumerated() {
                            let x = xPosition(index: index, count: points.count, left: leftInset, width: plotWidth)
                            let y = yPosition(for: point.score, top: topInset, height: plotHeight)
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Color.chartLineAccent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: 190)

            HStack(spacing: 10) {
                Label("正向", systemImage: "arrow.up.circle.fill")
                    .foregroundStyle(macMoodColor(3))
                Label("中性", systemImage: "minus.circle.fill")
                    .foregroundStyle(macMoodColor(0))
                Label("负向", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(macMoodColor(-3))
            }
            .font(.caption)
        }
        .padding(15)
        .background(Color.overlayMedium, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var averageScore: Double? {
        guard !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + $1.score } / Double(points.count)
    }

    @ViewBuilder
    private func chartGrid(
        width: CGFloat,
        plotWidth: CGFloat,
        leftInset: CGFloat,
        rightInset: CGFloat,
        topInset: CGFloat,
        plotHeight: CGFloat,
        baselineY: CGFloat
    ) -> some View {
        let positiveY = yPosition(for: 5, top: topInset, height: plotHeight)
        let negativeY = yPosition(for: -5, top: topInset, height: plotHeight)

        ForEach([
            ("+5", positiveY),
            ("0", baselineY),
            ("-5", negativeY),
        ], id: \.0) { label, y in
            Path { path in
                path.move(to: CGPoint(x: leftInset, y: y))
                path.addLine(to: CGPoint(x: width - rightInset, y: y))
            }
            .stroke(label == "0" ? Color.secondary.opacity(0.32) : Color.secondary.opacity(0.14), lineWidth: label == "0" ? 1.2 : 0.8)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .position(x: 15, y: y)
        }
    }

    private func xPosition(index: Int, count: Int, left: CGFloat, width: CGFloat) -> CGFloat {
        guard count > 1 else { return left + width / 2 }
        return left + width * CGFloat(index) / CGFloat(count - 1)
    }

    private func yPosition(for score: Double, top: CGFloat, height: CGFloat) -> CGFloat {
        let clamped = min(5, max(-5, score))
        let normalized = (clamped + 5) / 10
        return top + height * CGFloat(1 - normalized)
    }
}

private struct MacMoodDailyCard: View {
    let day: RemoteMoodDaily

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .center, spacing: 2) {
                Text(dayLabel)
                    .font(.caption.bold())
                Text(dayNumber)
                    .font(.title3.bold())
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(day.dominantEmotion)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(String(format: "%.1f", day.score))
                        .font(.subheadline.bold())
                        .foregroundStyle(moodColor(day.score))
                }

                if !day.keywords.isEmpty {
                    MacTagFlow(items: day.keywords)
                }

                if !day.summary.isEmpty {
                    Text(day.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .background(Color.overlayHeavy, in: RoundedRectangle(cornerRadius: 14))
    }

    private var dayLabel: String {
        guard let date = macParseDate(day.date + "T00:00:00Z") else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var dayNumber: String {
        guard let date = macParseDate(day.date + "T00:00:00Z") else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func moodColor(_ score: Double) -> Color {
        if score >= 2 { return Color.moodPositive }
        if score >= 0 { return Color.moodNeutral }
        if score >= -2 { return Color.moodMildNegative }
        return Color.moodNegative
    }
}

private struct MacSessionEmotionCurveCard: View {
    let journal: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(journal.dominantEmotion.isEmpty ? "一次夜谈" : journal.dominantEmotion)
                    .font(.subheadline.bold())
                Spacer()
                Text("心情 \(journal.moodScore)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.overlayMedium, in: Capsule())
                Text(macShortDate(journal.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !journal.emotionCurve.isEmpty {
                HStack(spacing: 8) {
                    ForEach(journal.emotionCurve, id: \.self) { emotion in
                        Text(emotion)
                            .font(.caption.bold())
                            .foregroundStyle(Color.textGreenMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Color.overlayMedium,
                                in: Capsule()
                            )
                    }
                }
            } else {
                Text("这次夜谈没有记录到情绪变化序列。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.overlayHeavy, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MacStateWorkspace: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        MacCollectionWorkspace(
            title: "长期状态",
            subtitle: "六个固定维度共同构成长程观察；空白也会明确显示。",
            isEmpty: false
        ) {
            MacStateRadarCard(profiles: store.stateProfiles)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ],
                spacing: 12
            ) {
                ForEach(macStateDomains) { domain in
                    MacStateDomainCard(
                        domain: domain,
                        profile: store.stateProfiles.first { $0.domain == domain.id }
                    )
                }
            }
        }
    }
}

private struct MacStateRadarCard: View {
    let profiles: [StateProfile]

    private var values: [Double] {
        macStateDomains.map { domain in
            Double(profiles.first { $0.domain == domain.id }?.intensity ?? 0)
        }
    }

    private var accessibilitySummary: String {
        zip(macStateDomains, values)
            .map { domain, value in
                let renderedValue = value > 0 ? "\(Int(value))/10" : "资料不足"
                return "\(domain.title) \(renderedValue)"
            }
            .joined(separator: "，")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("六维心理地图", systemImage: "hexagon")
                        .font(.title3.bold())
                    Text("这是关注度地图，不是能力评分；越靠外表示当前困扰、激活或重要程度越高。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("1–10")
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.overlayMedium, in: Capsule())
            }

            GeometryReader { geometry in
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = min(size.width, size.height) * 0.32
                    let axisCount = macStateDomains.count

                    for level in 1...5 {
                        let levelRadius = radius * CGFloat(level) / 5
                        let grid = radarPath(
                            center: center,
                            radius: levelRadius,
                            values: Array(repeating: 1, count: axisCount)
                        )
                        context.stroke(
                            grid,
                            with: .color(Color.chartStroke.opacity(0.16)),
                            lineWidth: level == 5 ? 1.2 : 0.7
                        )
                    }

                    for index in macStateDomains.indices {
                        let endpoint = radarPoint(
                            center: center,
                            radius: radius,
                            index: index,
                            count: axisCount
                        )
                        var axis = Path()
                        axis.move(to: center)
                        axis.addLine(to: endpoint)
                        context.stroke(
                            axis,
                            with: .color(Color.chartStroke.opacity(0.18)),
                            lineWidth: 0.8
                        )
                    }

                    let normalizedValues = values.map { CGFloat(min(max($0 / 10, 0), 1)) }
                    let dataPath = radarPath(
                        center: center,
                        radius: radius,
                        values: normalizedValues
                    )
                    context.fill(
                        dataPath,
                        with: .color(Color.chartFillLight.opacity(0.22))
                    )
                    context.stroke(
                        dataPath,
                        with: .color(Color.chartStroke.opacity(0.88)),
                        lineWidth: 2.2
                    )

                    for index in macStateDomains.indices {
                        let valuePoint = radarPoint(
                            center: center,
                            radius: radius * normalizedValues[index],
                            index: index,
                            count: axisCount
                        )
                        let dot = Path(
                            ellipseIn: CGRect(
                                x: valuePoint.x - 4,
                                y: valuePoint.y - 4,
                                width: 8,
                                height: 8
                            )
                        )
                        context.fill(dot, with: .color(Color.chartStroke))

                        let labelPoint = radarPoint(
                            center: center,
                            radius: radius + 34,
                            index: index,
                            count: axisCount
                        )
                        let valueText = values[index] > 0 ? "\(Int(values[index]))" : "—"
                        let label = Text("\(macStateDomains[index].title) \(valueText)")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.primary.opacity(0.78))
                        context.draw(label, at: labelPoint, anchor: .center)
                    }
                }
            }
            .frame(minHeight: 330)
            .accessibilityHidden(true)

            Text("“—”表示尚未形成画像，不代表强度为 0。点击下方维度卡可查看阶段、证据和支持方向。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(Color.overlayMedium, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.overlayMax, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("六维心理地图")
        .accessibilityValue(accessibilitySummary)
    }

    private func radarPath(
        center: CGPoint,
        radius: CGFloat,
        values: [CGFloat]
    ) -> Path {
        var path = Path()
        for index in values.indices {
            let point = radarPoint(
                center: center,
                radius: radius * values[index],
                index: index,
                count: values.count
            )
            if index == values.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    private func radarPoint(
        center: CGPoint,
        radius: CGFloat,
        index: Int,
        count: Int
    ) -> CGPoint {
        let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * CGFloat.pi / CGFloat(count)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

private struct MacSessionJournalSummary: View {
    let journal: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("总结日记", systemImage: "book.closed.fill")
                    .font(.subheadline.bold())
                Spacer()
                if !journal.dominantEmotion.isEmpty {
                    Text(journal.dominantEmotion)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.pink.opacity(0.12), in: Capsule())
                }
            }

            Text(journal.summary)
                .font(.callout)
                .textSelection(.enabled)

            if !journal.insights.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("洞察")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(journal.insights, id: \.self) { insight in
                        Label(insight, systemImage: "sparkle")
                            .font(.caption)
                    }
                }
            }

            if !journal.keywords.isEmpty {
                MacTagFlow(items: journal.keywords)
            }

            if !journal.suggestedNextStep.isEmpty {
                Label(journal.suggestedNextStep, systemImage: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .background(Color.cardGreenBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MacMemoryCompactRow: View {
    let memory: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(memory.subcategory)
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentMutedGreen)
                Spacer()
                Text(macShortDate(memory.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(memory.content)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(Color.overlayMedium, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MacMemoryDetailCard: View {
    let memory: MemoryEntry

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                if !memory.evidence.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("证据")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(memory.evidence)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                if !memory.keywords.isEmpty {
                    MacTagFlow(items: memory.keywords)
                }
                Text("来源会话 · \(memory.sourceSessionID.isEmpty ? "未关联" : memory.sourceSessionID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(.top, 9)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("\(memory.category) · \(memory.subcategory)")
                        .font(.caption.bold())
                        .foregroundStyle(Color.textGreenMuted)
                    Spacer()
                    Text(macShortDate(memory.updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(memory.content)
                    .textSelection(.enabled)
                Text("重要度 \(memory.importance)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(15)
        .background(Color.overlayHeavy, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MacTagFlow: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption2.bold())
                        .foregroundStyle(Color.textGreenMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.overlayMedium, in: Capsule())
                }
            }
        }
    }
}

private struct MacJournalWeek: Identifiable {
    let startDate: Date
    let journals: [JournalEntry]

    var id: Date { startDate }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDate(startDate, equalTo: Date(), toGranularity: .weekOfYear) {
            return "本周"
        }
        if
            let previousWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: Date()),
            calendar.isDate(startDate, equalTo: previousWeek, toGranularity: .weekOfYear)
        {
            return "上一周"
        }
        return macDateFormatter("M月d日").string(from: startDate)
    }

    var dateRange: String {
        let endDate = Calendar.current.date(byAdding: .day, value: 6, to: startDate) ?? startDate
        return "\(macDateFormatter("M月d日").string(from: startDate)) – \(macDateFormatter("M月d日").string(from: endDate))"
    }

    var averageMood: Double {
        guard !journals.isEmpty else { return 0 }
        return Double(journals.reduce(0) { $0 + $1.moodScore }) / Double(journals.count)
    }

    var dominantEmotion: String {
        mostFrequent(journals.map(\.dominantEmotion).filter { !$0.isEmpty }) ?? "未标注"
    }

    var keywords: [String] {
        frequencySorted(journals.flatMap(\.keywords)).prefix(8).map(\.0)
    }

    var reportText: String {
        let summaries = journals
            .map(\.summary)
            .filter { !$0.isEmpty }
            .prefix(3)
        return summaries.isEmpty ? "这一周的记录还在形成。" : summaries.joined(separator: "\n\n")
    }

    var chartPoints: [MacMoodChartPoint] {
        journals
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                MacMoodChartPoint(
                    id: $0.id,
                    label: macMoodShortDayLabel($0.createdAt),
                    score: Double($0.moodScore),
                    detail: $0.dominantEmotion
                )
            }
    }
}

private struct MacWeeklyReportCard: View {
    let week: MacJournalWeek

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(week.title)周报")
                        .font(.title3.bold())
                    Text("\(week.dateRange) · 根据 \(week.journals.count) 篇日记自动聚合")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(week.dominantEmotion)
                        .font(.subheadline.bold())
                    Text(String(format: "平均心情 %.1f", week.averageMood))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(week.reportText)
                .font(.callout)
                .lineLimit(8)
                .textSelection(.enabled)

            if !week.chartPoints.isEmpty {
                MacMoodTrendChart(
                    points: week.chartPoints,
                    title: "本周心情轨迹",
                    subtitle: "每根柱代表一篇总结日记，折线显示这一周的起伏。"
                )
            }

            if !week.keywords.isEmpty {
                MacTagFlow(items: week.keywords)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color.flowGradientTop,
                    Color.flowGradientBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }
}

private struct MacJournalDetailCard: View {
    let journal: JournalEntry

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text(journal.summary)
                    .textSelection(.enabled)

                if !journal.emotionCurve.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("情绪轨迹")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        MacTagFlow(items: journal.emotionCurve)
                    }
                }

                if !journal.insights.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("洞察")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(journal.insights, id: \.self) { insight in
                            Label(insight, systemImage: "sparkle")
                                .font(.caption)
                        }
                    }
                }

                if !journal.keywords.isEmpty {
                    MacTagFlow(items: journal.keywords)
                }

                if !journal.suggestedNextStep.isEmpty {
                    Label(journal.suggestedNextStep, systemImage: "arrow.right.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text("来源会话 · \(journal.sessionID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            .padding(.top, 10)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(journal.dominantEmotion.isEmpty ? "一次夜谈总结" : journal.dominantEmotion)
                        .font(.headline)
                    Text(macLongDate(journal.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("心情 \(journal.moodScore)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.overlayMedium, in: Capsule())
            }
        }
        .padding(15)
        .background(Color.overlayHeavy, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MacStateDomainCard: View {
    let domain: MacStateDomain
    let profile: StateProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: domain.systemImage)
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(domain.title)
                        .font(.headline)
                    Text(domain.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let profile {
                    Text(profile.trend.isEmpty ? "未标注" : profile.trend)
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.overlayMedium, in: Capsule())
                }
            }

            if let profile {
                Text(profile.stage.isEmpty ? "尚未形成清晰阶段" : profile.stage)
                    .font(.subheadline.bold())
                Text(profile.summary.isEmpty ? "当前没有足够信息。" : profile.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .textSelection(.enabled)

                HStack {
                    Text("强度 \(profile.intensity)/10")
                    Spacer()
                    Text("置信度 \(Int(profile.confidence * 100))%")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                ProgressView(value: Double(profile.intensity), total: 10)

                let evidence = macStringArray(profile.evidence)
                if !evidence.isEmpty {
                    DisclosureGroup("证据与支持方向") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(evidence, id: \.self) { item in
                                Label(item, systemImage: "quote.bubble")
                                    .font(.caption)
                            }
                            if !profile.supportStrategy.isEmpty {
                                Label(profile.supportStrategy, systemImage: "heart.text.square")
                                    .font(.caption)
                            }
                            Text("更新于 \(macLongDate(profile.updatedAt))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.top, 6)
                    }
                    .font(.caption)
                }
            } else {
                ContentUnavailableView(
                    "尚未形成",
                    systemImage: "ellipsis",
                    description: Text("更多跨会话证据出现后，这里会逐渐更新。")
                )
                .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .background(Color.overlayHeavy, in: RoundedRectangle(cornerRadius: 16))
    }
}

private func macJournalWeeks(_ journals: [JournalEntry]) -> [MacJournalWeek] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: journals) { journal -> Date in
        let date = macParseDate(journal.createdAt) ?? .distantPast
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }
    return grouped
        .map { MacJournalWeek(startDate: $0.key, journals: $0.value.sorted { $0.createdAt > $1.createdAt }) }
        .sorted { $0.startDate > $1.startDate }
}

private func frequencySorted(_ values: [String]) -> [(String, Int)] {
    Dictionary(grouping: values.filter { !$0.isEmpty }, by: { $0 })
        .map { ($0.key, $0.value.count) }
        .sorted {
            $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1
        }
}

private func mostFrequent(_ values: [String]) -> String? {
    frequencySorted(values).first?.0
}

private func macMemoryCategoryTitle(_ categoryID: String) -> String {
    macMemoryCategories.first { $0.id == categoryID }?.title ?? categoryID
}

private func macStateDomainTitle(_ domainID: String) -> String {
    macStateDomains.first { $0.id == domainID }?.title ?? domainID
}

private func macMoodColor(_ score: Double) -> Color {
    if score >= 2 { return Color.moodPositive }
    if score >= 0 { return Color.moodNeutral }
    if score >= -2 { return Color.moodMildNegative }
    return Color.moodNegative
}

private func macMoodDayLabel(_ value: String) -> String {
    guard let date = macParseDate(value + "T00:00:00Z") else { return value }
    return macDateFormatter("M/d").string(from: date)
}

private func macMoodShortDayLabel(_ value: String) -> String {
    guard let date = macParseDate(value) else { return "" }
    return macDateFormatter("d日").string(from: date)
}

private func macParseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }
    return ISO8601DateFormatter().date(from: value)
}

private func macIsThisWeek(_ value: String, now: Date = Date()) -> Bool {
    guard let date = macParseDate(value) else { return false }
    let calendar = Calendar.current
    guard
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now),
        let itemWeek = calendar.dateInterval(of: .weekOfYear, for: date)
    else {
        return false
    }
    return currentWeek.start == itemWeek.start
}

private func macDateFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = format
    return formatter
}

private func macShortDate(_ value: String) -> String {
    guard let date = macParseDate(value) else { return value }
    return macDateFormatter("M月d日").string(from: date)
}

private func macLongDate(_ value: String) -> String {
    guard let date = macParseDate(value) else { return value }
    return macDateFormatter("yyyy年M月d日 HH:mm").string(from: date)
}

private func macStringArray(_ value: String) -> [String] {
    guard
        let data = value.data(using: .utf8),
        let items = try? JSONSerialization.jsonObject(with: data) as? [String]
    else {
        return value.isEmpty ? [] : [value]
    }
    return items
}

private struct MacCollectionWorkspace<Content: View>: View {
    let title: String
    let subtitle: String
    let isEmpty: Bool
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 10)

                if isEmpty {
                    ContentUnavailableView(
                        "还没有内容",
                        systemImage: "leaf",
                        description: Text("完成几次夜谈后，这里会逐渐生长出来。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    content
                }
            }
            .padding(28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.conversationBgTop,
                    Color.conversationBgBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

private struct MacFlowRitualSheet: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var draft: String
    @FocusState private var isDraftFocused: Bool
    @State private var activeIntention: String?
    @State private var isClosing = false
    @Environment(\.dismiss) private var dismiss

    init(intention: String) {
        _draft = State(initialValue: intention)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.accentPurpleLight.ignoresSafeArea()

            VStack(spacing: 0) {
                if let activeIntention, isClosing {
                    closingView(intention: activeIntention)
                } else if let activeIntention {
                    activeView(intention: activeIntention)
                } else {
                    preparationView
                }
            }

            Button {
                store.dismissFlowRitual()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
            .zIndex(20)
            .accessibilityLabel("关闭心流任务")
        }
        .frame(maxWidth: 600, maxHeight: 500)
    }

    private var preparationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("这一轮，只靠近一件事")
                        .font(.title2.bold())
                        .foregroundStyle(Color.textPrimary)
                    Text("目标已经尽量缩小。你仍然可以改成此刻更合适的表达。")
                        .font(.callout)
                        .lineSpacing(6)
                        .foregroundStyle(Color.textSecondary)
                }

                TextField("写下一件此刻愿意靠近的事", text: $draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(2...4)
                    .focused($isDraftFocused)
                    .padding(16)
                    .background(Color.accentPurpleLighter, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("为什么这个难度可能合适")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Text(store.starMapInsight.flowSupport.isEmpty ? "根据你的长期状态和近期夜谈，系统为你推荐了合适的难度。" : store.starMapInsight.flowSupport)
                        .font(.subheadline)
                        .lineSpacing(5)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(14)
                .background(Color.overlaySubtle, in: RoundedRectangle(cornerRadius: 17, style: .continuous))

                MacFlowSuggestionLayout(items: suggestions) { suggestion in
                    draft = suggestion
                    isDraftFocused = false
                }

                Button {
                    begin()
                } label: {
                    Text("先只做这一件事")
                        .font(.body.bold())
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.decorativeLavender, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(cleanDraft.isEmpty)
                .opacity(cleanDraft.isEmpty ? 0.42 : 1)

                Text("这里不会计时，不会打卡，也不会评价你做了多少。")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func activeView(intention: String) -> some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.textSecondary)
            Text(intention)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 28)
            Text("不需要马上完成。\n注意力回来时，就再靠近一点点。")
                .font(.callout)
                .lineSpacing(7)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Button("先停在这里") {
                withAnimation(.easeInOut(duration: 0.24)) {
                    isClosing = true
                }
            }
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .buttonStyle(.plain)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
    }

    private func closingView(intention: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("先停在这里")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
            Text(intention)
                .font(.body)
                .lineSpacing(7)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("不总结成果。只留下此刻最接近的一句话。")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 11) {
                ForEach(["更清楚一点", "还在里面", "今天先到这里"], id: \.self) { ending in
                    Button {
                        store.recordFlowMoment(intention: intention, ending: ending)
                        store.dismissFlowRitual()
                    } label: {
                        Text(ending)
                            .font(.body)
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(Color.accentPurpleLighter, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("不留痕迹，直接离开") {
                store.dismissFlowRitual()
            }
            .font(.callout)
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
        .padding(28)
    }

    private var suggestions: [String] {
        let candidates = [
            store.starMapInsight.primaryGoalNextStep,
            store.starMapInsight.secondaryGoalNextStep,
        ] + store.starMapInsight.flowConditions
        var result: [String] = []
        for candidate in candidates {
            let item = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !item.isEmpty, !result.contains(item), result.count < 5 {
                result.append(item)
            }
        }
        return result
    }

    private var cleanDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func begin() {
        guard !cleanDraft.isEmpty else { return }
        isDraftFocused = false
        isClosing = false
        withAnimation(.easeInOut(duration: 0.28)) {
            activeIntention = cleanDraft
        }
    }
}

private struct MacFlowSuggestionLayout: View {
    let items: [String]
    let select: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(items, id: \.self) { item in
                Button {
                    select(item)
                } label: {
                    Text(item)
                        .font(.body)
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .background(Color.overlayMedium, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }
}

private struct MacHexagonRadarChart: View {
    let profiles: [StateProfile]
    private let chartCenter = CGPoint(x: 100, y: 100)

    private let stateDomains = [
        "情绪与压力",
        "身体与能量",
        "关系与边界",
        "自我与价值",
        "目标与行动",
        "资源与支持"
    ]

    private let domainKeys = [
        "emotion",
        "body",
        "relation",
        "self",
        "goal",
        "resource"
    ]

    var body: some View {
        if profiles.isEmpty {
            Text("完成几次夜谈总结后，这里会显示六维心理地图。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        } else {
            VStack(spacing: 0) {
                ZStack(alignment: .center) {
                    ForEach(1...5, id: \.self) { level in
                        hexagonShape(radius: 60 * CGFloat(level) / 5)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    }

                    ForEach(0..<6) { index in
                        let point = pointPosition(radius: 60, index: index)
                        Line(start: chartCenter, end: point)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    }

                    dataPolygon(radius: 60)
                        .fill(Color.chartFillLight.opacity(0.35))
                        .overlay(
                            dataPolygon(radius: 60)
                                                                .stroke(Color.chartStroke, lineWidth: 2)
                        )

                    ForEach(0..<6) { index in
                        let point = pointPosition(radius: 75, index: index)
                        Text(stateDomains[index])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(width: 42)
                            .position(point)
                    }
                }
                .frame(width: 200, height: 200)
            }
            .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
        }
    }

    private func hexagonShape(radius: CGFloat) -> Path {
        Path { path in
            for i in 0..<6 {
                let angle = CGFloat(i) * .pi / 3 - .pi / 2
                let x = chartCenter.x + radius * cos(angle)
                let y = chartCenter.y + radius * sin(angle)
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
        }
    }

    private func pointPosition(radius: CGFloat, index: Int) -> CGPoint {
        let angle = CGFloat(index) * .pi / 3 - .pi / 2
        return CGPoint(
            x: chartCenter.x + radius * cos(angle),
            y: chartCenter.y + radius * sin(angle)
        )
    }

    private func dataPolygon(radius: CGFloat) -> Path {
        Path { path in
            for i in 0..<6 {
                let domainKey = domainKeys[i]
                let profile = profiles.first { $0.domain == domainKey }
                let intensity = profile?.intensity ?? 5
                let normalizedValue = CGFloat(intensity) / 10.0
                let pointRadius = radius * normalizedValue
                let point = pointPosition(radius: pointRadius, index: i)
                if i == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.closeSubpath()
        }
    }
}

private struct Line: Shape {
    var start: CGPoint
    var end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}
