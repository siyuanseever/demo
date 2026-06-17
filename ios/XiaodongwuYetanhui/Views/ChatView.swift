import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var draft = ""
    @State private var isNotebookVisible = false
    @State private var isCompanionChatVisible = false
    @State private var isSideSettingsVisible = false
    @State private var isStateOverviewVisible = false
    @State private var notebookSpace: NotebookSpace = .chat
    @State private var isComposerVisible = false
    @State private var sceneNotice: String?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            SensenHomePage(
                openChat: { isCompanionChatVisible = true },
                openForest: { openNotebook(.state) },
                openNotebook: { openNotebook(.memory) },
                openMe: { isStateOverviewVisible = true }
            )
            .environmentObject(store)
            .ignoresSafeArea(.all)

            if isSideSettingsVisible {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.snappy) {
                            isSideSettingsVisible = false
                        }
                    }

                SideSettingsDrawer {
                    withAnimation(.snappy) {
                        isSideSettingsVisible = false
                    }
                }
                .environmentObject(store)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: isSideSettingsVisible)
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .sheet(isPresented: $isNotebookVisible) {
            ForestNotebookContent(
                selectedSpace: $notebookSpace,
                continueSession: continueHistoricalSession
            )
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $isStateOverviewVisible) {
            NavigationStack {
                StateOverviewView(
                    openChat: { isStateOverviewVisible = false; isCompanionChatVisible = true },
                    openMessages: { isStateOverviewVisible = false; openNotebook(.messages) },
                    openSessions: { isStateOverviewVisible = false; openNotebook(.sessions) },
                    openMemory: { isStateOverviewVisible = false; openNotebook(.memory) },
                    openJournals: { isStateOverviewVisible = false; openNotebook(.journals) },
                    openSourceSession: { sessionID in
                        isStateOverviewVisible = false
                        continueHistoricalSession(sessionID)
                    }
                )
                .environmentObject(store)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") {
                            isStateOverviewVisible = false
                        }
                    }
                }
            }
            .preferredColorScheme(.light)
        }
        .fullScreenCover(isPresented: $isCompanionChatVisible) {
            CompanionChatPage()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
        .onChange(of: store.isChatCheckInVisible) {
            if store.isChatCheckInVisible { openNotebook(.chat) }
        }
        .onChange(of: store.isMonsterCareGameVisible) {
            if store.isMonsterCareGameVisible { openNotebook(.chat) }
        }
        .onChange(of: store.isRecommendationVisible) {
            if store.isRecommendationVisible { openNotebook(.chat) }
        }
    }

    private func revealComposer() {
        withAnimation(.snappy) {
            isComposerVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isComposerFocused = true
        }
    }

    private func openNotebook(_ space: NotebookSpace) {
        isComposerFocused = false
        notebookSpace = space
        isNotebookVisible = true
    }

    private func continueHistoricalSession(_ sessionID: String) {
        store.openSession(sessionID)
        isNotebookVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            isCompanionChatVisible = true
        }
    }
}

private struct SideSettingsDrawer: View {
    let close: () -> Void

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Text("设置")
                        .font(SensenFonts.handwritten(size: 22))
                        .foregroundStyle(Color.warmBrown)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.warmBrown)
                            .frame(width: 34, height: 34)
                            .background(Color(hex: 0xffeee9), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭设置")
                }
                .padding(.horizontal, 18)
                .padding(.top, max(18, geometry.safeAreaInsets.top + 8))
                .padding(.bottom, 8)

                SettingsView()
            }
            .frame(width: min(360, geometry.size.width * 0.86), height: geometry.size.height)
            .background(Color(hex: 0xfffbf3))
            .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
            .shadow(color: Color.warmBrown.opacity(0.16), radius: 28, x: 10, y: 0)
            .ignoresSafeArea(.container, edges: .vertical)
        }
    }
}

private struct SensenHomePage: View {
    @EnvironmentObject private var store: CompanionStore

    let openChat: () -> Void
    let openForest: () -> Void
    let openNotebook: () -> Void
    let openMe: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let fullHeight = geometry.size.height + safeTop + safeBottom
            let backgroundOffset = -(safeTop - safeBottom) / 2
            let bottomGap: CGFloat = 26
            let interItemGap: CGFloat = 24
            let horizontalInset: CGFloat = 24

            ZStack {
                BundleImage(
                    name: "sensen-home-cloud-observatory-full",
                    contentMode: .fill,
                    fallbackSystemImage: "cloud.fill"
                )
                .frame(width: geometry.size.width, height: fullHeight)
                .offset(y: backgroundOffset)
                .clipped()
                .ignoresSafeArea(.all)

                VStack(spacing: 0) {
                    Spacer()

                    CloudConversationEntry(
                        text: store.homeEncouragement,
                        openChat: openChat
                    )
                    .padding(.horizontal, horizontalInset)
                    .padding(.bottom, interItemGap)

                    ImmersiveBottomBar(
                        openHome: {},
                        openForest: openForest,
                        openStarMap: openNotebook,
                        openMe: openMe
                    )
                    .padding(.horizontal, horizontalInset)
                    .padding(.bottom, bottomGap)
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
            .ignoresSafeArea(.all)
        }
        .ignoresSafeArea(.all)
        .task {
            await store.refreshHomeEncouragement()
        }
    }
}

private struct CloudConversationEntry: View {
    let text: String
    let openChat: () -> Void

    var body: some View {
        Button(action: openChat) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: 0xf2e6d0))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color(hex: 0xd8c8b2).opacity(0.72), lineWidth: 1)
                    }

                HStack(spacing: 12) {
                    Text(text.isEmpty ? "给自己留一个没有答案的问题。" : text)
                        .font(SensenFonts.handwritten(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(Color.warmBrown.opacity(0.88))
                        .lineLimit(2)
                        .minimumScaleFactor(0.86)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("...")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.warmBrown.opacity(0.52))
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
            }
            .frame(height: 64)
            .shadow(color: Color.warmBrown.opacity(0.08), radius: 8, x: 0, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("进入和忧忧兔的对话")
    }
}

private struct ImmersiveBottomBar: View {
    let openHome: () -> Void
    let openForest: () -> Void
    let openStarMap: () -> Void
    let openMe: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ImmersiveTabButton(title: "首页", systemImage: "house.fill", isSelected: true, action: openHome)
            ImmersiveTabButton(title: "森林", systemImage: "tree.fill", isSelected: false, action: openForest)
            ImmersiveTabButton(title: "星图", systemImage: "sparkles", isSelected: false, action: openStarMap)
            ImmersiveRabbitTabButton(action: openMe)
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

private struct ImmersiveTabButton: View {
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
                    .font(SensenFonts.handwritten(size: 10))
            }
            .foregroundStyle(isSelected ? Color(hex: 0x8a6ea8) : Color.warmBrown.opacity(0.72))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct ImmersiveRabbitTabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                BundleImage(
                    name: "sensen-rabbit-flat-icon-v1",
                    contentMode: .fill,
                    fallbackSystemImage: "hare.fill"
                )
                .frame(width: 31, height: 31)
                .clipShape(Circle())
                Text("我的")
                    .font(SensenFonts.handwritten(size: 10))
            }
            .foregroundStyle(Color.warmBrown.opacity(0.72))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeScene: Identifiable {
    let id: String
    let assetName: String
    let displayName: String
    let keywords: [String]
    let timeBuckets: Set<HomeSceneTime>
}

private enum HomeSceneTime {
    case morning
    case daytime
    case evening
    case night
}

private enum HomeSceneSelector {
    static let allScenes: [HomeScene] = [
        HomeScene(
            id: "campfire_companion",
            assetName: "sensen-scene-campfire-companion",
            displayName: "篝火边的小小营地",
            keywords: ["陪伴", "孤独", "失落", "被拒绝", "自责", "想放弃", "撑不住", "难过"],
            timeBuckets: [.evening, .night]
        ),
        HomeScene(
            id: "moonlight_tea",
            assetName: "sensen-scene-moonlight-tea",
            displayName: "月光下的晚安茶",
            keywords: ["安静", "焦虑", "睡前", "脑子停不下来", "反复思考", "失眠", "不安"],
            timeBuckets: [.night]
        ),
        HomeScene(
            id: "rainy_mushroom_house",
            assetName: "sensen-scene-rainy-mushroom-house",
            displayName: "雨天的蘑菇小屋",
            keywords: ["躲雨", "情绪低落", "想哭", "脆弱", "敏感", "委屈", "害怕"],
            timeBuckets: [.daytime, .evening, .night]
        ),
        HomeScene(
            id: "starlight_post_office",
            assetName: "sensen-scene-starlight-post-office",
            displayName: "星星邮局",
            keywords: ["表达", "委屈", "遗憾", "想念", "无法开口", "关系", "告别"],
            timeBuckets: [.evening, .night]
        ),
        HomeScene(
            id: "forest_bench",
            assetName: "sensen-scene-forest-bench",
            displayName: "森林长椅",
            keywords: ["发呆", "精神疲惫", "过载", "什么都不想做", "累", "耗尽", "低动力"],
            timeBuckets: [.daytime, .evening]
        ),
        HomeScene(
            id: "river_afternoon",
            assetName: "sensen-scene-river-afternoon",
            displayName: "河边的下午",
            keywords: ["放松", "工作太累", "连续加班", "压力大", "休息", "身体", "恢复"],
            timeBuckets: [.daytime]
        ),
        HomeScene(
            id: "flower_garden_gathering",
            assetName: "sensen-scene-flower-garden-gathering",
            displayName: "春日花园茶会",
            keywords: ["社交连接", "孤单", "需要温暖", "人际挫折", "朋友", "连接"],
            timeBuckets: [.morning, .daytime]
        ),
        HomeScene(
            id: "rainbow_hill",
            assetName: "sensen-scene-rainbow-hill",
            displayName: "彩虹山坡",
            keywords: ["希望", "失败", "面试被拒", "计划落空", "重新开始", "挫折"],
            timeBuckets: [.morning, .daytime, .evening]
        ),
        HomeScene(
            id: "snow_cabin",
            assetName: "sensen-scene-snow-cabin",
            displayName: "雪夜壁炉屋",
            keywords: ["安全感", "冬天", "失眠", "惊恐", "不安", "害怕", "安全"],
            timeBuckets: [.night]
        ),
        HomeScene(
            id: "morning_breakfast_shop",
            assetName: "sensen-scene-morning-breakfast-shop",
            displayName: "晨光早餐铺",
            keywords: ["新开始", "起床困难", "低动力", "拖延", "自我怀疑", "早上"],
            timeBuckets: [.morning]
        ),
        HomeScene(
            id: "firefly_meadow",
            assetName: "sensen-scene-firefly-meadow",
            displayName: "萤火虫草地",
            keywords: ["治愈", "恢复期", "轻微忧伤", "平静", "微弱", "慢慢"],
            timeBuckets: [.evening, .night]
        ),
        HomeScene(
            id: "forest_library",
            assetName: "sensen-scene-forest-library",
            displayName: "森林图书馆",
            keywords: ["思考", "迷茫", "人生选择", "职业困惑", "复盘", "理解", "意义"],
            timeBuckets: [.daytime, .evening]
        ),
        HomeScene(
            id: "wishing_tree",
            assetName: "sensen-scene-wishing-tree",
            displayName: "愿望树",
            keywords: ["梦想", "未来迷茫", "失去方向", "愿望", "方向", "期待"],
            timeBuckets: [.daytime, .evening]
        ),
        HomeScene(
            id: "sunset_lake",
            assetName: "sensen-scene-sunset-lake",
            displayName: "黄昏湖边",
            keywords: ["告别", "分手", "失去", "结束", "关系", "过去", "遗憾"],
            timeBuckets: [.evening]
        ),
        HomeScene(
            id: "cloud_observatory",
            assetName: "sensen-scene-cloud-observatory",
            displayName: "云朵观测站",
            keywords: ["想象力", "创作", "灵感", "探索", "自我成长", "好奇", "创造"],
            timeBuckets: [.morning, .daytime]
        ),
    ]

    static func select(
        journals: [JournalEntry],
        stateProfiles: [StateProfile],
        date: Date = Date()
    ) -> HomeScene {
        let time = timeBucket(for: date)
        let moodScore = journals.first?.moodScore ?? 0
        let context = searchableContext(journals: journals, stateProfiles: stateProfiles)
        guard !context.isEmpty else {
            return defaultScene(for: time)
        }

        let scoredScenes = allScenes.map { scene in
            var score = scene.timeBuckets.contains(time) ? 2 : 0
            for keyword in scene.keywords where context.contains(keyword) {
                score += 5
            }
            if moodScore <= -2, ["campfire_companion", "rainy_mushroom_house", "forest_bench", "snow_cabin"].contains(scene.id) {
                score += 2
            }
            if moodScore >= 2, ["rainbow_hill", "flower_garden_gathering", "firefly_meadow", "river_afternoon"].contains(scene.id) {
                score += 2
            }
            return (scene: scene, score: score)
        }
        return scoredScenes.max { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.scene.timeBuckets.contains(time) == false && rhs.scene.timeBuckets.contains(time)
            }
            return lhs.score < rhs.score
        }?.scene ?? defaultScene(for: time)
    }

    private static func searchableContext(
        journals: [JournalEntry],
        stateProfiles: [StateProfile]
    ) -> String {
        let recentJournals = journals.prefix(6).flatMap { journal in
            [
                journal.summary,
                journal.dominantEmotion,
                journal.suggestedNextStep,
                journal.emotionCurve.joined(separator: " "),
                journal.keywords.joined(separator: " "),
                journal.insights.joined(separator: " "),
            ]
        }
        let recentProfiles = stateProfiles.prefix(6).flatMap { profile in
            [
                profile.domain,
                profile.stage,
                profile.summary,
                profile.trend,
                profile.evidence,
                profile.supportStrategy,
            ]
        }
        return (recentJournals + recentProfiles).joined(separator: " ")
    }

    private static func timeBucket(for date: Date) -> HomeSceneTime {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11:
            return .morning
        case 11..<17:
            return .daytime
        case 17..<21:
            return .evening
        default:
            return .night
        }
    }

    private static func defaultScene(for time: HomeSceneTime) -> HomeScene {
        switch time {
        case .morning:
            return allScenes.first { $0.id == "morning_breakfast_shop" } ?? allScenes[0]
        case .daytime:
            return allScenes.first { $0.id == "river_afternoon" } ?? allScenes[0]
        case .evening:
            return allScenes.first { $0.id == "sunset_lake" } ?? allScenes[0]
        case .night:
            return allScenes.first { $0.id == "moonlight_tea" } ?? allScenes[0]
        }
    }
}

private enum SensenFonts {
    static func handwritten(size: CGFloat) -> Font {
        .custom("HannotateSC-W5", size: size)
    }
}

private struct SensenTopBar: View {
    let openMenu: () -> Void
    let openMe: () -> Void

    var body: some View {
        HStack {
            Button(action: openMenu) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(Color.warmBrown)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开菜单")

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xa8b987))
                Text("森森物语")
                    .font(SensenFonts.handwritten(size: 16))
                    .foregroundStyle(Color.warmBrown)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: 0xc99f8d))
            }

            Spacer()

            Button(action: openMe) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.warmBrown)
                    Circle()
                        .fill(Color(hex: 0xf4a4a0))
                        .frame(width: 9, height: 9)
                        .offset(x: 3, y: -3)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("通知")
        }
    }
}

private struct SensenHeroSection: View {
    let scenes: [HomeScene]
    @Binding var selectedSceneID: String
    let openChat: () -> Void

    var body: some View {
        TabView(selection: $selectedSceneID) {
            ForEach(scenes) { scene in
                Button(action: openChat) {
                    SoftSceneImage(name: scene.assetName)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开\(scene.displayName)场景")
                .tag(scene.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

private struct SoftSceneImage: View {
    let name: String

    var body: some View {
        ZStack {
            BundleImage(
                name: name,
                contentMode: .fill,
                fallbackSystemImage: "moon.stars.fill"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            EdgeFadeOverlay()
        }
        .compositingGroup()
    }
}

private struct EdgeFadeOverlay: View {
    private let pageBackground = Color(hex: 0xfffbf3)

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [pageBackground.opacity(0.82), pageBackground.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 24)

                Spacer()

                LinearGradient(
                    colors: [pageBackground.opacity(0), pageBackground.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)
            }

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [pageBackground.opacity(0.62), pageBackground.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 16)

                Spacer()

                LinearGradient(
                    colors: [pageBackground.opacity(0), pageBackground.opacity(0.62)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 16)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CompanionActionSection: View {
    private let items = [
        CompanionActionItem(title: "一盏灯的温度", subtitle: "像夜晚的灯光，给你安心与光亮", imageName: "sensen-prop-lantern-v1", tint: Color(hex: 0xffdf9f)),
        CompanionActionItem(title: "记录心情", subtitle: "写下你的心事，整理内心的声音", imageName: nil, tint: Color(hex: 0xd8c4e8)),
        CompanionActionItem(title: "放松一下", subtitle: "慢慢来，没关系，你已经很棒了", imageName: nil, tint: Color(hex: 0xf8c5b8)),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "今天的小陪伴")

            HStack(spacing: 9) {
                ForEach(items) { item in
                    CompanionActionCard(item: item)
                }
            }
        }
    }
}

private struct CompanionActionItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let imageName: String?
    let tint: Color
}

private struct CompanionActionCard: View {
    let item: CompanionActionItem

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 5) {
                if let imageName = item.imageName {
                    BundleImage(
                        name: imageName,
                        contentMode: .fit,
                        fallbackSystemImage: "lamp.table.fill"
                    )
                    .frame(height: 32)
                } else {
                    Image(systemName: item.title == "记录心情" ? "book.pages.fill" : "cup.and.saucer.fill")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(item.tint)
                        .frame(height: 32)
                }

                Text(item.title)
                    .font(SensenFonts.handwritten(size: 12))
                    .foregroundStyle(Color.warmBrown)
                    .multilineTextAlignment(.center)

                Text(item.subtitle)
                    .font(SensenFonts.handwritten(size: 8.5))
                    .foregroundStyle(Color.warmBrown.opacity(0.68))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 18, height: 18)
                    .background(item.tint.opacity(0.88), in: Circle())
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        Color(hex: 0xffeee9).opacity(0.9),
                        item.tint.opacity(0.18),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: 0xefd8cf).opacity(0.78), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MoodCheckSection: View {
    @Binding var selectedMoodIndex: Int

    private let moods = [
        ("很糟糕", "face.dashed"),
        ("有点难过", "face.smiling.inverse"),
        ("一般般", "face.smiling"),
        ("还不错", "face.smiling.fill"),
        ("很好", "sparkles"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionTitle(text: "此刻心情")
            HStack(spacing: 8) {
                ForEach(Array(moods.enumerated()), id: \.offset) { index, mood in
                    Button {
                        selectedMoodIndex = index
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle()
                                    .fill(moodColor(index).opacity(selectedMoodIndex == index ? 0.48 : 0.24))
                                    .frame(width: 38, height: 38)
                                Image(systemName: mood.1)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Color.warmBrown.opacity(0.72))
                            }
                            Text(mood.0)
                                .font(SensenFonts.handwritten(size: 11))
                                .foregroundStyle(Color.warmBrown.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(hex: 0xffeee9).opacity(0.72), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0xefd8cf).opacity(0.72), lineWidth: 1)
        }
    }

    private func moodColor(_ index: Int) -> Color {
        [Color(hex: 0xd8e2ed), Color(hex: 0xe5d6e9), Color(hex: 0xf1dfbf), Color(hex: 0xf5d5c9), Color(hex: 0xf7e3a4)][index]
    }
}

private struct EncouragementCard: View {
    let text: String
    let isLiked: Bool
    let toggleLike: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "camera.macro")
                .font(.system(size: 21, weight: .light))
                .foregroundStyle(Color(hex: 0xb7c99a))
                .frame(width: 28)

            Text(text)
                .font(SensenFonts.handwritten(size: 12))
                .lineSpacing(2)
                .foregroundStyle(Color.warmBrown.opacity(0.84))
                .lineLimit(4)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: toggleLike) {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isLiked ? Color(hex: 0xf4a4a0) : Color.warmBrown.opacity(0.34))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLiked ? "取消喜欢这句话" : "喜欢这句话")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxHeight: .infinity)
    }
}

private struct SensenBottomBar: View {
    let openHome: () -> Void
    let openForest: () -> Void
    let openChat: () -> Void
    let openNotebook: () -> Void
    let openMe: () -> Void
    let bottomInset: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            BottomBarButton(title: "首页", systemImage: "house.fill", isSelected: true, action: openHome)
            BottomBarButton(title: "森林", systemImage: "tree.fill", isSelected: false, action: openForest)

            Button(action: openChat) {
                BundleImage(
                    name: "sensen-rabbit-flat-icon-v1",
                    contentMode: .fill,
                    fallbackSystemImage: "hare.fill"
                )
                .frame(width: 46, height: 46)
                .clipShape(Circle())
                .padding(4)
                .background(Color(hex: 0xfff3ee), in: Circle())
                .shadow(color: Color(hex: 0xf4b8a8).opacity(0.28), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("忧忧兔")

            BottomBarButton(title: "心事本", systemImage: "book.closed", isSelected: false, action: openNotebook)
            BottomBarButton(title: "我的", systemImage: "person", isSelected: false, action: openMe)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Color(hex: 0xfffbf3).opacity(0.98))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(hex: 0xeadfcd).opacity(0.72))
                .frame(height: 1)
        }
    }
}

private struct BottomBarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(SensenFonts.handwritten(size: 9))
            }
            .foregroundStyle(isSelected ? Color(hex: 0xf28f86) : Color.warmBrown.opacity(0.72))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct BundleImage: View {
    enum ContentMode {
        case fit
        case fill
    }

    let name: String
    let contentMode: ContentMode
    let fallbackSystemImage: String

    var body: some View {
        Group {
            if let image = UIImage(named: name) ?? UIImage(named: "\(name).png") {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .fit ? .fit : .fill)
            } else if let image = UIImage(named: "\(name).webp") {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .fit ? .fit : .fill)
            } else {
                Image(systemName: fallbackSystemImage)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.warmBrown.opacity(0.5))
                    .padding(12)
            }
        }
    }
}

private struct SectionTitle: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Text(text)
                .font(SensenFonts.handwritten(size: 13))
                .foregroundStyle(Color.warmBrown)
            Image(systemName: "leaf.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0xa8b987))
        }
    }
}

private struct CompanionChatPage: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CompanionStore
    @State private var draft = ""
    @State private var isHistoryVisible = false
    @State private var isExitPromptVisible = false
    @State private var isSummaryResultVisible = false
    @State private var isClosingSession = false
    @State private var sentMessageCount = 0
    @FocusState private var isInputFocused: Bool

    var body: some View {
        ZStack {
            Color(hex: 0xfffbf3).ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Button {
                        if sentMessageCount == 0 {
                            dismiss()
                        } else {
                            isExitPromptVisible = true
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.warmBrown)
                            .frame(width: 42, height: 42)
                            .background(Color.white.opacity(0.68), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("忧忧兔")
                        .font(SensenFonts.handwritten(size: 19))
                        .foregroundStyle(Color.warmBrown)

                    Spacer()

                    HStack(spacing: 8) {
                        Button {
                            isHistoryVisible = true
                        } label: {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.warmBrown)
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.68), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看本次消息")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                BundleImage(
                    name: currentExpressionAssetName,
                    contentMode: .fit,
                    fallbackSystemImage: "hare.fill"
                )
                .frame(width: 240, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: Color(hex: 0xb7a0d4).opacity(0.18), radius: 24, y: 10)
                .onTapGesture {
                    isInputFocused = false
                    UIApplication.shared.dismissKeyboard()
                }

                CurrentConversationText(message: currentVisibleMessage)
                    .id(currentVisibleMessage.id)
                    .padding(.horizontal, 28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onTapGesture {
                        isInputFocused = false
                        UIApplication.shared.dismissKeyboard()
                    }

                VStack(spacing: 12) {
                    TextField("慢慢说，我在听。", text: $draft, axis: .vertical)
                        .font(SensenFonts.handwritten(size: 16))
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    HStack(spacing: 12) {
                        Button(action: {}) {
                            Label("语音", systemImage: "mic.fill")
                                .font(SensenFonts.handwritten(size: 15))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color(hex: 0xb7a0d4))

                        Button {
                            sendDraft()
                        } label: {
                            Label(store.isSending ? "发送中" : "发送", systemImage: "paperplane.fill")
                                .font(SensenFonts.handwritten(size: 15))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: 0xb7a0d4))
                        .disabled(store.isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $isHistoryVisible) {
            CurrentConversationHistoryView()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.light)
        }
        .confirmationDialog("离开前要总结这次对话吗？", isPresented: $isExitPromptVisible, titleVisibility: .visible) {
            Button(isClosingSession ? "正在总结..." : "结束并总结") {
                summarizeAndExit()
            }
            .disabled(isClosingSession)

            Button("直接返回", role: .destructive) {
                dismiss()
            }

            Button("继续聊一会儿", role: .cancel) {}
        } message: {
            Text("如果结束并总结，系统会整理这次对话，生成日记和记忆。")
        }
        .alert("本次对话总结", isPresented: $isSummaryResultVisible) {
            Button("回到首页") {
                dismiss()
            }
        } message: {
            Text(store.sessionNotice ?? "这次对话已经整理好了。")
        }
    }

    private var latestCompanionText: String {
        store.messages.last(where: { $0.role != .user })?.content ?? "我在这里。你不用急着整理好，先把这一刻交给我。"
    }

    private var currentExpressionAssetName: String {
        let latestAssistant = store.messages.last(where: { $0.role == .assistant || $0.role == .system })
        let character = store.character(id: latestAssistant?.characterID) ?? store.selectedCharacter
        return character.expression(id: latestAssistant?.expressionID)?.assetName ?? character.avatarName
    }

    private var currentVisibleMessage: ChatMessage {
        if let message = store.messages.last(where: { $0.role == .user || $0.role == .assistant }) {
            return message
        }
        return ChatMessage(
            id: "empty-companion-greeting",
            role: .assistant,
            content: latestCompanionText,
            characterID: store.selectedCharacterID,
            createdAt: ""
        )
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        sentMessageCount += 1
        isInputFocused = false
        UIApplication.shared.dismissKeyboard()
        Task {
            await store.sendDraft(text)
        }
    }

    private func summarizeAndExit() {
        guard !isClosingSession else { return }
        isClosingSession = true
        Task {
            await store.closeCurrentSession()
            isClosingSession = false
            isSummaryResultVisible = true
        }
    }
}

private struct CurrentConversationHistoryView: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeader(
                                title: "本次消息",
                                subtitle: "只看当前正在和忧忧兔说的话。"
                            )

                            if store.messages.isEmpty {
                                EmptyHintView(systemImage: "tray", title: "还没有消息", detail: "等你说第一句话，这里会留下本次对话。")
                            } else {
                                ForEach(store.messages) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }

                            if let sessionNotice = store.sessionNotice {
                                Text(sessionNotice)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                                    .id("session-notice")
                            }
                        }
                        .padding(18)
                    }
                    .onAppear {
                        scrollToLatest(proxy)
                    }
                    .onChange(of: store.messages.count) {
                        withAnimation(.snappy) {
                            scrollToLatest(proxy)
                        }
                    }
                }
            }
            .navigationTitle("本次消息")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        if let lastID = store.messages.last?.id {
            proxy.scrollTo(lastID, anchor: .bottom)
        } else {
            proxy.scrollTo("session-notice", anchor: .bottom)
        }
    }
}

private struct CurrentConversationText: View {
    @EnvironmentObject private var store: CompanionStore
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == .user
        let character = store.character(id: message.characterID) ?? store.selectedCharacter
        ScrollView {
            VStack(alignment: isUser ? .trailing : .leading, spacing: 10) {
                Text(isUser ? "你" : companionName(character))
                    .font(SensenFonts.handwritten(size: 13))
                    .foregroundStyle(isUser ? Color.warmBrown.opacity(0.48) : textColor(for: character).opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

                Text(message.content)
                    .font(SensenFonts.handwritten(size: 17))
                    .lineSpacing(7)
                    .foregroundStyle(isUser ? Color.warmBrown.opacity(0.58) : textColor(for: character))
                    .multilineTextAlignment(isUser ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            }
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func companionName(_ character: CompanionCharacter) -> String {
        if let label = character.expression(id: message.expressionID)?.label, !label.isEmpty {
            return "\(character.name) · \(label)"
        }
        return character.name
    }

    private func textColor(for character: CompanionCharacter) -> Color {
        switch character.id {
        case "momo":
            return Color(hex: 0x5f7890)
        case "yoran":
            return Color(hex: 0x776597)
        default:
            return Color(hex: 0x9a6b72)
        }
    }
}

private struct LatestConversationPanel: View {
    @EnvironmentObject private var store: CompanionStore
    let messages: [ChatMessage]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        LatestConversationRow(
                            message: message,
                            character: store.character(id: message.characterID) ?? store.selectedCharacter
                        )
                        .id(message.id)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 170)
            .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color(hex: 0xe6d6c6).opacity(0.8), lineWidth: 1)
            }
            .onAppear {
                if let lastID = messages.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: messages.map(\.id)) {
                if let lastID = messages.last?.id {
                    withAnimation(.snappy) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct LatestConversationRow: View {
    let message: ChatMessage
    let character: CompanionCharacter

    var body: some View {
        let isUser = message.role == .user
        VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
            Text(isUser ? "你" : companionName)
                .font(SensenFonts.handwritten(size: 12))
                .foregroundStyle(Color.warmBrown.opacity(0.68))
            Text(message.content)
                .font(SensenFonts.handwritten(size: 15))
                .lineSpacing(5)
                .foregroundStyle(Color.warmBrown.opacity(0.9))
                .multilineTextAlignment(isUser ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    isUser ? Color(hex: 0xf5ecff).opacity(0.82) : character.bubbleColor.opacity(0.88),
                    in: RoundedRectangle(cornerRadius: 17, style: .continuous)
                )
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var companionName: String {
        if let label = character.expression(id: message.expressionID)?.label, !label.isEmpty {
            return "\(character.name) · \(label)"
        }
        return character.name
    }
}

private struct CampfireStage: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var highlightedHotspotID: String?

    let openMailbox: () -> Void
    let openSessionNotebook: () -> Void
    let openLanternSettings: () -> Void
    let focusComposer: () -> Void
    let setNotice: (String) -> Void

    var body: some View {
        GeometryReader { _ in
            ZStack {
                if let background = UIImage(named: Self.generatedBackgroundAssetName) {
                    GeneratedNightScene(
                        background: background,
                        highlightedHotspotID: highlightedHotspotID,
                        openMailbox: openMailbox,
                        openSessionNotebook: openSessionNotebook,
                        openLanternSettings: openLanternSettings,
                        focusComposer: focusComposer,
                        setNotice: setNotice,
                        activateHotspot: activateHotspot
                    )
                } else {
                    CodeGeneratedNightScene(
                        highlightedHotspotID: highlightedHotspotID,
                        openMailbox: { activateHotspot("mailbox", action: openMailbox) },
                        openSessionNotebook: { activateHotspot("notebook", action: openSessionNotebook) },
                        openLanternSettings: { activateHotspot("lantern", action: openLanternSettings) },
                        focusComposer: { activateHotspot("campfire", action: focusComposer) },
                        setNotice: setNotice
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let generatedBackgroundAssetName = "sensen-home-rabbit-quiet-v1"

    private func activateHotspot(_ id: String, action: @escaping () -> Void) {
        highlightedHotspotID = id
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            if highlightedHotspotID == id {
                highlightedHotspotID = nil
            }
        }
    }
}

private struct CodeGeneratedNightScene: View {
    @EnvironmentObject private var store: CompanionStore
    let highlightedHotspotID: String?
    let openMailbox: () -> Void
    let openSessionNotebook: () -> Void
    let openLanternSettings: () -> Void
    let focusComposer: () -> Void
    let setNotice: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                DistantTreeLine()
                    .position(x: size.width * 0.5, y: size.height * 0.38)

                MoonAndStars {
                    setNotice("今晚的天空很安静。后续这里会接入天气和月相。")
                }
                .position(x: size.width * 0.78, y: size.height * 0.13)
                .sceneTouchHalo(isVisible: highlightedHotspotID == "moon", color: Color(hex: 0xfff3c2), radius: 82)

                Ellipse()
                    .fill(Color.white.opacity(0.055))
                    .frame(width: size.width * 0.86, height: size.height * 0.54)
                    .blur(radius: 4)
                    .position(x: size.width * 0.5, y: size.height * 0.6)

                ForEach(Array(CompanionFixtures.characters.enumerated()), id: \.element.id) { index, character in
                    let point = position(for: index, in: size)
                    SceneAnimalButton(
                        character: character,
                        isSelected: character.id == store.selectedCharacterID || highlightedHotspotID == character.id
                    ) {
                        store.selectedCharacterID = character.id
                        setNotice("\(character.name)靠近了一点。")
                    }
                    .position(point)
                }

                MailboxObject(messageCount: store.messages.count, action: openMailbox)
                    .sceneTouchHalo(isVisible: highlightedHotspotID == "mailbox", color: Color(hex: 0xffd27d), radius: 82)
                    .position(x: size.width * 0.15, y: size.height * 0.82)

                NotebookObject(action: openSessionNotebook)
                    .sceneTouchHalo(isVisible: highlightedHotspotID == "notebook", color: Color(hex: 0xffd27d), radius: 82)
                    .position(x: size.width * 0.86, y: size.height * 0.82)

                GroupLanternObject(isGroupMode: store.isGroupMode, action: openLanternSettings)
                    .sceneTouchHalo(isVisible: highlightedHotspotID == "lantern", color: Color(hex: 0xffd27d), radius: 82)
                    .position(x: size.width * 0.13, y: size.height * 0.25)

                CampfireButton(action: focusComposer)
                    .sceneTouchHalo(isVisible: highlightedHotspotID == "campfire", color: Color(hex: 0xffb45d), radius: 140)
                    .position(x: size.width * 0.5, y: size.height * 0.58)
            }
        }
    }

    private func position(for index: Int, in size: CGSize) -> CGPoint {
        let points = [
            CGPoint(x: size.width * 0.23, y: size.height * 0.53),
            CGPoint(x: size.width * 0.34, y: size.height * 0.73),
            CGPoint(x: size.width * 0.66, y: size.height * 0.73),
            CGPoint(x: size.width * 0.77, y: size.height * 0.53),
            CGPoint(x: size.width * 0.36, y: size.height * 0.39),
            CGPoint(x: size.width * 0.64, y: size.height * 0.39),
        ]
        return points[index]
    }
}

private struct GeneratedNightScene: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var ambientPulse = false
    @State private var isStreetlampLit = false
    @State private var litQuietObjectIDs: Set<String> = []

    let background: UIImage
    let highlightedHotspotID: String?
    let openMailbox: () -> Void
    let openSessionNotebook: () -> Void
    let openLanternSettings: () -> Void
    let focusComposer: () -> Void
    let setNotice: (String) -> Void
    let activateHotspot: (String, @escaping () -> Void) -> Void

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Image(uiImage: background)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .allowsHitTesting(false)

                AmbientFireflies(size: size, isAnimating: ambientPulse)
                    .allowsHitTesting(false)

                LanternGlowOverlay(
                    center: CGPoint(x: size.width * 0.16, y: size.height * 0.22),
                    isActive: isStreetlampLit || highlightedHotspotID == "streetlamp",
                    isGroupMode: false,
                    isAnimating: ambientPulse
                )
                .allowsHitTesting(false)

                QuietObjectGlowLayer(hotspots: quietObjectHotspots(in: size), litObjectIDs: litQuietObjectIDs)
                    .allowsHitTesting(false)

                RabbitWhisperBubble(message: rabbitWhisper) {
                    openMailbox()
                }
                .position(x: size.width * 0.62, y: size.height * 0.34)

                if let highlightedHotspotID,
                   let hotspot = hotspots(in: size).first(where: { $0.id == highlightedHotspotID })
                {
                    TouchedObjectRipple(hotspot: hotspot)
                        .allowsHitTesting(false)
                }

                ForEach(hotspots(in: size)) { hotspot in
                    SceneHotspotButton(
                        hotspot: hotspot,
                        isHighlighted: highlightedHotspotID == hotspot.id
                    ) {
                        activateHotspot(hotspot.id, hotspot.action)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.45).repeatForever(autoreverses: true)) {
                ambientPulse = true
            }
        }
    }

    private func hotspots(in size: CGSize) -> [SceneHotspot] {
        return [
            SceneHotspot(id: "streetlamp", label: isStreetlampLit ? "关掉路灯" : "点亮路灯", center: CGPoint(x: size.width * 0.16, y: size.height * 0.22), radius: 46, color: Color(hex: 0xffd27d)) {
                isStreetlampLit.toggle()
                openLanternSettings()
            },
            SceneHotspot(id: "notebook", label: "打开森林笔记本", center: CGPoint(x: size.width * 0.78, y: size.height * 0.82), radius: 70, color: Color(hex: 0xffd27d)) {
                openSessionNotebook()
            },
            SceneHotspot(id: "rabbit", label: "摸摸忧忧", center: CGPoint(x: size.width * 0.48, y: size.height * 0.52), radius: 96, color: Color(hex: 0xf4b8a8)) {
                store.selectedCharacterID = "youyou_rabbit"
                setNotice("忧忧轻轻点头：我在。")
                focusComposer()
            },
        ] + quietObjectHotspots(in: size)
    }

    private func quietObjectHotspots(in size: CGSize) -> [SceneHotspot] {
        [
            SceneHotspot(id: "quiet-speaker-left-top", label: "让小音箱轻轻亮起", center: CGPoint(x: size.width * 0.19, y: size.height * 0.62), radius: 34, color: Color(hex: 0xffd27d)) {
                toggleQuietObject("quiet-speaker-left-top")
            },
            SceneHotspot(id: "quiet-speaker-left-bottom", label: "让小音箱轻轻亮起", center: CGPoint(x: size.width * 0.28, y: size.height * 0.78), radius: 34, color: Color(hex: 0xf4b8a8)) {
                toggleQuietObject("quiet-speaker-left-bottom")
            },
            SceneHotspot(id: "quiet-speaker-right-top", label: "让小音箱轻轻亮起", center: CGPoint(x: size.width * 0.72, y: size.height * 0.61), radius: 34, color: Color(hex: 0xffd27d)) {
                toggleQuietObject("quiet-speaker-right-top")
            },
            SceneHotspot(id: "quiet-speaker-right-bottom", label: "让小音箱轻轻亮起", center: CGPoint(x: size.width * 0.62, y: size.height * 0.78), radius: 34, color: Color(hex: 0xf4b8a8)) {
                toggleQuietObject("quiet-speaker-right-bottom")
            },
        ]
    }

    private var rabbitWhisper: String {
        store.messages.last(where: { $0.role != .user })?.content ?? "我在这里，慢慢说。"
    }

    private func toggleQuietObject(_ id: String) {
        if litQuietObjectIDs.contains(id) {
            litQuietObjectIDs.remove(id)
        } else {
            litQuietObjectIDs.insert(id)
        }
    }
}

private struct SceneHotspot: Identifiable {
    let id: String
    let label: String
    let center: CGPoint
    let radius: CGFloat
    let color: Color
    let action: () -> Void
}

private struct RabbitWhisperBubble: View {
    let message: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("…")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Color.warmBrown.opacity(0.88))
                Text(message)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color.nightInk.opacity(0.86))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 206, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.1), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开忧忧的最近回复")
    }
}

private struct QuietObjectGlowLayer: View {
    let hotspots: [SceneHotspot]
    let litObjectIDs: Set<String>

    var body: some View {
        ZStack {
            ForEach(hotspots) { hotspot in
                QuietObjectGlow(hotspot: hotspot, isLit: litObjectIDs.contains(hotspot.id))
            }
        }
    }
}

private struct QuietObjectGlow: View {
    let hotspot: SceneHotspot
    let isLit: Bool

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        hotspot.color.opacity(isLit ? 0.24 : 0),
                        Color(hex: 0xffd27d).opacity(isLit ? 0.08 : 0),
                        Color.clear,
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: hotspot.radius * 0.72
                )
            )
            .frame(width: hotspot.radius * 1.45, height: hotspot.radius * 1.45)
            .blur(radius: 4)
            .position(hotspot.center)
            .blendMode(.screen)
            .animation(.easeInOut(duration: 0.3), value: isLit)
    }
}

private struct SceneHotspotButton: View {
    let hotspot: SceneHotspot
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isHighlighted ? hotspot.color.opacity(0.18) : Color.white.opacity(0.001))
                .overlay {
                    Circle()
                        .stroke(hotspot.color.opacity(isHighlighted ? 0.72 : 0), lineWidth: 2)
                }
                .shadow(color: hotspot.color.opacity(isHighlighted ? 0.35 : 0), radius: 18)
                .frame(width: hotspot.radius * 2, height: hotspot.radius * 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(hotspot.center)
        .accessibilityLabel(hotspot.label)
    }
}

private struct AmbientFireflies: View {
    let size: CGSize
    let isAnimating: Bool

    private let fireflies = FireflySpec.farLayer + FireflySpec.middleLayer + FireflySpec.nearLayer

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(fireflies.enumerated()), id: \.offset) { index, spec in
                    let phase = time * spec.speed + spec.delay * 4.0 + Double(index) * 0.63
                    let glow = spec.opacityBase + spec.opacityRange * (0.5 + 0.5 * sin(phase * spec.twinkleSpeed))
                    let xDrift = CGFloat(sin(phase * spec.horizontalFlow)) * spec.drift.width
                    let yDrift = CGFloat(cos(phase * spec.verticalFlow)) * spec.drift.height
                    FireflyDot(spec: spec, glow: glow)
                        .position(x: size.width * spec.x + xDrift, y: size.height * spec.y + yDrift)
                }
            }
            .opacity(isAnimating ? 1 : 0.88)
        }
    }
}

private struct FireflyDot: View {
    let spec: FireflySpec
    let glow: Double

    private var warmGlow: Double {
        min(0.98, glow + 0.3)
    }

    private var paleGlow: Double {
        min(0.82, glow + 0.12)
    }

    var body: some View {
        Circle()
            .fill(Color(hex: 0xffd27d).opacity(glow))
            .frame(width: spec.diameter, height: spec.diameter)
            .blur(radius: spec.blur)
            .shadow(color: Color(hex: 0xffd27d).opacity(warmGlow), radius: spec.shadowRadius)
            .shadow(color: Color(hex: 0xfff0b8).opacity(paleGlow), radius: spec.shadowRadius * 0.48)
            .blendMode(.screen)
    }
}

private struct FireflySpec {
    let x: CGFloat
    let y: CGFloat
    let delay: Double
    let diameter: CGFloat
    let drift: CGSize
    let speed: Double
    let twinkleSpeed: Double
    let horizontalFlow: Double
    let verticalFlow: Double
    let opacityBase: Double
    let opacityRange: Double
    let blur: CGFloat
    let shadowRadius: CGFloat

    static let farLayer = [
        FireflySpec(x: 0.12, y: 0.23, delay: 0.1, diameter: 2.0, drift: CGSize(width: 5, height: 7), speed: 0.24, twinkleSpeed: 0.9, horizontalFlow: 0.8, verticalFlow: 0.65, opacityBase: 0.12, opacityRange: 0.24, blur: 0.4, shadowRadius: 4),
        FireflySpec(x: 0.22, y: 0.34, delay: 0.6, diameter: 2.4, drift: CGSize(width: 6, height: 5), speed: 0.2, twinkleSpeed: 0.82, horizontalFlow: 0.7, verticalFlow: 0.78, opacityBase: 0.1, opacityRange: 0.22, blur: 0.45, shadowRadius: 4),
        FireflySpec(x: 0.44, y: 0.27, delay: 0.2, diameter: 1.8, drift: CGSize(width: 4, height: 6), speed: 0.18, twinkleSpeed: 0.86, horizontalFlow: 0.72, verticalFlow: 0.66, opacityBase: 0.1, opacityRange: 0.2, blur: 0.4, shadowRadius: 3),
        FireflySpec(x: 0.76, y: 0.28, delay: 0.8, diameter: 2.2, drift: CGSize(width: 6, height: 8), speed: 0.22, twinkleSpeed: 0.92, horizontalFlow: 0.64, verticalFlow: 0.72, opacityBase: 0.11, opacityRange: 0.24, blur: 0.45, shadowRadius: 4),
        FireflySpec(x: 0.9, y: 0.38, delay: 0.4, diameter: 2.0, drift: CGSize(width: 5, height: 7), speed: 0.2, twinkleSpeed: 0.8, horizontalFlow: 0.78, verticalFlow: 0.68, opacityBase: 0.1, opacityRange: 0.2, blur: 0.42, shadowRadius: 3),
    ]

    static let middleLayer = [
        FireflySpec(x: 0.16, y: 0.44, delay: 0.0, diameter: 4.2, drift: CGSize(width: 10, height: 13), speed: 0.38, twinkleSpeed: 1.0, horizontalFlow: 0.84, verticalFlow: 0.73, opacityBase: 0.28, opacityRange: 0.42, blur: 0.65, shadowRadius: 8),
        FireflySpec(x: 0.32, y: 0.49, delay: 0.5, diameter: 3.6, drift: CGSize(width: 13, height: 11), speed: 0.35, twinkleSpeed: 0.94, horizontalFlow: 0.76, verticalFlow: 0.8, opacityBase: 0.24, opacityRange: 0.38, blur: 0.6, shadowRadius: 8),
        FireflySpec(x: 0.55, y: 0.42, delay: 0.9, diameter: 4.0, drift: CGSize(width: 11, height: 14), speed: 0.34, twinkleSpeed: 0.98, horizontalFlow: 0.82, verticalFlow: 0.69, opacityBase: 0.25, opacityRange: 0.4, blur: 0.62, shadowRadius: 9),
        FireflySpec(x: 0.82, y: 0.48, delay: 0.25, diameter: 4.8, drift: CGSize(width: 12, height: 12), speed: 0.4, twinkleSpeed: 1.04, horizontalFlow: 0.7, verticalFlow: 0.86, opacityBase: 0.3, opacityRange: 0.42, blur: 0.68, shadowRadius: 9),
        FireflySpec(x: 0.69, y: 0.69, delay: 0.65, diameter: 3.8, drift: CGSize(width: 13, height: 10), speed: 0.36, twinkleSpeed: 0.96, horizontalFlow: 0.74, verticalFlow: 0.76, opacityBase: 0.25, opacityRange: 0.36, blur: 0.6, shadowRadius: 8),
    ]

    static let nearLayer = [
        FireflySpec(x: 0.25, y: 0.62, delay: 0.15, diameter: 6.6, drift: CGSize(width: 18, height: 20), speed: 0.55, twinkleSpeed: 1.18, horizontalFlow: 0.86, verticalFlow: 0.74, opacityBase: 0.48, opacityRange: 0.48, blur: 0.82, shadowRadius: 15),
        FireflySpec(x: 0.52, y: 0.58, delay: 0.75, diameter: 5.8, drift: CGSize(width: 22, height: 16), speed: 0.5, twinkleSpeed: 1.12, horizontalFlow: 0.72, verticalFlow: 0.88, opacityBase: 0.42, opacityRange: 0.46, blur: 0.8, shadowRadius: 14),
        FireflySpec(x: 0.78, y: 0.73, delay: 0.35, diameter: 6.2, drift: CGSize(width: 20, height: 18), speed: 0.58, twinkleSpeed: 1.22, horizontalFlow: 0.8, verticalFlow: 0.7, opacityBase: 0.46, opacityRange: 0.5, blur: 0.84, shadowRadius: 16),
    ]
}

private struct CampfireGlowOverlay: View {
    let center: CGPoint
    let isActive: Bool
    let isAnimating: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xffd27d).opacity(isActive ? 0.34 : 0.2),
                            Color(hex: 0xff8b4c).opacity(isActive ? 0.18 : 0.08),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: 124
                    )
                )
                .frame(width: isAnimating ? 230 : 198, height: isAnimating ? 230 : 198)

            Image(systemName: "flame.fill")
                .font(.system(size: isActive ? 38 : 30, weight: .bold))
                .foregroundStyle(Color(hex: 0xffd27d).opacity(isActive ? 0.86 : 0.44))
                .scaleEffect(isAnimating ? 1.08 : 0.94)
                .offset(y: isAnimating ? -4 : 3)
        }
        .position(center)
        .blendMode(.screen)
    }
}

private struct LanternGlowOverlay: View {
    let center: CGPoint
    let isActive: Bool
    let isGroupMode: Bool
    let isAnimating: Bool

    private var innerOpacity: Double {
        if isGroupMode {
            return 0.34
        }
        return isActive ? 0.24 : 0.1
    }

    private var middleOpacity: Double {
        if isGroupMode {
            return 0.14
        }
        return isActive ? 0.1 : 0.04
    }

    private var glowSize: CGFloat {
        if isGroupMode {
            return isAnimating ? 142 : 126
        }
        return isAnimating ? 108 : 98
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xffe1a0).opacity(innerOpacity),
                            Color(hex: 0xffb45d).opacity(middleOpacity),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: isGroupMode ? 78 : 58
                    )
                )
                .frame(width: glowSize, height: glowSize)

            if isGroupMode {
                Circle()
                    .stroke(Color(hex: 0xffe1a0).opacity(0.22), lineWidth: 1)
                    .frame(width: isAnimating ? 72 : 62, height: isAnimating ? 72 : 62)
                    .blur(radius: 0.8)
            }
        }
        .position(center)
        .blendMode(.screen)
    }
}

private struct AnimalPresenceGlowLayer: View {
    let hotspots: [SceneHotspot]
    let selectedCharacterID: String
    let isGroupMode: Bool
    let isAnimating: Bool

    var body: some View {
        ZStack {
            ForEach(Array(hotspots.enumerated()), id: \.element.id) { index, hotspot in
                let isSelected = hotspot.id == selectedCharacterID
                AnimalPresenceGlow(
                    hotspot: hotspot,
                    isVisible: isGroupMode || isSelected,
                    glow: glow(forSelected: isSelected),
                    scale: scale(forSelected: isSelected),
                    delay: isGroupMode ? Double(index) * 0.08 : 0
                )
            }
        }
    }

    private func glow(forSelected isSelected: Bool) -> Double {
        if isGroupMode {
            return isSelected ? 0.28 : 0.18
        }
        return isSelected ? 0.3 : 0
    }

    private func scale(forSelected isSelected: Bool) -> CGFloat {
        if isGroupMode {
            return isSelected ? 0.9 : 0.84
        }
        return isSelected ? 0.88 : 0.8
    }
}

private struct AnimalPresenceGlow: View {
    let hotspot: SceneHotspot
    let isVisible: Bool
    let glow: Double
    let scale: CGFloat
    let delay: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            hotspot.color.opacity(glow),
                            Color(hex: 0xffd27d).opacity(glow * 0.36),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 8,
                        endRadius: hotspot.radius * 0.62
                    )
                )
                .frame(width: hotspot.radius * 1.28, height: hotspot.radius * 1.28)
                .blur(radius: 5)

            Circle()
                .stroke(hotspot.color.opacity(glow * 0.42), lineWidth: 1)
                .frame(width: hotspot.radius * 0.92, height: hotspot.radius * 0.92)
                .blur(radius: 1.2)
        }
        .scaleEffect(scale)
        .opacity(isVisible ? 1 : 0)
        .position(hotspot.center)
        .blendMode(.screen)
        .animation(.easeInOut(duration: 0.72).delay(delay), value: isVisible)
    }
}

private struct TouchedObjectRipple: View {
    let hotspot: SceneHotspot

    var body: some View {
        Circle()
            .stroke(hotspot.color.opacity(0.72), lineWidth: 2)
            .background(Circle().fill(hotspot.color.opacity(0.12)))
            .frame(width: hotspot.radius * 2.24, height: hotspot.radius * 2.24)
            .scaleEffect(1.08)
            .shadow(color: hotspot.color.opacity(0.4), radius: 18)
            .position(hotspot.center)
            .transition(.scale.combined(with: .opacity))
    }
}

private extension View {
    func sceneTouchHalo(isVisible: Bool, color: Color, radius: CGFloat) -> some View {
        overlay {
            Circle()
                .fill(isVisible ? color.opacity(0.16) : Color.clear)
                .overlay {
                    Circle()
                        .stroke(color.opacity(isVisible ? 0.68 : 0), lineWidth: 2)
                }
                .shadow(color: color.opacity(isVisible ? 0.34 : 0), radius: 18)
                .frame(width: radius, height: radius)
                .allowsHitTesting(false)
        }
    }
}

private struct DistantTreeLine: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: -18) {
            ForEach(0..<7) { index in
                TreeSilhouette(height: [96, 132, 108, 154, 118, 140, 104][index])
                    .opacity(index == 3 ? 0.42 : 0.28)
            }
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}

private struct TreeSilhouette: View {
    let height: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(Color(hex: 0x0f1c18).opacity(0.9))
                .frame(width: height * 0.78, height: height * 0.64)
            Rectangle()
                .fill(Color(hex: 0x0b1410).opacity(0.9))
                .frame(width: 7, height: height * 0.36)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MoonAndStars: View {
    let moonAction: () -> Void

    var body: some View {
        ZStack {
            Button(action: moonAction) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xfff3c2).opacity(0.92))
                    Circle()
                        .fill(Color(hex: 0x1d2736).opacity(0.38))
                        .frame(width: 45, height: 45)
                        .offset(x: 15, y: -7)
                }
                .frame(width: 64, height: 64)
                .shadow(color: Color(hex: 0xfff3c2).opacity(0.35), radius: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("月亮和天气")

            ForEach(0..<9) { index in
                Image(systemName: "sparkle")
                    .font(.system(size: index % 3 == 0 ? 10 : 7, weight: .semibold))
                    .foregroundStyle(Color.softPaper.opacity(0.48))
                    .offset(starOffset(index))
            }
        }
    }

    private func starOffset(_ index: Int) -> CGSize {
        let offsets = [
            CGSize(width: -148, height: -48),
            CGSize(width: -92, height: -78),
            CGSize(width: -16, height: -96),
            CGSize(width: 82, height: -54),
            CGSize(width: -174, height: 34),
            CGSize(width: 128, height: 34),
            CGSize(width: -106, height: 88),
            CGSize(width: 72, height: 92),
            CGSize(width: 16, height: 58),
        ]
        return offsets[index]
    }
}

private struct GroupLanternObject: View {
    let isGroupMode: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Capsule()
                    .fill(Color(hex: 0x4f3527))
                    .frame(width: 8, height: 54)
                    .offset(y: -22)

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isGroupMode ? Color(hex: 0xffc56e).opacity(0.86) : Color(hex: 0x6e5140).opacity(0.82))
                    .frame(width: 54, height: 72)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color(hex: 0xffe3b0).opacity(isGroupMode ? 0.78 : 0.32), lineWidth: 2)
                    }
                    .shadow(color: Color(hex: 0xffb45d).opacity(isGroupMode ? 0.55 : 0.12), radius: isGroupMode ? 20 : 8)

                Image(systemName: isGroupMode ? "person.3.fill" : "person.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isGroupMode ? Color.nightInk.opacity(0.78) : Color.softPaper.opacity(0.8))
            }
            .frame(width: 82, height: 112)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isGroupMode ? "关闭群聊灯笼" : "点亮群聊灯笼")
    }
}

private struct SceneAnimalButton: View {
    let character: CompanionCharacter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(character.bubbleColor.opacity(0.24))
                        .frame(width: 82, height: 82)
                        .blur(radius: 4)
                }

                CharacterAvatar(character: character, size: isSelected ? 62 : 52)
                    .shadow(color: isSelected ? character.bubbleColor.opacity(0.72) : Color.black.opacity(0.16), radius: isSelected ? 16 : 8)
            }
            .contentShape(Rectangle())
            .frame(width: 86, height: 86)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("选择\(character.name)")
    }
}

private struct CampfireButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Ellipse()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: 150, height: 38)
                    .offset(y: 52)
                    .blur(radius: 8)

                Circle()
                    .fill(Color(hex: 0xffb45d).opacity(0.13))
                    .frame(width: 154, height: 154)
                    .blur(radius: 3)

                ForEach([-32, 32], id: \.self) { rotation in
                    Capsule()
                        .fill(Color(hex: 0x7b4c2d))
                        .frame(width: 84, height: 16)
                        .rotationEffect(.degrees(Double(rotation)))
                        .offset(y: 44)
                }

                Image(systemName: "flame.fill")
                    .font(.system(size: 82, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: 0xffe4a3), Color(hex: 0xf09a52), Color(hex: 0xbd5c35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: Color(hex: 0xffb45d).opacity(0.65), radius: 24)
            }
            .frame(width: 170, height: 170)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("点篝火开始输入")
    }
}

private struct NotebookObject: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: 0x7b5a42))
                    .frame(width: 64, height: 74)
                    .rotationEffect(.degrees(-7))
                    .shadow(color: Color.black.opacity(0.24), radius: 10, y: 6)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: 0xd8bd8f))
                    .frame(width: 50, height: 62)
                    .rotationEffect(.degrees(-7))

                VStack(spacing: 6) {
                    Capsule()
                        .fill(Color(hex: 0x8f6849).opacity(0.7))
                        .frame(width: 26, height: 3)
                    Capsule()
                        .fill(Color(hex: 0x8f6849).opacity(0.5))
                        .frame(width: 20, height: 3)
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x78583d))
                }
                .rotationEffect(.degrees(-7))
            }
            .frame(width: 92, height: 104)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开夜谈小笔记")
    }
}

private struct MailboxObject: View {
    let messageCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0xb87855))
                        .frame(width: 70, height: 46)
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color(hex: 0xffd7a2).opacity(0.75), lineWidth: 2)
                        }
                        .overlay {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Color(hex: 0xfff4dc))
                        }

                    Capsule()
                        .fill(Color(hex: 0x6f4b32))
                        .frame(width: 12, height: 34)
                }
                .shadow(color: Color.black.opacity(0.22), radius: 10, y: 6)

                Text("\(messageCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.nightInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: 0xffd27d), in: Capsule())
                    .offset(x: 8, y: -8)
            }
            .frame(width: 96, height: 98)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开夜谈信箱，\(messageCount)条消息")
    }
}

private struct ChatStatusStrip: View {
    @EnvironmentObject private var store: CompanionStore
    let sceneNotice: String?

    var body: some View {
        HStack {
            if store.isSending {
                Label("正在回应", systemImage: "ellipsis.bubble.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: 0xffd27d))
            } else if let sceneNotice {
                Text(sceneNotice)
                    .font(.caption)
                    .foregroundStyle(Color.softPaper.opacity(0.78))
                    .lineLimit(1)
            } else if let sessionNotice = store.sessionNotice {
                Text(sessionNotice)
                    .font(.caption)
                    .foregroundStyle(Color.softPaper.opacity(0.78))
                    .lineLimit(1)
            }

            Spacer()
        }
    }
}

private struct NightCampBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(hex: 0x111725),
                Color(hex: 0x1d2736),
                Color(hex: 0x31402e),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [Color.clear, Color(hex: 0x0e120d).opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .ignoresSafeArea()
        }
    }
}

private struct MessageDrawerContent: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        NavigationStack {
            ZStack {
                WarmBackground()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            SessionControlPanel()
                            if let loadError = store.loadError {
                                SoftPanel {
                                    Label(loadError, systemImage: "externaldrive.badge.questionmark")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let chatNotice = store.chatNotice {
                                SoftPanel {
                                    Label(chatNotice, systemImage: "wifi.exclamationmark")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            ForEach(store.messages.reversed()) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            if store.isChatCheckInVisible {
                                ChatEmotionCheckInCard()
                                    .id("chat-emotion-check-in")
                            }
                            if store.isMonsterCareGameVisible {
                                MonsterCareGameCard()
                                    .id("monster-care-game")
                            }
                            if store.isRecommendationVisible {
                                RecommendationCard()
                                    .id("recommendation-card")
                            }
                            if store.isSending {
                                TypingIndicator(character: store.selectedCharacter)
                            }
                            InteractionOfferShelf()
                            ChatQuickActions()
                        }
                        .padding(18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onAppear {
                        if let firstID = store.messages.last?.id {
                            proxy.scrollTo(firstID, anchor: .top)
                        }
                    }
                    .onChange(of: store.messages.count) {
                        if let firstID = store.messages.last?.id {
                            withAnimation(.snappy) {
                                proxy.scrollTo(firstID, anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationTitle("夜谈信箱")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.light)
    }
}

private struct SessionHistoryView: View {
    @EnvironmentObject private var store: CompanionStore
    let openSession: (String) -> Void

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "历史会话",
                        subtitle: "按时间回看已经留下的夜谈。可以先查看内容，再决定是否接着聊。"
                    )

                    if store.sessions.isEmpty {
                        EmptyHintView(systemImage: "clock.arrow.circlepath", title: "还没有历史会话", detail: "当本地数据库里有 sessions 时，这里会显示每一次夜谈。")
                    } else {
                        ForEach(store.sessions) { session in
                            NavigationLink {
                                SessionDetailView(session: session, openSession: openSession)
                            } label: {
                                SessionHistoryCard(session: session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("会话")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RecentMessagesView: View {
    @State private var messages: [ChatMessage] = []

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "消息流",
                        subtitle: "按最近时间回看数据库里保存的夜谈消息。"
                    )

                    if messages.isEmpty {
                        EmptyHintView(systemImage: "text.bubble", title: "还没有读到消息", detail: "当本地数据库里有 messages 时，这里会显示最近的对话内容。")
                    } else {
                        ForEach(messages.reversed()) { message in
                            MessageBubble(message: message)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            messages = (try? SQLiteDatabase().recentMessages(limit: 120)) ?? []
        }
    }
}

private struct SessionHistoryCard: View {
    let session: SessionSummary

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(session.createdAt.isEmpty ? "未标记时间" : session.createdAt, systemImage: "moon.stars.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warmBrown)
                        .lineLimit(1)
                    Spacer()
                    Text("\(session.messageCount) 条")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(session.preview.isEmpty ? "这次会话暂时没有预览。" : session.preview)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.nightInk)
                    .lineLimit(3)

                Text(session.endedAt.isEmpty ? "可继续对话" : "已结束：\(session.endedAt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct JournalHistoryView: View {
    @EnvironmentObject private var store: CompanionStore
    let openSession: (String) -> Void

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(
                        title: "会话总结",
                        subtitle: "结束夜谈后生成的日记、心情和下一步建议会放在这里。"
                    )

                    if store.journals.isEmpty {
                        EmptyHintView(systemImage: "book.closed", title: "暂无总结", detail: "当 Web 后端结束会话并写入 journals 后，这里会显示总结内容。")
                    } else {
                        ForEach(store.journals) { journal in
                            JournalHistoryCard(journal: journal, openSession: openSession)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("总结")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct JournalHistoryCard: View {
    let journal: JournalEntry
    let openSession: (String) -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Label(journal.dominantEmotion.isEmpty ? "会话总结" : journal.dominantEmotion, systemImage: "book.pages.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.warmBrown)
                    Spacer()
                    Text(journal.createdAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }

                Text(journal.summary.isEmpty ? "这条总结暂时没有正文。" : journal.summary)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.nightInk)
                    .fixedSize(horizontal: false, vertical: true)

                if !journal.keywords.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(journal.keywords, id: \.self) { keyword in
                                Text(keyword)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.warmBrown)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.66), in: Capsule())
                            }
                        }
                    }
                }

                HStack {
                    Label("心情 \(journal.moodScore)", systemImage: "waveform.path.ecg")
                    Spacer()
                    if !journal.sessionID.isEmpty {
                        Button {
                            openSession(journal.sessionID)
                        } label: {
                            Label("来源会话", systemImage: "arrow.up.right.circle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.warmBrown)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                if !journal.emotionCurve.isEmpty {
                    JournalDetailBlock(title: "情绪轨迹", items: journal.emotionCurve)
                }

                if !journal.insights.isEmpty {
                    JournalDetailBlock(title: "理解线索", items: journal.insights)
                }

                if !journal.suggestedNextStep.isEmpty {
                    Text(journal.suggestedNextStep)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
    }
}

private struct JournalDetailBlock: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.warmBrown)
            ForEach(items, id: \.self) { item in
                Text("· \(item)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SessionDetailView: View {
    let session: SessionSummary
    let openSession: (String) -> Void

    @State private var messages: [ChatMessage] = []

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SoftPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("会话内容", systemImage: "text.bubble.fill")
                                .font(.headline)
                                .foregroundStyle(Color.warmBrown)
                            Text(session.createdAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                openSession(session.id)
                            } label: {
                                Label("继续对话", systemImage: "arrow.up.right.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.warmBrown)
                        }
                    }

                    if messages.isEmpty {
                        EmptyHintView(systemImage: "bubble.left.and.text.bubble.right", title: "没有读到消息", detail: "这次会话暂时没有消息记录。")
                    } else {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("会话详情")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard messages.isEmpty else { return }
            messages = (try? SQLiteDatabase().messages(sessionID: session.id)) ?? []
        }
    }
}

private struct ForestNotebookContent: View {
    @EnvironmentObject private var store: CompanionStore
    @Binding var selectedSpace: NotebookSpace
    let continueSession: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("笔记本空间", selection: $selectedSpace) {
                    ForEach(NotebookSpace.primarySpaces) { space in
                        Label(space.title, systemImage: space.systemImageName)
                            .tag(space)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 8)

                notebookContent
            }
            .background(WarmBackground())
            .navigationTitle("森林笔记本")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var notebookContent: some View {
        switch selectedSpace {
        case .chat:
            MessageDrawerContent()
        case .messages:
            RecentMessagesView()
        case .sessions:
            SessionHistoryView(openSession: continueSession)
        case .state:
            StateOverviewView(
                openChat: { selectedSpace = .chat },
                openMessages: { selectedSpace = .messages },
                openSessions: { selectedSpace = .sessions },
                openMemory: { selectedSpace = .memory },
                openJournals: { selectedSpace = .journals },
                openSourceSession: continueSession
            )
        case .memory:
            MemoryListView { sessionID in
                continueSession(sessionID)
            }
        case .journals:
            JournalHistoryView(openSession: continueSession)
        case .settings:
            SettingsView()
        }
    }
}

private enum NotebookSpace: String, CaseIterable, Identifiable {
    case chat
    case messages
    case sessions
    case state
    case memory
    case journals
    case settings

    var id: String { rawValue }

    static var primarySpaces: [NotebookSpace] {
        [.chat, .state, .memory, .settings]
    }

    var title: String {
        switch self {
        case .chat:
            return "信箱"
        case .messages:
            return "消息"
        case .sessions:
            return "会话"
        case .state:
            return "状态"
        case .memory:
            return "记忆"
        case .journals:
            return "总结"
        case .settings:
            return "设置"
        }
    }

    var systemImageName: String {
        switch self {
        case .chat:
            return "envelope.fill"
        case .messages:
            return "text.bubble.fill"
        case .sessions:
            return "clock.arrow.circlepath"
        case .state:
            return "heart.text.square.fill"
        case .memory:
            return "leaf.fill"
        case .journals:
            return "book.closed.fill"
        case .settings:
            return "gearshape.fill"
        }
    }

}

private struct SessionControlPanel: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("自动形态", systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text("始终开启")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warmBrown)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.62), in: Capsule())
                }

                HStack(spacing: 10) {
                    Button {
                        store.startNewSession()
                    } label: {
                        Label("新夜谈", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.warmBrown)
                    .disabled(store.isSending)

                    Button {
                        Task {
                            await store.closeCurrentSession()
                        }
                    } label: {
                        Label("结束总结", systemImage: "checkmark.seal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.warmBrown)
                    .disabled(store.isSending)
                }

                if let sessionNotice = store.sessionNotice {
                    Text(sessionNotice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct CharacterPicker: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(CompanionFixtures.characters) { character in
                    Button {
                        store.selectedCharacterID = character.id
                    } label: {
                        VStack(spacing: 8) {
                            CharacterAvatar(character: character, size: 58)
                            Text(character.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            character.id == store.selectedCharacterID
                                ? character.bubbleColor
                                : Color.white.opacity(0.55),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct MessageBubble: View {
    @EnvironmentObject private var store: CompanionStore
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == .user
        let character = store.character(id: message.characterID) ?? store.selectedCharacter
        VStack(alignment: isUser ? .trailing : .leading, spacing: 7) {
            if let routeSummary = message.routeSummary, !routeSummary.isEmpty {
                Label(routeSummary, systemImage: "wand.and.stars")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.warmBrown)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.56), in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 10) {
                if !isUser {
                    CharacterAvatar(character: character, size: 40, expressionID: message.expressionID)
                }

                VStack(alignment: .leading, spacing: 9) {
                    if !isUser, message.hasGroupMetadata {
                        MessageMetaRow(groupRole: message.groupRole, action: message.action)
                    }

                    Text(message.content)
                        .font(.body)
                        .lineSpacing(4)
                        .foregroundStyle(Color.nightInk)
                        .fixedSize(horizontal: false, vertical: true)

                    if !message.knowledgeCards.isEmpty {
                        KnowledgeCardStrip(cards: message.knowledgeCards)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(
                    isUser ? Color.white.opacity(0.82) : character.bubbleColor,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)

                if isUser {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.warmBrown)
                }
            }
        }
    }
}

private struct MessageMetaRow: View {
    let groupRole: String
    let action: String

    var body: some View {
        HStack(spacing: 6) {
            if let roleLabel {
                Text(roleLabel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.nightInk.opacity(0.76))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.42), in: Capsule())
            }

            if let actionIcon {
                Image(systemName: actionIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.warmBrown.opacity(0.82))
                    .accessibilityLabel(actionLabel ?? "小动物动作")
            }
        }
    }

    private var roleLabel: String? {
        switch groupRole.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "empathy", "empathic":
            return "共情"
        case "need", "pinpoint":
            return "需求"
        case "main":
            return "主回复"
        case "anchor":
            return "收束"
        case "":
            return nil
        default:
            return groupRole
        }
    }

    private var actionIcon: String? {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "soft_lean":
            return "arrow.down.forward.circle.fill"
        case "tilt_head":
            return "sparkle.magnifyingglass"
        case "slow_nod":
            return "checkmark.circle.fill"
        case "warm_glow":
            return "sparkles"
        case "steady_guard":
            return "shield.fill"
        case "small_breath":
            return "wind"
        case "":
            return nil
        default:
            return "circle.fill"
        }
    }

    private var actionLabel: String? {
        switch action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "soft_lean":
            return "轻轻靠近"
        case "tilt_head":
            return "歪头思考"
        case "slow_nod":
            return "慢慢点头"
        case "warm_glow":
            return "温暖发光"
        case "steady_guard":
            return "稳定守护"
        case "small_breath":
            return "陪你呼吸"
        default:
            return nil
        }
    }
}

private struct KnowledgeCardStrip: View {
    let cards: [KnowledgeCard]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("本轮参考知识卡", systemImage: "leaf.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.nightInk.opacity(0.68))

            FlowLayout(spacing: 6) {
                ForEach(cards) { card in
                    Text(card.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.warmBrown)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.45), in: Capsule())
                        .accessibilityLabel(card.concept.isEmpty ? card.title : "\(card.title)：\(card.concept)")
                }
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 280
        let layout = rows(in: maxWidth, subviews: subviews)
        return CGSize(width: maxWidth, height: layout.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> (height: CGFloat, rowCount: Int) {
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowCount = subviews.isEmpty ? 0 : 1

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
                rowCount += 1
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return (totalHeight, rowCount)
    }
}

private extension ChatMessage {
    var hasGroupMetadata: Bool {
        !groupRole.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct ComposerBar: View {
    @Binding var draft: String
    let isSending: Bool
    @FocusState.Binding var isFocused: Bool
    let dismiss: () -> Void
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("慢慢说一点...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button(action: dismiss) {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 23, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.softPaper.opacity(0.85))
            .accessibilityLabel("收起键盘")
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
            }
            .foregroundStyle(Color(hex: 0xffd27d))
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: 0x111725).opacity(0.74))
    }
}

private extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct TypingIndicator: View {
    let character: CompanionCharacter

    var body: some View {
        HStack(spacing: 10) {
            CharacterAvatar(character: character, size: 38)
            HStack(spacing: 6) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.warmBrown.opacity(0.45 + Double(index) * 0.15))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(character.bubbleColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityLabel("\(character.name)正在回应")
    }
}
