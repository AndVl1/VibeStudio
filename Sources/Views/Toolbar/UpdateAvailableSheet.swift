// MARK: - UpdateAvailableSheet
// Modal sheet presenting available app update with download capability.
// macOS 14+, Swift 5.10

import SwiftUI

/// Sheet shown when a newer VibeStudio release is available on GitHub.
///
/// Follows the same structure as ``InstallAgentSheet``: header, scrollable body, footer.
/// The user can download the DMG, skip this version, or dismiss to be reminded later.
struct UpdateAvailableSheet: View {

    let update: AppUpdate

    @Environment(\.dismiss) private var dismiss
    @Environment(\.updateService) private var updateService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(DSColor.borderDefault)

            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    versionBadge
                    releaseNotes
                    downloadSize
                }
                .padding(DSSpacing.lg)
            }

            progressBar
            Divider().background(DSColor.borderDefault)
            footer
        }
        .frame(width: 480, height: 440)
        .background(DSColor.surfaceOverlay)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("Update Available")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)
            Text("A new version of VibeStudio is available.")
                .font(DSFont.sidebarItemSmall)
                .foregroundStyle(DSColor.textMuted)
        }
        .padding(DSSpacing.lg)
    }

    // MARK: - Version Badge

    private var versionBadge: some View {
        HStack(spacing: DSSpacing.sm) {
            let currentVersion = SemanticVersion.current?.description ?? "unknown"
            Text(currentVersion)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(DSColor.textSecondary)

            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textMuted)

            Text(update.version)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(DSColor.accentPrimary)

            if update.isPreRelease {
                Text("PRE-RELEASE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DSColor.actionStop)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        DSColor.actionStop.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: DSRadius.sm)
                    )
            }
        }
    }

    // MARK: - Release Notes

    @ViewBuilder
    private var releaseNotes: some View {
        if !update.releaseNotesMarkdown.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Release Notes")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DSColor.textSecondary)

                Text(update.releaseNotesMarkdown)
                    .font(.system(size: 12))
                    .foregroundStyle(DSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(DSSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DSColor.surfaceBase, in: RoundedRectangle(cornerRadius: DSRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.sm)
                            .stroke(DSColor.borderDefault, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Download Size

    private var downloadSize: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 11))
                .foregroundStyle(DSColor.textMuted)

            Text("Download size: \(formattedFileSize)")
                .font(.system(size: 12))
                .foregroundStyle(DSColor.textMuted)
        }
    }

    private var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: update.dmgFileSize)
    }

    // MARK: - Progress Bar

    @ViewBuilder
    private var progressBar: some View {
        if case .downloading(let progress) = updateService.state {
            VStack(spacing: DSSpacing.xs) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                Text("\(Int(progress * 100))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DSColor.textMuted)
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.vertical, DSSpacing.sm)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: DSSpacing.sm) {
            Button("Skip This Version") {
                updateService.skipVersion(update.version)
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(DSColor.textMuted)

            Spacer()

            Button("Later") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(DSFont.buttonLabel)
            .foregroundStyle(DSColor.textSecondary)
            .frame(width: 72, height: DSLayout.gitButtonHeight)
            .background(DSColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.md)
                    .stroke(DSColor.borderDefault, lineWidth: 1)
            )

            primaryButton
        }
        .padding(DSSpacing.lg)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch updateService.state {
        case .downloading:
            Button("Downloading...") {}
                .buttonStyle(.plain)
                .font(DSFont.buttonLabel)
                .foregroundStyle(DSColor.buttonPrimaryText)
                .frame(width: 120, height: DSLayout.gitButtonHeight)
                .background(DSColor.buttonPrimaryBg.opacity(0.6), in: RoundedRectangle(cornerRadius: DSRadius.md))
                .disabled(true)

        case .downloaded:
            Button("Open DMG") {
                updateService.openDownloadedDMG()
                dismiss()
            }
            .buttonStyle(.plain)
            .font(DSFont.buttonLabel)
            .foregroundStyle(DSColor.buttonPrimaryText)
            .frame(width: 120, height: DSLayout.gitButtonHeight)
            .background(DSColor.actionRun, in: RoundedRectangle(cornerRadius: DSRadius.md))

        default:
            Button("Download") {
                Task { await updateService.downloadUpdate(update) }
            }
            .buttonStyle(.plain)
            .font(DSFont.buttonLabel)
            .foregroundStyle(DSColor.buttonPrimaryText)
            .frame(width: 120, height: DSLayout.gitButtonHeight)
            .background(DSColor.buttonPrimaryBg, in: RoundedRectangle(cornerRadius: DSRadius.md))
        }
    }
}
