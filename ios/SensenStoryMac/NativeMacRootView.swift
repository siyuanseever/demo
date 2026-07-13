import SwiftUI

private enum NativeMacSection: String, CaseIterable, Identifiable {
    case conversation
    case flow
    case cache
    case diagnostics
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversation: "夜谈"
        case .flow: "心流"
        case .cache: "本地资料"
        case .diagnostics: "诊断"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .conversation: "bubble.left.and.bubble.right.fill"
        case .flow: "sparkles"
        case .cache: "externaldrive.fill"
        case .diagnostics: "stethoscope"
        case .settings: "gearshape.fill"
        }
    }
}

struct NativeMacRootView: View {
    @EnvironmentObject private var store: NativeMacShellStore
    @State private var selection: NativeMacSection? = .conversation

    var body: some View {
        NavigationSplitView {
            List(NativeMacSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("森森物语")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(store.backendStatus.state == .online ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("原生 macOS · N1")
                        .font(.caption)
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(12)
                .background(.thinMaterial)
            }
        } detail: {
            detailView(for: selection ?? .conversation)
        }
        .navigationSplitViewStyle(.balanced)
        .onReceive(NotificationCenter.default.publisher(for: .nativeOpenConversation)) { _ in
            selection = .conversation
        }
    }

    @ViewBuilder
    private func detailView(for section: NativeMacSection) -> some View {
        switch section {
        case .conversation:
            NativeConversationShellView()
        case .flow:
            NativePlaceholderView(
                title: "心流导航",
                subtitle: "N3 将接入每周目标、近期情绪和可选的小步骤。",
                systemImage: "sparkles"
            )
        case .cache:
            NativeCacheOverviewView()
        case .diagnostics:
            NativeDiagnosticsView()
        case .settings:
            NativeMacSettingsView()
        }
    }
}

private struct NativeConversationShellView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("和忧忧兔夜谈", systemImage: "moon.stars.fill")
                    .font(.headline)
                Spacer()
                Button("新夜谈", systemImage: "plus") {}
                Button("结束并总结", systemImage: "sparkles") {}
                    .disabled(true)
            }
            .controlSize(.small)
            .padding(.horizontal, 18)
            .frame(height: 46)
            .background(.regularMaterial)

            Divider()

            ContentUnavailableView {
                Label("原生夜谈已经有了一个安静的房间", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("N2 会把 quick / plan 并行、按需 deep、对话轨迹和本地缓存完整迁移到这里。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                TextField("N2 接入真实发送后，可以从这里开始夜谈…", text: .constant(""))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)
                Button("发送", systemImage: "paperplane.fill") {}
                    .disabled(true)
            }
            .padding(16)
            .background(.regularMaterial)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: 0xFDFAF2), Color(hex: 0xF2F7ED)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct NativeCacheOverviewView: View {
    @EnvironmentObject private var store: NativeMacShellStore

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NativePageHeader(
                    title: "本地资料",
                    subtitle: "原生 target 已经复用现有 SQLite schema，并以只读概览验证共享核心。"
                )

                LazyVGrid(columns: columns, spacing: 14) {
                    NativeMetricCard(title: "会话", value: store.snapshot.sessionCount, icon: "bubble.left.and.bubble.right")
                    NativeMetricCard(title: "消息", value: store.snapshot.messageCount, icon: "text.bubble")
                    NativeMetricCard(title: "记忆", value: store.snapshot.memoryCount, icon: "books.vertical")
                    NativeMetricCard(title: "日记", value: store.snapshot.journalCount, icon: "book.closed")
                }

                if let databaseError = store.databaseError {
                    Label(databaseError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .padding(28)
        }
        .toolbar {
            Button("刷新缓存", systemImage: "arrow.clockwise") {
                store.loadLocalCache()
            }
        }
    }
}

private struct NativeDiagnosticsView: View {
    @EnvironmentObject private var store: NativeMacShellStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NativePageHeader(
                    title: "原生诊断",
                    subtitle: "用于验证 target、缓存和本机后端边界，不承载正式产品功能。"
                )

                GroupBox("运行环境") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("平台", value: "Native macOS")
                        LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "未知")
                        LabeledContent("缓存路径", value: store.databasePath)
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }

                GroupBox("Python 后端") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("状态", value: store.backendStatus.state.rawValue)
                        Text(store.backendStatus.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button(store.isCheckingBackend ? "正在检查…" : "检查 localhost 后端") {
                            Task { await store.checkBackend() }
                        }
                        .disabled(store.isCheckingBackend)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }
            }
            .padding(28)
        }
    }
}

struct NativeMacSettingsView: View {
    @EnvironmentObject private var store: NativeMacShellStore

    var body: some View {
        Form {
            Section("原生迁移") {
                LabeledContent("阶段", value: "N1 原生壳")
                Text("真实聊天、TTS 和完整同步将在后续纵切中接入。Catalyst 版本仍是当前可用基线。")
                    .foregroundStyle(.secondary)
            }

            Section("数据边界") {
                Text("Python 后端仍是权威数据源；原生 App 只使用独立沙盒缓存，不直接读写仓库数据库。")
                    .foregroundStyle(.secondary)
                Button("重新读取本地缓存") {
                    store.loadLocalCache()
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle("设置")
    }
}

private struct NativePlaceholderView: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(subtitle))
    }
}

private struct NativePageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
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
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.title2.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
