import SwiftUI
import AppKit

// MARK: - RealESRGANInstallView

/// Real-ESRGAN 安装管理视图
/// 显示当前安装状态，支持自动下载、手动更新、检查更新、打开目录、配置 GitHub Token。
struct RealESRGANInstallView: View {

    /// 使用 @ObservedObject 而非 @StateObject：
    /// shared 是单例，其生命周期由外部管理，@StateObject 会错误地接管所有权。
    @ObservedObject private var manager = RealESRGANManager.shared

    // MARK: - Token 输入状态

    /// 控制 Token 输入区域的展开/折叠
    @State private var showTokenInput: Bool = false
    /// 输入框中的临时 Token 文本
    @State private var tokenDraft: String = ""
    /// Token 保存成功的短暂反馈
    @State private var tokenSavedFeedback: Bool = false

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

                // GitHub Token 配置按钮
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showTokenInput.toggle()
                        if showTokenInput {
                            // 展开时预填已保存的 token（脱敏显示）
                            tokenDraft = ""
                        }
                    }
                } label: {
                    Image(systemName: manager.hasGitHubToken
                          ? "key.fill"
                          : "key")
                        .font(.caption)
                        .foregroundStyle(manager.hasGitHubToken ? Color.accentColor : .secondary)
                }
                .buttonStyle(.borderless)
                .help(manager.hasGitHubToken
                      ? "已配置 GitHub Token（点击修改）"
                      : "配置 GitHub Token（解决 API 速率限制）")

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

            // ── GitHub Token 输入区域 ─────────────────────────────────
            if showTokenInput {
                tokenInputSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
        .animation(.easeInOut(duration: 0.2), value: showTokenInput)
        .task {
            await manager.downloadIfNeeded()
        }
    }

    // MARK: - Token 输入区域

    private var tokenInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {

            // 标题行
            HStack(spacing: 5) {
                Image(systemName: "key.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Text("GitHub Personal Access Token")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                // 已配置标记
                if manager.hasGitHubToken && tokenDraft.isEmpty {
                    Label("已配置", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            // 说明文字
            Text("配置 Token 可将 GitHub API 速率限制从 60次/小时 提升至 5000次/小时，解决下载失败问题。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // 输入框 + 操作按钮
            HStack(spacing: 6) {
                SecureField(
                    manager.hasGitHubToken ? "输入新 Token 以替换…" : "ghp_xxxxxxxxxxxxxxxxxxxx",
                    text: $tokenDraft
                )
                .font(.caption.monospaced())
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveToken() }

                // 保存按钮
                Button {
                    saveToken()
                } label: {
                    Text(tokenSavedFeedback ? "已保存 ✓" : "保存")
                        .font(.caption)
                        .foregroundStyle(tokenSavedFeedback ? .green : .primary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(tokenDraft.trimmingCharacters(in: .whitespaces).isEmpty)

                // 清除按钮（已有 Token 时显示）
                if manager.hasGitHubToken {
                    Button {
                        clearToken()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red.opacity(0.7))
                    .help("删除已保存的 Token")
                }
            }

            // 帮助链接
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Button("如何创建 Token？") {
                    NSWorkspace.shared.open(
                        URL(string: "https://github.com/settings/tokens/new?scopes=&description=IconKit")!
                    )
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(Color.accentColor.opacity(0.8))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.accentColor.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.accentColor.opacity(0.15), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Token Actions

    private func saveToken() {
        let trimmed = tokenDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        manager.githubToken = trimmed
        tokenDraft = ""
        withAnimation {
            tokenSavedFeedback = true
        }
        // 1.5 秒后隐藏反馈并折叠输入区（使用 Task 替代 DispatchQueue，与 SwiftUI 并发模型一致）
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                tokenSavedFeedback = false
                showTokenInput = false
            }
        }
    }

    private func clearToken() {
        manager.githubToken = nil
        tokenDraft = ""
        withAnimation(.easeInOut(duration: 0.2)) {
            showTokenInput = false
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
