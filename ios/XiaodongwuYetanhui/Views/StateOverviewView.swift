import SwiftUI

struct StateOverviewView: View {
    @EnvironmentObject private var store: CompanionStore
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
                    SnapshotGrid(
                        snapshot: store.snapshot,
                        openMessages: openMessages,
                        openSessions: openSessions,
                        openMemory: openMemory,
                        openJournals: openJournals
                    )
                    StateProfilePanel(profiles: store.stateProfiles, openSourceSession: openSourceSession)
                    CareMomentPanel(careMoments: store.careMoments)
                    RecommendationHistoryPanel(
                        recommendations: store.recommendationHistory,
                        openChat: openChat
                    )
                    NextInteractionPanel(openChat: openChat)
                    EmotionCheckInView()
                    RecentJournalList(journals: store.journals)
                }
                .padding(18)
            }
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.backendStatus.state == .unknown {
                await store.checkBackendConnection()
            }
        }
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
    let openSourceSession: (String) -> Void

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
                            StateProfileCompactCard(profile: profile, openSourceSession: openSourceSession)
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
    let openSourceSession: (String) -> Void

    var body: some View {
        Button {
            if !profile.sourceSessionID.isEmpty {
                openSourceSession(profile.sourceSessionID)
            }
        } label: {
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
