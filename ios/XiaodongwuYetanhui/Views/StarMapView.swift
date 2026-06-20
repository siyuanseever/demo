import SwiftUI

struct StarMapView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var selectedDetail: StarMapDetailArea?

    let openHome: () -> Void
    let openForest: () -> Void
    let openMe: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let fullHeight = geometry.size.height + safeTop + safeBottom
            let backgroundOffset = -(safeTop - safeBottom) / 2

            ZStack {
                StarMapBundleImage(name: "starmap_background_cloud")
                    .frame(width: geometry.size.width, height: fullHeight)
                    .offset(y: backgroundOffset)
                    .clipped()
                    .ignoresSafeArea(.all)

                StarMapTextOverlay(insight: store.starMapInsight)
                    .frame(width: geometry.size.width, height: fullHeight)
                    .offset(y: backgroundOffset)

                StarMapHitOverlay(
                    insight: store.starMapInsight,
                    openCoreInsight: { selectedDetail = .coreInsight(store.starMapInsight) },
                    openRecentPattern: { selectedDetail = .recentPattern(store.starMapInsight) },
                    openFlowCondition: { selectedDetail = .flowCondition(store.starMapInsight) },
                    openGentleReminder: { selectedDetail = .gentleReminder(store.starMapInsight) },
                    openFlowRitual: { selectedDetail = .flowRitual(store.starMapInsight) }
                )
                    .frame(width: geometry.size.width, height: fullHeight)
                    .offset(y: backgroundOffset)

                StarMapBottomBar(
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
            .ignoresSafeArea(.all)
        }
        .task {
            await store.refreshStarMapInsight()
        }
        .sheet(item: $selectedDetail) { detail in
            switch detail {
            case .flowRitual(let insight):
                FlowRitualSheet(insight: insight)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            default:
                StarMapDetailSheet(detail: detail)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

private struct StarMapBundleImage: View {
    let name: String

    var body: some View {
        Group {
            if let image = UIImage(named: name) ?? UIImage(named: "\(name).png") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(hex: 0xf4efe8)
            }
        }
    }
}

private struct StarMapTextOverlay: View {
    let insight: StarMapInsight

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                Text(insight.coreInsight)
                    .font(.custom("HannotateSC-W5", size: 22))
                    .lineSpacing(8)
                    .foregroundStyle(Color(hex: 0x5d536f))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.82)
                    .frame(width: width * 0.72, height: height * 0.18)
                    .position(x: width * 0.5, y: height * 0.335)

                Text(patternText)
                    .font(.custom("HannotateSC-W5", size: 17))
                    .lineSpacing(8)
                    .foregroundStyle(Color(hex: 0x5f5369))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.78)
                    .frame(width: width * 0.2, height: height * 0.15)
                    .position(x: width * 0.17, y: height * 0.64)

                Text(flowText)
                    .font(.custom("HannotateSC-W5", size: 15))
                    .lineSpacing(7)
                    .foregroundStyle(Color(hex: 0x5f5369))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.74)
                    .frame(width: width * 0.24, height: height * 0.16)
                    .position(x: width * 0.5, y: height * 0.64)

                Text(insight.gentleReminder)
                    .font(.custom("HannotateSC-W5", size: 16))
                    .lineSpacing(7)
                    .foregroundStyle(Color(hex: 0x6a5c59))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.76)
                    .frame(width: width * 0.23, height: height * 0.16)
                    .position(x: width * 0.83, y: height * 0.64)
            }
        }
        .allowsHitTesting(false)
    }

    private var patternText: String {
        insight.recentPattern.joined(separator: "\n↓\n")
    }

    private var flowText: String {
        insight.flowConditions.joined(separator: "\n")
    }
}

private struct StarMapHitOverlay: View {
    let insight: StarMapInsight
    let openCoreInsight: () -> Void
    let openRecentPattern: () -> Void
    let openFlowCondition: () -> Void
    let openGentleReminder: () -> Void
    let openFlowRitual: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                transparentButton(label: "本月心流观察", action: openCoreInsight)
                    .frame(width: width * 0.76, height: height * 0.22)
                    .position(x: width * 0.5, y: height * 0.34)

                transparentButton(label: insight.recentPatternTitle, action: openRecentPattern)
                    .frame(width: width * 0.26, height: height * 0.28)
                    .position(x: width * 0.17, y: height * 0.66)

                transparentButton(label: insight.flowConditionTitle, action: openFlowCondition)
                    .frame(width: width * 0.28, height: height * 0.28)
                    .position(x: width * 0.5, y: height * 0.66)

                transparentButton(label: insight.gentleReminderTitle, action: openGentleReminder)
                    .frame(width: width * 0.26, height: height * 0.28)
                    .position(x: width * 0.83, y: height * 0.66)

                transparentButton(label: "进入此刻的心流", action: openFlowRitual)
                    .frame(width: width * 0.56, height: height * 0.12)
                    .position(x: width * 0.52, y: height * 0.86)
            }
        }
    }

    private func transparentButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Rectangle()
                .fill(Color.black.opacity(0.001))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .accessibilityHint("查看这个月度观察的详细说明")
    }
}

private enum StarMapDetailArea: Identifiable {
    case coreInsight(StarMapInsight)
    case recentPattern(StarMapInsight)
    case flowCondition(StarMapInsight)
    case gentleReminder(StarMapInsight)
    case flowRitual(StarMapInsight)

    var id: String {
        switch self {
        case .coreInsight(let insight):
            return "\(insight.id)-core"
        case .recentPattern(let insight):
            return "\(insight.id)-pattern"
        case .flowCondition(let insight):
            return "\(insight.id)-flow"
        case .gentleReminder(let insight):
            return "\(insight.id)-reminder"
        case .flowRitual(let insight):
            return "\(insight.id)-ritual"
        }
    }

    var title: String {
        switch self {
        case .coreInsight:
            return "本月心流观察"
        case .recentPattern(let insight):
            return insight.recentPatternTitle
        case .flowCondition(let insight):
            return insight.flowConditionTitle
        case .gentleReminder(let insight):
            return insight.gentleReminderTitle
        case .flowRitual:
            return "进入此刻"
        }
    }

    var summary: String {
        switch self {
        case .coreInsight(let insight):
            return insight.coreInsight
        case .recentPattern(let insight):
            return insight.recentPattern.joined(separator: " · ")
        case .flowCondition(let insight):
            return insight.flowConditions.joined(separator: " · ")
        case .gentleReminder(let insight):
            return insight.gentleReminder
        case .flowRitual:
            return "先只和一件事待在一起。"
        }
    }

    var detail: String {
        switch self {
        case .coreInsight(let insight):
            return insight.coreInsightDetail
        case .recentPattern(let insight):
            return insight.recentPatternDetail
        case .flowCondition(let insight):
            return insight.flowConditionDetail
        case .gentleReminder(let insight):
            return insight.gentleReminderDetail
        case .flowRitual:
            return "不计时，也不要求完成。"
        }
    }

    var periodLabel: String {
        switch self {
        case .coreInsight(let insight),
             .recentPattern(let insight),
             .flowCondition(let insight),
             .gentleReminder(let insight),
             .flowRitual(let insight):
            return insight.periodLabel
        }
    }

    var sourceSummary: String {
        switch self {
        case .coreInsight(let insight),
             .recentPattern(let insight),
             .flowCondition(let insight),
             .gentleReminder(let insight),
             .flowRitual(let insight):
            return insight.sourceSummary
        }
    }
}

private struct FlowRitualSheet: View {
    let insight: StarMapInsight

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var activeIntention: String?
    @FocusState private var isDraftFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: 0xeee9f3)
                    .ignoresSafeArea()

                if let activeIntention {
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
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("现在想把注意力放在哪里？")
                        .font(.custom("HannotateSC-W5", size: 25))
                        .foregroundStyle(Color(hex: 0x4f455d))
                    Text("不用完成，也不用证明效率。先只和一件事待在一起。")
                        .font(.custom("HannotateSC-W5", size: 16))
                        .lineSpacing(6)
                        .foregroundStyle(Color(hex: 0x71677b))
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("写下一件此刻愿意靠近的事", text: $draft, axis: .vertical)
                    .font(.custom("HannotateSC-W5", size: 18))
                    .lineLimit(2...4)
                    .focused($isDraftFocused)
                    .padding(16)
                    .background(Color(hex: 0xf8f2e9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("也可以从最近会亮起来的事开始")
                            .font(.custom("HannotateSC-W5", size: 14))
                            .foregroundStyle(Color(hex: 0x81758d))

                        FlowSuggestionLayout(items: suggestions) { suggestion in
                            draft = suggestion
                            isDraftFocused = false
                        }
                    }
                }

                Button {
                    begin()
                } label: {
                    Text("先只做这一件事")
                        .font(.custom("HannotateSC-W5", size: 17))
                        .foregroundStyle(Color(hex: 0x4f455d))
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
                .foregroundStyle(Color(hex: 0x4f455d))
                .padding(.horizontal, 28)

            Text("不需要马上完成。\n注意力回来时，就再靠近一点点。")
                .font(.custom("HannotateSC-W5", size: 16))
                .lineSpacing(7)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(hex: 0x756b7e))

            Spacer()

            Button("先停在这里") {
                dismiss()
            }
            .font(.custom("HannotateSC-W5", size: 16))
            .foregroundStyle(Color(hex: 0x5f5369))
            .buttonStyle(.plain)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity)
    }

    private var suggestions: [String] {
        var result: [String] = []
        for item in insight.recentPattern + insight.flowConditions {
            let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty, !result.contains(cleaned) {
                result.append(cleaned)
            }
            if result.count == 5 {
                break
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
        withAnimation(.easeInOut(duration: 0.28)) {
            activeIntention = cleanDraft
        }
    }
}

private struct FlowSuggestionLayout: View {
    let items: [String]
    let select: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                Button(item) {
                    select(item)
                }
                .font(.custom("HannotateSC-W5", size: 14))
                .foregroundStyle(Color(hex: 0x665a73))
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.58), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }
}

private struct StarMapDetailSheet: View {
    let detail: StarMapDetailArea
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(detail.title)
                            .font(.custom("HannotateSC-W5", size: 24))
                            .foregroundStyle(Color(hex: 0x5d536f))
                        Text(detail.periodLabel)
                            .font(.custom("HannotateSC-W5", size: 13))
                            .foregroundStyle(Color(hex: 0x8b7b78))
                    }

                    Text(detail.summary)
                        .font(.custom("HannotateSC-W5", size: 18))
                        .lineSpacing(7)
                        .foregroundStyle(Color(hex: 0x4f455d))
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Text(detail.detail)
                        .font(.custom("HannotateSC-W5", size: 16))
                        .lineSpacing(8)
                        .foregroundStyle(Color(hex: 0x5e544f))
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xf8f1e7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Label(detail.sourceSummary, systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(Color(hex: 0x8b7b78))
                        .padding(.horizontal, 4)
                }
                .padding(20)
            }
            .background(Color(hex: 0xf5ede4).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("知道了") {
                        dismiss()
                    }
                    .font(.custom("HannotateSC-W5", size: 16))
                    .foregroundStyle(Color(hex: 0x8a6ea8))
                }
            }
        }
    }
}

private struct StarMapBottomBar: View {
    let openHome: () -> Void
    let openForest: () -> Void
    let openStarMap: () -> Void
    let openMe: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            StarMapTabButton(title: "疗愈", systemImage: "house.fill", isSelected: false, action: openHome)
            StarMapTabButton(title: "摆烂", systemImage: "sofa.fill", isSelected: false, action: openForest)
            StarMapTabButton(title: "心流", systemImage: "sparkles", isSelected: true, action: openStarMap)
            StarMapRabbitTabButton(action: openMe)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(hex: 0xf2e6d0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xd8c8b2).opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color.warmBrown.opacity(0.1), radius: 14, x: 0, y: 6)
    }
}

private struct StarMapTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 31, height: 24)
                    .background(isSelected ? Color(hex: 0xd7c4f2).opacity(0.5) : Color.clear, in: Capsule())
                Text(title)
                    .font(.custom("HannotateSC-W5", size: 10))
            }
            .foregroundStyle(isSelected ? Color(hex: 0x8a6ea8) : Color.warmBrown.opacity(0.72))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct StarMapRabbitTabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                StarMapBundleImage(name: "sensen-rabbit-flat-icon-v1")
                    .frame(width: 31, height: 31)
                    .clipShape(Circle())
                Text("我的")
                    .font(.custom("HannotateSC-W5", size: 10))
            }
            .foregroundStyle(Color.warmBrown.opacity(0.72))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
