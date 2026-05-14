import SwiftUI
import AppKit

// MARK: - RealESRGANInstallView

/// Real-ESRGAN 安装管理视图
/// 显示当前安装状态，支持自动下载、手动更新、检查更新、打开目录。
struct RealESRGANInstallView: View {

    @ObservedObject private var manager = RealESRGANManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // ── 状态行 ────────────────────────────────────────────────
            HStack(spacing: 8) {
                stateIcon
                    .frame(width: 16, height: 16)

                Text(manager.installState.label)
                    .font(.caption)
                    .foregroundStyle(stateLabelColor)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                // 更新徽章
                if manager.updateAvailable, let latest = manager.latestVersion {
                    Text("v\(latest)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(stateBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(stateBorderColor, lineWidth: 0.5)
                    )
            )

            // ── 进度条（下载中显示）────────────────────────────────────
            if case .downloading(let p) = manager.installState {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                    Text(String(format: "%.0f%%", p * 100))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── 操作按钮行 ────────────────────────────────────────────
            HStack(spacing: 6) {
                // 安装 / 重试：未安装或失败时显示
                // !isInstalled 已包含 .notInstalled 情况，无需额外 || == .notInstalled
                if !manager.installState.isInstalled {
                    Button {
                        Task { await manager.downloadIfNeeded() }
                    } label: {
                        Label(
                            manager.installState == .notInstalled ? "自动安装" : "重试",
                            systemImage: "arrow.down.circle"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(manager.installState.isWorking)
                }

                // 检查更新（含加载指示器）
                if manager.installState.isInstalled {
                    Button {
                        Task { await manager.checkForUpdate() }
                    } label: {
                        HStack(spacing: 4) {
                            if manager.isCheckingUpdate {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                            Text(manager.isCheckingUpdate ? "检查中…" : "检查更新")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(manager.installState.isWorking || manager.isCheckingUpdate)
                }

                // 立即更新（有新版时高亮）
                if manager.updateAvailable {
                    Button {
                        Task { await manager.forceUpdate() }
                    } label: {
                        Label("立即更新", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(manager.installState.isWorking)
                }

                Spacer(minLength: 0)

                // 打开目录
                Button {
                    openInstallDir()
                } label: {
                    Image(systemName: "folder")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("打开 Real-ESRGAN 安装目录")
            }
            // ── 检查更新反馈信息 ──────────────────────────────────────
            if let feedback = manager.checkFeedback {
                HStack(spacing: 5) {
                    Image(systemName: feedbackIcon)
                        .foregroundStyle(feedbackColor)
                        .font(.caption2)
                    Text(feedback)
                        .font(.caption2)
                        .foregroundStyle(feedbackColor.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(feedbackColor.opacity(0.08))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeInOut(duration: 0.2), value: manager.checkFeedback)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: manager.installState.isInstalled)
        .task {
            await manager.downloadIfNeeded()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var stateIcon: some View {
        switch manager.installState {
        case .notInstalled:
            Image(systemName: "arrow.down.circle")
                .foregroundStyle(.secondary)
        case .fetchingRelease, .extracting:
            ProgressView()
                .controlSize(.mini)
        case .downloading:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .installed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var stateLabelColor: Color {
        switch manager.installState {
        case .installed:  return .primary
        case .failed:     return .orange
        default:          return .secondary
        }
    }

    private var stateBackgroundColor: Color {
        switch manager.installState {
        case .installed:  return Color.green.opacity(0.06)
        case .failed:     return Color.orange.opacity(0.06)
        case .downloading: return Color.accentColor.opacity(0.06)
        default:          return Color.secondary.opacity(0.05)
        }
    }

    private var stateBorderColor: Color {
        switch manager.installState {
        case .installed:  return Color.green.opacity(0.2)
        case .failed:     return Color.orange.opacity(0.2)
        case .downloading: return Color.accentColor.opacity(0.2)
        default:          return Color.secondary.opacity(0.12)
        }
    }

    private var feedbackIcon: String {
        if manager.updateAvailable { return "exclamationmark.circle.fill" }
        if let f = manager.checkFeedback, f.hasPrefix("检查失败") { return "xmark.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var feedbackColor: Color {
        if manager.updateAvailable { return .orange }
        if let f = manager.checkFeedback, f.hasPrefix("检查失败") { return .red }
        return .green
    }

    private func openInstallDir() {
        let url = RealESRGANManager.shared.installDirURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    RealESRGANInstallView()
        .padding()
        .frame(width: 300)
}
