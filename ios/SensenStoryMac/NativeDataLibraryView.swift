import Charts
import SwiftUI

private enum NativeDataTab: String, CaseIterable, Identifiable {
    case overview = "概览"
    case sessions = "会话"
    case memories = "记忆"
    case journals = "日记"
    case states = "长期状态"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .sessions: "bubble.left.and.bubble.right.fill"
        case .memories: "books.vertical.fill"
        case .journals: "book.closed.fill"
        case .states: "person.text.rectangle.fill"
        }
    }
}

struct NativeDataLibraryView: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @State private var tab: NativeDataTab = .overview
    @State private var query = ""
    @State private var selectedMemoryCategory: String?

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
                if tab != .overview {
                    TextField("搜索\(tab.rawValue)", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                Button("刷新本地资料", systemImage: "arrow.clockwise") {
                    store.loadLocalCache()
                }
            }
            .padding(24)

            Picker("资料类型", selection: $tab) {
                ForEach(NativeDataTab.allCases) { item in
                    Label(item.rawValue, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Divider()
            content
        }
        .onChange(of: tab) { _, newTab in
            query = ""
            if newTab != .memories {
                selectedMemoryCategory = nil
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview:
            NativeOverviewGrid(tab: $tab, selectedMemoryCategory: $selectedMemoryCategory)
        case .sessions:
            NativeSessionList(query: query)
        case .memories:
            NativeMemoryBrowser(query: query, selectedCategory: $selectedMemoryCategory)
        case .journals:
            NativeJournalTimeline(query: query)
        case .states:
            NativeStateProfileGrid(query: query)
        }
    }
}

private struct NativeOverviewGrid: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @Binding var tab: NativeDataTab
    @Binding var selectedMemoryCategory: String?
    private let metricColumns = [GridItem(.adaptive(minimum: 190), spacing: 14)]
    private let sectionColumns = [GridItem(.adaptive(minimum: 360), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: metricColumns, spacing: 14) {
                    NativeMetricCard(title: "会话", value: store.snapshot.sessionCount, icon: "bubble.left.and.bubble.right") { tab = .sessions }
                    NativeMetricCard(title: "消息", value: store.snapshot.messageCount, icon: "text.bubble") { tab = .sessions }
                    NativeMetricCard(title: "记忆", value: store.snapshot.memoryCount, icon: "books.vertical") {
                        selectedMemoryCategory = nil
                        tab = .memories
                    }
                    NativeMetricCard(title: "日记", value: store.snapshot.journalCount, icon: "book.closed") { tab = .journals }
                    NativeMetricCard(title: "长期状态", value: store.stateProfiles.count, icon: "person.text.rectangle") { tab = .states }
                }

                LazyVGrid(columns: sectionColumns, spacing: 14) {
                    NativeRecentDataCard(tab: $tab, selectedMemoryCategory: $selectedMemoryCategory)
                    NativeMemoryMapCard(tab: $tab, selectedMemoryCategory: $selectedMemoryCategory)
                }
            }
            .padding(24)
        }
    }
}

private struct NativeRecentDataCard: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @Binding var tab: NativeDataTab
    @Binding var selectedMemoryCategory: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("最近更新", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            NativeOverviewDataRow(
                title: "最近夜谈",
                detail: store.sessions.first.map { NativeDateFormat.displayDate($0.createdAt) } ?? "暂无",
                summary: store.sessions.first?.preview ?? "完成一次夜谈后会出现在这里。",
                icon: "bubble.left.and.bubble.right.fill"
            ) { tab = .sessions }
            Divider()
            NativeOverviewDataRow(
                title: "最近日记",
                detail: store.journals.first.map { NativeDateFormat.displayDate($0.createdAt) } ?? "暂无",
                summary: latestJournalSummary,
                icon: "book.closed.fill"
            ) { tab = .journals }
            Divider()
            NativeOverviewDataRow(
                title: "最近记忆",
                detail: latestMemoryDetail,
                summary: store.memories.first?.content ?? "尚未形成长期记忆。",
                icon: "brain.head.profile"
            ) {
                selectedMemoryCategory = store.memories.first.map {
                    NativeDataTaxonomy.normalizedCategory($0.category)
                }
                tab = .memories
            }
            Divider()
            NativeOverviewDataRow(
                title: "状态画像",
                detail: latestStateDetail,
                summary: latestStateSummary,
                icon: "person.text.rectangle.fill"
            ) { tab = .states }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var latestJournalSummary: String {
        guard let journal = store.journals.first else { return "完成总结后会形成日记。" }
        let emotion = journal.dominantEmotion.isEmpty ? "未标注情绪" : journal.dominantEmotion
        return "\(emotion) · 心情 \(journal.moodScore) · \(journal.summary)"
    }

    private var latestMemoryDetail: String {
        guard let memory = store.memories.first else { return "暂无" }
        return "\(NativeDataTaxonomy.categoryLabel(memory.category)) · \(NativeDateFormat.displayDate(memory.updatedAt))"
    }

    private var latestStateDetail: String {
        guard let profile = latestState else { return "暂无" }
        return "\(NativeDataTaxonomy.stateDomainLabel(profile.domain)) · \(NativeDateFormat.displayDate(profile.updatedAt))"
    }

    private var latestStateSummary: String {
        latestState?.summary ?? "积累足够证据后会形成长期状态。"
    }

    private var latestState: StateProfile? {
        store.stateProfiles.max { $0.updatedAt < $1.updatedAt }
    }
}

private struct NativeOverviewDataRow: View {
    let title: String
    let detail: String
    let summary: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title).font(.callout.bold())
                        Spacer()
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct NativeMemoryMapCard: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @Binding var tab: NativeDataTab
    @Binding var selectedMemoryCategory: String?
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("记忆地图", systemImage: "square.grid.2x2.fill")
                    .font(.headline)
                Spacer()
                Button("查看全部") {
                    selectedMemoryCategory = nil
                    tab = .memories
                }
                    .buttonStyle(.link)
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(NativeDataTaxonomy.memoryCategoryKeys, id: \.self) { category in
                    Button {
                        selectedMemoryCategory = category
                        tab = .memories
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: NativeDataTaxonomy.categoryIcon(category))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NativeDataTaxonomy.categoryLabel(category))
                                    .font(.caption.bold())
                                Text("\(memoryCounts[category, default: 0]) 条")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("按八个心理陪伴维度整理；进入记忆页后可继续查看小类和每条依据。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var memoryCounts: [String: Int] {
        Dictionary(grouping: store.memories) {
            NativeDataTaxonomy.normalizedCategory($0.category)
        }
        .mapValues(\.count)
    }
}

private struct NativeSessionList: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @State private var sessionToDelete: SessionSummary?
    @State private var expandedPeriods: Set<String> = []
    let query: String

    var body: some View {
        ScrollView {
            if filteredSessions.isEmpty {
                NativeDataEmptyState(query: query, type: "会话")
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(sessionGroups, id: \.0) { period, sessions in
                        DisclosureGroup(isExpanded: periodExpansionBinding(period)) {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(sessions) { session in
                                    sessionCard(session)
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            HStack {
                                Text(period)
                                    .font(.headline)
                                Text("\(sessions.count) 段")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                        .padding(14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(24)
            }
        }
        .onAppear { updateExpandedPeriods(for: query) }
        .onChange(of: query) { _, newQuery in
            updateExpandedPeriods(for: newQuery)
        }
        .alert(
            "删除这段夜谈？",
            isPresented: Binding(
                get: { sessionToDelete != nil },
                set: { if !$0 { sessionToDelete = nil } }
            ),
            presenting: sessionToDelete
        ) { session in
            Button("删除", role: .destructive) {
                store.deleteSession(session.id)
                sessionToDelete = nil
            }
            Button("取消", role: .cancel) { sessionToDelete = nil }
        } message: { _ in
            Text("会同时删除这段夜谈关联的消息、日记、记忆和状态更新，此操作无法撤销。")
        }
    }

    private func sessionCard(_ session: SessionSummary) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                let linkedJournals = store.journals.filter { $0.sessionID == session.id }
                if !linkedJournals.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("会后日记 · \(linkedJournals.count)", systemImage: "book.closed.fill")
                            .font(.caption.bold())
                        ForEach(linkedJournals) { journal in
                            NativeSessionJournalSummary(journal: journal)
                        }
                    }
                }

                let linkedMemories = store.memories.filter { $0.sourceSessionID == session.id }
                if !linkedMemories.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("关联记忆 · \(linkedMemories.count)", systemImage: "brain.head.profile")
                            .font(.caption.bold())
                        ForEach(linkedMemories) { memory in
                            NativeSessionMemorySummary(memory: memory)
                        }
                    }
                }

                let linkedProfiles = stateUpdates(for: session.id)
                if !linkedProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("长期状态更新 · \(linkedProfiles.count)", systemImage: "person.text.rectangle.fill")
                            .font(.caption.bold())
                        ForEach(linkedProfiles) { profile in
                            NativeSessionStateSummary(profile: profile)
                        }
                    }
                }

                HStack {
                    Button("继续这段夜谈", systemImage: "arrowshape.turn.up.left.fill") {
                        if store.openSession(session.id) {
                            NotificationCenter.default.post(name: .nativeOpenConversation, object: nil)
                        }
                    }
                    Button("删除", systemImage: "trash", role: .destructive) {
                        sessionToDelete = session
                    }
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
                        Text(NativeDateFormat.displayDate(session.createdAt))
                        Text("\(session.messageCount) 条消息")
                        if !session.endedAt.isEmpty { Text("已总结") }
                        let memoryCount = store.memories.filter { $0.sourceSessionID == session.id }.count
                        if memoryCount > 0 { Text("\(memoryCount) 条记忆") }
                        let profileCount = stateUpdates(for: session.id).count
                        if profileCount > 0 { Text("\(profileCount) 项状态") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var filteredSessions: [SessionSummary] {
        let needle = normalizedQuery
        guard !needle.isEmpty else { return store.sessions }
        return store.sessions.filter { session in
            if session.preview.localizedCaseInsensitiveContains(needle) { return true }
            if store.journals.contains(where: {
                $0.sessionID == session.id && $0.summary.localizedCaseInsensitiveContains(needle)
            }) { return true }
            if store.memories.contains(where: {
                $0.sourceSessionID == session.id
                    && ($0.content.localizedCaseInsensitiveContains(needle)
                        || $0.keywords.contains(where: { $0.localizedCaseInsensitiveContains(needle) }))
            }) { return true }
            return (store.stateProfiles + store.stateProfileVersions).contains(where: {
                $0.sourceSessionID == session.id
                    && ($0.summary.localizedCaseInsensitiveContains(needle)
                        || NativeDataTaxonomy.stateDomainLabel($0.domain).localizedCaseInsensitiveContains(needle))
            })
        }
    }

    private var sessionGroups: [(String, [SessionSummary])] {
        Dictionary(grouping: filteredSessions) { NativeDateFormat.periodLabel($0.createdAt) }
            .map { label, sessions in
                (label, sessions.sorted { $0.createdAt > $1.createdAt })
            }
            .sorted {
                ($0.1.first?.createdAt ?? "") > ($1.1.first?.createdAt ?? "")
            }
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func periodExpansionBinding(_ period: String) -> Binding<Bool> {
        Binding(
            get: { expandedPeriods.contains(period) },
            set: { isExpanded in
                if isExpanded {
                    expandedPeriods.insert(period)
                } else {
                    expandedPeriods.remove(period)
                }
            }
        )
    }

    private func updateExpandedPeriods(for query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            expandedPeriods = Set(sessionGroups.first.map { [$0.0] } ?? [])
        } else {
            expandedPeriods = Set(sessionGroups.map(\.0))
        }
    }

    private func stateUpdates(for sessionID: String) -> [StateProfile] {
        let versions = store.stateProfileVersions.filter { $0.sourceSessionID == sessionID }
        if !versions.isEmpty { return versions }
        return store.stateProfiles.filter { $0.sourceSessionID == sessionID }
    }
}

private struct NativeSessionJournalSummary: View {
    let journal: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(journal.dominantEmotion.isEmpty ? "日记总结" : journal.dominantEmotion)
                    .font(.callout.bold())
                Spacer()
                Text("心情 \(journal.moodScore) · \(NativeDateFormat.displayDate(journal.createdAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(journal.summary).textSelection(.enabled)
            if !journal.emotionCurve.isEmpty {
                Text("情绪变化：\(journal.emotionCurve.joined(separator: " → "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !journal.insights.isEmpty {
                Text("洞察：\(journal.insights.joined(separator: "；"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !journal.suggestedNextStep.isEmpty {
                Label(journal.suggestedNextStep, systemImage: "arrow.forward.circle.fill")
                    .font(.caption)
            }
            if !journal.keywords.isEmpty {
                NativeTagFlow(tags: journal.keywords)
            }
        }
        .padding(12)
        .background(Color.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NativeSessionMemorySummary: View {
    let memory: MemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(
                    "\(NativeDataTaxonomy.categoryLabel(memory.category)) / "
                        + NativeDataTaxonomy.subcategoryLabel(memory.subcategory)
                )
                .font(.caption.bold())
                Spacer()
                Text("重要度 \(memory.importance)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(memory.content)
                .font(.caption)
                .textSelection(.enabled)
            if !memory.keywords.isEmpty {
                NativeTagFlow(tags: memory.keywords)
            }
            if !memory.evidence.isEmpty {
                Text("依据：\(memory.evidence)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NativeSessionStateSummary: View {
    let profile: StateProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(NativeDataTaxonomy.stateDomainLabel(profile.domain))
                    .font(.caption.bold())
                Spacer()
                Text("强度 \(profile.intensity)/10 · \(NativeDataTaxonomy.trendLabel(profile.trend))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(profile.summary)
                .font(.caption)
                .textSelection(.enabled)
            if !profile.supportStrategy.isEmpty {
                Text("支持方式：\(profile.supportStrategy)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
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
    @State private var expandedCategories: Set<String> = []
    let query: String
    @Binding var selectedCategory: String?

    private var categories: [(String, [MemoryEntry])] {
        Dictionary(grouping: filteredMemories) { memory in
            NativeDataTaxonomy.normalizedCategory(memory.category)
        }
            .map { ($0.key, $0.value) }
            .sorted { NativeDataTaxonomy.categoryOrder($0.0) < NativeDataTaxonomy.categoryOrder($1.0) }
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

            ScrollViewReader { proxy in
                ScrollView {
                    if filteredMemories.isEmpty {
                        NativeDataEmptyState(query: query, type: "记忆")
                    } else {
                        LazyVStack(spacing: 12) {
                        if mode == .categories {
                            ForEach(categories, id: \.0) { category, memories in
                                DisclosureGroup(isExpanded: categoryExpansionBinding(category)) {
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
                                                    Text(NativeDataTaxonomy.subcategoryLabel(subcategory))
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
                                        Label(
                                            NativeDataTaxonomy.categoryLabel(category),
                                            systemImage: NativeDataTaxonomy.categoryIcon(category)
                                        )
                                        Spacer()
                                        Text("\(memories.count)").foregroundStyle(.secondary)
                                    }
                                    .font(.headline)
                                }
                                .id(category)
                                .padding(14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                            }
                        } else {
                            ForEach(filteredMemories.sorted { $0.updatedAt > $1.updatedAt }) { memory in
                                NativeMemoryCard(memory: memory)
                            }
                        }
                        }
                        .padding(24)
                    }
                }
                .onAppear { focusSelectedCategory(using: proxy) }
                .onChange(of: selectedCategory) { _, _ in
                    focusSelectedCategory(using: proxy)
                }
                .onChange(of: mode) { _, newMode in
                    if newMode == .categories {
                        focusSelectedCategory(using: proxy)
                    }
                }
            }
        }
    }

    private func categoryExpansionBinding(_ category: String) -> Binding<Bool> {
        Binding(
            get: { expandedCategories.contains(category) },
            set: { isExpanded in
                if isExpanded {
                    expandedCategories.insert(category)
                } else {
                    expandedCategories.remove(category)
                }
            }
        )
    }

    private func focusSelectedCategory(using proxy: ScrollViewProxy) {
        guard let selectedCategory else { return }
        mode = .categories
        expandedCategories.insert(selectedCategory)
        Task { @MainActor in
            proxy.scrollTo(selectedCategory, anchor: .top)
        }
    }

    private func subcategories(_ memories: [MemoryEntry]) -> [(String, [MemoryEntry])] {
        Dictionary(grouping: memories, by: \.subcategory)
            .map { ($0.key, $0.value) }
            .sorted {
                NativeDataTaxonomy.subcategoryLabel($0.0)
                    < NativeDataTaxonomy.subcategoryLabel($1.0)
            }
    }

    private var filteredMemories: [MemoryEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return store.memories }
        return store.memories.filter { memory in
            memory.content.localizedCaseInsensitiveContains(needle)
                || NativeDataTaxonomy.categoryLabel(memory.category).localizedCaseInsensitiveContains(needle)
                || NativeDataTaxonomy.subcategoryLabel(memory.subcategory).localizedCaseInsensitiveContains(needle)
                || memory.keywords.contains(where: { $0.localizedCaseInsensitiveContains(needle) })
        }
    }
}

private struct NativeJournalTimeline: View {
    @EnvironmentObject private var store: NativeMacShellStore
    let query: String

    var body: some View {
        ScrollView {
            if filteredJournals.isEmpty {
                NativeDataEmptyState(query: query, type: "日记")
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    NativeMoodChart(journals: canonicalJournals)
                    ForEach(journalWeeks, id: \.0) { week, groups in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(week)
                                .font(.headline)
                            NativeWeeklyReportCard(
                                weekLabel: week,
                                journals: groups.map(\.latest),
                                versionCount: groups.reduce(0) { $0 + $1.versions.count }
                            )
                            ForEach(groups) { group in
                                NativeJournalGroupCard(group: group)
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private var journalGroups: [NativeJournalGroup] {
        Dictionary(grouping: filteredJournals) { journal in
            journal.sessionID.isEmpty ? journal.id : journal.sessionID
        }
        .map { key, journals in
            let sorted = journals.sorted { $0.createdAt > $1.createdAt }
            return NativeJournalGroup(
                id: key,
                latest: sorted[0],
                versions: Array(sorted.dropFirst())
            )
        }
        .sorted { $0.latest.createdAt > $1.latest.createdAt }
    }

    private var canonicalJournals: [JournalEntry] {
        journalGroups.map(\.latest)
    }

    private var journalWeeks: [(String, [NativeJournalGroup])] {
        Dictionary(grouping: journalGroups) {
            NativeDateFormat.weekLabel($0.latest.createdAt)
        }
        .map { ($0.key, $0.value.sorted { $0.latest.createdAt > $1.latest.createdAt }) }
        .sorted { ($0.1.first?.latest.createdAt ?? "") > ($1.1.first?.latest.createdAt ?? "") }
    }

    private var filteredJournals: [JournalEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return store.journals }
        return store.journals.filter { journal in
            journal.summary.localizedCaseInsensitiveContains(needle)
                || journal.dominantEmotion.localizedCaseInsensitiveContains(needle)
                || journal.keywords.contains(where: { $0.localizedCaseInsensitiveContains(needle) })
                || journal.insights.contains(where: { $0.localizedCaseInsensitiveContains(needle) })
        }
    }
}

private struct NativeJournalGroup: Identifiable {
    let id: String
    let latest: JournalEntry
    let versions: [JournalEntry]
}

private struct NativeJournalGroupCard: View {
    let group: NativeJournalGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NativeJournalCard(journal: group.latest)
            if !group.versions.isEmpty {
                DisclosureGroup("同一会话的历史总结 · \(group.versions.count)") {
                    VStack(spacing: 8) {
                        ForEach(group.versions) { journal in
                            NativeJournalVersionRow(journal: journal)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.caption.bold())
                .padding(.horizontal, 14)
            }
        }
    }
}

private struct NativeJournalVersionRow: View {
    let journal: JournalEntry

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 7) {
                Text(journal.summary).textSelection(.enabled)
                if !journal.emotionCurve.isEmpty {
                    Text("情绪变化：\(journal.emotionCurve.joined(separator: " → "))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !journal.insights.isEmpty {
                    Text("洞察：\(journal.insights.joined(separator: "；"))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !journal.keywords.isEmpty {
                    NativeTagFlow(tags: journal.keywords)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(journal.dominantEmotion.isEmpty ? "历史总结" : journal.dominantEmotion)
                Spacer()
                Text("心情 \(journal.moodScore) · \(NativeDateFormat.displayDate(journal.createdAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NativeWeeklyReportCard: View {
    let weekLabel: String
    let journals: [JournalEntry]
    let versionCount: Int

    private var averageMood: Double {
        guard !journals.isEmpty else { return 0 }
        return Double(journals.reduce(0) { $0 + $1.moodScore }) / Double(journals.count)
    }

    private var dominantEmotion: String {
        let values = journals.map(\.dominantEmotion).filter { !$0.isEmpty }
        return Dictionary(grouping: values, by: { $0 })
            .max { $0.value.count < $1.value.count }?.key ?? "未标注"
    }

    private var keywords: [String] {
        let counts = Dictionary(grouping: journals.flatMap(\.keywords), by: { $0 })
            .mapValues(\.count)
        return counts.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }
        .prefix(8)
        .map(\.key)
    }

    private var reportText: String {
        let summaries = journals.map(\.summary).filter { !$0.isEmpty }.prefix(3)
        return summaries.isEmpty ? "这一周的记录还在形成。" : summaries.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本周小结")
                        .font(.title3.bold())
                    Text(reportSourceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(dominantEmotion).font(.subheadline.bold())
                    Text(String(format: "平均心情 %.1f", averageMood))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(reportText)
                .font(.callout)
                .lineLimit(8)
                .textSelection(.enabled)

            NativeMoodChart(journals: journals)

            if !keywords.isEmpty {
                NativeTagFlow(tags: keywords)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.flowGradientTop, Color.flowGradientBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private var reportSourceLabel: String {
        let base = "\(weekLabel) · 根据 \(journals.count) 段夜谈的最新日记自动聚合"
        guard versionCount > 0 else { return base }
        return "\(base) · 另保留 \(versionCount) 个历史版本"
    }
}

private struct NativeStateProfileGrid: View {
    @EnvironmentObject private var store: NativeMacShellStore
    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)]
    let query: String

    var body: some View {
        ScrollView {
            if domainGroups.isEmpty {
                NativeDataEmptyState(query: query, type: "长期状态")
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(domainGroups) { group in
                        NativeStateDomainCard(group: group)
                    }
                }
                .padding(24)
            }
        }
    }

    private var filteredProfiles: [StateProfile] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return store.stateProfiles }
        return store.stateProfiles.filter { profile in
            NativeDataTaxonomy.stateDomainLabel(profile.domain).localizedCaseInsensitiveContains(needle)
                || profile.summary.localizedCaseInsensitiveContains(needle)
                || profile.stage.localizedCaseInsensitiveContains(needle)
                || profile.supportStrategy.localizedCaseInsensitiveContains(needle)
        }
    }

    private var filteredVersions: [StateProfile] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return store.stateProfileVersions }
        return store.stateProfileVersions.filter { profile in
            NativeDataTaxonomy.stateDomainLabel(profile.domain).localizedCaseInsensitiveContains(needle)
                || profile.summary.localizedCaseInsensitiveContains(needle)
                || profile.stage.localizedCaseInsensitiveContains(needle)
                || profile.supportStrategy.localizedCaseInsensitiveContains(needle)
        }
    }

    private var domainGroups: [NativeStateDomainGroup] {
        let currentByDomain = Dictionary(
            uniqueKeysWithValues: filteredProfiles.map { ($0.domain, $0) }
        )
        let versionsByDomain = Dictionary(grouping: filteredVersions, by: \.domain)
        let knownDomains = NativeDataTaxonomy.stateDomainKeys
        let availableDomains = Set(currentByDomain.keys).union(versionsByDomain.keys)
        let unknownDomains = availableDomains
            .filter { !knownDomains.contains($0) }
            .sorted()
        let domains = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? knownDomains + unknownDomains
            : availableDomains.sorted {
                NativeDataTaxonomy.stateDomainOrder($0) < NativeDataTaxonomy.stateDomainOrder($1)
            }
        return domains.map { domain in
            let current = currentByDomain[domain]
            let history = (versionsByDomain[domain] ?? [])
                .filter { version in
                    guard let current else { return true }
                    return version.updatedAt != current.updatedAt || version.summary != current.summary
                }
                .sorted { $0.updatedAt > $1.updatedAt }
            return NativeStateDomainGroup(
                domain: domain,
                current: current,
                history: history
            )
        }
    }
}

private struct NativeStateDomainGroup: Identifiable {
    let domain: String
    let current: StateProfile?
    let history: [StateProfile]

    var id: String { domain }
}

private struct NativeStateDomainCard: View {
    let group: NativeStateDomainGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(
                    NativeDataTaxonomy.stateDomainLabel(group.domain),
                    systemImage: NativeDataTaxonomy.stateDomainIcon(group.domain)
                )
                .font(.headline)
                Spacer()
                if let current = group.current {
                    Text(NativeDataTaxonomy.trendLabel(current.trend))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let current = group.current {
                Label("当前状态", systemImage: "circle.inset.filled")
                    .font(.caption.bold())
                    .foregroundStyle(.indigo)
                NativeCurrentStateContent(profile: current)

                if !group.history.isEmpty {
                    DisclosureGroup("历史变化 · \(group.history.count)") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(group.history) { profile in
                                NativeStateHistoryRow(profile: profile)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.caption.bold())
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("尚未形成稳定记录")
                        .font(.callout.weight(.medium))
                    Text("后续夜谈积累出足够证据后，这里会出现当前状态和历史变化。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct NativeCurrentStateContent: View {
    let profile: StateProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if shouldShowStage {
                Text(profile.stage)
                    .font(.caption.bold())
                    .foregroundStyle(.indigo)
            }
            Text(profile.summary).textSelection(.enabled)
            ProgressView(value: Double(profile.intensity), total: 10)
                .tint(profile.intensity >= 7 ? .orange : .green)
            if !profile.supportStrategy.isEmpty {
                Text("支持方式：\(profile.supportStrategy)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !profile.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("依据")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    ForEach(NativeStateEvidence.items(from: profile.evidence), id: \.self) { item in
                        Text("• \(item)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("置信度 \(Int(profile.confidence * 100))% · 更新于 \(NativeDateFormat.displayDate(profile.updatedAt))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if !profile.sourceSessionID.isEmpty {
                NativeSourceSessionButton(sessionID: profile.sourceSessionID)
            }
        }
    }

    private var shouldShowStage: Bool {
        let stage = profile.stage.trimmingCharacters(in: .whitespacesAndNewlines)
        return !stage.isEmpty && stage != "当前状态"
    }
}

private enum NativeStateEvidence {
    static func items(from value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data),
              !decoded.isEmpty else {
            return [value]
        }
        return decoded
    }
}

private struct NativeStateHistoryRow: View {
    let profile: StateProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(NativeDateFormat.displayDate(profile.updatedAt))
                if !profile.stage.isEmpty, profile.stage != "当前状态" {
                    Text("· \(profile.stage)")
                }
                Spacer()
                Text(NativeDataTaxonomy.trendLabel(profile.trend))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text("强度 \(profile.intensity)/10")
                    .font(.caption2.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.09), in: Capsule())
                Text("置信度 \(Int(profile.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(profile.summary)
                .font(.caption)
                .textSelection(.enabled)
            if !profile.supportStrategy.isEmpty {
                Text("支持方式：\(profile.supportStrategy)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if !profile.evidence.isEmpty {
                ForEach(NativeStateEvidence.items(from: profile.evidence).prefix(2), id: \.self) { item in
                    Text("• \(item)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            if !profile.sourceSessionID.isEmpty {
                NativeSourceSessionButton(sessionID: profile.sourceSessionID)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NativeMemoryCard: View {
    let memory: MemoryEntry

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text(memory.content).textSelection(.enabled)
                if !memory.keywords.isEmpty {
                    NativeTagFlow(tags: memory.keywords)
                }
                if !memory.evidence.isEmpty {
                    Text("依据：\(memory.evidence)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    if !memory.updatedAt.isEmpty { Text("更新于 \(NativeDateFormat.displayDate(memory.updatedAt))") }
                    if !memory.sourceSessionID.isEmpty { Text("来源会话 \(memory.sourceSessionID.prefix(8))") }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                if !memory.sourceSessionID.isEmpty {
                    NativeSourceSessionButton(sessionID: memory.sourceSessionID)
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(
                        "\(NativeDataTaxonomy.categoryLabel(memory.category)) / "
                            + NativeDataTaxonomy.subcategoryLabel(memory.subcategory)
                    )
                        .font(.caption.bold())
                    Spacer()
                    Text("重要度 \(memory.importance)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(memory.content)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.cardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct NativeJournalCard: View {
    let journal: JournalEntry

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 9) {
                Text(journal.summary).textSelection(.enabled)
                if !journal.emotionCurve.isEmpty {
                    Text("情绪变化：\(journal.emotionCurve.joined(separator: " → "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !journal.insights.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("洞察").font(.caption.bold()).foregroundStyle(.secondary)
                        ForEach(journal.insights, id: \.self) { insight in
                            Label(insight, systemImage: "lightbulb.fill").font(.callout)
                        }
                    }
                }
                if !journal.suggestedNextStep.isEmpty {
                    Label(journal.suggestedNextStep, systemImage: "arrow.forward.circle.fill")
                        .font(.callout)
                }
                if !journal.keywords.isEmpty {
                    NativeTagFlow(tags: journal.keywords)
                }
                Text("来源会话 · \(journal.sessionID)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                if !journal.sessionID.isEmpty {
                    NativeSourceSessionButton(sessionID: journal.sessionID)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(journal.dominantEmotion.isEmpty ? "日记总结" : journal.dominantEmotion, systemImage: "book.closed.fill")
                        .font(.headline)
                    Text(NativeDateFormat.displayDate(journal.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("心情 \(journal.moodScore)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(NativeMoodColor.color(journal.moodScore).opacity(0.14), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct NativeTagFlow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentPurple.opacity(0.10), in: Capsule())
                }
            }
        }
    }
}

private struct NativeDataEmptyState: View {
    let query: String
    let type: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: query.isEmpty ? "tray" : "magnifyingglass")
        } description: {
            Text(detail)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding(24)
    }

    private var title: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "还没有\(type)"
            : "没有找到相关\(type)"
    }

    private var detail: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "完成夜谈和总结后，内容会出现在这里。"
            : "试试更短的关键词，或切换到其他资料分类。"
    }
}

private struct NativeSourceSessionButton: View {
    @EnvironmentObject private var store: NativeMacShellStore
    let sessionID: String

    var body: some View {
        Button("打开来源夜谈", systemImage: "arrowshape.turn.up.left.fill") {
            if store.openSession(sessionID) {
                NotificationCenter.default.post(name: .nativeOpenConversation, object: nil)
            }
        }
        .buttonStyle(.link)
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

private enum NativeDataTaxonomy {
    private static let categoryKeys = [
        "self_core",
        "emotion_pattern",
        "body_response",
        "relationship_pattern",
        "trauma_shadow",
        "resource_support",
        "life_habit",
        "goal_action",
    ]

    static var memoryCategoryKeys: [String] { categoryKeys }

    private static let categoryLabels = [
        "self_core": "自我核心",
        "emotion_pattern": "情绪模式",
        "body_response": "身体反应",
        "relationship_pattern": "关系模式",
        "trauma_shadow": "创伤影子",
        "resource_support": "支持资源",
        "life_habit": "生活习惯",
        "goal_action": "目标行动",
    ]

    private static let categoryIcons = [
        "self_core": "person.crop.circle.fill",
        "emotion_pattern": "heart.text.square.fill",
        "body_response": "waveform.path.ecg",
        "relationship_pattern": "person.2.fill",
        "trauma_shadow": "cloud.moon.fill",
        "resource_support": "hands.sparkles.fill",
        "life_habit": "cup.and.saucer.fill",
        "goal_action": "flag.checkered",
    ]

    private static let categoryAliases = [
        "self relation": "self_core",
        "self_relation": "self_core",
        "meaning value": "self_core",
        "meaning_value": "self_core",
        "preference": "self_core",
        "偏好": "self_core",
        "兴趣": "self_core",
        "experience": "self_core",
        "agency boundary": "self_core",
        "agency_boundary": "self_core",
        "behavioral pattern": "life_habit",
        "behavioral_pattern": "life_habit",
        "behavior": "life_habit",
        "行为模式": "life_habit",
        "经济状况": "life_habit",
        "health": "body_response",
        "健康": "body_response",
        "social": "relationship_pattern",
        "relationship": "relationship_pattern",
        "关系": "relationship_pattern",
        "关系模式": "relationship_pattern",
        "社交关系": "relationship_pattern",
        "trauma pattern": "trauma_shadow",
        "trauma_pattern": "trauma_shadow",
        "coping strategy": "resource_support",
        "coping_strategy": "resource_support",
        "coping mechanism": "resource_support",
        "coping_mechanism": "resource_support",
        "work": "goal_action",
        "工作经历": "goal_action",
    ]

    private static let subcategoryLabels = [
        "identity": "身份与自我认同", "values": "价值观", "energy_source": "能量来源",
        "boundary": "个人边界", "self_image": "自我形象", "inner_critic": "内在批评",
        "self_compassion": "自我关怀", "anxiety": "焦虑", "freeze_response": "冻结反应",
        "shame": "羞耻", "grief": "悲伤与失落", "anger": "愤怒", "loneliness": "孤独",
        "numbness": "麻木", "fatigue": "疲惫", "tension": "紧绷", "sleep": "睡眠",
        "somatic_signal": "身体信号", "collapse": "耗竭与坍塌", "sensory_overload": "感官过载",
        "pain": "疼痛与不适", "family": "家庭关系", "intimacy": "亲密关系",
        "work_relation": "工作关系", "attachment_trigger": "依恋触发", "support_need": "支持需要",
        "rejection": "拒绝与疏离", "boundary_conflict": "边界冲突", "fear": "恐惧",
        "abandonment": "被抛弃感", "humiliation": "羞辱经历", "suppression": "压抑与控制",
        "dark_part": "阴影部分", "hypervigilance": "过度警觉", "trigger": "创伤触发",
        "person": "支持我的人", "place": "安全的地方", "activity": "有帮助的活动",
        "ritual": "安定仪式", "inner_strength": "内在力量", "professional_support": "专业支持",
        "creative_resource": "创作与文化资源", "routine": "日常节奏", "food": "饮食",
        "movement": "活动与运动", "work_rhythm": "工作节奏", "rest": "休息",
        "environment": "生活环境", "digital_habit": "数字习惯", "career": "职业方向",
        "project": "正在推进的项目", "small_step": "下一小步", "avoidance": "回避模式",
        "decision": "选择与决定", "uncertainty": "不确定性", "learning": "学习与探索",
        "general": "其他记录",
    ]

    private static let stateLabels = [
        "self_relation": "与自己的关系",
        "emotion_regulation": "情绪调节",
        "relationship": "关系与连接",
        "agency_boundary": "行动力与边界",
        "trauma_pattern": "创伤模式",
        "meaning_value": "意义与价值",
    ]

    static let stateDomainKeys = [
        "self_relation",
        "emotion_regulation",
        "relationship",
        "agency_boundary",
        "trauma_pattern",
        "meaning_value",
    ]

    private static let stateIcons = [
        "self_relation": "person.crop.circle",
        "emotion_regulation": "heart.circle",
        "relationship": "person.2.circle",
        "agency_boundary": "shield.lefthalf.filled",
        "trauma_pattern": "waveform.path.ecg.rectangle",
        "meaning_value": "sparkles",
    ]

    private static let trendLabels = [
        "unknown": "仍在观察", "stable": "相对稳定", "softening": "正在缓和",
        "intensifying": "有所增强", "fluctuating": "有所起伏", "integrating": "正在整合",
    ]

    static func categoryOrder(_ key: String) -> Int {
        categoryKeys.firstIndex(of: normalizedCategory(key)) ?? categoryKeys.count
    }

    static func categoryLabel(_ key: String) -> String {
        let normalizedKey = normalizedCategory(key)
        return categoryLabels[normalizedKey] ?? readableFallback(normalizedKey)
    }

    static func categoryIcon(_ key: String) -> String {
        categoryIcons[normalizedCategory(key)] ?? "folder.fill"
    }

    static func normalizedCategory(_ key: String) -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedKey = trimmedKey.lowercased()
        return categoryAliases[lowercasedKey] ?? lowercasedKey
    }

    static func subcategoryLabel(_ key: String) -> String {
        subcategoryLabels[key] ?? readableFallback(key)
    }

    static func stateDomainLabel(_ key: String) -> String {
        stateLabels[key] ?? readableFallback(key)
    }

    static func stateDomainOrder(_ key: String) -> Int {
        stateDomainKeys.firstIndex(of: key) ?? stateDomainKeys.count
    }

    static func stateDomainIcon(_ key: String) -> String {
        stateIcons[key] ?? "person.text.rectangle"
    }

    static func trendLabel(_ key: String) -> String {
        trendLabels[key] ?? readableFallback(key)
    }

    private static func readableFallback(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
    }
}

private enum NativeDateFormat {
    static func displayDate(_ value: String) -> String {
        guard let date = date(value) else { return value }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"
        if calendar.isDateInToday(date) {
            return "今天 \(timeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(timeFormatter.string(from: date))"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
            ? "M月d日 HH:mm"
            : "yyyy年M月d日"
        return formatter.string(from: date)
    }

    static func periodLabel(_ value: String) -> String {
        guard let date = date(value) else { return "较早的夜谈" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) { return "本周" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
            ? "M月"
            : "yyyy年M月"
        return formatter.string(from: date)
    }

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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
