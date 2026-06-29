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
            CharacterAvatar(character: store.selectedCharacter, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("和 \(store.selectedCharacter.name) 夜谈")
                    .font(.headline)
                Text(store.sessionNotice ?? "你可以慢慢说，不需要先整理好。")
                    .font(.caption)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }
}

private struct MacMessageRow: View {
    @EnvironmentObject private var store: CompanionStore
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

                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundStyle(message.role == .user ? Color.primary.opacity(0.72) : Color.primary)
                        .textSelection(.enabled)
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
    let openConversation: () -> Void

    var body: some View {
        MacCollectionWorkspace(
            title: "历史会话",
            subtitle: "继续过去的夜谈，或者查看最近发生了什么。",
            isEmpty: store.sessions.isEmpty
        ) {
            ForEach(store.sessions) { session in
                Button {
                    store.openSession(session.id)
                    openConversation()
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(session.preview.isEmpty ? "一次安静的夜谈" : session.preview)
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            Text("\(session.messageCount) 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(session.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MacMemoriesWorkspace: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        MacCollectionWorkspace(
            title: "长期记忆",
            subtitle: "按最近更新时间查看已经留下来的线索。",
            isEmpty: store.memories.isEmpty
        ) {
            ForEach(store.memories) { memory in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(memory.category) · \(memory.subcategory)")
                            .font(.caption.bold())
                            .foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.28))
                        Spacer()
                        Text("重要度 \(memory.importance)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(memory.content)
                        .textSelection(.enabled)
                    if !memory.keywords.isEmpty {
                        Text(memory.keywords.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(15)
                .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

private struct MacJournalsWorkspace: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        MacCollectionWorkspace(
            title: "总结日记",
            subtitle: "每次夜谈结束后生成的摘要、情绪和下一步。",
            isEmpty: store.journals.isEmpty
        ) {
            ForEach(store.journals) { journal in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(journal.dominantEmotion.isEmpty ? "一次夜谈总结" : journal.dominantEmotion)
                            .font(.headline)
                        Spacer()
                        Text(journal.createdAt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(journal.summary)
                        .textSelection(.enabled)
                    if !journal.suggestedNextStep.isEmpty {
                        Label(journal.suggestedNextStep, systemImage: "arrow.right.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(15)
                .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

private struct MacStateWorkspace: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        MacCollectionWorkspace(
            title: "长期状态",
            subtitle: "这不是诊断，而是跨会话持续整理的观察。",
            isEmpty: store.stateProfiles.isEmpty
        ) {
            ForEach(store.stateProfiles) { profile in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text(profile.domain)
                            .font(.headline)
                        Spacer()
                        Text(profile.trend)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(profile.stage)
                        .font(.subheadline.bold())
                    Text(profile.summary)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    ProgressView(value: Double(profile.intensity), total: 10)
                }
                .padding(15)
                .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
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
