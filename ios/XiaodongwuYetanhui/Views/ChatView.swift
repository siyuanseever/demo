import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var draft = ""
    @State private var isMessageDrawerVisible = false
    @State private var isSessionMenuVisible = false
    @State private var sceneNotice: String?
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack {
            NightCampBackground()
                .onTapGesture {
                    isComposerFocused = false
                    UIApplication.shared.dismissKeyboard()
                }

            VStack(spacing: 0) {
                Spacer(minLength: 10)

                CampfireStage(
                    openMailbox: {
                        isComposerFocused = false
                        isMessageDrawerVisible = true
                    },
                    openSessionNotebook: {
                        isComposerFocused = false
                        isSessionMenuVisible = true
                    },
                    toggleGroupMode: {
                        store.isGroupMode.toggle()
                        sceneNotice = store.isGroupMode ? "灯笼亮起，六只小动物会一起听。" : "灯笼变暗，先由一只小动物陪你。"
                    },
                    focusComposer: {
                        isComposerFocused = true
                        sceneNotice = "篝火在听。可以直接说一句。"
                    },
                    setNotice: { notice in
                        sceneNotice = notice
                    }
                )
                    .padding(.horizontal, 18)

                Spacer(minLength: 12)

                ChatStatusStrip(sceneNotice: sceneNotice)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)

                ComposerBar(
                    draft: $draft,
                    isSending: store.isSending,
                    isFocused: $isComposerFocused
                ) {
                    let text = draft
                    draft = ""
                    isComposerFocused = false
                    UIApplication.shared.dismissKeyboard()
                    Task {
                        await store.sendDraft(text)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
        .sheet(isPresented: $isMessageDrawerVisible) {
            MessageDrawerContent()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.light)
        }
        .confirmationDialog("夜谈小笔记", isPresented: $isSessionMenuVisible, titleVisibility: .visible) {
            Button(store.isGroupMode ? "收起群聊灯笼" : "点亮群聊灯笼") {
                store.isGroupMode.toggle()
                sceneNotice = store.isGroupMode ? "灯笼亮起，六只小动物会一起听。" : "灯笼变暗，先由一只小动物陪你。"
            }
            Button("翻开新的一页") {
                store.startNewSession()
                sceneNotice = "新的夜谈已经铺好。"
            }
            Button("把今晚收进总结") {
                Task {
                    await store.closeCurrentSession()
                }
            }
            .disabled(store.isSending)
            Button("取消", role: .cancel) {}
        }
        .onChange(of: store.isChatCheckInVisible) {
            if store.isChatCheckInVisible { isMessageDrawerVisible = true }
        }
        .onChange(of: store.isMonsterCareGameVisible) {
            if store.isMonsterCareGameVisible { isMessageDrawerVisible = true }
        }
        .onChange(of: store.isRecommendationVisible) {
            if store.isRecommendationVisible { isMessageDrawerVisible = true }
        }
    }
}

private struct CampfireStage: View {
    @EnvironmentObject private var store: CompanionStore
    let openMailbox: () -> Void
    let openSessionNotebook: () -> Void
    let toggleGroupMode: () -> Void
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

                Ellipse()
                    .fill(Color.white.opacity(0.055))
                    .frame(width: size.width * 0.86, height: size.height * 0.54)
                    .blur(radius: 4)
                    .position(x: size.width * 0.5, y: size.height * 0.6)

                ForEach(Array(CompanionFixtures.characters.enumerated()), id: \.element.id) { index, character in
                    let point = position(for: index, in: size)
                    SceneAnimalButton(
                        character: character,
                        isSelected: character.id == store.selectedCharacterID
                    ) {
                        store.selectedCharacterID = character.id
                        setNotice("\(character.name)靠近了一点。")
                    }
                    .position(point)
                }

                MailboxObject(messageCount: store.messages.count, action: openMailbox)
                    .position(x: size.width * 0.15, y: size.height * 0.82)

                NotebookObject(action: openSessionNotebook)
                    .position(x: size.width * 0.86, y: size.height * 0.82)

                GroupLanternObject(isGroupMode: store.isGroupMode, action: toggleGroupMode)
                    .position(x: size.width * 0.13, y: size.height * 0.25)

                CampfireButton(action: focusComposer)
                    .position(x: size.width * 0.5, y: size.height * 0.58)
            }
        }
        .frame(height: 500)
        .frame(maxWidth: .infinity)
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
                            ChatQuickActions()
                            InteractionOfferShelf()
                            CharacterPicker()
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
                            ForEach(store.messages) { message in
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
                        }
                        .padding(18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: store.messages.count) {
                        if let lastID = store.messages.last?.id {
                            withAnimation(.snappy) {
                                proxy.scrollTo(lastID, anchor: .bottom)
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

private struct SessionControlPanel: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("会话", systemImage: "moon.stars.fill")
                        .font(.headline)
                    Spacer()
                    Toggle(isOn: $store.isGroupMode) {
                        Label("群聊", systemImage: "person.3.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(Color.warmBrown)
                    .accessibilityLabel("群聊模式")
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
                    CharacterAvatar(character: character, size: 40)
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
            Button {
                isFocused = false
                UIApplication.shared.dismissKeyboard()
            } label: {
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    isFocused = false
                    UIApplication.shared.dismissKeyboard()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
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
