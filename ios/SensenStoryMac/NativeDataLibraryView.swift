import SwiftUI

private enum NativeDataTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case sessions = "会话"
    case memories = "记忆"
    case journals = "日记"
    case states = "长期状态"

    var id: String { rawValue }
}

struct NativeDataLibraryView: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @State private var tab: NativeDataTab = .overview

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本地资料")
                        .font(.title.bold())
                    Text("看见系统保存了什么，也能从历史会话继续说下去。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新本地资料", systemImage: "arrow.clockwise") {
                    store.loadLocalCache()
                }
            }
            .padding(24)

            Picker("资料类型", selection: $tab) {
                ForEach(NativeDataTab.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Divider()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview:
            NativeOverviewGrid()
        case .sessions:
            NativeSessionList()
        case .memories:
            NativeMemoryBrowser()
        case .journals:
            NativeJournalTimeline()
        case .states:
            NativeStateProfileGrid()
        }
    }
}

private struct NativeOverviewGrid: View {
    @EnvironmentObject private var store: NativeMacShellStore
    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                NativeMetricCard(title: "会话", value: store.snapshot.sessionCount, icon: "bubble.left.and.bubble.right")
                NativeMetricCard(title: "消息", value: store.snapshot.messageCount, icon: "text.bubble")
                NativeMetricCard(title: "记忆", value: store.snapshot.memoryCount, icon: "books.vertical")
                NativeMetricCard(title: "日记", value: store.snapshot.journalCount, icon: "book.closed")
                NativeMetricCard(title: "长期状态", value: store.stateProfiles.count, icon: "person.text.rectangle")
            }
            .padding(24)
        }
    }
}

private struct NativeSessionList: View {
    @EnvironmentObject private var store: NativeMacShellStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.sessions) { session in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "moon.stars.fill")
                            .foregroundStyle(.indigo)
                            .frame(width: 32, height: 32)
                            .background(Color.indigo.opacity(0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text(session.preview.isEmpty ? "一段夜谈" : session.preview)
                                .lineLimit(2)
                            HStack {
                                Text(session.createdAt)
                                Text("\(session.messageCount) 条消息")
                                if !session.endedAt.isEmpty { Text("已总结") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("继续") {
                            store.openSession(session.id)
                            NotificationCenter.default.post(name: .nativeOpenConversation, object: nil)
                        }
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
    }
}

private struct NativeMemoryBrowser: View {
    @EnvironmentObject private var store: NativeMacShellStore

    private var categories: [(String, [MemoryEntry])] {
        Dictionary(grouping: store.memories, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(categories, id: \.0) { category, memories in
                    DisclosureGroup {
                        VStack(spacing: 8) {
                            ForEach(memories) { memory in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(memory.subcategory).font(.caption.bold())
                                        Spacer()
                                        Text("重要度 \(memory.importance)").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(memory.content)
                                    if !memory.keywords.isEmpty {
                                        Text(memory.keywords.joined(separator: " · "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !memory.evidence.isEmpty {
                                        Text("依据：\(memory.evidence)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .padding(.top, 10)
                    } label: {
                        HStack {
                            Label(category, systemImage: "folder.fill")
                            Spacer()
                            Text("\(memories.count)").foregroundStyle(.secondary)
                        }
                        .font(.headline)
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
    }
}

private struct NativeJournalTimeline: View {
    @EnvironmentObject private var store: NativeMacShellStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(store.journals) { journal in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Label(journal.dominantEmotion.isEmpty ? "日记总结" : journal.dominantEmotion, systemImage: "book.closed.fill")
                                .font(.headline)
                            Spacer()
                            Text(journal.createdAt).font(.caption).foregroundStyle(.secondary)
                            Text("心情 \(journal.moodScore)")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(moodColor(journal.moodScore).opacity(0.14), in: Capsule())
                        }
                        Text(journal.summary)
                        if !journal.insights.isEmpty {
                            Label(journal.insights.joined(separator: "；"), systemImage: "lightbulb.fill")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        if !journal.suggestedNextStep.isEmpty {
                            Label(journal.suggestedNextStep, systemImage: "arrow.forward.circle.fill")
                                .font(.callout)
                        }
                        if !journal.keywords.isEmpty {
                            Text(journal.keywords.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
    }

    private func moodColor(_ score: Int) -> Color {
        score >= 2 ? .green : score >= -1 ? .orange : .red
    }
}

private struct NativeStateProfileGrid: View {
    @EnvironmentObject private var store: NativeMacShellStore
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(store.stateProfiles) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(profile.domain).font(.headline)
                            Spacer()
                            Text(profile.trend).font(.caption).foregroundStyle(.secondary)
                        }
                        if !profile.stage.isEmpty {
                            Text(profile.stage).font(.caption.bold()).foregroundStyle(.indigo)
                        }
                        Text(profile.summary)
                        ProgressView(value: Double(profile.intensity), total: 10)
                            .tint(profile.intensity >= 7 ? .orange : .green)
                        if !profile.supportStrategy.isEmpty {
                            Text("支持方式：\(profile.supportStrategy)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("更新于 \(profile.updatedAt)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(24)
        }
    }
}

private struct NativeMetricCard: View {
    let title: String
    let value: Int
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)").font(.title2.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
