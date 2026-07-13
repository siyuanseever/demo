import SwiftUI

struct NativeFlowView: View {
    @EnvironmentObject private var store: NativeMacShellStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if let insight = store.flowInsight {
                    goalGrid(insight)
                    contextGrid(insight)
                    sourceCard(insight)
                } else {
                    emptyState
                }
            }
            .padding(28)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(
            LinearGradient(
                colors: [Color.flowGradientTop, Color.flowGradientBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            NativeCharacterAvatar(
                character: CompanionFixtures.characters[0],
                expressionID: store.flowInsight == nil ? "listening" : "gentlesmile",
                size: 62
            )
            VStack(alignment: .leading, spacing: 5) {
                Text("本周心流导航")
                    .font(.largeTitle.bold())
                Text(store.flowInsight?.periodLabel ?? "从近期日记、记忆和长期状态中，找出这一周最值得照看的方向。")
                    .foregroundStyle(.secondary)
                if let notice = store.flowNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(store.isGeneratingFlow ? "生成中…" : "重新生成", systemImage: "arrow.clockwise") {
                Task { await store.refreshWeeklyFlow(force: true) }
            }
            .disabled(store.isGeneratingFlow || !store.hasFlowSources)
        }
    }

    @ViewBuilder
    private func goalGrid(_ insight: StarMapInsight) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 16)], spacing: 16) {
            NativeFlowGoalCard(
                eyebrow: "主要方向",
                title: insight.primaryGoalTitle,
                reason: insight.primaryGoalReason,
                nextStep: insight.primaryGoalNextStep,
                challenge: insight.primaryGoalChallenge,
                tint: .accentPurple
            )
            if insight.hasSecondaryGoal {
                NativeFlowGoalCard(
                    eyebrow: "次要方向",
                    title: insight.secondaryGoalTitle,
                    reason: insight.secondaryGoalReason,
                    nextStep: insight.secondaryGoalNextStep,
                    challenge: insight.secondaryGoalChallenge,
                    tint: .accentGreen
                )
            }
        }
    }

    private func contextGrid(_ insight: StarMapInsight) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
            NativeFlowInfoCard(
                title: "最近的情绪天气",
                systemImage: "cloud.sun.fill",
                detail: insight.recentEmotionSummary,
                tags: insight.recentEmotionTags
            )
            NativeFlowInfoCard(
                title: insight.recentPatternTitle,
                systemImage: "point.3.connected.trianglepath.dotted",
                detail: insight.recentPatternDetail,
                tags: insight.recentPatternItems
            )
            NativeFlowInfoCard(
                title: insight.flowConditionTitle,
                systemImage: "sparkles",
                detail: insight.flowConditionDetail,
                tags: insight.flowConditionItems
            )
            NativeFlowInfoCard(
                title: insight.gentleReminderTitle.isEmpty ? "一个温柔提醒" : insight.gentleReminderTitle,
                systemImage: "moon.stars.fill",
                detail: [insight.gentleReminder, insight.gentleReminderDetail]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n"),
                tags: []
            )
            NativeFlowInfoCard(
                title: "帮助进入心流",
                systemImage: "wind",
                detail: insight.flowSupport,
                tags: insight.memoryCues
            )
            NativeFlowInfoCard(
                title: "这一周看见的核心",
                systemImage: "eye.fill",
                detail: [insight.coreInsight, insight.coreInsightDetail]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n"),
                tags: []
            )
        }
    }

    private func sourceCard(_ insight: StarMapInsight) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "tray.full.fill")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("生成依据")
                    .font(.caption.bold())
                Text(insight.sourceSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("更新于 \(insight.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有本周导航", systemImage: "sparkles")
        } description: {
            Text(store.hasFlowSources
                ? "准备好后可以生成一次；同一自然周会直接读取缓存，不会因为进入页面而重复调用模型。"
                : "至少完成一段夜谈并生成日记或记忆后，这里才会开始整理。")
        } actions: {
            if store.hasFlowSources {
                Button("生成本周导航") {
                    Task { await store.refreshWeeklyFlow(force: true) }
                }
                .disabled(store.isGeneratingFlow)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .background(Color.cardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct NativeFlowGoalCard: View {
    let eyebrow: String
    let title: String
    let reason: String
    let nextStep: String
    let challenge: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(eyebrow)
                    .font(.caption.bold())
                    .foregroundStyle(tint)
                Spacer()
                if !challenge.isEmpty {
                    Text(challenge)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12), in: Capsule())
                }
            }
            Text(title)
                .font(.title3.bold())
            Text(reason)
                .foregroundStyle(.secondary)
            if !nextStep.isEmpty {
                Label(nextStep, systemImage: "arrow.forward.circle.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.cardBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(tint.opacity(0.16))
        }
    }
}

private struct NativeFlowInfoCard: View {
    let title: String
    let systemImage: String
    let detail: String
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            if !detail.isEmpty {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !tags.isEmpty {
                NativeFlowTags(tags: tags)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.cardBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 15))
    }
}

private struct NativeFlowTags: View {
    let tags: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { tagViews }
            VStack(alignment: .leading, spacing: 6) { tagViews }
        }
    }

    @ViewBuilder
    private var tagViews: some View {
        ForEach(tags.prefix(5), id: \.self) { tag in
            Text(tag)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentPurple.opacity(0.1), in: Capsule())
        }
    }
}
