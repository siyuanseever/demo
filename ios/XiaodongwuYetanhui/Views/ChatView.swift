import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var draft = ""

    var body: some View {
        ZStack {
            WarmBackground()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionHeader(
                                title: "小动物夜谈会",
                                subtitle: "先把今晚的心事放在这里。你可以选择一个小动物，也可以之后交给系统自动选择。"
                            )
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
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: store.messages.count) {
                        if let lastID = store.messages.last?.id {
                            withAnimation(.snappy) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: store.isChatCheckInVisible) {
                        if store.isChatCheckInVisible {
                            withAnimation(.snappy) {
                                proxy.scrollTo("chat-emotion-check-in", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: store.isMonsterCareGameVisible) {
                        if store.isMonsterCareGameVisible {
                            withAnimation(.snappy) {
                                proxy.scrollTo("monster-care-game", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: store.isRecommendationVisible) {
                        if store.isRecommendationVisible {
                            withAnimation(.snappy) {
                                proxy.scrollTo("recommendation-card", anchor: .bottom)
                            }
                        }
                    }
                }
                ComposerBar(draft: $draft, isSending: store.isSending) {
                    let text = draft
                    draft = ""
                    Task {
                        await store.sendDraft(text)
                    }
                }
            }
        }
        .navigationTitle("夜谈")
        .navigationBarTitleDisplayMode(.inline)
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
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("慢慢说一点...", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
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
