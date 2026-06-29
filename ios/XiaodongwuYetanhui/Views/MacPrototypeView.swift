import SwiftUI

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
        .background(Color(red: 0.98, green: 0.96, blue: 0.92))
    }
}

private enum MacWorkspaceSection: String, CaseIterable, Identifiable {
    case conversation
    case sessions
    case memories
    case journals
    case state
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversation: "夜谈"
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

            Section("资料概览") {
                MacSidebarMetric(title: "会话", value: store.snapshot.sessionCount)
                MacSidebarMetric(title: "消息", value: store.snapshot.messageCount)
                MacSidebarMetric(title: "记忆", value: store.snapshot.memoryCount)
                MacSidebarMetric(title: "日记", value: store.snapshot.journalCount)
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

private struct MacSidebarMetric: View {
    let title: String
    let value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.formatted())
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
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
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                MacConversationHeader()

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(store.messages) { message in
                                MacMessageRow(message: message)
                                    .id(message.id)
                            }

                            if store.isSending {
                                MacThinkingRow(character: store.selectedCharacter)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity)
                    }
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.99, green: 0.98, blue: 0.95),
                                Color(red: 0.95, green: 0.97, blue: 0.93),
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
                }

                Divider()

                MacComposer(draft: $draft, isFocused: $isComposerFocused)
                    .environmentObject(store)
            }

            Divider()

            MacConversationInspector()
                .environmentObject(store)
                .frame(width: 260)
        }
        .task {
            isComposerFocused = true
        }
    }
}

private struct MacConversationHeader: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        HStack(spacing: 12) {
            CharacterAvatar(character: store.selectedCharacter, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("和 \(store.selectedCharacter.name) 夜谈")
                    .font(.subheadline.bold())
                Text(store.sessionNotice ?? "你可以慢慢说，不需要先整理好。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

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
                    systemImage: "checkmark.circle"
                )
            }
            .disabled(store.isSending || store.summarizingSessionID != nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .background(.regularMaterial)
    }
}

private struct MacMessageRow: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var selectedKnowledgeCard: KnowledgeCard?
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

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                    if message.role == .assistant {
                        Text(store.character(id: message.characterID)?.name ?? store.selectedCharacter.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        if let routeSummary = message.routeSummary, !routeSummary.isEmpty {
                            Label(routeSummary, systemImage: "wand.and.stars")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text(message.content)
                            .font(.system(size: 15))
                            .foregroundStyle(message.role == .user ? Color.primary.opacity(0.72) : Color.primary)
                            .textSelection(.enabled)

                        if !message.knowledgeCards.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("本轮参考知识", systemImage: "leaf.fill")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)

                                ForEach(message.knowledgeCards) { card in
                                    Button {
                                        selectedKnowledgeCard = card
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(card.title)
                                                .lineLimit(1)
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(Color.white.opacity(0.48), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(
                        message.role == .user
                            ? Color.gray.opacity(0.10)
                            : (store.character(id: message.characterID)?.bubbleColor ?? store.selectedCharacter.bubbleColor),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                }
                .frame(maxWidth: 620, alignment: message.role == .user ? .trailing : .leading)

                if message.role == .assistant {
                    Spacer(minLength: 90)
                }
            }
            .frame(maxWidth: .infinity)
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
        }
    }
}

private struct MacThinkingRow: View {
    let character: CompanionCharacter

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
                    .background(Color.white.opacity(0.74), in: RoundedRectangle(cornerRadius: 14))
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
                .tint(Color(red: 0.46, green: 0.39, blue: 0.66))
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

private struct MacConversationInspector: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(spacing: 12) {
                    CharacterAvatar(character: store.selectedCharacter, size: 88)
                    Text(store.selectedCharacter.name)
                        .font(.title3.bold())
                    Text(store.selectedCharacter.tagline)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                Divider()

                MacInspectorSection(title: "当前连接") {
                    Label(store.backendStatus.state.rawValue, systemImage: "network")
                    Text(store.backendStatus.baseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                MacInspectorSection(title: "这次夜谈") {
                    Label("\(store.messages.count) 条消息", systemImage: "text.bubble")
                    Label(
                        store.isLocalAIConfigured ? "本机 API 模式" : "后端服务模式",
                        systemImage: "brain"
                    )
                }

                if let notice = store.sessionNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                }

                Spacer(minLength: 20)
            }
            .padding(20)
        }
        .background(Color(red: 0.96, green: 0.94, blue: 0.90))
    }
}

private struct MacInspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            content
                .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacSessionsWorkspace: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var expandedSessionID: String?
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
                        .tint(Color(red: 0.46, green: 0.39, blue: 0.66))
                    }
                    .padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(session.preview.isEmpty ? "一次安静的夜谈" : session.preview)
                                .font(.headline)
                                .lineLimit(2)
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
                }
                .padding(16)
                .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
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
                        .foregroundStyle(Color(red: 0.35, green: 0.43, blue: 0.30))
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
        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.72))
        }
    }
}

private struct MacJournalsWorkspace: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        MacCollectionWorkspace(
            title: "总结日记",
            subtitle: "按周查看日记、情绪轨迹、关键词和阶段性小结。",
            isEmpty: store.journals.isEmpty
        ) {
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
}

private struct MacStateWorkspace: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        MacCollectionWorkspace(
            title: "长期状态",
            subtitle: "六个固定维度共同构成长程观察；空白也会明确显示。",
            isEmpty: false
        ) {
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
        .background(Color(red: 0.94, green: 0.96, blue: 0.90), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MacMemoryCompactRow: View {
    let memory: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(memory.subcategory)
                    .font(.caption.bold())
                    .foregroundStyle(Color(red: 0.34, green: 0.42, blue: 0.29))
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
        .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 10))
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
                        .foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.28))
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
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
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
                        .foregroundStyle(Color(red: 0.36, green: 0.39, blue: 0.31))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.62), in: Capsule())
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

            if !week.keywords.isEmpty {
                MacTagFlow(items: week.keywords)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.91, green: 0.94, blue: 0.84),
                    Color(red: 0.96, green: 0.90, blue: 0.86),
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
                    .background(Color.white.opacity(0.62), in: Capsule())
            }
        }
        .padding(15)
        .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
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
                    .foregroundStyle(Color(red: 0.42, green: 0.37, blue: 0.59))
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
                        .background(Color.white.opacity(0.62), in: Capsule())
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
        .background(Color.white.opacity(0.70), in: RoundedRectangle(cornerRadius: 16))
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

private func macParseDate(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) {
        return date
    }
    return ISO8601DateFormatter().date(from: value)
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
                    Color(red: 0.99, green: 0.98, blue: 0.95),
                    Color(red: 0.94, green: 0.96, blue: 0.91),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}
