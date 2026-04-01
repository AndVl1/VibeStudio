// MARK: - UpdateService
// Checks GitHub releases for app updates and downloads DMGs.
// macOS 14+, Swift 5.10

import AppKit
import Foundation
import Observation
import OSLog

/// Checks the `AlexGladkov/VibeStudio` GitHub repository for new releases
/// and offers to download them.
///
/// Follows the same patterns as ``AgentAvailabilityService`` and ``GitStatusPoller``:
/// `@Observable @MainActor`, `Task.detached` for networking, `UserDefaults` for persistence.
@Observable
@MainActor
final class UpdateService: UpdateChecking {

    // MARK: - Observable State

    private(set) var state: UpdateState = .idle
    private(set) var updateChannel: UpdateChannel

    // MARK: - Configuration

    private static let releasesURL = "https://api.github.com/repos/AlexGladkov/VibeStudio/releases"
    private static let checkInterval: TimeInterval = 24 * 60 * 60 // 24 hours

    // MARK: - UserDefaults Keys

    private static let channelKey = "vs_updateChannel"
    private static let skippedKey = "vs_skippedVersions"
    private static let lastCheckKey = "vs_lastUpdateCheck"

    // MARK: - Private State

    private let navigationCoordinator: AppNavigationCoordinator
    private let defaults: UserDefaults
    private var skippedVersions: Set<String>
    private var lastCheckDate: Date

    // nonisolated(unsafe): deinit is nonisolated and must cancel these tasks.
    // Safe because deinit only runs when no other references exist.
    nonisolated(unsafe) private var periodicCheckTask: Task<Void, Never>?
    nonisolated(unsafe) private var downloadTask: Task<Void, Never>?

    /// Guards against concurrent check calls.
    private var isChecking = false

    // MARK: - Init

    init(navigationCoordinator: AppNavigationCoordinator, defaults: UserDefaults = .standard) {
        self.navigationCoordinator = navigationCoordinator
        self.defaults = defaults

        // Load persisted update channel
        let rawChannel = defaults.integer(forKey: Self.channelKey)
        self.updateChannel = UpdateChannel(rawValue: rawChannel) ?? .stable

        // Load skipped versions
        if let data = defaults.data(forKey: Self.skippedKey),
           let versions = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.skippedVersions = versions
        } else {
            self.skippedVersions = []
        }

        // Load last check timestamp
        let timestamp = defaults.double(forKey: Self.lastCheckKey)
        self.lastCheckDate = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : .distantPast
    }

    deinit {
        periodicCheckTask?.cancel()
        downloadTask?.cancel()
    }

    // MARK: - UpdateChecking

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        state = .checking
        defer { isChecking = false }

        do {
            let releases = try await fetchReleases()
            let update = findBestUpdate(from: releases)

            if let update {
                state = .available(update)
                navigationCoordinator.availableUpdate = update
            } else {
                state = .idle
            }

            lastCheckDate = Date()
            defaults.set(lastCheckDate.timeIntervalSince1970, forKey: Self.lastCheckKey)
        } catch {
            let message = error.localizedDescription
            state = .error(message)
            Logger.update.error("Update check failed: \(message, privacy: .public)")
        }
    }

    func downloadUpdate(_ update: AppUpdate) async {
        state = .downloading(progress: 0.0)

        do {
            let localURL = try await downloadDMG(from: update.dmgDownloadURL, version: update.version, fileSize: update.dmgFileSize)
            state = .downloaded(localURL: localURL)
        } catch is CancellationError {
            state = .idle
        } catch {
            let message = error.localizedDescription
            state = .error(message)
            Logger.update.error("Download failed: \(message, privacy: .public)")
        }
    }

    func skipVersion(_ version: String) {
        skippedVersions.insert(version)
        persistSkippedVersions()
        state = .idle
        navigationCoordinator.availableUpdate = nil
    }

    func setUpdateChannel(_ channel: UpdateChannel) {
        updateChannel = channel
        defaults.set(channel.rawValue, forKey: Self.channelKey)
        // Re-check immediately with the new channel
        Task { await checkForUpdates() }
    }

    func openDownloadedDMG() {
        guard case .downloaded(let url) = state else { return }
        NSWorkspace.shared.open(url)
        state = .idle
        navigationCoordinator.availableUpdate = nil
    }

    func startPeriodicChecks() {
        guard periodicCheckTask == nil else { return }

        periodicCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Initial check (skip if checked recently)
            if Date().timeIntervalSince(self.lastCheckDate) >= Self.checkInterval {
                await self.checkForUpdates()
            }

            // Periodic loop
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.checkInterval))
                guard !Task.isCancelled else { return }
                await self.checkForUpdates()
            }
        }
    }

    func stopPeriodicChecks() {
        periodicCheckTask?.cancel()
        periodicCheckTask = nil
        downloadTask?.cancel()
        downloadTask = nil
    }

    // MARK: - Private: Networking

    /// Fetch all releases from the GitHub API.
    private func fetchReleases() async throws -> [GitHubRelease] {
        guard let url = URL(string: Self.releasesURL) else {
            throw UpdateServiceError.networkError(underlying: "Invalid releases URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateServiceError.networkError(underlying: "Invalid response")
        }

        if httpResponse.statusCode == 403 {
            throw UpdateServiceError.rateLimited
        }

        guard httpResponse.statusCode == 200 else {
            throw UpdateServiceError.networkError(underlying: "HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([GitHubRelease].self, from: data)
    }

    /// Download a DMG to ~/Downloads with progress tracking.
    private func downloadDMG(from url: URL, version: String, fileSize: Int64) async throws -> URL {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destination = downloadsDir.appendingPathComponent("VibeStudio-\(version).dmg")

        // Remove existing file if present (re-download)
        try? FileManager.default.removeItem(at: destination)

        let (asyncBytes, response) = try await URLSession.shared.bytes(from: url)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UpdateServiceError.downloadFailed(underlying: "HTTP error")
        }

        let expectedLength = httpResponse.expectedContentLength > 0
            ? httpResponse.expectedContentLength
            : fileSize

        var receivedData = Data()
        receivedData.reserveCapacity(Int(expectedLength))

        var lastReportedPercent: Int = -1

        for try await byte in asyncBytes {
            try Task.checkCancellation()
            receivedData.append(byte)

            // Throttle progress updates to every 1%
            if expectedLength > 0 {
                let percent = Int(Double(receivedData.count) / Double(expectedLength) * 100)
                if percent != lastReportedPercent {
                    lastReportedPercent = percent
                    let progress = Double(receivedData.count) / Double(expectedLength)
                    await MainActor.run { [weak self] in
                        self?.state = .downloading(progress: min(progress, 1.0))
                    }
                }
            }
        }

        do {
            try receivedData.write(to: destination, options: .atomic)
        } catch {
            throw UpdateServiceError.fileWriteFailed(underlying: error.localizedDescription)
        }

        Logger.update.info("Downloaded update v\(version, privacy: .public) to \(destination.path, privacy: .public)")
        return destination
    }

    // MARK: - Private: Version Comparison

    /// Find the best available update from a list of GitHub releases.
    private func findBestUpdate(from releases: [GitHubRelease]) -> AppUpdate? {
        guard let currentVersion = SemanticVersion.current else {
            Logger.update.warning("Could not determine current app version")
            return nil
        }

        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        var bestUpdate: AppUpdate?
        var bestVersion: SemanticVersion?

        for release in releases {
            // Filter by channel
            if updateChannel == .stable && release.prerelease {
                continue
            }

            // Parse version
            guard let version = SemanticVersion.parse(release.tagName) else {
                Logger.update.debug("Skipping release with unparseable tag: \(release.tagName, privacy: .public)")
                continue
            }

            // Must be newer than current
            guard version > currentVersion else { continue }

            // Must be newer than current best candidate
            if let best = bestVersion, version <= best { continue }

            // Must not be skipped
            if skippedVersions.contains(version.description) { continue }

            // Must have a DMG asset
            guard let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }),
                  let dmgURL = URL(string: dmgAsset.browserDownloadUrl),
                  let htmlURL = URL(string: release.htmlUrl) else {
                continue
            }

            let publishedDate = iso8601Formatter.date(from: release.publishedAt)
                ?? fallbackFormatter.date(from: release.publishedAt)
                ?? Date()

            bestUpdate = AppUpdate(
                version: version.description,
                tagName: release.tagName,
                isPreRelease: release.prerelease,
                releaseNotesMarkdown: release.body ?? "",
                htmlURL: htmlURL,
                dmgDownloadURL: dmgURL,
                dmgFileSize: dmgAsset.size,
                publishedAt: publishedDate
            )
            bestVersion = version
        }

        return bestUpdate
    }

    // MARK: - Private: Persistence

    private func persistSkippedVersions() {
        if let data = try? JSONEncoder().encode(skippedVersions) {
            defaults.set(data, forKey: Self.skippedKey)
        }
    }
}
