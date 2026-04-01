// MARK: - UpdateChecking
// Protocol and models for the in-app update checker.
// macOS 14+, Swift 5.10

import Foundation

// MARK: - UpdateChannel

/// Which releases the user wants to be notified about.
enum UpdateChannel: Int, CaseIterable, Codable, Sendable {
    /// Only stable (non-prerelease) versions.
    case stable = 0
    /// All versions including pre-releases.
    case preRelease = 1

    var displayName: String {
        switch self {
        case .stable:     return "Stable"
        case .preRelease: return "Pre-release"
        }
    }
}

// MARK: - AppUpdate

/// Describes an available update found on GitHub.
struct AppUpdate: Sendable, Equatable, Identifiable {
    /// Unique identifier (the tag name, e.g. `"v0.1.0"`).
    var id: String { tagName }

    let version: String
    let tagName: String
    let isPreRelease: Bool
    let releaseNotesMarkdown: String
    let htmlURL: URL
    let dmgDownloadURL: URL
    let dmgFileSize: Int64
    let publishedAt: Date
}

// MARK: - UpdateState

/// Observable state of the update service.
enum UpdateState: Sendable {
    case idle
    case checking
    case available(AppUpdate)
    case downloading(progress: Double)
    case downloaded(localURL: URL)
    case error(String)
}

// MARK: - UpdateChecking Protocol

/// Service that checks GitHub releases for app updates.
@MainActor
protocol UpdateChecking: AnyObject, Observable {
    /// Current state of the update checker.
    var state: UpdateState { get }
    /// The user's preferred update channel.
    var updateChannel: UpdateChannel { get }
    /// Check GitHub for a newer release.
    func checkForUpdates() async
    /// Download the DMG for the given update.
    func downloadUpdate(_ update: AppUpdate) async
    /// Mark a version as skipped (user won't be prompted again).
    func skipVersion(_ version: String)
    /// Change the update channel preference.
    func setUpdateChannel(_ channel: UpdateChannel)
    /// Open a previously downloaded DMG.
    func openDownloadedDMG()
    /// Start the periodic check timer (called once at app launch).
    func startPeriodicChecks()
    /// Stop the periodic check timer (called at app termination).
    func stopPeriodicChecks()
}
