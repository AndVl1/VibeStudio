// MARK: - GitHub Release API Models
// Codable DTOs for the GitHub Releases REST API.
// macOS 14+, Swift 5.10

import Foundation

/// A single release from the GitHub Releases API.
///
/// Only the fields relevant to update checking are decoded;
/// the rest are silently ignored by the decoder.
struct GitHubRelease: Decodable, Sendable {
    let tagName: String
    let name: String?
    let htmlUrl: String
    let prerelease: Bool
    let publishedAt: String
    let body: String?
    let assets: [GitHubReleaseAsset]
}

/// An asset attached to a GitHub release (DMG, ZIP, etc.).
struct GitHubReleaseAsset: Decodable, Sendable {
    let name: String
    let browserDownloadUrl: String
    let size: Int64
}
