import SwiftUI

struct EmotionCheckInView: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        EmotionCheckInCard(
            response: store.checkInResponse,
            saveTitle: "收进今晚"
        ) { monster, intensity, note in
            store.saveEmotionCheckIn(monster: monster, intensity: intensity, note: note)
        }
    }
}

struct EmotionCheckInCard: View {
    @State private var selectedMonsterID = CompanionFixtures.emotionMonsters[0].id
    @State private var intensity = 0.45
    @State private var note = ""
    let response: String
    let saveTitle: String
    let onSave: (EmotionMonster, Double, String) -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Label("情绪小怪兽", systemImage: "face.smiling.inverse")
                        .font(.headline)
                    Spacer()
                    Text(selectedMonster.colorName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(CompanionFixtures.emotionMonsters) { monster in
                            EmotionMonsterButton(
                                monster: monster,
                                isSelected: monster.id == selectedMonsterID
                            ) {
                                selectedMonsterID = monster.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }

                Text(selectedMonster.prompt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("强度")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text(intensityLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $intensity, in: 0...1)
                        .tint(selectedMonster.color)
                }

                TextField("给它留一句话，也可以空着", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    onSave(selectedMonster, intensity, note)
                } label: {
                    Label(saveTitle, systemImage: "tray.and.arrow.down.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.warmBrown)

                Text(response)
                    .font(.callout)
                    .foregroundStyle(Color.nightInk)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedMonster.color.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedMonster: EmotionMonster {
        CompanionFixtures.emotionMonsters.first { $0.id == selectedMonsterID } ?? CompanionFixtures.emotionMonsters[0]
    }

    private var intensityLabel: String {
        EmotionCheckIn(monster: selectedMonster, intensity: intensity, note: "", createdAt: Date()).intensityLabel
    }
}

private struct EmotionMonsterButton: View {
    let monster: EmotionMonster
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(monster.color)
                    Image(systemName: monster.systemImageName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.nightInk.opacity(0.72))
                }
                .frame(width: 52, height: 52)
                .overlay {
                    Circle()
                        .stroke(isSelected ? Color.warmBrown : Color.white.opacity(0.7), lineWidth: isSelected ? 2 : 1)
                }
                Text(monster.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.nightInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                isSelected ? Color.white.opacity(0.86) : Color.white.opacity(0.48),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(monster.name)
    }
}
