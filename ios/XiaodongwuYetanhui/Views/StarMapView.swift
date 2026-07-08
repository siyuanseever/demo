import SwiftUI

struct StarMapView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var selectedDestination: FlowDestination?

    let openHome: () -> Void
    let openForest: () -> Void
    let openMe: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.accentPurpleLight
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        FlowPageHeader(
                            insight: store.starMapInsight,
                            notice: store.flowInsightNotice,
                            isRefreshing: store.isFlowInsightRefreshing
                        ) {
                            Task {
                                await store.refreshStarMapInsight(forceRefresh: true)
                            }
                        }

                        FlowGoalCard(
                            title: store.starMapInsight.primaryGoalTitle,
                            reason: store.starMapInsight.primaryGoalReason,
                            nextStep: store.starMapInsight.primaryGoalNextStep,
                            challenge: store.starMapInsight.primaryGoalChallenge,
                            role: "主要目标",
                            tint: Color.decorativeLavender
                        ) {
                            if store.starMapInsight.isMockInsight {
                                Task {
                                    await store.refreshStarMapInsight(forceRefresh: true)
                                }
                            } else {
                                selectedDestination = .ritual(
                                    store.starMapInsight,
                                    store.starMapInsight.primaryGoalNextStep
                                )
                            }
                        }

                        if store.starMapInsight.hasSecondaryGoal {
                            FlowGoalCard(
                                title: store.starMapInsight.secondaryGoalTitle,
                                reason: store.starMapInsight.secondaryGoalReason,
                                nextStep: store.starMapInsight.secondaryGoalNextStep,
                                challenge: store.starMapInsight.secondaryGoalChallenge,
                                role: "次要目标",
                                tint: Color.decorativeMint
                            ) {
                                if store.starMapInsight.isMockInsight {
                                    Task {
                                        await store.refreshStarMapInsight(forceRefresh: true)
                                    }
                                } else {
                                    selectedDestination = .ritual(
                                        store.starMapInsight,
                                        store.starMapInsight.secondaryGoalNextStep
                                    )
                                }
                            }
                        }

                        FlowEmotionCard(insight: store.starMapInsight)
                        FlowSupportCard(insight: store.starMapInsight)
                        FlowMemoryCard(cues: store.starMapInsight.memoryCues)
                        FlowMonthlyThreadCard(insight: store.starMapInsight)
                        FlowReminderCard(insight: store.starMapInsight)

                        Button {
                            selectedDestination = .ritual(store.starMapInsight, "")
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 19, weight: .semibold))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("进入此刻的心流")
                                        .font(.custom("HannotateSC-W5", size: 18))
                                    Text("带上一个合适的小目标，只和它待一会儿")
                                        .font(.custom("HannotateSC-W5", size: 13))
                                        .opacity(0.72)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundStyle(Color.textPrimary)
                            .padding(18)
                            .background(
                                LinearGradient(
                                    colors: [Color.flowHeaderGradientTop, Color.flowHeaderGradientBottom],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(store.starMapInsight.isMockInsight)
                        .opacity(store.starMapInsight.isMockInsight ? 0.55 : 1)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, max(52, geometry.safeAreaInsets.top + 12))
                    .padding(.bottom, 118)
                }
                .scrollIndicators(.hidden)

                ImmersiveBottomBar(
                    selectedTab: .starMap,
                    openHome: openHome,
                    openForest: openForest,
                    openStarMap: {},
                    openMe: openMe
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 26)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
            }
        }
        .task {
            await store.refreshStarMapInsight()
        }
        .sheet(item: $selectedDestination) { destination in
            switch destination {
            case .ritual(let insight, let intention):
                FlowRitualSheet(insight: insight, initialIntention: intention)
                    .environmentObject(store)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private enum FlowDestination: Identifiable {
    case ritual(StarMapInsight, String)

    var id: String {
        switch self {
        case .ritual(let insight, let intention):
            return "\(insight.id)-\(intention)"
        }
    }
}

private struct FlowPageHeader: View {
    let insight: StarMapInsight
    let notice: String
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("心流导航")
                        .font(.custom("HannotateSC-W5", size: 31))
                        .foregroundStyle(Color.textPrimary)
                    Text("把记忆变成此刻可以靠近的方向")
                        .font(.custom("HannotateSC-W5", size: 14))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button(action: refresh) {
                    Image(systemName: isRefreshing ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(Color.overlayLight, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isRefreshing)
                .accessibilityLabel("重新生成心流导航")
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(insight.isMockInsight ? Color.orange.opacity(0.72) : Color.accentGreen)
                    .frame(width: 7, height: 7)
                Text(isRefreshing ? "正在提炼..." : notice)
                    .font(.custom("HannotateSC-W5", size: 12))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(insight.periodLabel)
                    .font(.custom("HannotateSC-W5", size: 11))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.overlaySubtle, in: Capsule())
        }
    }
}

private struct FlowGoalCard: View {
    let title: String
    let reason: String
    let nextStep: String
    let challenge: String
    let role: String
    let tint: Color
    let begin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(role)
                    .font(.custom("HannotateSC-W5", size: 13))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.overlayMedium, in: Capsule())
                Spacer()
                FlowChallengeBadge(level: challenge)
            }

            Text(title)
                .font(.custom("HannotateSC-W5", size: 22))
                .lineSpacing(6)
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(reason)
                .font(.custom("HannotateSC-W5", size: 15))
                .lineSpacing(6)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: begin) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("可以从这里开始")
                            .font(.custom("HannotateSC-W5", size: 12))
                            .opacity(0.7)
                        Text(nextStep)
                            .font(.custom("HannotateSC-W5", size: 15))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 2)
                }
                .foregroundStyle(Color.textPrimary)
                .padding(13)
                .background(Color.overlayMedium, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(tint.opacity(0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.overlaySubtle, lineWidth: 1)
        }
        .shadow(color: Color(hex: 0x5b4968).opacity(0.08), radius: 18, x: 0, y: 8)
    }
}

private struct FlowChallengeBadge: View {
    let level: String

    private var activeDots: Int {
        switch level {
        case "稍有挑战": return 3
        case "适中": return 2
        default: return 1
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...3, id: \.self) { index in
                Circle()
                    .fill(index <= activeDots ? Color(hex: 0x756488) : Color.overlayLight)
                    .frame(width: 6, height: 6)
            }
            Text(level.isEmpty ? "轻量" : level)
                .font(.custom("HannotateSC-W5", size: 11))
                .foregroundStyle(Color.textSecondary)
        }
    }
}

private struct FlowEmotionCard: View {
    let insight: StarMapInsight

    var body: some View {
        FlowSectionCard(icon: "cloud.sun.fill", title: "近期情绪天气", tint: Color(hex: 0xf1d9c6)) {
            FlowTagRow(items: insight.recentEmotionTags)
            Text(insight.recentEmotionSummary)
                .flowBodyStyle()
        }
    }
}

private struct FlowSupportCard: View {
    let insight: StarMapInsight

    var body: some View {
        FlowSectionCard(icon: "scope", title: "怎样更容易进入", tint: Color(hex: 0xcfe1dc)) {
            Text(insight.flowSupport)
                .flowBodyStyle()
            FlowTagRow(items: insight.flowConditions)
        }
    }
}

private struct FlowMemoryCard: View {
    let cues: [String]

    var body: some View {
        FlowSectionCard(icon: "bookmark.fill", title: "记忆在提醒你", tint: Color(hex: 0xe5d4bb)) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(cues.prefix(4).enumerated()), id: \.offset) { index, cue in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.custom("HannotateSC-W5", size: 12))
                            .foregroundStyle(Color(hex: 0x76654f))
                            .frame(width: 24, height: 24)
                            .background(Color.overlayMedium, in: Circle())
                        Text(cue)
                            .font(.custom("HannotateSC-W5", size: 15))
                            .lineSpacing(6)
                            .foregroundStyle(Color(hex: 0x5d544c))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct FlowMonthlyThreadCard: View {
    let insight: StarMapInsight

    var body: some View {
        FlowSectionCard(icon: "sparkles", title: "这段时间的心流主线", tint: Color(hex: 0xd8cdea)) {
            Text(insight.coreInsight)
                .font(.custom("HannotateSC-W5", size: 19))
                .lineSpacing(7)
                .foregroundStyle(Color(hex: 0x50465b))
                .fixedSize(horizontal: false, vertical: true)
            Text(insight.coreInsightDetail)
                .flowBodyStyle()
            FlowTagRow(items: insight.recentPattern)
            Label(insight.sourceSummary, systemImage: "tray.full.fill")
                .font(.custom("HannotateSC-W5", size: 11))
                .lineSpacing(4)
                .foregroundStyle(Color(hex: 0x81758d))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FlowReminderCard: View {
    let insight: StarMapInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Color(hex: 0x8d6e63))
            VStack(alignment: .leading, spacing: 6) {
                Text(insight.gentleReminderTitle)
                    .font(.custom("HannotateSC-W5", size: 14))
                    .foregroundStyle(Color(hex: 0x77615b))
                Text(insight.gentleReminder)
                    .font(.custom("HannotateSC-W5", size: 17))
                    .lineSpacing(6)
                    .foregroundStyle(Color(hex: 0x5e514d))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xf0ddd4).opacity(0.82), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
    }
}

private struct FlowSectionCard<Content: View>: View {
    let icon: String
    let title: String
    let tint: Color
    @ViewBuilder let content: Content

    init(
        icon: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: icon)
                .font(.custom("HannotateSC-W5", size: 17))
                .foregroundStyle(Color(hex: 0x584c62))
            content
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.76), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.overlaySubtle, lineWidth: 1)
        }
    }
}

private struct FlowTagRow: View {
    let items: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 7)], alignment: .leading, spacing: 7) {
            ForEach(items.filter { !$0.isEmpty }.prefix(5), id: \.self) { item in
                Text(item)
                    .font(.custom("HannotateSC-W5", size: 12))
                    .foregroundStyle(Color(hex: 0x655b6c))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.overlayLight, in: Capsule())
            }
        }
    }
}

private extension Text {
    func flowBodyStyle() -> some View {
        font(.custom("HannotateSC-W5", size: 15))
            .lineSpacing(6)
            .foregroundStyle(Color(hex: 0x655c69))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FlowRitualSheet: View {
    let insight: StarMapInsight
    let initialIntention: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CompanionStore
    @State private var draft: String
    @State private var activeIntention: String?
    @State private var isClosing = false
    @FocusState private var isDraftFocused: Bool

    init(insight: StarMapInsight, initialIntention: String) {
        self.insight = insight
        self.initialIntention = initialIntention
        _draft = State(initialValue: initialIntention)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: 0xeee9f3).ignoresSafeArea()
                if let activeIntention, isClosing {
                    closingView(intention: activeIntention)
                } else if let activeIntention {
                    activeView(intention: activeIntention)
                } else {
                    preparationView
                }
            }
            .navigationTitle("进入此刻")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("先离开") {
                        dismiss()
                    }
                    .font(.custom("HannotateSC-W5", size: 15))
                    .foregroundStyle(Color(hex: 0x756887))
                }
            }
        }
    }

    private var preparationView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("这一轮，只靠近一件事")
                        .font(.custom("HannotateSC-W5", size: 25))
                        .foregroundStyle(Color.textPrimary)
                    Text("目标已经尽量缩小。你仍然可以改成此刻更合适的表达。")
                        .font(.custom("HannotateSC-W5", size: 15))
                        .lineSpacing(6)
                        .foregroundStyle(Color(hex: 0x71677b))
                }

                TextField("写下一件此刻愿意靠近的事", text: $draft, axis: .vertical)
                    .font(.custom("HannotateSC-W5", size: 18))
                    .lineLimit(2...4)
                    .focused($isDraftFocused)
                    .padding(16)
                    .background(Color(hex: 0xf8f2e9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("为什么这个难度可能合适")
                        .font(.custom("HannotateSC-W5", size: 13))
                        .foregroundStyle(Color(hex: 0x81758d))
                    HStack(spacing: 9) {
                        FlowChallengeBadge(level: insight.primaryGoalChallenge)
                        Text(insight.flowSupport)
                            .font(.custom("HannotateSC-W5", size: 13))
                            .lineSpacing(5)
                            .foregroundStyle(Color(hex: 0x71677b))
                    }
                }
                .padding(14)
                .background(Color.overlaySubtle, in: RoundedRectangle(cornerRadius: 17, style: .continuous))

                FlowSuggestionLayout(items: suggestions) { suggestion in
                    draft = suggestion
                    isDraftFocused = false
                }

                Button {
                    begin()
                } label: {
                    Text("先只做这一件事")
                        .font(.custom("HannotateSC-W5", size: 17))
                        .foregroundStyle(Color.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(hex: 0xd9cdea), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(cleanDraft.isEmpty)
                .opacity(cleanDraft.isEmpty ? 0.42 : 1)

                Text("这里不会计时，不会打卡，也不会评价你做了多少。")
                    .font(.custom("HannotateSC-W5", size: 13))
                    .foregroundStyle(Color(hex: 0x8b8194))
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
                .foregroundStyle(Color(hex: 0x8a78a5))
            Text(intention)
                .font(.custom("HannotateSC-W5", size: 27))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 28)
            Text("不需要马上完成。\n注意力回来时，就再靠近一点点。")
                .font(.custom("HannotateSC-W5", size: 16))
                .lineSpacing(7)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x756b7e))
            Spacer()
            Button("先停在这里") {
                withAnimation(.easeInOut(duration: 0.24)) {
                    isClosing = true
                }
            }
            .font(.custom("HannotateSC-W5", size: 16))
            .foregroundStyle(Color(hex: 0x5f5369))
            .buttonStyle(.plain)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
    }

    private func closingView(intention: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("先停在这里")
                .font(.custom("HannotateSC-W5", size: 28))
                .foregroundStyle(Color.textPrimary)
            Text(intention)
                .font(.custom("HannotateSC-W5", size: 19))
                .lineSpacing(7)
                .foregroundStyle(Color(hex: 0x665a73))
                .fixedSize(horizontal: false, vertical: true)
            Text("不总结成果。只留下此刻最接近的一句话。")
                .font(.custom("HannotateSC-W5", size: 15))
                .foregroundStyle(Color(hex: 0x81758d))
            VStack(spacing: 11) {
                ForEach(["更清楚一点", "还在里面", "今天先到这里"], id: \.self) { ending in
                    Button {
                        store.recordFlowMoment(intention: intention, ending: ending)
                        dismiss()
                    } label: {
                        Text(ending)
                            .font(.custom("HannotateSC-W5", size: 17))
                            .foregroundStyle(Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .background(Color(hex: 0xf8f2e9), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("不留痕迹，直接离开") {
                dismiss()
            }
            .font(.custom("HannotateSC-W5", size: 14))
            .foregroundStyle(Color(hex: 0x8b8194))
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer()
        }
        .padding(28)
    }

    private var suggestions: [String] {
        let candidates = [
            insight.primaryGoalNextStep,
            insight.secondaryGoalNextStep,
        ] + insight.flowConditions
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

private struct FlowSuggestionLayout: View {
    let items: [String]
    let select: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                Button(item) {
                    select(item)
                }
                .font(.custom("HannotateSC-W5", size: 13))
                .foregroundStyle(Color(hex: 0x665a73))
                .buttonStyle(.plain)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Color.overlayMedium, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }
}
