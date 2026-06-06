import SwiftUI
import UIKit

struct ChatView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var draft = ""
    @State private var isMessageDrawerVisible = false
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
                ChatTopBar(
                    isMessageDrawerVisible: $isMessageDrawerVisible,
                    dismissKeyboard: { isComposerFocused = false }
                )
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer(minLength: 10)

                CampfireStage(
                    openMailbox: {
                        isComposerFocused = false
                        isMessageDrawerVisible = true
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

                ChatStatusStrip(sceneNotice: sceneNotice, openDrawer: { isMessageDrawerVisible = true })
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
        .navigationTitle("夜谈")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
        .sheet(isPresented: $isMessageDrawerVisible) {
            MessageDrawerContent()
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.light)
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

private struct ChatTopBar: View {
    @EnvironmentObject private var store: CompanionStore
    @Binding var isMessageDrawerVisible: Bool
    let dismissKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("小动物夜谈会")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.softPaper)
                Text(store.isGroupMode ? "六只小动物围在火边听你说" : "\(store.selectedCharacter.name)在火边陪你")
                    .font(.caption)
                    .foregroundStyle(Color.softPaper.opacity(0.78))
            }

            Spacer()

            Button {
                store.isGroupMode.toggle()
            } label: {
                Image(systemName: store.isGroupMode ? "person.3.fill" : "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.isGroupMode ? Color(hex: 0xffd27d) : Color.softPaper)
            .background(Color.white.opacity(store.isGroupMode ? 0.22 : 0.14), in: Circle())
            .accessibilityLabel(store.isGroupMode ? "关闭群聊模式" : "开启群聊模式")
        }
    }
}

private struct CampfireStage: View {
    @EnvironmentObject private var store: CompanionStore
    let openMailbox: () -> Void
    let focusComposer: () -> Void
    let setNotice: (String) -> Void

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                MoonAndStars {
                    setNotice("今晚的天空很安静。后续这里会接入天气和月相。")
                }

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: side * 0.92, height: side * 0.92)
                    .blur(radius: 2)

                ForEach(Array(CompanionFixtures.characters.enumerated()), id: \.element.id) { index, character in
                    let point = position(for: index, side: side)
                    SceneAnimalButton(
                        character: character,
                        isSelected: character.id == store.selectedCharacterID
                    ) {
                        store.selectedCharacterID = character.id
                        setNotice("\(character.name)靠近了一点。")
                    }
                    .position(x: geometry.size.width / 2 + point.x, y: geometry.size.height / 2 + point.y)
                }

                MailboxObject(messageCount: store.messages.count, action: openMailbox)
                    .position(x: geometry.size.width / 2 - side * 0.34, y: geometry.size.height / 2 + side * 0.29)

                CampfireButton(action: focusComposer)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + side * 0.04)
            }
        }
        .frame(height: 430)
        .frame(maxWidth: .infinity)
    }

    private func position(for index: Int, side: CGFloat) -> CGPoint {
        let radius = side * 0.32
        let angles: [CGFloat] = [-130, -78, -28, 28, 78, 130]
        let radians = angles[index] * .pi / 180
        return CGPoint(x: cos(radians) * radius, y: sin(radians) * radius)
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
            .offset(x: 110, y: -178)
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
            CGSize(width: -150, height: -175),
            CGSize(width: -82, height: -134),
            CGSize(width: 12, height: -190),
            CGSize(width: 155, height: -112),
            CGSize(width: -170, height: -35),
            CGSize(width: 170, height: 35),
            CGSize(width: -108, height: 132),
            CGSize(width: 88, height: 150),
            CGSize(width: 22, height: 114),
        ]
        return offsets[index]
    }
}

private struct SceneAnimalButton: View {
    let character: CompanionCharacter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                CharacterAvatar(character: character, size: isSelected ? 66 : 56)
                    .shadow(color: isSelected ? character.bubbleColor.opacity(0.72) : Color.black.opacity(0.16), radius: isSelected ? 16 : 8)
                Text(character.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.softPaper.opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(isSelected ? 0.28 : 0.16), in: Capsule())
            }
            .contentShape(Rectangle())
            .frame(minWidth: 74, minHeight: 86)
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
    let openDrawer: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: openDrawer) {
                Label("\(store.messages.count)", systemImage: "bubble.left.and.bubble.right.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.softPaper)
            .background(Color.white.opacity(0.14), in: Capsule())

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
            } else {
                Text(store.isGroupMode ? "群聊模式已开启" : "轻声说，火边会接住")
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
