import Charts
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
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 12) {
                            if let journal = store.journals.first(where: { $0.sessionID == session.id }) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("会后日记", systemImage: "book.closed.fill")
                                        .font(.caption.bold())
                                    Text(journal.summary)
                                    if !journal.insights.isEmpty {
                                        Text("洞察：\(journal.insights.joined(separator: "；"))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !journal.suggestedNextStep.isEmpty {
                                        Label(journal.suggestedNextStep, systemImage: "arrow.forward.circle.fill")
                                            .font(.caption)
                                    }
                                }
                                .padding(12)
                                .background(Color.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
                            }

                            let linkedMemories = store.memories.filter { $0.sourceSessionID == session.id }
                            if !linkedMemories.isEmpty {
                                VStack(alignment: .leading, spacing: 7) {
                                    Label("关联记忆 · \(linkedMemories.count)", systemImage: "brain.head.profile")
                                        .font(.caption.bold())
                                    ForEach(linkedMemories) { memory in
                                        Text("• \(memory.content)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Button("继续这段夜谈", systemImage: "arrowshape.turn.up.left.fill") {
                                store.openSession(session.id)
                                NotificationCenter.default.post(name: .nativeOpenConversation, object: nil)
                            }
                        }
                        .padding(.top, 12)
                    } label: {
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
                                    let memoryCount = store.memories.filter { $0.sourceSessionID == session.id }.count
                                    if memoryCount > 0 { Text("\(memoryCount) 条记忆") }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
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

private enum NativeMemoryViewMode: String, CaseIterable, Identifiable {
    case categories = "按分类"
    case recent = "最近更新"

    var id: String { rawValue }
}

private struct NativeMemoryBrowser: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @State private var mode: NativeMemoryViewMode = .categories

    private var categories: [(String, [MemoryEntry])] {
        Dictionary(grouping: store.memories, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("查看方式", selection: $mode) {
                ForEach(NativeMemoryViewMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .padding(.top, 18)

            ScrollView {
                LazyVStack(spacing: 12) {
                    if mode == .categories {
                        ForEach(categories, id: \.0) { category, memories in
                            DisclosureGroup {
                                VStack(spacing: 9) {
                                    ForEach(subcategories(memories), id: \.0) { subcategory, items in
                                        DisclosureGroup {
                                            VStack(spacing: 8) {
                                                ForEach(items) { memory in
                                                    NativeMemoryCard(memory: memory)
                                                }
                                            }
                                            .padding(.top, 8)
                                        } label: {
                                            HStack {
                                                Text(subcategory)
                                                Spacer()
                                                Text("\(items.count)").foregroundStyle(.secondary)
                                            }
                                            .font(.callout.bold())
                                        }
                                        .padding(10)
                                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
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
                    } else {
                        ForEach(store.memories.sorted { $0.updatedAt > $1.updatedAt }) { memory in
                            NativeMemoryCard(memory: memory)
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private func subcategories(_ memories: [MemoryEntry]) -> [(String, [MemoryEntry])] {
        Dictionary(grouping: memories, by: \.subcategory)
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }
}

private struct NativeJournalTimeline: View {
    @EnvironmentObject private var store: NativeMacShellStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !store.journals.isEmpty {
                    NativeMoodChart(journals: store.journals)
                }
                ForEach(journalWeeks, id: \.0) { week, journals in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(week)
                            .font(.headline)
                        ForEach(journals) { journal in
                            NativeJournalCard(journal: journal)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var journalWeeks: [(String, [JournalEntry])] {
        Dictionary(grouping: store.journals) { NativeDateFormat.weekLabel($0.createdAt) }
            .map { ($0.key, $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { ($0.1.first?.createdAt ?? "") > ($1.1.first?.createdAt ?? "") }
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
                        if !profile.evidence.isEmpty {
                            Text("依据：\(profile.evidence)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("置信度 \(Int(profile.confidence * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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

private struct NativeMemoryCard: View {
    let memory: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(memory.category) / \(memory.subcategory)")
                    .font(.caption.bold())
                Spacer()
                Text("重要度 \(memory.importance)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
            HStack {
                if !memory.updatedAt.isEmpty { Text("更新于 \(memory.updatedAt)") }
                if !memory.sourceSessionID.isEmpty { Text("来源会话 \(memory.sourceSessionID.prefix(8))") }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NativeJournalCard: View {
    let journal: JournalEntry

    var body: some View {
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
                    .background(NativeMoodColor.color(journal.moodScore).opacity(0.14), in: Capsule())
            }
            Text(journal.summary)
            if !journal.emotionCurve.isEmpty {
                Text("情绪变化：\(journal.emotionCurve.joined(separator: " → "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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

private struct NativeMoodChart: View {
    let journals: [JournalEntry]

    private var points: [NativeMoodPoint] {
        journals.reversed().enumerated().map { index, journal in
            NativeMoodPoint(index: index, journal: journal)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("心情轨迹", systemImage: "chart.xyaxis.line")
                .font(.headline)
            Chart(points) { point in
                LineMark(
                    x: .value("记录", point.index),
                    y: .value("心情", point.journal.moodScore)
                )
                .foregroundStyle(Color.chartLineAccent)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("记录", point.index),
                    y: .value("心情", point.journal.moodScore)
                )
                .foregroundStyle(NativeMoodColor.color(point.journal.moodScore))
            }
            .chartYScale(domain: -5...5)
            .chartXAxis(.hidden)
            .frame(height: 150)
        }
        .padding(16)
        .background(Color.cardBackground.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct NativeMoodPoint: Identifiable {
    let index: Int
    let journal: JournalEntry

    var id: String { journal.id }
}

private enum NativeMoodColor {
    static func color(_ score: Int) -> Color {
        score >= 2 ? .moodPositive : score >= -1 ? .moodNeutral : .moodNegative
    }
}

private enum NativeDateFormat {
    static func weekLabel(_ value: String) -> String {
        guard let date = date(value) else { return "较早的日记" }
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else { return "较早的日记" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        let end = calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end
        return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
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
