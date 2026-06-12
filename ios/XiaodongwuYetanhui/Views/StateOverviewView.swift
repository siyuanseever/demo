import SwiftUI

struct StateOverviewView: View {
    @EnvironmentObject private var store: CompanionStore
    let openChat: () -> Void
    let openSessions: () -> Void

    init(openChat: @escaping () -> Void = {}, openSessions: @escaping () -> Void = {}) {
        self.openChat = openChat
        self.openSessions = openSessions
    }

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(title: "状态花园", subtitle: "把长期对话留下的轨迹，整理成可以回看的状态。")
                    SnapshotGrid(snapshot: store.snapshot, openSessions: openSessions)
                    CareMomentPanel(careMoments: store.careMoments)
                    RecommendationHistoryPanel(
                        recommendations: store.recommendationHistory,
                        openChat: openChat
                    )
                    NextInteractionPanel(openChat: openChat)
                    MoodPanel(journals: store.journals)
                    EmotionCheckInView()
                    RecentJournalList(journals: store.journals)
                }
                .padding(18)
            }
        }
        .navigationTitle("状态")
        .navigationBarTitleDisplayMode(.inline)
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
    let openSessions: () -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            Button(action: openSessions) {
                StatTile(title: "会话", value: snapshot.sessionCount, icon: "moon.stars.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看会话")
            StatTile(title: "消息", value: snapshot.messageCount, icon: "text.bubble.fill")
            StatTile(title: "记忆", value: snapshot.memoryCount, icon: "leaf.fill")
            StatTile(title: "总结", value: snapshot.journalCount, icon: "book.closed.fill")
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
