// MARK: - UpdateSettingsPane
// Settings pane for configuring in-app update preferences.
// macOS 14+, Swift 5.10

import SwiftUI

/// Settings pane for update channel selection and manual check trigger.
///
/// Follows the same layout pattern as ``GeneralSettingsPane``.
struct UpdateSettingsPane: View {

    @Environment(\.updateService) private var updateService

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xl) {
            Text("Обновления")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DSColor.textPrimary)

            Divider().background(DSColor.borderDefault)

            // Update channel picker
            HStack(spacing: DSSpacing.lg) {
                Text("Канал")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(width: 120, alignment: .leading)

                Picker("", selection: Binding(
                    get: { updateService.updateChannel.rawValue },
                    set: { updateService.setUpdateChannel(UpdateChannel(rawValue: $0) ?? .stable) }
                )) {
                    Text("Stable").tag(0)
                    Text("Pre-release").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .labelsHidden()

                Spacer()
            }

            // Last checked
            HStack(spacing: DSSpacing.lg) {
                Text("Последняя проверка")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(width: 120, alignment: .leading)

                Text(lastCheckedText)
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textSecondary)

                Spacer()
            }

            // Check now button
            HStack(spacing: DSSpacing.lg) {
                Text("")
                    .frame(width: 120)

                Button {
                    Task { await updateService.checkForUpdates() }
                } label: {
                    HStack(spacing: DSSpacing.xs) {
                        if case .checking = updateService.state {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(checkButtonLabel)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DSColor.buttonPrimaryText)
                .padding(.horizontal, DSSpacing.md)
                .frame(height: DSLayout.gitButtonHeight)
                .background(DSColor.buttonPrimaryBg, in: RoundedRectangle(cornerRadius: DSRadius.md))
                .disabled(isCheckDisabled)

                statusText

                Spacer()
            }

            Divider().background(DSColor.borderDefault)

            // Current version
            HStack(spacing: DSSpacing.lg) {
                Text("Текущая версия")
                    .font(.system(size: 13))
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(width: 120, alignment: .leading)

                Text(SemanticVersion.current?.description ?? "unknown")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(DSColor.textSecondary)

                Spacer()
            }

            Spacer()
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Computed Helpers

    private var lastCheckedText: String {
        let defaults = UserDefaults.standard
        let timestamp = defaults.double(forKey: "vs_lastUpdateCheck")
        guard timestamp > 0 else { return "Никогда" }

        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var checkButtonLabel: String {
        if case .checking = updateService.state {
            return "Проверяю..."
        }
        return "Проверить сейчас"
    }

    private var isCheckDisabled: Bool {
        if case .checking = updateService.state { return true }
        return false
    }

    @ViewBuilder
    private var statusText: some View {
        switch updateService.state {
        case .available(let update):
            Text("Доступна версия \(update.version)")
                .font(.system(size: 12))
                .foregroundStyle(DSColor.actionRun)
        case .error(let message):
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(DSColor.actionStop)
                .lineLimit(1)
        default:
            EmptyView()
        }
    }
}
