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
                    openGentleReminder: { selectedDetail = .gentleReminder(store.starMapInsight) }
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
            StarMapDetailSheet(detail: detail)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                transparentButton(label: "本月生命力观察", action: openCoreInsight)
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
        }
    }

    var title: String {
        switch self {
        case .coreInsight:
            return "本月生命力观察"
        case .recentPattern(let insight):
            return insight.recentPatternTitle
        case .flowCondition(let insight):
            return insight.flowConditionTitle
        case .gentleReminder(let insight):
            return insight.gentleReminderTitle
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
        }
    }

    var periodLabel: String {
        switch self {
        case .coreInsight(let insight),
             .recentPattern(let insight),
             .flowCondition(let insight),
             .gentleReminder(let insight):
            return insight.periodLabel
        }
    }

    var sourceSummary: String {
        switch self {
        case .coreInsight(let insight),
             .recentPattern(let insight),
             .flowCondition(let insight),
             .gentleReminder(let insight):
            return insight.sourceSummary
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
            StarMapTabButton(title: "森林", systemImage: "tree.fill", isSelected: false, action: openForest)
            StarMapTabButton(title: "星图", systemImage: "sparkles", isSelected: true, action: openStarMap)
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
