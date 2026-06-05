import SwiftUI

struct MemoryListView: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "记忆叶片", subtitle: "长期有用的信息会被折叠成小叶片，方便之后的回应和复盘。")
                    if store.memories.isEmpty {
                        EmptyHintView(systemImage: "leaf", title: "还没有读到记忆", detail: "当数据库里有 active memories 时，这里会按重要性展示。")
                    } else {
                        ForEach(store.memories) { memory in
                            MemoryCard(memory: memory)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MemoryCard: View {
    let memory: MemoryEntry

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(memory.category, systemImage: "leaf.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.warmBrown)
                    Spacer()
                    Text("重要度 \(memory.importance)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(memory.content)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.nightInk)
                    .fixedSize(horizontal: false, vertical: true)
                if !memory.evidence.isEmpty {
                    Text(memory.evidence)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }
}
