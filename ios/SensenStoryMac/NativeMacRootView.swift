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
        case .cache: "books.vertical.fill"
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
            .navigationSplitViewColumnWidth(min: 184, ideal: 210, max: 250)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(store.backendStatus.state.rawValue)
                    Spacer()
                    Text("Native · N3")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)
                .background(.thinMaterial)
            }
        } detail: {
            detailView(for: selection ?? .conversation)
        }
        .navigationSplitViewStyle(.balanced)
        .task { await store.bootstrap() }
        .onReceive(NotificationCenter.default.publisher(for: .nativeOpenConversation)) { _ in
            selection = .conversation
        }
    }

    private var statusColor: Color {
        switch store.backendStatus.state {
        case .online: .green
        case .checking: .yellow
        case .unknown, .fallback: .orange
        }
    }

    @ViewBuilder
    private func detailView(for section: NativeMacSection) -> some View {
        switch section {
        case .conversation:
            NativeConversationView()
        case .flow:
            NativeFlowView()
        case .cache:
            NativeDataLibraryView()
        case .diagnostics:
            NativeDiagnosticsView()
        case .settings:
            NativeMacSettingsView()
        }
    }
}

private struct NativeDiagnosticsView: View {
    @EnvironmentObject private var store: NativeMacShellStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NativePageHeader(
                    title: "运行诊断",
                    subtitle: "观察原生 target、本地数据库和 DeepSeek 直连状态，不把调试信息混进夜谈。"
                )

                GroupBox("运行环境") {
                    VStack(alignment: .leading, spacing: 10) {
                        LabeledContent("平台", value: "Native macOS")
                        LabeledContent("阶段", value: "N3 数据纵切")
                        LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "未知")
                        LabeledContent("缓存路径", value: store.databasePath)
                        LabeledContent("内存消息上限", value: "120 条")
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }

                GroupBox("DeepSeek API") {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledContent("状态", value: store.backendStatus.state.rawValue)
                        LabeledContent("服务", value: store.backendStatus.baseURL)
                        Text(store.backendStatus.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(store.isCheckingBackend ? "正在检查…" : "检查连接") {
                                Task { await store.testDeepSeekConnection() }
                            }
                            .disabled(store.isCheckingBackend)
                            Button("刷新本地资料") {
                                store.loadLocalCache()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }

                if let databaseError = store.databaseError {
                    Label(databaseError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
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
                LabeledContent("阶段", value: "N3 数据纵切")
                Text("原生 App 直接调用 DeepSeek，并在本地管理夜谈、日记、记忆、长期状态和每周心流导航；不依赖 Python 或 SSE。")
                    .foregroundStyle(.secondary)
            }

            Section("DeepSeek") {
                SecureField("DeepSeek API Key", text: $store.apiKeyText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("保存 Key") { store.saveAPIKey() }
                    Button(store.isCheckingBackend ? "测试中…" : "测试连接") {
                        Task { await store.testDeepSeekConnection() }
                    }
                    .disabled(store.isCheckingBackend)
                    Button("删除 Key", role: .destructive) { store.deleteAPIKey() }
                }
                Text("Key 只供原生 App 直接访问 DeepSeek；聊天、总结和资料读取均不要求启动 Python 服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .navigationTitle("设置")
    }
}

struct NativePageHeader: View {
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
