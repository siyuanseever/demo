import SwiftUI

struct CompanionGardenView: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(title: "小动物们", subtitle: "每个角色都有不同的陪伴方式。后续的自动选角和互动游戏都会从这里长出来。")
                    ForEach(CompanionFixtures.characters) { character in
                        CompanionCard(character: character, isSelected: character.id == store.selectedCharacterID)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("小动物")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CompanionCard: View {
    @EnvironmentObject private var store: CompanionStore
    let character: CompanionCharacter
    let isSelected: Bool

    var body: some View {
        Button {
            store.selectedCharacterID = character.id
        } label: {
            SoftPanel {
                HStack(alignment: .center, spacing: 14) {
                    CharacterAvatar(character: character, size: 74)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(character.name)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Color.nightInk)
                            Text(character.animal)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.warmBrown)
                            }
                        }
                        Text(character.tagline)
                            .font(.callout)
                            .foregroundStyle(Color.nightInk)
                            .fixedSize(horizontal: false, vertical: true)
                        Label(character.voice, systemImage: character.systemImageName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}
