import SwiftUI

struct StateOverviewView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var selectedProfile: StateProfile?
    @State private var showsMoreRecords = false
    let openChat: () -> Void
    let openMessages: () -> Void
    let openSessions: () -> Void
    let openMemory: () -> Void
    let openJournals: () -> Void
    let openSourceSession: (String) -> Void

    init(
        openChat: @escaping () -> Void = {},
        openMessages: @escaping () -> Void = {},
        openSessions: @escaping () -> Void = {},
        openMemory: @escaping () -> Void = {},
        openJournals: @escaping () -> Void = {},
        openSourceSession: @escaping (String) -> Void = { _ in }
    ) {
        self.openChat = openChat
        self.openMessages = openMessages
        self.openSessions = openSessions
        self.openMemory = openMemory
        self.openJournals = openJournals
        self.openSourceSession = openSourceSession
    }

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PersonalOverviewHeader()
                    MoodPanel(journals: store.journals)
                    WeeklyReportPanel(journals: store.journals)
                    StateProfilePanel(
                        profiles: store.stateProfiles,
                        selectProfile: { selectedProfile = $0 }
                    )
                    SnapshotGrid(
                        snapshot: store.snapshot,
                        openMessages: openMessages,
                        openSessions: openSessions,
                        openMemory: openMemory,
                        openJournals: openJournals
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
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedProfile) { profile in
            StateProfileDetailSheet(
                profile: profile,
                openSourceSession: openSourceSession
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await store.syncIfNeeded()
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

                NavigationLink {
                    SettingsView()
                } label: {
                    Label("设置", systemImage: "gearshape.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.warmBrown)
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
