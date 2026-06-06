import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var draft = ""
    @State private var isMessageDrawerVisible = false
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        ZStack {
            NightCampBackground()
                .onTapGesture {
                    isComposerFocused = false
                }

            VStack(spacing: 0) {
                ChatTopBar(
                    isMessageDrawerVisible: $isMessageDrawerVisible,
                    dismissKeyboard: { isComposerFocused = false }
                )
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer(minLength: 10)

                CampfireStage()
                    .padding(.horizontal, 18)

                Spacer(minLength: 12)

                ChatStatusStrip(openDrawer: { isMessageDrawerVisible = true })
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
                dismissKeyboard()
                isMessageDrawerVisible = true
            } label: {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.softPaper)
            .background(Color.white.opacity(0.14), in: Circle())
            .accessibilityLabel("打开夜谈信箱")

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

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                MoonAndStars()

                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: side * 0.92, height: side * 0.92)
                    .blur(radius: 2)

                ForEach(Array(CompanionFixtures.characters.enumerated()), id: \.element.id) { index, character in
                    let point = position(for: index, side: side)
                    Button {
                        store.selectedCharacterID = character.id
                    } label: {
                        VStack(spacing: 5) {
                            CharacterAvatar(character: character, size: character.id == store.selectedCharacterID ? 62 : 54)
                            Text(character.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.softPaper.opacity(0.86))
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: geometry.size.width / 2 + point.x, y: geometry.size.height / 2 + point.y)
                    .accessibilityLabel("选择\(character.name)")
                }

                CampfireSymbol()
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
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xfff3c2).opacity(0.9))
                .frame(width: 58, height: 58)
                .offset(x: 110, y: -178)
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

private struct CampfireSymbol: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color.black.opacity(0.28))
                .frame(width: 150, height: 38)
                .offset(y: 52)
                .blur(radius: 8)

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
        .accessibilityLabel("深夜篝火")
    }
}

private struct ChatStatusStrip: View {
    @EnvironmentObject private var store: CompanionStore
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
        HStack(alignment: .bottom, spacing: 10) {
            if !isUser {
                CharacterAvatar(character: character, size: 40)
            }
            Text(message.content)
                .font(.body)
                .lineSpacing(4)
                .foregroundStyle(Color.nightInk)
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
