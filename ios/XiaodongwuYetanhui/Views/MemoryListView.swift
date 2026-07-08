import SwiftUI

struct MemoryListView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var sortMode: MemorySortMode = .updated

    let openSession: (String) -> Void

    init(openSession: @escaping (String) -> Void = { _ in }) {
        self.openSession = openSession
    }

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "记忆叶片", subtitle: "长期有用的信息会被折叠成小叶片，方便之后的回应和复盘。")
                    Picker("记忆排序", selection: $sortMode) {
                        ForEach(MemorySortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if store.memories.isEmpty {
                        EmptyHintView(systemImage: "leaf", title: "还没有读到记忆", detail: "当数据库里有 active memories 时，这里会按重要性展示。")
                    } else if sortMode == .category {
                        ForEach(groupedMemories, id: \.category) { group in
                            MemoryCategorySection(category: group.category, memories: group.memories, openSession: openSession)
                        }
                    } else {
                        ForEach(sortedMemories) { memory in
                            NavigationLink {
                                MemoryDetailView(memory: memory, openSession: openSession)
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
        .task {
            await store.syncIfNeeded()
        }
    }

    private var sortedMemories: [MemoryEntry] {
        store.memories.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.importance > $1.importance
            }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private var groupedMemories: [(category: String, memories: [MemoryEntry])] {
        Dictionary(grouping: store.memories, by: \.category)
            .map { category, memories in
                (
                    category,
                    memories.sorted {
                        if $0.subcategory == $1.subcategory {
                            return $0.importance > $1.importance
                        }
                        return $0.subcategory < $1.subcategory
                    }
                )
            }
            .sorted { $0.category < $1.category }
    }
}

private enum MemorySortMode: String, CaseIterable, Identifiable {
    case updated
    case category

    var id: String { rawValue }

    var title: String {
        switch self {
        case .updated:
            return "按更新"
        case .category:
            return "按分类"
        }
    }
}

private struct MemoryCategorySection: View {
    let category: String
    let memories: [MemoryEntry]
    let openSession: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(category, systemImage: "folder.fill")
                .font(.headline)
                .foregroundStyle(Color.warmBrown)

            ForEach(memories) { memory in
                NavigationLink {
                    MemoryDetailView(memory: memory, openSession: openSession)
                } label: {
                    MemoryCard(memory: memory)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MemoryDetailView: View {
    let memory: MemoryEntry
    let openSession: (String) -> Void

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
                                .background(Color.overlayHeavy, in: Capsule())
                            Text(memory.content)
                                .font(.title3.weight(.semibold))
                                .lineSpacing(5)
                                .foregroundStyle(Color.nightInk)
                                .fixedSize(horizontal: false, vertical: true)
                            if !memory.keywords.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 7) {
                                        ForEach(memory.keywords, id: \.self) { keyword in
                                            Text(keyword)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(Color.warmBrown)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 5)
                                                .background(Color.overlayHeavy, in: Capsule())
                                        }
                                    }
                                }
                            }
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
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label("重要度 \(memory.importance)", systemImage: "star.fill")
                                Spacer()
                                Text(memory.updatedAt)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.nightInk)

                            if !memory.sourceSessionID.isEmpty {
                                NavigationLink {
                                    HistoricalSessionDestination(
                                        sessionID: memory.sourceSessionID,
                                        continueSession: openSession
                                    )
                                } label: {
                                    Label("查看来源会话", systemImage: "arrow.up.right.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(Color.warmBrown)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("记忆详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MemoryCard: View {
    let memory: MemoryEntry

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Label(memory.category, systemImage: "leaf.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.warmBrown)
                        if !memory.subcategory.isEmpty && memory.subcategory != "general" {
                            Text("· \(memory.subcategory)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                if !memory.keywords.isEmpty {
                    Text(memory.keywords.prefix(4).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Color.warmBrown.opacity(0.72))
                        .lineLimit(1)
                }
                HStack {
                    Spacer()
                    Text(relativeTime(from: memory.updatedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
            }
        }
    }
}

private func relativeTime(from dateString: String) -> String {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: dateString) else { return dateString }
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "刚刚" }
    if interval < 3600 { return "\(Int(interval / 60))分钟前" }
    if interval < 86400 { return "\(Int(interval / 3600))小时前" }
    if interval < 172800 { return "昨天" }
    if interval < 604800 { return "\(Int(interval / 86400))天前" }
    if interval < 2592000 { return "\(Int(interval / 604800))周前" }
    let df = DateFormatter()
    df.dateStyle = .short
    df.timeStyle = .none
    return df.string(from: date)
}
