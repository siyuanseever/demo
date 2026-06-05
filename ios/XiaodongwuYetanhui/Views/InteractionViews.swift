import SwiftUI

struct ChatQuickActions: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.requestChatEmotionCheckIn()
            } label: {
                Label("小怪兽", systemImage: "face.smiling.inverse")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Color.warmBrown)

            Text("需要时，把感受先变成一个能碰到的小东西。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InteractionOfferShelf: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("今晚可以这样开始", systemImage: "hand.tap.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nightInk)
                Spacer()
                Text("可跳过")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(store.interactionOffers) { offer in
                        InteractionOfferCard(offer: offer)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct InteractionOfferCard: View {
    @EnvironmentObject private var store: CompanionStore
    let offer: CompanionInteractionOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(offer.tint.opacity(0.65))
                    Image(systemName: offer.systemImageName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.nightInk.opacity(0.72))
                }
                .frame(width: 38, height: 38)

                Spacer()

                Button {
                    store.dismissInteractionOffer(offer)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("隐藏\(offer.title)")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(offer.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.nightInk)
                    .lineLimit(1)
                Text(offer.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    await store.acceptInteractionOffer(offer)
                }
            } label: {
                Label(offer.actionTitle, systemImage: "plus.bubble.fill")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.warmBrown)
            .disabled(store.isSending)
        }
        .padding(13)
        .frame(width: 188, alignment: .leading)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(offer.tint.opacity(0.75), lineWidth: 1)
        }
    }
}

struct ChatEmotionCheckInCard: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                Text("先不急着解释，给此刻选一只小怪兽。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.dismissChatEmotionCheckIn()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("暂时不做小怪兽 check-in")
            }

            EmotionCheckInCard(
                response: "选完以后，我会把它放进这段对话里，作为一个更柔软的上下文。",
                saveTitle: "放进对话"
            ) { monster, intensity, note in
                Task {
                    await store.completeChatEmotionCheckIn(monster: monster, intensity: intensity, note: note)
                }
            }
        }
    }
}

struct MonsterCareGameCard: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var selectedMonsterID = CompanionFixtures.emotionMonsters[1].id
    @State private var customName = ""
    @State private var selectedSafePlaceID = CompanionFixtures.monsterSafePlaces[0].id
    @State private var selectedActionID = CompanionFixtures.monsterCareActions[0].id
    @State private var note = ""

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("情绪怪兽小屋", systemImage: "hands.sparkles.fill")
                            .font(.headline)
                        Text("给它一个名字、一个位置和一个动作。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.dismissMonsterCareGame()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("关闭小怪兽照顾站")
                }

                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(selectedMonster.color.opacity(0.72))
                        Image(systemName: selectedSafePlace.systemImageName)
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.42))
                        Image(systemName: selectedMonster.systemImageName)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(Color.nightInk.opacity(0.74))
                    }
                    .frame(width: 86, height: 86)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayMonsterName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.nightInk)
                        Text("\(selectedSafePlace.title) · \(selectedAction.title)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.warmBrown)
                        Text(selectedAction.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(selectedMonster.color.opacity(0.32), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("1. 选择一只")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(CompanionFixtures.emotionMonsters) { monster in
                                GameChoiceButton(
                                    title: monster.name,
                                    systemImageName: monster.systemImageName,
                                    tint: monster.color,
                                    isSelected: monster.id == selectedMonsterID
                                ) {
                                    selectedMonsterID = monster.id
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("2. 给它一个小名")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("可以叫它：软软、刺刺、雨团...", text: $customName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("3. 把它安置在哪里")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CompanionFixtures.monsterSafePlaces) { safePlace in
                            GameChoiceButton(
                                title: safePlace.title,
                                systemImageName: safePlace.systemImageName,
                                tint: selectedMonster.color,
                                isSelected: safePlace.id == selectedSafePlaceID
                            ) {
                                selectedSafePlaceID = safePlace.id
                            }
                        }
                    }
                    Text(selectedSafePlace.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("4. 给它一个动作")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(CompanionFixtures.monsterCareActions) { action in
                            GameChoiceButton(
                                title: action.title,
                                systemImageName: action.systemImageName,
                                tint: selectedMonster.color,
                                isSelected: action.id == selectedActionID
                            ) {
                                selectedActionID = action.id
                            }
                        }
                    }
                }

                TextField("给这个动作留一句话，也可以空着", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    Task {
                        await store.completeMonsterCareGame(
                            monster: selectedMonster,
                            action: selectedAction,
                            safePlace: selectedSafePlace,
                            customName: customName,
                            note: note
                        )
                    }
                } label: {
                    Label("带回对话", systemImage: "arrowshape.turn.up.left.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.warmBrown)
                .disabled(store.isSending)
            }
        }
    }

    private var selectedMonster: EmotionMonster {
        CompanionFixtures.emotionMonsters.first { $0.id == selectedMonsterID } ?? CompanionFixtures.emotionMonsters[0]
    }

    private var selectedAction: MonsterCareAction {
        CompanionFixtures.monsterCareActions.first { $0.id == selectedActionID } ?? CompanionFixtures.monsterCareActions[0]
    }

    private var selectedSafePlace: MonsterSafePlace {
        CompanionFixtures.monsterSafePlaces.first { $0.id == selectedSafePlaceID } ?? CompanionFixtures.monsterSafePlaces[0]
    }

    private var displayMonsterName: String {
        let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? selectedMonster.name : trimmedName
    }
}

struct RecommendationCard: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        if let recommendation = store.latestRecommendation {
            SoftPanel {
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("今晚推荐", systemImage: "sparkles.rectangle.stack.fill")
                                .font(.headline)
                            Text("先只选一个陪伴，不把夜晚塞满。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.dismissRecommendation()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("关闭今晚推荐")
                    }

                    HStack(alignment: .center, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(recommendation.tint.opacity(0.62))
                            Image(systemName: recommendation.medium.systemImageName)
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(Color.nightInk.opacity(0.72))
                        }
                        .frame(width: 82, height: 82)

                        VStack(alignment: .leading, spacing: 7) {
                            Text(recommendation.medium.displayName)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.warmBrown)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.68), in: Capsule())
                            Text(recommendation.displayTitle)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.nightInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(recommendation.tint.opacity(0.25), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(recommendation.reason)
                            .font(.callout)
                            .foregroundStyle(Color.nightInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(recommendation.practice, systemImage: "hand.point.up.left.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        ForEach(RecommendationMedium.allCases, id: \.self) { medium in
                            Button {
                                store.requestRecommendation(preferredMedium: medium)
                            } label: {
                                Label(medium.displayName, systemImage: medium.systemImageName)
                                    .font(.caption.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(medium == recommendation.medium ? Color.warmBrown : Color.nightInk.opacity(0.45))
                            .disabled(store.isSending)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            store.requestRecommendation(preferredMedium: recommendation.medium)
                        } label: {
                            Label("换一个", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.warmBrown)
                        .disabled(store.isSending)

                        Button {
                            Task {
                                await store.sendRecommendationToChat()
                            }
                        } label: {
                            Label("带回对话", systemImage: "arrowshape.turn.up.left.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.warmBrown)
                        .disabled(store.isSending)
                    }
                }
            }
        }
    }
}

private struct GameChoiceButton: View {
    let title: String
    let systemImageName: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImageName)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 18)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.nightInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? tint.opacity(0.55) : Color.white.opacity(0.58),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.warmBrown : Color.white.opacity(0.7), lineWidth: isSelected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
