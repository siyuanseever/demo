import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CompanionStore
    @State private var apiKey = ""
    @State private var macBackendURL = ""
    @State private var macSyncToken = ""

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(
                        title: "设置",
                        subtitle: "手机可以独立保存和对话；需要时再与同一局域网里的 Mac 同步。"
                    )
                    LocalAISettingsPanel(
                        apiKey: $apiKey,
                        isConfigured: store.isLocalAIConfigured,
                        notice: store.localAISettingsNotice,
                        save: {
                            store.saveDeepSeekAPIKey(apiKey)
                            apiKey = ""
                        },
                        clear: store.clearDeepSeekAPIKey
                    )
                    MacConnectionPanel(
                        backendURL: $macBackendURL,
                        syncToken: $macSyncToken,
                        isTokenConfigured: store.isMacSyncTokenConfigured,
                        status: store.backendStatus,
                        save: {
                            store.saveMacBackendURL(macBackendURL)
                        },
                        saveToken: {
                            store.saveMacSyncToken(macSyncToken)
                            macSyncToken = ""
                        }
                    )
                    BackendStatusPanel(status: store.backendStatus) {
                        Task {
                            await store.checkBackendConnection()
                        }
                    }
                    DataSyncPanel(
                        snapshot: store.snapshot,
                        isSyncing: store.isBackendSyncing,
                        lastSyncAt: store.lastBackendSyncAt,
                        notice: store.sessionNotice
                    ) {
                        Task {
                            await store.syncAllFromBackend()
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            macBackendURL = store.macBackendURL
        }
    }
}

private struct LocalAISettingsPanel: View {
    @Binding var apiKey: String
    let isConfigured: Bool
    let notice: String?
    let save: () -> Void
    let clear: () -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("手机独立模式", systemImage: "iphone.gen3")
                        .font(.headline)
                    Spacer()
                    Text(isConfigured ? "已启用" : "未配置")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isConfigured ? Color.green : Color.warmBrown)
                }

                Text("配置后，聊天会由手机直接调用 DeepSeek，session 和消息保存在手机数据库中，不需要连接 Mac。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField(isConfigured ? "输入新 Key 可替换现有 Key" : "DeepSeek API Key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Button(action: save) {
                        Label("保存 Key", systemImage: "key.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.warmBrown)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if isConfigured {
                        Button(role: .destructive, action: clear) {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("移除 DeepSeek API Key")
                    }
                }

                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label("API Key 仅保存在这台设备的系统钥匙串，不会写入数据库或同步给 Mac。", systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct MacConnectionPanel: View {
    @Binding var backendURL: String
    @Binding var syncToken: String
    let isTokenConfigured: Bool
    let status: BackendConnectionStatus
    let save: () -> Void
    let saveToken: () -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("Mac 局域网连接", systemImage: "desktopcomputer")
                    .font(.headline)

                TextField("例如 http://192.168.1.20:8765", text: $backendURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.callout.monospaced())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))

                Button(action: save) {
                    Label("保存局域网地址", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.warmBrown)

                SecureField(
                    isTokenConfigured ? "输入新令牌可替换现有令牌" : "Mac 同步令牌",
                    text: $syncToken
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout.monospaced())
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))

                Button(action: saveToken) {
                    Label(isTokenConfigured ? "更新同步令牌" : "保存同步令牌", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.warmBrown)
                .disabled(syncToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Mac 启动前设置相同的 SENSEN_SYNC_TOKEN。只有点击下面的同步按钮时，App 才会连接 Mac。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BackendStatusPanel: View {
    let status: BackendConnectionStatus
    let check: () -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center) {
                    Label(status.state.rawValue, systemImage: iconName)
                        .font(.headline)
                        .foregroundStyle(status.isOnline ? Color.green : Color.warmBrown)
                    Spacer()
                    Button(action: check) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(status.state == .checking)
                    .accessibilityLabel("重新检查后端连接")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("后端地址")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(status.baseURL.isEmpty ? "未设置" : status.baseURL)
                        .font(.callout.monospaced())
                        .foregroundStyle(Color.nightInk)
                        .textSelection(.enabled)
                }
                Text(status.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastCheckedAt = status.lastCheckedAt {
                    Text("上次检查：\(lastCheckedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var iconName: String {
        switch status.state {
        case .unknown:
            return "questionmark.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .online:
            return "checkmark.circle.fill"
        case .fallback:
            return "exclamationmark.circle.fill"
        }
    }
}

private struct DataSyncPanel: View {
    let snapshot: DashboardSnapshot
    let isSyncing: Bool
    let lastSyncAt: Date?
    let notice: String?
    let sync: () -> Void

    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 14) {
                Label("数据与同步", systemImage: "externaldrive.fill")
                    .font(.headline)

                Text("手机本地数据始终可用。连接同一局域网的 Mac 后，可手动交换会话、记忆、总结和长期画像。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SettingsDataCount(title: "会话", value: snapshot.sessionCount)
                    SettingsDataCount(title: "消息", value: snapshot.messageCount)
                    SettingsDataCount(title: "记忆", value: snapshot.memoryCount)
                    SettingsDataCount(title: "总结", value: snapshot.journalCount)
                }

                if let lastSyncAt {
                    Label(
                        "最近同步：\(lastSyncAt.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "checkmark.icloud.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let notice, !notice.isEmpty {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(action: sync) {
                    Label(isSyncing ? "正在同步" : "与 Mac 同步", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.nightInk)
                .background(Color(hex: 0xffeee9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(isSyncing)
            }
        }
    }
}

private struct SettingsDataCount: View {
    let title: String
    let value: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.nightInk)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
