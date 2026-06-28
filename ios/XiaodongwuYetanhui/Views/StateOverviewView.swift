import SwiftUI

struct StateOverviewView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var selectedRoute: PersonalRoute?
    @State private var showsMoreRecords = false
    let openChat: () -> Void
    let continueSession: (String) -> Void

    init(
        openChat: @escaping () -> Void = {},
        continueSession: @escaping (String) -> Void = { _ in }
    ) {
        self.openChat = openChat
        self.continueSession = continueSession
    }

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PersonalOverviewHeader()
                    CurrentStateSnapshotPanel(
                        journals: store.journals,
                        memories: store.memories,
                        profiles: store.stateProfiles,
                        selectProfile: { selectedRoute = .profile($0.id) }
                    )
                    MoodPanel(journals: store.journals)
                    StateProfilePanel(
                        profiles: store.stateProfiles,
                        selectProfile: { selectedRoute = .profile($0.id) }
                    )
                    PatternAnalysisPanel(
                        journals: store.journals,
                        memories: store.memories,
                        profiles: store.stateProfiles
                    )
                    WeeklyReportPanel(journals: store.journals)
                    ThemeClusterPanel(
                        memories: store.memories,
                        journals: store.journals,
                        profiles: store.stateProfiles,
                        openTheme: { selectedRoute = .theme($0) }
                    )
                    MemoryMapPanel(
                        memories: store.memories,
                        openMemory: { selectedRoute = .memory },
                        openCategory: { selectedRoute = .memoryCategory($0) }
                    )
                    MoreRecordsToggle(isExpanded: $showsMoreRecords)
                    if showsMoreRecords {
                        BailanDiaryPanel(entries: store.bailanDiaryEntries)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        FlowMomentPanel(moments: store.flowMoments)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        CareMomentPanel(careMoments: store.careMoments)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        RecommendationHistoryPanel(
                            recommendations: store.recommendationHistory,
                            openChat: openChat
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        NextInteractionPanel(openChat: openChat)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        EmotionCheckInView()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        RecentJournalList(journals: store.journals)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(18)
                .padding(.bottom, 112)
            }
        }
        .navigationTitle("自我")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("资料") {
                        Button("夜谈信箱", systemImage: "envelope.fill") { selectedRoute = .inbox }
                        Button("全部消息", systemImage: "text.bubble.fill") { selectedRoute = .messages }
                        Button("历史会话", systemImage: "clock.arrow.circlepath") { selectedRoute = .sessions }
                        Button("会话总结", systemImage: "book.pages.fill") { selectedRoute = .journals }
                        Button("记忆叶片", systemImage: "leaf.fill") { selectedRoute = .memory }
                    }
                    Section("管理") {
                        Button("数据管理", systemImage: "externaldrive.fill") { selectedRoute = .dataManagement }
                        Button("设置", systemImage: "gearshape.fill") { selectedRoute = .settings }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.warmBrown)
                }
                .accessibilityLabel("资料与设置")
            }
        }
        .navigationDestination(item: $selectedRoute) { route in
            personalDestination(route)
        }
        .task {
            await store.syncIfNeeded()
        }
    }

    @ViewBuilder
    private func personalDestination(_ route: PersonalRoute) -> some View {
        switch route {
        case .inbox:
            MessageDrawerContent()
        case .messages:
            RecentMessagesView()
        case .sessions:
            SessionHistoryView(openSession: continueSession)
        case .memory:
            MemoryListView(openSession: continueSession)
        case .journals:
            JournalHistoryView(openSession: continueSession)
        case .settings:
            SettingsView()
        case .dataManagement:
            PersonalDataManagementPage(
                openMessages: { selectedRoute = .messages },
                openSessions: { selectedRoute = .sessions },
                openMemory: { selectedRoute = .memory },
                openJournals: { selectedRoute = .journals },
                openSourceSession: { selectedRoute = .session($0) }
            )
        case let .session(sessionID):
            HistoricalSessionDestination(
                sessionID: sessionID,
                continueSession: continueSession
            )
        case let .profile(profileID):
            StateProfileDetailPage(
                profile: store.stateProfiles.first { $0.id == profileID },
                continueSession: continueSession
            )
        case let .theme(theme):
            ThemeDetailPage(
                theme: theme,
                memories: store.memories,
                journals: store.journals,
                profiles: store.stateProfiles,
                continueSession: continueSession
            )
        case let .memoryCategory(category):
            MemoryCategoryDetailPage(
                category: category,
                memories: store.memories,
                continueSession: continueSession
            )
        }
    }
}

private enum PersonalRoute: Hashable, Identifiable {
    case inbox
    case messages
    case sessions
    case memory
    case journals
    case settings
    case dataManagement
    case session(String)
    case profile(String)
    case theme(String)
    case memoryCategory(String)

    var id: String {
        switch self {
        case .inbox: return "inbox"
        case .messages: return "messages"
        case .sessions: return "sessions"
        case .memory: return "memory"
        case .journals: return "journals"
        case .settings: return "settings"
        case .dataManagement: return "data-management"
        case let .session(id): return "session-\(id)"
        case let .profile(id): return "profile-\(id)"
        case let .theme(name): return "theme-\(name)"
        case let .memoryCategory(name): return "memory-\(name)"
        }
    }
}

struct HistoricalSessionDestination: View {
    @EnvironmentObject private var store: CompanionStore
    let sessionID: String
    let continueSession: (String) -> Void

    var body: some View {
        if let session = store.sessions.first(where: { $0.id == sessionID }) {
            SessionDetailView(session: session, openSession: continueSession)
        } else {
            ZStack {
                WarmBackground()
                EmptyHintView(
                    systemImage: "link.badge.plus",
                    title: "暂时没有找到来源会话",
                    detail: "这条记录保存了来源编号，但对应会话还没有同步到手机。"
                )
                .padding(18)
            }
            .navigationTitle("来源会话")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await store.syncSessionFromBackend(sessionID)
            }
        }
    }
}

private struct StateProfileDetailPage: View {
    let profile: StateProfile?
    let continueSession: (String) -> Void

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                if let profile {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(
                            title: profile.domain.isEmpty ? "长期画像" : profile.domain,
                            subtitle: "这是长期对话中逐渐形成的一条理解，不是对你的固定定义。"
                        )
                        ProfileDetailPageBlock(title: "当前理解", text: profile.summary, icon: "person.text.rectangle.fill")
                        ProfileDetailPageBlock(title: "形成依据", text: profile.evidence, icon: "quote.bubble.fill")
                        ProfileDetailPageBlock(title: "陪伴策略", text: profile.supportStrategy, icon: "hands.and.sparkles.fill")

                        SoftPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    ProfileMetaPill(title: "阶段", value: profile.stage)
                                    ProfileMetaPill(title: "趋势", value: profile.trend)
                                }
                                HStack {
                                    ProfileMetaPill(title: "强度", value: "\(profile.intensity)")
                                    ProfileMetaPill(title: "可信度", value: "\(Int(profile.confidence * 100))%")
                                }
                            }
                        }

                        if !profile.sourceSessionID.isEmpty {
                            NavigationLink {
                                HistoricalSessionDestination(
                                    sessionID: profile.sourceSessionID,
                                    continueSession: continueSession
                                )
                            } label: {
                                Label("查看形成这条画像的会话", systemImage: "arrow.up.right.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.warmBrown)
                        }
                    }
                    .padding(18)
                } else {
                    EmptyHintView(systemImage: "person.crop.circle.badge.questionmark", title: "没有找到这条画像", detail: "它可能已在最近一次同步中被更新。")
                        .padding(18)
                }
            }
        }
        .navigationTitle("画像详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileDetailPageBlock: View {
    let title: String
    let text: String
    let icon: String

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 9) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(Color.warmBrown)
                Text(text.isEmpty ? "这部分信息还没有形成。" : text)
                    .font(.body)
                    .foregroundStyle(Color.nightInk.opacity(0.84))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ProfileMetaPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "未标记" : value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.nightInk)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ThemeDetailPage: View {
    let theme: String
    let memories: [MemoryEntry]
    let journals: [JournalEntry]
    let profiles: [StateProfile]
    let continueSession: (String) -> Void

    private var matchingMemories: [MemoryEntry] {
        memories.filter {
            normalized($0.category) == normalized(theme)
                || $0.keywords.contains { normalized($0) == normalized(theme) }
        }
    }

    private var matchingJournals: [JournalEntry] {
        journals.filter {
            normalized($0.dominantEmotion) == normalized(theme)
                || $0.keywords.contains { normalized($0) == normalized(theme) }
        }
    }

    private var matchingProfiles: [StateProfile] {
        profiles.filter { normalized($0.domain) == normalized(theme) }
    }

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: theme,
                        subtitle: "这里只展示与这个主题直接相关的画像、记忆和总结。"
                    )
                    HStack(spacing: 8) {
                        ThemeCountPill(title: "画像", value: matchingProfiles.count, icon: "person.text.rectangle")
                        ThemeCountPill(title: "记忆", value: matchingMemories.count, icon: "leaf")
                        ThemeCountPill(title: "总结", value: matchingJournals.count, icon: "book.pages")
                    }

                    ThemeDetailSection(title: "长期画像", icon: "person.text.rectangle.fill") {
                        ForEach(matchingProfiles) { profile in
                            NavigationLink {
                                StateProfileDetailPage(profile: profile, continueSession: continueSession)
                            } label: {
                                ThemeRecordCard(
                                    title: profile.domain,
                                    detail: profile.summary.isEmpty ? profile.evidence : profile.summary,
                                    meta: profile.updatedAt
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ThemeDetailSection(title: "记忆叶片", icon: "leaf.fill") {
                        ForEach(matchingMemories) { memory in
                            ThemeRecordWithSource(
                                title: memory.subcategory.isEmpty ? memory.category : memory.subcategory,
                                detail: memory.content,
                                meta: memory.updatedAt,
                                sessionID: memory.sourceSessionID,
                                continueSession: continueSession
                            )
                        }
                    }

                    ThemeDetailSection(title: "会话总结", icon: "book.pages.fill") {
                        ForEach(matchingJournals) { journal in
                            ThemeRecordWithSource(
                                title: journal.dominantEmotion.isEmpty ? "会话总结" : journal.dominantEmotion,
                                detail: journal.summary,
                                meta: journal.createdAt,
                                sessionID: journal.sessionID,
                                continueSession: continueSession
                            )
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("主题详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct MemoryCategoryDetailPage: View {
    let category: String
    let memories: [MemoryEntry]
    let continueSession: (String) -> Void

    private var matchingMemories: [MemoryEntry] {
        memories.filter {
            let value = $0.category.isEmpty ? "未分类" : $0.category
            return value == category
        }
    }

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: category,
                        subtitle: "这个分类下共有 \(matchingMemories.count) 片记忆。"
                    )
                    ForEach(matchingMemories) { memory in
                        ThemeRecordWithSource(
                            title: memory.subcategory.isEmpty ? "一般记录" : memory.subcategory,
                            detail: memory.content.isEmpty ? memory.evidence : memory.content,
                            meta: memory.updatedAt,
                            sessionID: memory.sourceSessionID,
                            continueSession: continueSession
                        )
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("记忆分类")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThemeDetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundStyle(Color.warmBrown)
                content
            }
        }
    }
}

private struct ThemeRecordCard: View {
    let title: String
    let detail: String
    let meta: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.isEmpty ? "未命名记录" : title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nightInk)
                Text(detail.isEmpty ? "这条记录暂时没有正文。" : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.warmBrown.opacity(0.65))
        }
        .padding(10)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct ThemeRecordWithSource: View {
    let title: String
    let detail: String
    let meta: String
    let sessionID: String
    let continueSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ThemeRecordCard(title: title, detail: detail, meta: meta)
            if !sessionID.isEmpty {
                NavigationLink {
                    HistoricalSessionDestination(
                        sessionID: sessionID,
                        continueSession: continueSession
                    )
                } label: {
                    Label("查看来源会话", systemImage: "arrow.up.right.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warmBrown)
                }
                .buttonStyle(.plain)
                .padding(.leading, 6)
            }
        }
    }
}

private struct MoreRecordsToggle: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.warmBrown)
                    .frame(width: 38, height: 38)
                    .background(Color(hex: 0xffeee9), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(isExpanded ? "收起更多记录" : "更多记录与陪伴")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                    Text("摆烂日记、心流片刻、照顾记录与陪伴建议")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.warmBrown)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Divider()
                    .overlay(Color.warmBrown.opacity(0.18))
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
    }
}

private struct BailanDiaryPanel: View {
    let entries: [BailanDiaryEntry]

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("摆烂日记", systemImage: "tray.full.fill")
                        .font(.headline)

                    Spacer()

                    if !entries.isEmpty {
                        NavigationLink {
                            BailanDiaryHistoryView(entries: entries)
                        } label: {
                            Label("全部", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(hex: 0x676a52))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查看保存的全部摆烂日记")
                    }
                }

                if entries.isEmpty {
                    EmptyHintView(
                        systemImage: "rectangle.and.pencil.and.ellipsis",
                        title: "这里还没有东西",
                        detail: "摆烂页写下的话会原样放在这里，不分析，也不处理。"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                            BailanDiaryRow(entry: entry)
                            if index < min(entries.count, 3) - 1 {
                                Divider()
                                    .overlay(Color(hex: 0xd8cbbb).opacity(0.55))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct BailanDiaryHistoryView: View {
    let entries: [BailanDiaryEntry]

    var body: some View {
        ZStack {
            WarmBackground()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        BailanDiaryRow(entry: entry)
                        if index < entries.count - 1 {
                            Divider()
                                .overlay(Color(hex: 0xd8cbbb).opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(18)
            }
        }
        .navigationTitle("摆烂日记")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BailanDiaryRow: View {
    let entry: BailanDiaryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x676a52))
                .frame(width: 32, height: 32)
                .background(Color(hex: 0xe4e1d2), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.content)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nightInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.response)
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0x676a52))
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

private struct FlowMomentPanel: View {
    let moments: [FlowMoment]

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("最近心流片刻", systemImage: "moon.stars.fill")
                        .font(.headline)

                    Spacer()

                    if !moments.isEmpty {
                        NavigationLink {
                            FlowMomentHistoryView(moments: moments)
                        } label: {
                            Label("全部", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(hex: 0x756887))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查看保存的全部心流片刻")
                    }
                }

                if moments.isEmpty {
                    EmptyHintView(
                        systemImage: "sparkles",
                        title: "还没有留下心流片刻",
                        detail: "在心流页停下来时，可以只留下一句当时的感受。"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(moments.prefix(4).enumerated()), id: \.offset) { index, moment in
                            FlowMomentRow(moment: moment)
                            if index < min(moments.count, 4) - 1 {
                                Divider()
                                    .overlay(Color(hex: 0xd8cbbb).opacity(0.55))
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct FlowMomentHistoryView: View {
    let moments: [FlowMoment]

    var body: some View {
        ZStack {
            WarmBackground()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(moments.enumerated()), id: \.element.id) { index, moment in
                        FlowMomentRow(moment: moment)

                        if index < moments.count - 1 {
                            Divider()
                                .overlay(Color(hex: 0xd8cbbb).opacity(0.55))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(18)
            }
        }
        .navigationTitle("心流片刻")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FlowMomentRow: View {
    let moment: FlowMoment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x8a78a5))
                .frame(width: 32, height: 32)
                .background(Color(hex: 0xeee9f3), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(moment.intention)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nightInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(moment.ending)
                    .font(.caption)
                    .foregroundStyle(Color(hex: 0x756887))
                Text(moment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

private struct PersonalOverviewHeader: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("此刻的你")
                    .font(SensenFonts.handwritten(size: 26))
                    .foregroundStyle(Color.nightInk)
                Text("这里收好对话留下的心情、记忆、总结、周报和长期状态。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Label(connectionLabel, systemImage: connectionIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.backendStatus.isOnline ? Color.green : Color.warmBrown)

                Spacer()

                Button {
                    Task {
                        await store.syncAllFromBackend()
                    }
                } label: {
                    Label(store.isBackendSyncing ? "同步中" : "同步", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.warmBrown)
                .disabled(store.isBackendSyncing)
            }

            if let notice = store.sessionNotice, !notice.isEmpty {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastSyncAt = store.lastBackendSyncAt {
                Label(
                    "最近同步：\(lastSyncAt.formatted(date: .omitted, time: .shortened))",
                    systemImage: "checkmark.icloud.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.warmBrown.opacity(0.12), lineWidth: 1)
        }
    }

    private var connectionLabel: String {
        switch store.backendStatus.state {
        case .unknown: return "尚未检查连接"
        case .checking: return "正在连接 Mac"
        case .online: return "已连接 Mac"
        case .fallback: return "正在使用手机缓存"
        }
    }

    private var connectionIcon: String {
        switch store.backendStatus.state {
        case .unknown: return "questionmark.circle"
        case .checking: return "arrow.triangle.2.circlepath"
        case .online: return "checkmark.circle.fill"
        case .fallback: return "iphone"
        }
    }
}

private struct NextInteractionPanel: View {
    @EnvironmentObject private var store: CompanionStore
    let openChat: () -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("今晚下一步", systemImage: "hand.point.up.left.fill")
                            .font(.headline)
                        Text("从状态里选一个小动作，再回到夜谈里慢慢做。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                VStack(spacing: 10) {
                    ForEach(store.interactionOffers.prefix(3)) { offer in
                        NextInteractionRow(offer: offer, openChat: openChat)
                    }
                }
            }
        }
    }
}

private struct NextInteractionRow: View {
    @EnvironmentObject private var store: CompanionStore
    let offer: CompanionInteractionOffer
    let openChat: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(offer.tint.opacity(0.58))
                Image(systemName: offer.systemImageName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.nightInk.opacity(0.72))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(offer.kind.displayName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.warmBrown)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.68), in: Capsule())
                    Text(offer.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                        .lineLimit(1)
                }
                Text(offer.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button {
                Task {
                    await store.acceptInteractionOffer(offer)
                    openChat()
                }
            } label: {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 28))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.warmBrown)
            .disabled(store.isSending)
            .accessibilityLabel("\(offer.actionTitle)：\(offer.title)")
        }
        .padding(10)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(offer.tint.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct RecommendationHistoryPanel: View {
    @EnvironmentObject private var store: CompanionStore
    let recommendations: [CompanionRecommendation]
    let openChat: () -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("今晚陪伴架", systemImage: "sparkles.rectangle.stack.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(recommendations.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if recommendations.isEmpty {
                    EmptyRecommendationShelf(openChat: openChat)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(recommendations) { recommendation in
                                RecommendationHistoryCard(recommendation: recommendation)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

private struct EmptyRecommendationShelf: View {
    @EnvironmentObject private var store: CompanionStore
    let openChat: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            EmptyHintView(
                systemImage: "music.note.list",
                title: "还没有放上陪伴",
                detail: "在夜谈里打开一次今晚推荐，这里会留下适合此刻的书、音乐或电影。"
            )
            Button {
                store.requestRecommendation()
                openChat()
            } label: {
                Label("去选一个推荐", systemImage: "arrow.up.right.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Color.warmBrown)
            .disabled(store.isSending)
        }
    }
}

private struct RecommendationHistoryCard: View {
    let recommendation: CompanionRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(recommendation.tint.opacity(0.7))
                    Image(systemName: recommendation.medium.systemImageName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.nightInk.opacity(0.72))
                }
                .frame(width: 42, height: 42)
                Spacer()
                Text(recommendation.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(recommendation.medium.displayName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.warmBrown)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.66), in: Capsule())

            Text(recommendation.displayTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.nightInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(recommendation.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(width: 190, height: 178, alignment: .topLeading)
        .background(recommendation.tint.opacity(0.24), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        }
    }
}

private struct SelfMapGuidePanel: View {
    let sessions: [SessionSummary]
    let memories: [MemoryEntry]
    let journals: [JournalEntry]
    let profiles: [StateProfile]
    let openSessions: () -> Void
    let openMemory: () -> Void
    let openJournals: () -> Void

    private var latestStateLine: String {
        guard let journal = journals.first else {
            return "还没有近期总结"
        }
        let emotion = cleaned(journal.dominantEmotion)
        let summary = cleaned(journal.summary)
        if !emotion.isEmpty {
            return emotion
        }
        return summary.isEmpty ? "最近有一条总结" : summary
    }

    private var themeLine: String {
        let domains = Array(Set(profiles.map { cleaned($0.domain) }.filter { !$0.isEmpty }))
            .sorted()
            .prefix(2)
        if !domains.isEmpty {
            return domains.joined(separator: " · ")
        }

        let categories = Array(Set(memories.map { cleaned($0.category) }.filter { !$0.isEmpty }))
            .sorted()
            .prefix(2)
        return categories.isEmpty ? "主题还在形成" : categories.joined(separator: " · ")
    }

    private var sourceCount: Int {
        memories.filter { !cleaned($0.sourceSessionID).isEmpty }.count
            + journals.filter { !cleaned($0.sessionID).isEmpty }.count
            + profiles.filter { !cleaned($0.sourceSessionID).isEmpty }.count
    }

    private var gapCount: Int {
        sessions.filter { $0.messageCount == 0 }.count
            + memories.filter { cleaned($0.category).isEmpty || cleaned($0.subcategory).isEmpty || cleaned($0.sourceSessionID).isEmpty }.count
            + journals.filter { cleaned($0.summary).isEmpty || cleaned($0.sessionID).isEmpty }.count
            + profiles.filter { cleaned($0.summary).isEmpty || cleaned($0.evidence).isEmpty || cleaned($0.supportStrategy).isEmpty || cleaned($0.sourceSessionID).isEmpty }.count
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("自我地图怎么读", systemImage: "map.fill")
                        .font(.headline)
                    Text("这页不是让你打分，而是把最近留下的痕迹整理成几条可以慢慢看的路径。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    GuideStepRow(
                        index: 1,
                        title: "先看现在",
                        detail: latestStateLine,
                        systemImage: "sparkles",
                        actionTitle: journals.isEmpty ? nil : "总结",
                        action: journals.isEmpty ? nil : openJournals
                    )
                    GuideStepRow(
                        index: 2,
                        title: "再看反复出现的主题",
                        detail: themeLine,
                        systemImage: "leaf.fill",
                        actionTitle: memories.isEmpty ? nil : "记忆",
                        action: memories.isEmpty ? nil : openMemory
                    )
                    GuideStepRow(
                        index: 3,
                        title: "需要确认时回到来源",
                        detail: sourceCount == 0 ? "来源链路还在等待形成" : "\(sourceCount) 条内容可以追溯到会话",
                        systemImage: "link.circle.fill",
                        actionTitle: sessions.isEmpty ? nil : "会话",
                        action: sessions.isEmpty ? nil : openSessions
                    )
                    GuideStepRow(
                        index: 4,
                        title: "最后看待整理的地方",
                        detail: gapCount == 0 ? "目前没有明显缺口" : "\(gapCount) 处资料还可以补齐",
                        systemImage: "wand.and.stars",
                        actionTitle: nil,
                        action: nil
                    )
                }
            }
        }
    }

    private func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GuideStepRow: View {
    let index: Int
    let title: String
    let detail: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0xf7e5d8))
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.warmBrown)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warmBrown)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                }
                Text(detail.isEmpty ? "等待更多记录" : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warmBrown)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.58), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct PersonalArchivePanel: View {
    let snapshot: DashboardSnapshot
    let profileCount: Int
    let openInbox: () -> Void
    let openMessages: () -> Void
    let openSessions: () -> Void
    let openMemory: () -> Void
    let openJournals: () -> Void
    let openSettings: () -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("资料与设置", systemImage: "books.vertical.fill")
                        .font(.headline)
                    Text("信箱、消息、历史会话、总结、记忆和设置都从这里进入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ArchiveActionTile(
                        title: "夜谈信箱",
                        detail: "本次对话与互动",
                        value: nil,
                        systemImage: "envelope.fill",
                        action: openInbox
                    )
                    ArchiveActionTile(
                        title: "全部消息",
                        detail: "数据库消息流",
                        value: snapshot.messageCount,
                        systemImage: "text.bubble.fill",
                        action: openMessages
                    )
                    ArchiveActionTile(
                        title: "历史会话",
                        detail: "查看或继续夜谈",
                        value: snapshot.sessionCount,
                        systemImage: "clock.arrow.circlepath",
                        action: openSessions
                    )
                    ArchiveActionTile(
                        title: "会话总结",
                        detail: "日记与理解线索",
                        value: snapshot.journalCount,
                        systemImage: "book.pages.fill",
                        action: openJournals
                    )
                    ArchiveActionTile(
                        title: "记忆叶片",
                        detail: "分类与来源",
                        value: snapshot.memoryCount,
                        systemImage: "leaf.fill",
                        action: openMemory
                    )
                    Button(action: openSettings) {
                        ArchiveTileLabel(
                            title: "设置",
                            detail: "连接、隐私与缓存",
                            value: nil,
                            systemImage: "gearshape.fill"
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Image(systemName: "person.text.rectangle.fill")
                        .foregroundStyle(Color.warmBrown)
                    Text("长期画像")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(profileCount) 个主题已在本页展开")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }
}

private struct ArchiveActionTile: View {
    let title: String
    let detail: String
    let value: Int?
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ArchiveTileLabel(
                title: title,
                detail: detail,
                value: value,
                systemImage: systemImage
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ArchiveTileLabel: View {
    let title: String
    let detail: String
    let value: Int?
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.warmBrown)
                    .frame(width: 30, height: 30)
                    .background(Color(hex: 0xf7e5d8), in: Circle())
                Spacer()
                if let value {
                    Text("\(value)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.nightInk)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.warmBrown.opacity(0.62))
                }
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.nightInk)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct ControlCenterPanel: View {
    let snapshot: DashboardSnapshot
    let profiles: [StateProfile]
    let openMessages: () -> Void
    let openSessions: () -> Void
    let openMemory: () -> Void
    let openJournals: () -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("掌控总览", systemImage: "square.grid.2x2.fill")
                        .font(.headline)
                    Text("先看清楚已经留下了什么，再决定要打开哪一层。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SnapshotGrid(
                    snapshot: snapshot,
                    openMessages: openMessages,
                    openSessions: openSessions,
                    openMemory: openMemory,
                    openJournals: openJournals
                )

                HStack(spacing: 8) {
                    DataPill(title: "长期画像", value: profiles.count, systemImage: "person.text.rectangle")
                    DataPill(title: "可追溯来源", value: profiles.filter { !$0.sourceSessionID.isEmpty }.count, systemImage: "link")
                }
            }
        }
    }
}

private struct DataPill: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.warmBrown)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text("\(value)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.nightInk)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct DatabaseIndexPanel: View {
    let sessions: [SessionSummary]
    let messages: [ChatMessage]
    let memories: [MemoryEntry]
    let journals: [JournalEntry]
    let profiles: [StateProfile]
    let bailanEntries: [BailanDiaryEntry]
    let flowMoments: [FlowMoment]
    let careMoments: [CareMoment]
    let recommendations: [CompanionRecommendation]

    private var profileDomains: String {
        compactList(profiles.map(\.domain), limit: 3, fallback: "等待形成")
    }

    private var memoryCategories: String {
        compactList(memories.map { $0.category.isEmpty ? "未分类" : $0.category }, limit: 3, fallback: "等待生成")
    }

    private var latestJournalEmotion: String {
        let emotion = journals.first?.dominantEmotion.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return emotion.isEmpty ? "暂无总结" : emotion
    }

    private var latestSessionLabel: String {
        if let session = sessions.first {
            return session.createdAt.isEmpty ? "\(session.messageCount) 条消息" : session.createdAt
        }
        return "暂无会话"
    }

    private var localRecordCount: Int {
        bailanEntries.count + flowMoments.count + careMoments.count + recommendations.count
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("资料索引", systemImage: "folder.badge.gearshape")
                        .font(.headline)
                    Text("把数据库里的东西按用途分层：原始对话、总结、记忆、画像和手机本地记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 9) {
                    IndexLayerRow(
                        title: "原始对话层",
                        detail: latestSessionLabel,
                        count: sessions.count,
                        systemImage: "bubble.left.and.text.bubble.right.fill"
                    )
                    IndexLayerRow(
                        title: "会话总结层",
                        detail: latestJournalEmotion,
                        count: journals.count,
                        systemImage: "book.pages.fill"
                    )
                    IndexLayerRow(
                        title: "记忆叶片层",
                        detail: memoryCategories,
                        count: memories.count,
                        systemImage: "leaf.fill"
                    )
                    IndexLayerRow(
                        title: "长期画像层",
                        detail: profileDomains,
                        count: profiles.count,
                        systemImage: "person.text.rectangle.fill"
                    )
                    IndexLayerRow(
                        title: "手机记录层",
                        detail: localRecordCount == 0 ? "摆烂、心流、照顾、推荐" : "摆烂 \(bailanEntries.count) · 心流 \(flowMoments.count) · 照顾 \(careMoments.count)",
                        count: localRecordCount,
                        systemImage: "tray.full.fill"
                    )
                }

                if let latestMessage = messages.last(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    LatestMessageStrip(message: latestMessage)
                }
            }
        }
    }

    private func compactList(_ values: [String], limit: Int, fallback: String) -> String {
        let cleaned = Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted()
            .prefix(limit)
        return cleaned.isEmpty ? fallback : cleaned.joined(separator: " · ")
    }
}

private struct IndexLayerRow: View {
    let title: String
    let detail: String
    let count: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.warmBrown)
                .frame(width: 32, height: 32)
                .background(Color(hex: 0xffeee9), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nightInk)
                Text(detail.isEmpty ? "暂无信息" : detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text("\(count)")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.nightInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.56), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct LatestMessageStrip: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message.role == .user ? "最近我说" : "最近回应", systemImage: message.role == .user ? "person.fill" : "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.warmBrown)
            Text(message.content)
                .font(.caption)
                .foregroundStyle(Color.nightInk.opacity(0.78))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xf6eadf).opacity(0.54), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DataCompletenessPanel: View {
    let sessions: [SessionSummary]
    let memories: [MemoryEntry]
    let journals: [JournalEntry]
    let profiles: [StateProfile]
    let backendStatus: BackendConnectionStatus
    let loadError: String?
    let lastSyncAt: Date?

    private var traceableMemoryCount: Int {
        memories.filter { !$0.sourceSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var traceableJournalCount: Int {
        journals.filter { !$0.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var traceableProfileCount: Int {
        profiles.filter { !$0.sourceSessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var traceableCount: Int {
        traceableMemoryCount + traceableJournalCount + traceableProfileCount
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("数据完整度", systemImage: "checklist")
                        .font(.headline)
                    Text("这里不是评价你，只是告诉你：哪些资料已经在手机里，哪些还需要同步或继续形成。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 9) {
                    CompletenessRow(
                        title: "Mac 后端连接",
                        detail: backendStatus.detail,
                        state: backendStatus.isOnline ? .ready : .waiting,
                        systemImage: backendStatus.isOnline ? "checkmark.icloud.fill" : "iphone"
                    )
                    CompletenessRow(
                        title: "原始会话",
                        detail: sessions.isEmpty ? "还没有同步到可查看的历史会话。" : "已读到 \(sessions.count) 次夜谈。",
                        state: sessions.isEmpty ? .waiting : .ready,
                        systemImage: "bubble.left.and.text.bubble.right.fill"
                    )
                    CompletenessRow(
                        title: "总结与周报材料",
                        detail: journals.isEmpty ? "结束会话并总结后，这里会出现日记和周报材料。" : "已读到 \(journals.count) 条总结材料。",
                        state: journals.isEmpty ? .waiting : .ready,
                        systemImage: "book.pages.fill"
                    )
                    CompletenessRow(
                        title: "记忆叶片",
                        detail: memories.isEmpty ? "active memories 还没有同步或生成。" : "已读到 \(memories.count) 片记忆，其中 \(traceableMemoryCount) 片可追溯。",
                        state: memories.isEmpty ? .waiting : .ready,
                        systemImage: "leaf.fill"
                    )
                    CompletenessRow(
                        title: "长期画像",
                        detail: profiles.isEmpty ? "长期画像还在等待更多总结形成。" : "已形成 \(profiles.count) 个主题，其中 \(traceableProfileCount) 个有来源。",
                        state: profiles.isEmpty ? .waiting : .ready,
                        systemImage: "person.text.rectangle.fill"
                    )
                    CompletenessRow(
                        title: "来源链路",
                        detail: traceableCount == 0 ? "还没有能直接跳回会话的来源链路。" : "\(traceableCount) 条记录可以跳回来源会话。",
                        state: traceableCount == 0 ? .waiting : .ready,
                        systemImage: "link.circle.fill"
                    )
                }

                if let loadError, !loadError.isEmpty {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(Color.warmBrown)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let lastSyncAt {
                    Label(
                        "最近同步：\(lastSyncAt.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "clock.badge.checkmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private enum CompletenessState {
    case ready
    case waiting
}

private struct CompletenessRow: View {
    let title: String
    let detail: String
    let state: CompletenessState
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                    Text(stateLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(iconColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.58), in: Capsule())
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.36), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var iconColor: Color {
        switch state {
        case .ready:
            return Color(hex: 0x6f8f68)
        case .waiting:
            return Color.warmBrown
        }
    }

    private var stateLabel: String {
        switch state {
        case .ready:
            return "已在这里"
        case .waiting:
            return "待形成"
        }
    }
}

private struct DataGapPanel: View {
    let sessions: [SessionSummary]
    let memories: [MemoryEntry]
    let journals: [JournalEntry]
    let profiles: [StateProfile]
    let openSessions: () -> Void
    let openMemory: () -> Void
    let openJournals: () -> Void

    private var gaps: [DataGapItem] {
        var items: [DataGapItem] = []

        let emptySessions = sessions.filter { $0.messageCount == 0 }.count
        if emptySessions > 0 {
            items.append(
                DataGapItem(
                    title: "空会话",
                    detail: "这些会话还没有消息，后续可以在新建 session 的时机上继续收紧。",
                    count: emptySessions,
                    systemImage: "tray",
                    destination: .sessions
                )
            )
        }

        let uncategorizedMemories = memories.filter {
            isBlank($0.category) || isBlank($0.subcategory)
        }.count
        if uncategorizedMemories > 0 {
            items.append(
                DataGapItem(
                    title: "记忆分类不完整",
                    detail: "有些记忆还没有进入明确的大类或小类。",
                    count: uncategorizedMemories,
                    systemImage: "tag",
                    destination: .memories
                )
            )
        }

        let untracedMemories = memories.filter { isBlank($0.sourceSessionID) }.count
        if untracedMemories > 0 {
            items.append(
                DataGapItem(
                    title: "记忆缺少来源",
                    detail: "这些记忆暂时不能直接跳回当时的会话。",
                    count: untracedMemories,
                    systemImage: "link.badge.plus",
                    destination: .memories
                )
            )
        }

        let thinMemories = memories.filter {
            isBlank($0.content) && isBlank($0.evidence)
        }.count
        if thinMemories > 0 {
            items.append(
                DataGapItem(
                    title: "记忆内容偏薄",
                    detail: "有些记忆缺少正文或证据，之后可以由总结逻辑补强。",
                    count: thinMemories,
                    systemImage: "leaf",
                    destination: .memories
                )
            )
        }

        let untracedJournals = journals.filter { isBlank($0.sessionID) }.count
        if untracedJournals > 0 {
            items.append(
                DataGapItem(
                    title: "总结缺少会话来源",
                    detail: "这些总结还不能从这里回到原始对话。",
                    count: untracedJournals,
                    systemImage: "book.closed",
                    destination: .journals
                )
            )
        }

        let thinJournals = journals.filter {
            isBlank($0.summary) || ($0.keywords.isEmpty && $0.insights.isEmpty)
        }.count
        if thinJournals > 0 {
            items.append(
                DataGapItem(
                    title: "总结信息偏少",
                    detail: "有些总结缺少摘要、关键词或洞察。",
                    count: thinJournals,
                    systemImage: "text.badge.checkmark",
                    destination: .journals
                )
            )
        }

        let untracedProfiles = profiles.filter { isBlank($0.sourceSessionID) }.count
        if untracedProfiles > 0 {
            items.append(
                DataGapItem(
                    title: "长期画像缺少来源",
                    detail: "这些画像主题还没有绑定到具体会话。",
                    count: untracedProfiles,
                    systemImage: "person.text.rectangle",
                    destination: .sessions
                )
            )
        }

        let thinProfiles = profiles.filter {
            isBlank($0.summary) || isBlank($0.evidence) || isBlank($0.supportStrategy)
        }.count
        if thinProfiles > 0 {
            items.append(
                DataGapItem(
                    title: "长期画像待补充",
                    detail: "有些画像缺少摘要、证据或支持策略。",
                    count: thinProfiles,
                    systemImage: "sparkle.magnifyingglass",
                    destination: .sessions
                )
            )
        }

        return items
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("待整理清单", systemImage: "wand.and.stars.inverse")
                        .font(.headline)
                    Text("这些不是错误，只是还没被整理完整的地方。把缺口摊开，后续就知道该补哪里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if gaps.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Color(hex: 0x6f8f68))
                        Text("目前没有明显缺口。会话、总结、记忆和长期画像之间的链路看起来比较完整。")
                            .font(.caption)
                            .foregroundStyle(Color.nightInk.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xf5ead8).opacity(0.58), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 9) {
                        ForEach(gaps) { gap in
                            DataGapRow(
                                gap: gap,
                                openSessions: openSessions,
                                openMemory: openMemory,
                                openJournals: openJournals
                            )
                        }
                    }
                }
            }
        }
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private enum DataGapDestination {
    case sessions
    case memories
    case journals
}

private struct DataGapItem: Identifiable {
    var id: String { "\(title)-\(count)" }
    let title: String
    let detail: String
    let count: Int
    let systemImage: String
    let destination: DataGapDestination
}

private struct DataGapRow: View {
    let gap: DataGapItem
    let openSessions: () -> Void
    let openMemory: () -> Void
    let openJournals: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: gap.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.warmBrown)
                .frame(width: 32, height: 32)
                .background(Color.warmBrown.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(gap.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                    Text("\(gap.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.warmBrown)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.62), in: Capsule())
                }

                Text(gap.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(action: openDestination) {
                Text(actionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.warmBrown)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.58), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionTitle: String {
        switch gap.destination {
        case .sessions:
            return "看会话"
        case .memories:
            return "看记忆"
        case .journals:
            return "看总结"
        }
    }

    private func openDestination() {
        switch gap.destination {
        case .sessions:
            openSessions()
        case .memories:
            openMemory()
        case .journals:
            openJournals()
        }
    }
}

private struct SessionProcessingPanel: View {
    let sessions: [SessionSummary]
    let memories: [MemoryEntry]
    let journals: [JournalEntry]
    let profiles: [StateProfile]
    let openSourceSession: (String) -> Void
    let openSessions: () -> Void

    private var processedSessionCount: Int {
        sessionItems.filter { $0.hasJournal || $0.memoryCount > 0 || $0.profileCount > 0 }.count
    }

    private var visibleSessions: [SessionSummary] {
        sessions.filter { $0.messageCount > 0 }.prefix(8).map { $0 }
    }

    private var sessionItems: [SessionProcessingItem] {
        visibleSessions.map { session in
            SessionProcessingItem(
                session: session,
                hasJournal: journals.contains { cleaned($0.sessionID) == session.id },
                memoryCount: memories.filter { cleaned($0.sourceSessionID) == session.id }.count,
                profileCount: profiles.filter { cleaned($0.sourceSessionID) == session.id }.count
            )
        }
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("会话整理状态", systemImage: "arrow.triangle.branch")
                            .font(.headline)
                        Text("看每次夜谈有没有被整理成总结、记忆或长期画像。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(processedSessionCount)/\(visibleSessions.count)")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.nightInk)
                        Text("已整理")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if sessionItems.isEmpty {
                    EmptyHintView(
                        systemImage: "bubble.left.and.text.bubble.right",
                        title: "还没有可整理的会话",
                        detail: "开始一段有内容的夜谈之后，这里会显示它有没有形成总结、记忆和画像。"
                    )
                } else {
                    VStack(spacing: 9) {
                        ForEach(sessionItems) { item in
                            SessionProcessingRow(
                                item: item,
                                openSourceSession: openSourceSession
                            )
                        }
                    }

                    Button(action: openSessions) {
                        Label("查看全部历史会话", systemImage: "list.bullet.rectangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.warmBrown)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cleaned(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SessionProcessingItem: Identifiable {
    var id: String { session.id }
    let session: SessionSummary
    let hasJournal: Bool
    let memoryCount: Int
    let profileCount: Int
}

private struct SessionProcessingRow: View {
    let item: SessionProcessingItem
    let openSourceSession: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: item.hasJournal ? "checkmark.circle.fill" : "circle.dotted")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.hasJournal ? Color(hex: 0x6f8f68) : Color.warmBrown)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.54), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                Text(item.session.preview.isEmpty ? "一次夜谈" : item.session.preview)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nightInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ProcessingBadge(title: item.hasJournal ? "已总结" : "未总结", isReady: item.hasJournal)
                    ProcessingBadge(title: "记忆 \(item.memoryCount)", isReady: item.memoryCount > 0)
                    ProcessingBadge(title: "画像 \(item.profileCount)", isReady: item.profileCount > 0)
                }
            }

            Spacer(minLength: 0)

            Button {
                openSourceSession(item.session.id)
            } label: {
                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.warmBrown)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开来源会话")
        }
        .padding(10)
        .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ProcessingBadge: View {
    let title: String
    let isReady: Bool

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isReady ? Color(hex: 0x6f8f68) : Color.warmBrown.opacity(0.82))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                (isReady ? Color(hex: 0xe9f2df) : Color(hex: 0xf6eadf)).opacity(0.72),
                in: Capsule()
            )
    }
}

private struct RecentActivityTimelinePanel: View {
    let sessions: [SessionSummary]
    let memories: [MemoryEntry]
    let journals: [JournalEntry]
    let profiles: [StateProfile]
    let openSourceSession: (String) -> Void

    private var items: [ActivityTimelineItem] {
        let sessionItems = sessions.prefix(4).map { session in
            ActivityTimelineItem(
                id: "session-\(session.id)",
                kind: "会话",
                title: session.preview.isEmpty ? "一次夜谈" : session.preview,
                detail: "\(session.messageCount) 条消息",
                timestamp: session.createdAt,
                sessionID: session.id,
                icon: "bubble.left.and.text.bubble.right.fill"
            )
        }

        let journalItems = journals.prefix(4).map { journal in
            ActivityTimelineItem(
                id: "journal-\(journal.id)",
                kind: "总结",
                title: journal.dominantEmotion.isEmpty ? "会话总结" : journal.dominantEmotion,
                detail: journal.summary,
                timestamp: journal.createdAt,
                sessionID: journal.sessionID,
                icon: "book.pages.fill"
            )
        }

        let memoryItems = memories.prefix(4).map { memory in
            ActivityTimelineItem(
                id: "memory-\(memory.id)",
                kind: "记忆",
                title: [memory.category, memory.subcategory].filter { !$0.isEmpty }.joined(separator: " / "),
                detail: memory.content,
                timestamp: memory.updatedAt,
                sessionID: memory.sourceSessionID,
                icon: "leaf.fill"
            )
        }

        let profileItems = profiles.prefix(4).map { profile in
            ActivityTimelineItem(
                id: "profile-\(profile.id)",
                kind: "画像",
                title: profile.domain.isEmpty ? "长期状态" : profile.domain,
                detail: profile.summary,
                timestamp: profile.updatedAt,
                sessionID: profile.sourceSessionID,
                icon: "person.text.rectangle.fill"
            )
        }

        return Array((sessionItems + journalItems + memoryItems + profileItems)
            .sorted { lhs, rhs in
                lhs.timestamp > rhs.timestamp
            }
            .prefix(8))
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("最近变动", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                    Text("把最近发生变化的会话、总结、记忆和画像放到同一条时间线里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if items.isEmpty {
                    EmptyHintView(
                        systemImage: "clock",
                        title: "还没有最近变动",
                        detail: "同步到数据库内容后，这里会显示最近被写入或更新的资料。"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            ActivityTimelineRow(item: item) {
                                openIfPossible(item.sessionID)
                            }
                            if index < items.count - 1 {
                                Divider()
                                    .overlay(Color.warmBrown.opacity(0.12))
                                    .padding(.leading, 42)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
            }
        }
    }

    private func openIfPossible(_ sessionID: String) {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        openSourceSession(trimmed)
    }
}

private struct ActivityTimelineItem: Identifiable {
    let id: String
    let kind: String
    let title: String
    let detail: String
    let timestamp: String
    let sessionID: String
    let icon: String
}

private struct ActivityTimelineRow: View {
    let item: ActivityTimelineItem
    let open: () -> Void

    private var canOpen: Bool {
        !item.sessionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: item.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.warmBrown)
                    .frame(width: 31, height: 31)
                    .background(Color(hex: 0xffeee9), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(item.kind)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.warmBrown)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.62), in: Capsule())
                        Text(item.timestamp.isEmpty ? "时间未知" : item.timestamp)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(item.title.isEmpty ? "未命名记录" : item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                        .lineLimit(1)

                    Text(item.detail.isEmpty ? (canOpen ? "点击查看来源会话。" : "这条记录暂时没有摘要。") : item.detail)
                        .font(.caption)
                        .foregroundStyle(Color.nightInk.opacity(0.75))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if canOpen {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.warmBrown.opacity(0.78))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
        .accessibilityHint(canOpen ? "打开关联会话" : "没有关联会话")
    }
}

private struct ThemeClusterPanel: View {
    let memories: [MemoryEntry]
    let journals: [JournalEntry]
    let profiles: [StateProfile]
    let openTheme: (String) -> Void

    private var clusters: [ThemeCluster] {
        var buckets: [String: ThemeClusterAccumulator] = [:]

        for profile in profiles {
            let key = normalizedTheme(profile.domain, fallback: "长期状态")
            buckets[key, default: ThemeClusterAccumulator(title: key)].profileCount += 1
            buckets[key]?.samples.append(profile.summary)
        }

        for memory in memories {
            let key = normalizedTheme(memory.category, fallback: "未分类记忆")
            buckets[key, default: ThemeClusterAccumulator(title: key)].memoryCount += 1
            buckets[key]?.samples.append(memory.content)
            buckets[key]?.keywords.append(contentsOf: memory.keywords)
        }

        for journal in journals {
            let keys = journal.keywords.isEmpty ? [normalizedTheme(journal.dominantEmotion, fallback: "会话总结")] : journal.keywords
            for rawKey in keys.prefix(3) {
                let key = normalizedTheme(rawKey, fallback: "会话总结")
                buckets[key, default: ThemeClusterAccumulator(title: key)].journalCount += 1
                buckets[key]?.samples.append(journal.summary)
                buckets[key]?.keywords.append(contentsOf: journal.keywords)
            }
        }

        return buckets.values
            .map(\.cluster)
            .sorted { lhs, rhs in
                if lhs.totalCount == rhs.totalCount { return lhs.title < rhs.title }
                return lhs.totalCount > rhs.totalCount
            }
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("主题聚合", systemImage: "square.stack.3d.up.fill")
                        .font(.headline)
                    Text("把画像、记忆和总结按主题收在一起，看见哪些事情反复出现。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if clusters.isEmpty {
                    EmptyHintView(
                        systemImage: "square.stack.3d.up",
                        title: "还没有主题簇",
                        detail: "当记忆、总结和长期画像同步后，这里会自动聚合成几个可扫读的主题。"
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(clusters.prefix(6)) { cluster in
                            ThemeClusterRow(
                                cluster: cluster,
                                openTheme: { openTheme(cluster.title) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func normalizedTheme(_ rawValue: String, fallback: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private struct ThemeClusterAccumulator {
    let title: String
    var profileCount: Int = 0
    var memoryCount: Int = 0
    var journalCount: Int = 0
    var samples: [String] = []
    var keywords: [String] = []

    var cluster: ThemeCluster {
        ThemeCluster(
            id: title,
            title: title,
            profileCount: profileCount,
            memoryCount: memoryCount,
            journalCount: journalCount,
            sample: samples.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? "",
            keywords: Array(Set(keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        )
    }
}

private struct ThemeCluster: Identifiable {
    let id: String
    let title: String
    let profileCount: Int
    let memoryCount: Int
    let journalCount: Int
    let sample: String
    let keywords: [String]

    var totalCount: Int {
        profileCount + memoryCount + journalCount
    }
}

private struct ThemeClusterRow: View {
    let cluster: ThemeCluster
    let openTheme: () -> Void

    var body: some View {
        Button(action: openTheme) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(cluster.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text("\(cluster.totalCount)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.warmBrown)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.62), in: Capsule())
                }

                HStack(spacing: 8) {
                    ThemeCountPill(title: "画像", value: cluster.profileCount, icon: "person.text.rectangle")
                    ThemeCountPill(title: "记忆", value: cluster.memoryCount, icon: "leaf")
                    ThemeCountPill(title: "总结", value: cluster.journalCount, icon: "book.pages")
                }

                if !cluster.sample.isEmpty {
                    Text(cluster.sample)
                        .font(.caption)
                        .foregroundStyle(Color.nightInk.opacity(0.76))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !cluster.keywords.isEmpty {
                    Text(cluster.keywords.prefix(4).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("查看这个主题")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.warmBrown)
            }
            .padding(12)
            .background(Color.white.opacity(0.42), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeCountPill: View {
    let title: String
    let value: Int
    let icon: String

    var body: some View {
        Label("\(title) \(value)", systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(value > 0 ? Color.warmBrown : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(hex: 0xffeee9).opacity(value > 0 ? 0.78 : 0.35), in: Capsule())
    }
}

private struct RecentSignalsPanel: View {
    let journals: [JournalEntry]
    let memories: [MemoryEntry]
    let profiles: [StateProfile]
    let openMemory: () -> Void
    let openJournals: () -> Void
    let openSourceSession: (String) -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("最近读到的线索", systemImage: "sparkle.magnifyingglass")
                    .font(.headline)

                if journals.isEmpty && memories.isEmpty && profiles.isEmpty {
                    EmptyHintView(
                        systemImage: "tray",
                        title: "暂时还没有可整理的线索",
                        detail: "同步 Mac 后，最近总结、记忆叶片和长期状态会在这里汇合。"
                    )
                } else {
                    VStack(spacing: 10) {
                        if let journal = journals.first {
                            SignalRow(
                                title: journal.dominantEmotion.isEmpty ? "最近一次总结" : journal.dominantEmotion,
                                subtitle: journal.summary,
                                badge: journal.createdAt,
                                icon: "book.pages.fill",
                                actionTitle: "打开总结",
                                action: openJournals
                            )
                        }

                        if let profile = profiles.first {
                            SignalRow(
                                title: profile.domain,
                                subtitle: profile.summary.isEmpty ? profile.supportStrategy : profile.summary,
                                badge: [profile.stage, profile.trend].filter { !$0.isEmpty }.joined(separator: " · "),
                                icon: "person.text.rectangle.fill",
                                actionTitle: profile.sourceSessionID.isEmpty ? nil : "来源",
                                action: profile.sourceSessionID.isEmpty ? nil : { openSourceSession(profile.sourceSessionID) }
                            )
                        }

                        if let memory = memories.first {
                            SignalRow(
                                title: [memory.category, memory.subcategory].filter { !$0.isEmpty }.joined(separator: " / "),
                                subtitle: memory.content,
                                badge: memory.keywords.prefix(3).joined(separator: " · "),
                                icon: "leaf.fill",
                                actionTitle: "打开记忆",
                                action: openMemory
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct SignalRow: View {
    let title: String
    let subtitle: String
    let badge: String
    let icon: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.warmBrown)
                .frame(width: 34, height: 34)
                .background(Color(hex: 0xffeee9), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title.isEmpty ? "未分类线索" : title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                        .lineLimit(1)
                    if !badge.isEmpty {
                        Text(badge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(subtitle.isEmpty ? "这条线索暂时没有正文。" : subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.nightInk.opacity(0.78))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warmBrown)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
}

private struct SourceTracePanel: View {
    let memories: [MemoryEntry]
    let journals: [JournalEntry]
    let profiles: [StateProfile]
    let openSourceSession: (String) -> Void

    private var traces: [SourceTraceItem] {
        let profileItems = profiles.compactMap { profile -> SourceTraceItem? in
            let sessionID = profile.sourceSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sessionID.isEmpty else { return nil }
            return SourceTraceItem(
                id: "profile-\(profile.id)",
                kind: "画像",
                title: profile.domain.isEmpty ? "长期状态" : profile.domain,
                detail: profile.summary.isEmpty ? profile.evidence : profile.summary,
                sessionID: sessionID,
                updatedAt: profile.updatedAt,
                icon: "person.text.rectangle.fill"
            )
        }

        let memoryItems = memories.compactMap { memory -> SourceTraceItem? in
            let sessionID = memory.sourceSessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sessionID.isEmpty else { return nil }
            return SourceTraceItem(
                id: "memory-\(memory.id)",
                kind: "记忆",
                title: [memory.category, memory.subcategory].filter { !$0.isEmpty }.joined(separator: " / "),
                detail: memory.content.isEmpty ? memory.evidence : memory.content,
                sessionID: sessionID,
                updatedAt: memory.updatedAt,
                icon: "leaf.fill"
            )
        }

        let journalItems = journals.compactMap { journal -> SourceTraceItem? in
            let sessionID = journal.sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sessionID.isEmpty else { return nil }
            return SourceTraceItem(
                id: "journal-\(journal.id)",
                kind: "总结",
                title: journal.dominantEmotion.isEmpty ? "会话总结" : journal.dominantEmotion,
                detail: journal.summary,
                sessionID: sessionID,
                updatedAt: journal.createdAt,
                icon: "book.pages.fill"
            )
        }

        return Array((profileItems + memoryItems + journalItems).prefix(6))
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("来源追溯", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.headline)
                    Text("这里列出能回到具体夜谈的判断和记忆。点开后可以看到它们来自哪一次对话。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if traces.isEmpty {
                    EmptyHintView(
                        systemImage: "link.badge.plus",
                        title: "暂时没有可追溯来源",
                        detail: "当总结、记忆或长期画像保存 source session 后，这里会变成一张来源地图。"
                    )
                } else {
                    VStack(spacing: 9) {
                        ForEach(traces) { trace in
                            SourceTraceRow(trace: trace) {
                                openSourceSession(trace.sessionID)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SourceTraceItem: Identifiable {
    let id: String
    let kind: String
    let title: String
    let detail: String
    let sessionID: String
    let updatedAt: String
    let icon: String
}

private struct SourceTraceRow: View {
    let trace: SourceTraceItem
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: trace.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.warmBrown)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: 0xffeee9), in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Text(trace.kind)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.warmBrown)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.66), in: Capsule())
                        Text(trace.title.isEmpty ? "未命名来源" : trace.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.nightInk)
                            .lineLimit(1)
                    }

                    Text(trace.detail.isEmpty ? "这条记录没有单独保存正文。" : trace.detail)
                        .font(.caption)
                        .foregroundStyle(Color.nightInk.opacity(0.78))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(trace.updatedAt.isEmpty ? "点击查看来源会话" : trace.updatedAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.right.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.warmBrown.opacity(0.84))
            }
            .padding(10)
            .background(Color.white.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("打开来源会话")
    }
}

private struct MemoryMapPanel: View {
    let memories: [MemoryEntry]
    let openMemory: () -> Void
    let openCategory: (String) -> Void

    private var groups: [(category: String, count: Int, keywords: [String])] {
        Dictionary(grouping: memories, by: { $0.category.isEmpty ? "未分类" : $0.category })
            .map { category, entries in
                let keywords = Array(Set(entries.flatMap(\.keywords))).sorted().prefix(3)
                return (category, entries.count, Array(keywords))
            }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count { return lhs.category < rhs.category }
                return lhs.count > rhs.count
            }
    }

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("记忆分类地图", systemImage: "leaf.circle.fill")
                        .font(.headline)
                    Spacer()
                    if !memories.isEmpty {
                        Button(action: openMemory) {
                            Label("全部", systemImage: "chevron.right")
                                .labelStyle(.titleAndIcon)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.warmBrown)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if groups.isEmpty {
                    EmptyHintView(
                        systemImage: "leaf",
                        title: "还没有记忆分类",
                        detail: "当后端生成 active memories 后，这里会按主题把它们收纳起来。"
                    )
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(groups.prefix(6), id: \.category) { group in
                            Button {
                                openCategory(group.category)
                            } label: {
                                MemoryCategoryTile(group: group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

private struct MemoryCategoryTile: View {
    let group: (category: String, count: Int, keywords: [String])

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(group.category)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nightInk)
                    .lineLimit(1)
                Spacer()
                Text("\(group.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.warmBrown)
            }

            Text(group.keywords.isEmpty ? "等待更多关键词" : group.keywords.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(Color(hex: 0xf6eadf).opacity(0.62), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.warmBrown.opacity(0.1), lineWidth: 1)
        }
    }
}

private struct SnapshotGrid: View {
    let snapshot: DashboardSnapshot
    let openMessages: () -> Void
    let openSessions: () -> Void
    let openMemory: () -> Void
    let openJournals: () -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Button(action: openSessions) {
                StatTile(title: "会话", value: snapshot.sessionCount, icon: "moon.stars.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看会话")
            Button(action: openMessages) {
                StatTile(title: "消息", value: snapshot.messageCount, icon: "text.bubble.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看消息")
            Button(action: openMemory) {
                StatTile(title: "记忆", value: snapshot.memoryCount, icon: "leaf.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看记忆")
            Button(action: openJournals) {
                StatTile(title: "总结", value: snapshot.journalCount, icon: "book.closed.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看总结")
        }
    }
}

private struct StatTile: View {
    let title: String
    let value: Int
    let icon: String

    var body: some View {
        SoftPanel {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(value)")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.nightInk)
                }
                Spacer()
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.warmBrown)
            }
        }
    }
}

private struct StateProfilePanel: View {
    let profiles: [StateProfile]
    let selectProfile: (StateProfile) -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("长期状态画像", systemImage: "person.text.rectangle.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(profiles.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if profiles.isEmpty {
                    EmptyHintView(systemImage: "person.text.rectangle", title: "还没有状态画像", detail: "结束并总结几次会话后，长期状态会在这里慢慢形成。")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                        ForEach(profiles.prefix(5)) { profile in
                            StateProfileCompactCard(profile: profile) {
                                selectProfile(profile)
                            }
                        }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

private struct StateProfileCompactCard: View {
    let profile: StateProfile
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(profile.domain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                        .lineLimit(1)
                    Spacer()
                    Text("\(profile.intensity)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.warmBrown)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: 0xffeee9), in: Capsule())
                }

                Text([profile.stage, profile.trend].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(profile.summary.isEmpty ? "这条状态暂时没有摘要。" : profile.summary)
                    .font(.caption)
                    .foregroundStyle(Color.nightInk.opacity(0.78))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 174, height: 132, alignment: .topLeading)
            .background(Color(hex: 0xffeee9).opacity(0.66), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: 0xefd8cf).opacity(0.78), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看完整画像")
    }
}

private struct StateProfileDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: StateProfile
    let openSourceSession: (String) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(profile.domain)
                                .font(SensenFonts.handwritten(size: 28))
                                .foregroundStyle(Color.nightInk)
                            Text([profile.stage, profile.trend].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        ProfileDetailBlock(
                            title: "森森看到的状态",
                            text: profile.summary,
                            fallback: "这条状态还在慢慢形成。"
                        )
                        ProfileDetailBlock(
                            title: "留下这条判断的线索",
                            text: profile.evidence,
                            fallback: "暂时没有单独保存线索。"
                        )
                        ProfileDetailBlock(
                            title: "适合你的支持方式",
                            text: profile.supportStrategy,
                            fallback: "暂时没有形成明确的支持方式。"
                        )

                        HStack(spacing: 10) {
                            Label("强度 \(profile.intensity)", systemImage: "waveform.path")
                            if profile.confidence > 0 {
                                Text("置信度 \(Int(profile.confidence * 100))%")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if !profile.sourceSessionID.isEmpty {
                            Button {
                                let sessionID = profile.sourceSessionID
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    openSourceSession(sessionID)
                                }
                            } label: {
                                Label("查看来源会话", systemImage: "arrow.up.right.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.nightInk)
                            .background(Color(hex: 0xffeee9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("长期画像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct ProfileDetailBlock: View {
    let title: String
    let text: String
    let fallback: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.nightInk)
            Text(text.isEmpty ? fallback : text)
                .font(.callout)
                .foregroundStyle(Color.nightInk.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StateProfileRow: View {
    let profile: StateProfile
    let openSourceSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.domain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                    Text([profile.stage, profile.trend].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("强度 \(profile.intensity)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.warmBrown)
            }

            Text(profile.summary.isEmpty ? "这条状态暂时没有摘要。" : profile.summary)
                .font(.callout)
                .foregroundStyle(Color.nightInk.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)

            if !profile.supportStrategy.isEmpty {
                Text(profile.supportStrategy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !profile.sourceSessionID.isEmpty {
                Button {
                    openSourceSession(profile.sourceSessionID)
                } label: {
                    Label("查看来源会话", systemImage: "arrow.up.right.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.warmBrown)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CareMomentPanel: View {
    let careMoments: [CareMoment]

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("今晚照顾过的东西", systemImage: "hands.and.sparkles.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(careMoments.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if careMoments.isEmpty {
                    EmptyHintView(
                        systemImage: "sparkle.magnifyingglass",
                        title: "还没有照顾记录",
                        detail: "做一次小怪兽 check-in，或在夜谈里玩一次照顾小怪兽，这里会留下今晚的小痕迹。"
                    )
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(careMoments) { moment in
                                CareMomentCard(moment: moment)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}

private struct CareMomentCard: View {
    let moment: CareMoment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(moment.tint.opacity(0.7))
                    Image(systemName: moment.systemImageName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.nightInk.opacity(0.72))
                }
                .frame(width: 42, height: 42)
                Spacer()
                Text(moment.createdAt, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(moment.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.nightInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(moment.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(width: 176, height: 144, alignment: .topLeading)
        .background(moment.tint.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.65), lineWidth: 1)
        }
    }
}

private struct MoodPanel: View {
    let journals: [JournalEntry]

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("最近心情曲线", systemImage: "waveform.path.ecg")
                    .font(.headline)
                if journals.isEmpty {
                    EmptyHintView(systemImage: "chart.xyaxis.line", title: "还没有心情轨迹", detail: "结束几次会话后，这里会显示更稳定的变化。")
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(journals.prefix(10).reversed()) { journal in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(color(for: journal.moodScore))
                                .frame(height: CGFloat(max(18, 42 + journal.moodScore * 10)))
                                .accessibilityLabel("心情分数 \(journal.moodScore)")
                        }
                    }
                    .frame(height: 88, alignment: .bottom)
                }
            }
        }
    }

    private func color(for score: Int) -> Color {
        if score > 0 { return .fieldGreen }
        if score < 0 { return .duskRose }
        return Color(hex: 0xd8cbbb)
    }
}

private struct WeeklyReportPanel: View {
    let journals: [JournalEntry]

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("本周小结", systemImage: "calendar.badge.clock")
                    .font(.headline)

                if let latest = journals.first {
                    Text(latest.summary.isEmpty ? "这一周的记录还在慢慢形成。" : latest.summary)
                        .font(.callout)
                        .foregroundStyle(Color.nightInk.opacity(0.86))
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    if !latest.suggestedNextStep.isEmpty {
                        Text(latest.suggestedNextStep)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    EmptyHintView(systemImage: "calendar", title: "还没有周报", detail: "有几次总结之后，这里会先显示最近一周的小结。")
                }
            }
        }
    }
}

private struct RecentJournalList: View {
    let journals: [JournalEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近总结")
                .font(.headline)
            if journals.isEmpty {
                EmptyHintView(systemImage: "book", title: "暂无总结", detail: "Web 端结束会话后，本地数据库里的总结会出现在这里。")
            } else {
                ForEach(journals.prefix(5)) { journal in
                    SoftPanel {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(journal.dominantEmotion.isEmpty ? "会话总结" : journal.dominantEmotion)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("心情 \(journal.moodScore)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(journal.summary)
                                .font(.callout)
                                .foregroundStyle(Color.nightInk)
                                .lineLimit(4)
                            if !journal.suggestedNextStep.isEmpty {
                                Text(journal.suggestedNextStep)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
