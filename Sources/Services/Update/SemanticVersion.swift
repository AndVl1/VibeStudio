// MARK: - SemanticVersion
// Lightweight semantic version parser and comparator.
// macOS 14+, Swift 5.10

import Foundation

/// A parsed semantic version (major.minor.patch with optional pre-release suffix).
///
/// Supports version strings like `"0.0.6"`, `"v1.2.3"`, `"v1.0.0-beta.1"`.
/// The leading `v` prefix is stripped automatically.
struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {

    let major: Int
    let minor: Int
    let patch: Int
    /// Pre-release identifier (e.g. `"beta.1"`, `"rc.2"`). `nil` for stable releases.
    let preRelease: String?

    var isPreRelease: Bool { preRelease != nil }

    var description: String {
        let base = "\(major).\(minor).\(patch)"
        if let pre = preRelease {
            return "\(base)-\(pre)"
        }
        return base
    }

    // MARK: - Parsing

    /// Parse a version string into a ``SemanticVersion``.
    ///
    /// Accepts formats: `"0.0.6"`, `"v1.2.3"`, `"1.0.0-beta.1"`, `"v2.0.0-rc.1"`.
    /// Returns `nil` for unparseable strings.
    static func parse(_ string: String) -> SemanticVersion? {
        var s = string.trimmingCharacters(in: .whitespaces)
        // Strip leading "v" or "V"
        if s.hasPrefix("v") || s.hasPrefix("V") {
            s = String(s.dropFirst())
        }
        guard !s.isEmpty else { return nil }

        // Split on first "-" to separate base from pre-release
        let preRelease: String?
        let base: String
        if let dashIndex = s.firstIndex(of: "-") {
            base = String(s[s.startIndex..<dashIndex])
            let pre = String(s[s.index(after: dashIndex)...])
            preRelease = pre.isEmpty ? nil : pre
        } else {
            base = s
            preRelease = nil
        }

        // Parse major.minor.patch
        let parts = base.split(separator: ".", maxSplits: 3)
        guard parts.count >= 2, parts.count <= 3 else { return nil }

        guard let major = Int(parts[0]),
              let minor = Int(parts[1]) else { return nil }
        let patch: Int
        if parts.count == 3 {
            guard let p = Int(parts[2]) else { return nil }
            patch = p
        } else {
            patch = 0
        }

        return SemanticVersion(major: major, minor: minor, patch: patch, preRelease: preRelease)
    }

    /// The current app version parsed from `Bundle.main`.
    static var current: SemanticVersion? {
        guard let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return parse(versionString)
    }

    // MARK: - Comparable

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        // Compare major.minor.patch numerically
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Same numeric version: stable (nil preRelease) > pre-release
        switch (lhs.preRelease, rhs.preRelease) {
        case (nil, nil):
            return false // equal
        case (nil, .some):
            return false // stable > pre-release
        case (.some, nil):
            return true  // pre-release < stable
        case (.some(let l), .some(let r)):
            return l < r // lexicographic comparison
        }
    }
}
