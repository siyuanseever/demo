import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: CompanionStore

    var body: some View {
        ZStack {
            WarmBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader(
                        title: "连接与开发",
                        subtitle: "这里用来确认 iOS 正在连接哪里，也保留离线 fallback 的边界。"
                    )
                    BackendStatusPanel(status: store.backendStatus) {
                        Task {
                            await store.checkBackendConnection()
                        }
                    }
                    DevelopmentNotesPanel()
                }
                .padding(18)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.backendStatus.state == .unknown {
                await store.checkBackendConnection()
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

private struct DevelopmentNotesPanel: View {
    var body: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("开发提示", systemImage: "hammer.fill")
                    .font(.headline)
                Text("默认连接 README 里的 http://127.0.0.1:8765。模拟器调试时可以通过 XIAOLU_BACKEND_URL 覆盖，例如指向 fake provider 的 8768。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("当后端不可用时，对话页会显示提示，并使用 iOS 原型回复，不会让用户卡在空白状态。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
