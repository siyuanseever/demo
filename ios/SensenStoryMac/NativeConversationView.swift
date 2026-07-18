import AppKit
import SwiftUI

struct NativeConversationView: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @EnvironmentObject private var speech: SpeechService
    @Binding var flowCardIndex: Int
    @State private var draft = ""
    @State private var measuredDraftHeight: CGFloat = 36

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header
                    Divider()
                    statusArea
                    conversationBody
                    Divider()
                    composer(maxEditorHeight: geometry.size.height / 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                NativeConversationSidebar(flowCardIndex: $flowCardIndex)
                    .frame(width: 300)
            }
        }
        .background(
            LinearGradient(
                colors: [Color.conversationBgTop, Color.conversationBgBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onChange(of: store.latestLiveAssistantMessage?.id) { _, _ in
            guard speech.automaticallyReadsReplies,
                  let message = store.latestLiveAssistantMessage else { return }
            speech.enqueue(messageID: message.id, text: message.content)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            NativeCharacterAvatar(
                character: store.selectedCharacter,
                expressionID: store.messages.last(where: { $0.role == .assistant })?.expressionID,
                size: 34
            )
            VStack(alignment: .leading, spacing: 1) {
                Text("和\(store.selectedCharacter.name)夜谈")
                    .font(.headline)
                Text(store.selectedSessionID == nil ? "一段新的夜谈" : "正在继续这段对话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("新夜谈", systemImage: "plus") { store.newConversation() }
            if store.isSending {
                Button("停止", systemImage: "stop.fill") { store.cancelSend() }
            } else {
                Button("结束并总结", systemImage: "sparkles") {
                    Task { await store.closeCurrentSession() }
                }
                .disabled(
                    store.selectedSessionID == nil
                        || store.messages.allSatisfy { $0.role != .user }
                )
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var statusArea: some View {
        if store.operationStatus != nil || store.notice != nil || store.latestAssessment != nil || store.closeSummary != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let operationStatus = store.operationStatus {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(operationStatus)
                    }
                    .font(.caption)
                }
                if let notice = store.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let assessment = store.latestAssessment {
                    NativeAssessmentStrip(assessment: assessment)
                }
                if let summary = store.closeSummary {
                    NativeCloseSummaryCard(summary: summary)
                        .id("\(summary.journalSummary)|\(summary.memoryCount)|\(summary.stateProfileCount)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.thinMaterial)
        }
    }

    private var conversationBody: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.messages) { message in
                        NativeMessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.leading, 54)
                .padding(.trailing, 24)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if store.messages.isEmpty {
                    ContentUnavailableView {
                        Label("今晚想从哪里说起？", systemImage: "moon.stars")
                    } description: {
                        Text("不用整理好。先写下一句最靠近此刻的话。")
                    }
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .leading) {
                NativeConversationTrail(
                    turns: turns,
                    onSelect: { turn in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(turn.user.id, anchor: .top)
                        }
                    }
                )
                .frame(width: 360)
            }
            .task(id: store.messages.last?.id) {
                guard let lastID = store.messages.last?.id else { return }
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    private func composer(maxEditorHeight: CGFloat) -> some View {
        let maxContentHeight = max(36, maxEditorHeight - 8)
        let editorHeight = min(maxContentHeight, max(36, measuredDraftHeight))
        let hasOverflow = measuredDraftHeight > maxContentHeight

        return HStack(alignment: .bottom, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("慢慢说，我在听…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }

                Text(draftHeightMeasurementText)
                    .font(.body)
                    .foregroundStyle(.clear)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: NativeDraftHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }

                NativeGrowingTextEditor(
                    text: $draft,
                    showsVerticalScroller: hasOverflow
                )
            }
                // Measure at most a small prefix, then cap the editor at one third of
                // the conversation view. This keeps large pastes out of full-document
                // SwiftUI layout while preserving a naturally growing composer.
                .frame(height: editorHeight)
                .clipped()
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.inputBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.cardBorder.opacity(0.7))
                )
                .disabled(store.isSending)
                .onPreferenceChange(NativeDraftHeightPreferenceKey.self) { height in
                    measuredDraftHeight = height
                }

            Button("发送", systemImage: "paperplane.fill") { submit() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending)
        }
        .padding(16)
        .background(.regularMaterial)
    }

    private var draftHeightMeasurementText: String {
        let prefix = draft.prefix(4_000)
        let isTruncated = prefix.endIndex != draft.endIndex
        return draft.isEmpty ? " " : String(prefix) + (isTruncated ? "\n" : "")
    }

    private var turns: [NativeConversationTurn] {
        NativeConversationTurn.build(from: store.messages)
    }

    private func submit() {
        let text = draft
        draft = ""
        store.send(text)
    }
}

private struct NativeDraftHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 36

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NativeGrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    let showsVerticalScroller: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = showsVerticalScroller
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.hasVerticalScroller = showsVerticalScroller
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        textView.string = text
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private struct NativeMessageContent: View {
    let content: String
    @State private var isExpanded = false

    private let previewLimit = 1_200
    private let chunkSize = 2_000

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLongMessage, !isExpanded {
                Text(String(content.prefix(previewLimit)) + "\n…")
                    .textSelection(.enabled)
                Button("展开全文（" + String(content.count) + " 字）") {
                    isExpanded = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if isLongMessage {
                ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                    Text(chunk)
                        .textSelection(.enabled)
                }
                Button("收起长文本") {
                    isExpanded = false
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(content)
                    .textSelection(.enabled)
            }
        }
    }

    private var isLongMessage: Bool {
        content.count > previewLimit
    }

    private var chunks: [String] {
        var result: [String] = []
        var start = content.startIndex
        while start < content.endIndex {
            let end = content.index(start, offsetBy: chunkSize, limitedBy: content.endIndex)
                ?? content.endIndex
            result.append(String(content[start..<end]))
            start = end
        }
        return result
    }
}

private struct NativeMessageBubble: View {
    @EnvironmentObject private var speech: SpeechService
    @State private var selectedKnowledgeCard: KnowledgeCard?
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                avatar
            } else {
                Spacer(minLength: 80)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 7) {
                if message.role == .assistant {
                    HStack(spacing: 6) {
                        Text(character.name)
                            .font(.caption.bold())
                        if !message.replyStage.isEmpty {
                            Text(message.replyStage == "quick" ? "先接住你" : "再想深一点")
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.overlayLight.opacity(0.82), in: Capsule())
                        }
                    }
                    .foregroundStyle(.secondary)
                }

                NativeMessageContent(content: message.content)
                    .foregroundStyle(message.role == .user ? .secondary : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(bubbleColor, in: RoundedRectangle(cornerRadius: 16))

                if let routeSummary = message.routeSummary, !routeSummary.isEmpty {
                    Label(routeSummary, systemImage: "point.3.filled.connected.trianglepath.dotted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !message.knowledgeCards.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.knowledgeCards.prefix(3)) { card in
                            Button {
                                selectedKnowledgeCard = card
                            } label: {
                                Label(card.title, systemImage: "leaf.fill")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.1), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if message.role == .assistant {
                    Button {
                        speech.toggle(messageID: message.id, text: message.content)
                    } label: {
                        Label(
                            speech.activeMessageID == message.id && speech.isPreparing
                                ? "正在生成语音…"
                                : (speech.activeMessageID == message.id && speech.isSpeaking ? "停止朗读" : "听\(character.name)说"),
                            systemImage: speech.activeMessageID == message.id && speech.isActive
                                ? "stop.circle.fill"
                                : "speaker.wave.2.fill"
                        )
                        .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentPurple)
                    .accessibilityHint("使用本机 Qwen3-TTS Serena 女性声线朗读\(character.name)的这条回复")
                }
            }
            .frame(maxWidth: 700, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .contextMenu {
            Button("复制", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            }
        }
        .popover(item: $selectedKnowledgeCard) { card in
            VStack(alignment: .leading, spacing: 12) {
                Label("本轮参考知识", systemImage: "leaf.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(card.title).font(.title3.bold())
                Text(card.concept.isEmpty ? "当前只保存了知识卡标识：\(card.id)" : card.concept)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(18)
            .frame(width: 360, alignment: .leading)
        }
    }

    private var character: CompanionCharacter {
        CompanionFixtures.character(id: message.characterID) ?? CompanionFixtures.characters[0]
    }

    private var bubbleColor: Color {
        message.role == .user ? Color.overlaySubtle.opacity(0.92) : character.bubbleColor.opacity(0.82)
    }

    private var avatar: some View {
        NativeCharacterAvatar(
            character: character,
            expressionID: message.expressionID,
            size: 38
        )
    }
}

private struct NativeConversationTrail: View {
    let turns: [NativeConversationTurn]
    let onSelect: (NativeConversationTurn) -> Void
    @State private var hoveredTurnID: String?

    private let shortTick: CGFloat = 10
    private let longTick: CGFloat = 28

    var body: some View {
        let visibleTurns = Array(turns.suffix(36))

        GeometryReader { geometry in
            let availableHeight = max(1, geometry.size.height - 36)
            let rowHeight = min(28, max(14, availableHeight / CGFloat(max(visibleTurns.count, 1))))

            VStack(spacing: 0) {
                Spacer(minLength: 18)
                ForEach(visibleTurns) { turn in
                    trailRow(turn, visibleTurns: visibleTurns, rowHeight: rowHeight)
                }
                Spacer(minLength: 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }

    private func trailRow(
        _ turn: NativeConversationTurn,
        visibleTurns: [NativeConversationTurn],
        rowHeight: CGFloat
    ) -> some View {
        let isHovered = hoveredTurnID == turn.id

        return ZStack(alignment: .leading) {
            if isHovered {
                NativeTurnPreview(turn: turn)
                    .frame(width: 300)
                    .padding(.leading, 52)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Color.clear
                .frame(width: 44, height: rowHeight)
                .contentShape(Rectangle())
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(isHovered ? Color.accentColor : Color.secondary.opacity(0.28))
                        .frame(width: tickLength(for: turn, visibleTurns: visibleTurns), height: 4)
                        .padding(.leading, 8)
                }
                .onTapGesture { onSelect(turn) }
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.12)) {
                        hoveredTurnID = hovering ? turn.id : nil
                    }
                }
            }
        .frame(width: 360, height: rowHeight, alignment: .leading)
        .zIndex(isHovered ? 10 : 0)
        .help(turn.user.content)
    }

    private func tickLength(for turn: NativeConversationTurn, visibleTurns: [NativeConversationTurn]) -> CGFloat {
        guard let hoveredTurnID,
              let currentIndex = visibleTurns.firstIndex(where: { $0.id == turn.id }),
              let hoveredIndex = visibleTurns.firstIndex(where: { $0.id == hoveredTurnID }) else {
            return shortTick
        }
        let distance = abs(currentIndex - hoveredIndex)
        guard distance <= 3 else { return shortTick }
        let ratio = CGFloat(3 - distance) / 3
        return shortTick + (longTick - shortTick) * ratio
    }
}

private struct NativeTurnPreview: View {
    let turn: NativeConversationTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.user.content)
                .font(.callout.bold())
                .lineLimit(3)
            Divider()
            Text(turn.replies.map(\.content).joined(separator: "\n"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
        .padding(14)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}

private struct NativeConversationSidebar: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @Binding var flowCardIndex: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NativeSidebarSection(title: "本周心流") {
                    NativeSidebarFlowCarousel(
                        cards: flowCards,
                        selectedIndex: $flowCardIndex,
                        onOpenFlow: {
                            NotificationCenter.default.post(name: .nativeOpenFlow, object: nil)
                        }
                    )
                }

                Divider()

                VStack(spacing: 10) {
                    NativeRabbitPortrait(
                        character: store.selectedCharacter,
                        expressionID: latestAssistantMessage?.expressionID
                    )
                    Text(store.selectedCharacter.name)
                        .font(.title3.bold())
                    Text(store.selectedCharacter.tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity)

                Divider()

                NativeSidebarSection(title: "此刻的你") {
                    NativeSidebarAssessment(
                        assessment: store.latestAssessment,
                        isAnalyzing: store.isSending
                    )
                }

                NativeSidebarSection(title: "这次夜谈") {
                    Label("\(store.messages.count) 条消息", systemImage: "text.bubble")
                    Label("DeepSeek 直连双阶段", systemImage: "brain.head.profile")
                }
                .font(.callout)

                if let deepReply = latestDeepReply {
                    Divider()

                    if let planMetadata = deepReply.routePlan {
                        NativeSidebarSection(title: "规划详情") {
                            VStack(alignment: .leading, spacing: 6) {
                                planInfoRow(label: "用户状态", value: planMetadata["user_state"] as? String)
                                planInfoRow(label: "核心需要", value: planMetadata["core_need"] as? String)
                                planInfoRow(label: "风险等级", value: planMetadata["risk_level"] as? String)
                                planInfoRow(label: "回复模式", value: planMetadata["response_mode"] as? String)
                                planInfoRow(label: "历史轮数", value: (planMetadata["history_turns_needed"] as? Int).map { "\($0)" })
                                planInfoRow(label: "需要状态画像", value: (planMetadata["need_state_profiles"] as? Bool).map { $0 ? "是" : "否" })
                                planInfoRow(label: "需要更多记忆", value: (planMetadata["need_more_memories"] as? Bool).map { $0 ? "是" : "否" })
                                planInfoRow(label: "上下文策略", value: planMetadata["context_strategy"] as? String)
                                if let queries = planMetadata["memory_queries"] as? [String], !queries.isEmpty {
                                    planInfoRow(label: "记忆检索词", value: queries.joined(separator: "、"))
                                }
                                planInfoRow(label: "选择理由", value: planMetadata["reason"] as? String)
                            }
                        }
                    }

                    NativeSidebarSection(title: "检索到的记忆（\(deepReply.retrievedMemories.count) 条）") {
                        if deepReply.retrievedMemories.isEmpty {
                            Label("未检索到相关记忆", systemImage: "tray")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(deepReply.retrievedMemories.prefix(5)) { memory in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(memory.content)
                                            .font(.callout)
                                            .foregroundStyle(.primary)
                                            .lineLimit(4)
                                        HStack(spacing: 6) {
                                            Text("[\(memory.category)/\(memory.subcategory)]")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                            if !memory.keywords.isEmpty {
                                                Text(memory.keywords.joined(separator: "、"))
                                                    .font(.caption2)
                                                    .foregroundStyle(.tertiary)
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.overlayLight, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }

                    NativeSidebarSection(title: "参考知识卡（\(deepReply.knowledgeCards.count) 张）") {
                        if deepReply.knowledgeCards.isEmpty {
                            Label("未检索到相关知识", systemImage: "tray")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(deepReply.knowledgeCards) { card in
                                    HStack(spacing: 6) {
                                        Image(systemName: "leaf.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(card.title)
                                            .font(.callout)
                                            .lineLimit(2)
                                    }
                                    .padding(8)
                                    .background(Color.overlayLight, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color.sidebarBackground)
    }

    private var latestAssistantMessage: ChatMessage? {
        store.messages.last(where: { $0.role == .assistant })
    }

    private var latestDeepReply: ChatMessage? {
        store.messages.reversed().first { $0.replyStage == "deep" && $0.role == .assistant }
    }

    @ViewBuilder
    private func planInfoRow(label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 4) {
                Text("\(label)：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var flowCards: [NativeSidebarFlowCardModel] {
        guard let insight = store.flowInsight else { return [] }
        var cards = [
            NativeSidebarFlowCardModel(
                id: "primary",
                title: "主要方向",
                headline: insight.primaryGoalTitle,
                detail: insight.primaryGoalNextStep.isEmpty ? insight.primaryGoalReason : insight.primaryGoalNextStep,
                systemImage: "scope"
            )
        ]
        if insight.hasSecondaryGoal {
            cards.append(
                NativeSidebarFlowCardModel(
                    id: "secondary",
                    title: "次要方向",
                    headline: insight.secondaryGoalTitle,
                    detail: insight.secondaryGoalNextStep.isEmpty ? insight.secondaryGoalReason : insight.secondaryGoalNextStep,
                    systemImage: "arrow.triangle.branch"
                )
            )
        }
        if !insight.recentEmotionSummary.isEmpty {
            cards.append(
                NativeSidebarFlowCardModel(
                    id: "emotion",
                    title: "最近的情绪天气",
                    headline: insight.recentEmotionTags.prefix(3).joined(separator: " · "),
                    detail: insight.recentEmotionSummary,
                    systemImage: "cloud.sun.fill"
                )
            )
        }
        return cards.filter { !$0.headline.isEmpty || !$0.detail.isEmpty }
    }
}

private struct NativeSidebarFlowCardModel: Identifiable {
    let id: String
    let title: String
    let headline: String
    let detail: String
    let systemImage: String
}

private struct NativeSidebarFlowCarousel: View {
    let cards: [NativeSidebarFlowCardModel]
    @Binding var selectedIndex: Int
    let onOpenFlow: () -> Void

    var body: some View {
        if cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("还没有本周导航", systemImage: "sparkles")
                    .font(.callout.bold())
                Text("完成夜谈总结后，这里会安静地出现本周方向。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("前往心流", systemImage: "arrow.right") {
                    onOpenFlow()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentPurple)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(14)
            .background(Color.cardBackground.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
        } else {
            let index = selectedIndex % cards.count
            let card = cards[index]
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(card.title, systemImage: card.systemImage)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentPurple)
                    Spacer()
                    HStack(spacing: 4) {
                        Button { move(-1) } label: { Image(systemName: "chevron.left") }
                        Button { move(1) } label: { Image(systemName: "chevron.right") }
                        Button(action: onOpenFlow) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .accessibilityLabel("查看完整心流导航")
                    }
                    .buttonStyle(.plain)
                }
                Text(card.headline)
                    .font(.headline)
                    .lineLimit(2)
                Text(card.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    ForEach(cards.indices, id: \.self) { item in
                        Capsule()
                            .fill(item == index ? Color.accentPurple : Color.secondary.opacity(0.2))
                            .frame(width: item == index ? 16 : 6, height: 5)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 142, maxHeight: 142, alignment: .topLeading)
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.flowGradientTop, Color.flowGradientBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
    }

    private func move(_ offset: Int) {
        guard cards.count > 1 else { return }
        let index = selectedIndex % cards.count
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedIndex = (index + offset + cards.count) % cards.count
        }
    }
}

private struct NativeRabbitPortrait: View {
    let character: CompanionCharacter
    let expressionID: String?

    var body: some View {
        VStack(spacing: 8) {
            NativeCharacterAvatar(
                character: character,
                expressionID: expressionID,
                size: 112,
                cornerRadius: 14,
                fillsWidth: true
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            Text(expressionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 10)
        .background(character.bubbleColor.opacity(0.34), in: RoundedRectangle(cornerRadius: 18))
        .animation(.easeInOut(duration: 0.2), value: expressionID)
        .accessibilityLabel("\(character.name)，\(expressionLabel)")
    }

    private var expressionLabel: String {
        character.expression(id: expressionID ?? character.defaultExpressionID)?.label ?? "正在倾听"
    }
}

private struct NativeSidebarSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NativeSidebarAssessment: View {
    let assessment: UserConversationAssessment?
    let isAnalyzing: Bool

    var body: some View {
        if let assessment {
            VStack(alignment: .leading, spacing: 10) {
                assessmentRow("状态与情绪", assessment.userState, "heart.text.square.fill")
                assessmentRow("此刻需要", assessment.coreNeed, "hand.raised.fingers.spread.fill")
                HStack(spacing: 6) {
                    Text("风险 · \(riskLabel(assessment.riskLevel))")
                    Text("回应 · \(assessment.responseMode)")
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentPurple.opacity(0.09), in: Capsule())
                if !assessment.reason.isEmpty {
                    Text(assessment.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        } else {
            Label(
                isAnalyzing ? "正在理解你此刻的情绪与需要…" : "开始说话后，这里会显示本轮理解。",
                systemImage: isAnalyzing ? "waveform.badge.magnifyingglass" : "moon.stars"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func assessmentRow(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "正在继续理解" : value)
                .font(.callout)
        }
    }

    private func riskLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "medium", "moderate": "需留意"
        case "high": "较高"
        case "crisis", "critical": "紧急"
        default: "较低"
        }
    }
}

private struct NativeAssessmentStrip: View {
    let assessment: UserConversationAssessment

    var body: some View {
        HStack(spacing: 8) {
            assessmentItem("状态", assessment.userState)
            assessmentItem("需要", assessment.coreNeed)
            assessmentItem("风险", assessment.riskLevel)
            assessmentItem("策略", assessment.responseMode)
        }
    }

    private func assessmentItem(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            Text(value).lineLimit(1)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.overlaySubtle.opacity(0.82), in: Capsule())
    }
}

private struct NativeCloseSummaryCard: View {
    let summary: SessionCloseSummary
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                NativeSpeechButton(
                    messageID: "session-summary-\(summary.id.uuidString)",
                    text: NativeSpeechNarration.sessionSummary(summary),
                    idleLabel: "听忧忧兔总结"
                )
                Text(summary.journalSummary)
                    .font(.callout)
                    .textSelection(.enabled)
                if let journal = summary.journal {
                    HStack(spacing: 8) {
                        if !journal.dominantEmotion.isEmpty {
                            Label(journal.dominantEmotion, systemImage: "heart.text.square.fill")
                        }
                        Text("心情 \(journal.moodScore > 0 ? "+" : "")\(journal.moodScore)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    if !journal.emotionCurve.isEmpty {
                        Text("情绪变化：\(journal.emotionCurve.joined(separator: " → "))")
                            .font(.caption)
                    }
                    if !journal.keywords.isEmpty {
                        Text("关键词：\(journal.keywords.joined(separator: " · "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !journal.insights.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("洞察").font(.caption.bold()).foregroundStyle(.secondary)
                            ForEach(journal.insights, id: \.self) { insight in
                                Label(insight, systemImage: "lightbulb.fill").font(.caption)
                            }
                        }
                    }
                    if !journal.suggestedNextStep.isEmpty {
                        Label(journal.suggestedNextStep, systemImage: "arrow.forward.circle.fill")
                            .font(.caption)
                    }
                }
                if !summary.memories.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本轮记忆").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(summary.memories) { memory in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("• [\(memory.category)/\(memory.subcategory)] \(memory.content)")
                                if !memory.keywords.isEmpty {
                                    Text("  \(memory.keywords.joined(separator: " · "))")
                                        .foregroundStyle(.secondary)
                                }
                                if !memory.reason.isEmpty {
                                    Text("  依据：\(memory.reason)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
                if !changedStateProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("长期状态更新").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(changedStateProfiles) { profile in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("• \(profile.domain)：\(profile.summary)")
                                Text("  \(profile.stage) · \(profile.trend) · 强度 \(profile.intensity)/10")
                                    .foregroundStyle(.secondary)
                                if !profile.supportStrategy.isEmpty {
                                    Text("  支持方式：\(profile.supportStrategy)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label("本轮整理完成", systemImage: "checkmark.seal.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                HStack {
                    Text("\(summary.memoryCount) 条记忆")
                    Text("\(summary.stateProfileCount) 项长期状态更新")
                    if let emotion = summary.journal?.dominantEmotion, !emotion.isEmpty {
                        Text(emotion)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var changedStateProfiles: [SessionCloseStateProfile] {
        summary.stateProfiles.filter { $0.action != "no_change" }
    }
}

struct NativeSpeechButton: View {
    @EnvironmentObject private var speech: SpeechService
    let messageID: String
    let text: String
    var idleLabel = "听忧忧兔说"

    var body: some View {
        Button {
            speech.toggle(messageID: messageID, text: text)
        } label: {
            Label(label, systemImage: isActive ? "stop.circle.fill" : "speaker.wave.2.fill")
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentPurple)
        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityHint(isActive ? "停止当前朗读" : "使用忧忧兔的声音朗读这段内容")
    }

    private var isActive: Bool {
        speech.activeMessageID == messageID && speech.isActive
    }

    private var label: String {
        guard speech.activeMessageID == messageID else {
            return speech.queuedMessageID == messageID ? "等待朗读…" : idleLabel
        }
        if speech.isPreparing { return "正在生成语音…" }
        if speech.isSpeaking { return "停止朗读" }
        return idleLabel
    }
}

enum NativeSpeechNarration {
    static func sessionSummary(_ summary: SessionCloseSummary) -> String {
        var parts = ["今晚的夜谈结束啦，我是忧忧兔，来陪你回顾一下。", summary.journalSummary]
        if let journal = summary.journal {
            if !journal.dominantEmotion.isEmpty {
                parts.append("今天比较明显的感受是\(journal.dominantEmotion)。")
            }
            if !journal.insights.isEmpty {
                parts.append("我们还一起看见了：\(journal.insights.joined(separator: "；"))。")
            }
            if !journal.suggestedNextStep.isEmpty {
                parts.append("接下来，如果你愿意，可以试试：\(journal.suggestedNextStep)。")
            }
        }
        parts.append("今天先到这里也很好。晚一点休息时，记得对自己温柔一点。")
        return joined(parts)
    }

    static func journal(_ journal: JournalEntry) -> String {
        var parts = ["我是忧忧兔，来陪你读这篇日记。", journal.summary]
        if !journal.emotionCurve.isEmpty {
            parts.append("这段时间的情绪变化是：\(journal.emotionCurve.joined(separator: "，然后"))。")
        }
        if !journal.insights.isEmpty {
            parts.append("日记里留下的洞察是：\(journal.insights.joined(separator: "；"))。")
        }
        if !journal.suggestedNextStep.isEmpty {
            parts.append("给自己的下一小步是：\(journal.suggestedNextStep)。")
        }
        return joined(parts)
    }

    static func weeklyReport(weekLabel: String, journals: [JournalEntry]) -> String {
        let summaries = journals.map(\.summary).filter { !$0.isEmpty }.prefix(3)
        let emotions = journals.map(\.dominantEmotion).filter { !$0.isEmpty }
        let dominantEmotion = Dictionary(grouping: emotions, by: { $0 })
            .max { $0.value.count < $1.value.count }?.key
        var parts = ["我是忧忧兔，来陪你回顾\(weekLabel)的小结。"]
        if let dominantEmotion {
            parts.append("这一周比较常出现的感受是\(dominantEmotion)。")
        }
        parts.append(contentsOf: summaries)
        let nextSteps = journals.map(\.suggestedNextStep).filter { !$0.isEmpty }.prefix(2)
        if !nextSteps.isEmpty {
            parts.append("接下来可以轻轻记住：\(nextSteps.joined(separator: "；"))。")
        }
        return joined(parts)
    }

    static func flow(_ insight: StarMapInsight) -> String {
        var parts = ["我是忧忧兔，来陪你看看\(insight.periodLabel)的心流导航。"]
        if !insight.primaryGoalTitle.isEmpty {
            parts.append("这一周最值得照看的方向是：\(insight.primaryGoalTitle)。\(insight.primaryGoalReason)")
        }
        if !insight.primaryGoalNextStep.isEmpty {
            parts.append("可以从这一步开始：\(insight.primaryGoalNextStep)。")
        }
        if !insight.recentEmotionSummary.isEmpty {
            parts.append("最近的情绪天气是：\(insight.recentEmotionSummary)")
        }
        if !insight.coreInsight.isEmpty || !insight.coreInsightDetail.isEmpty {
            parts.append("这一周看见的核心是：\(joined([insight.coreInsight, insight.coreInsightDetail]))")
        }
        if !insight.gentleReminder.isEmpty || !insight.gentleReminderDetail.isEmpty {
            parts.append("最后留一个温柔提醒：\(joined([insight.gentleReminder, insight.gentleReminderDetail]))")
        }
        return joined(parts)
    }

    private static func joined<S: Sequence>(_ parts: S) -> String where S.Element == String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
