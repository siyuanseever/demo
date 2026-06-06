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
                            NavigationLink {
                                MemoryDetailView(memory: memory)
                            } label: {
                                MemoryCard(memory: memory)
                            }
                            .buttonStyle(.plain)
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

private struct MemoryDetailView: View {
    let memory: MemoryEntry

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SoftPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(memory.category, systemImage: "leaf.fill")
                                .font(.headline)
                                .foregroundStyle(Color.warmBrown)
                            Text(memory.subcategory.isEmpty ? "general" : memory.subcategory)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.68), in: Capsule())
                            Text(memory.content)
                                .font(.title3.weight(.semibold))
                                .lineSpacing(5)
                                .foregroundStyle(Color.nightInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SoftPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("证据", systemImage: "quote.bubble.fill")
                                .font(.headline)
                            Text(memory.evidence.isEmpty ? "这条记忆暂时没有单独保存证据。" : memory.evidence)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SoftPanel {
                        HStack {
                            Label("重要度 \(memory.importance)", systemImage: "star.fill")
                            Spacer()
                            Text(memory.updatedAt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.nightInk)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("记忆详情")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.light)
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
