import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(
                        title: "设置",
                        subtitle: "管理 Mac 连接、数据同步和手机上的本地记录。"
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
        .task {
            await store.syncIfNeeded()
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

                Text("手机会保留最近同步的会话、记忆、总结和长期画像。Mac 暂时不在线时，仍然可以查看已经保存的内容。")
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
                    Label(isSyncing ? "正在同步" : "立即同步", systemImage: "arrow.triangle.2.circlepath")
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
