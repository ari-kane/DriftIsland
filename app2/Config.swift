//
//  Config.swift
//  Global app configuration. Change `kAppName` here and the entire app
//  re-brands itself: window titles, Bonjour service type, log labels, UI text.
//

import Foundation

// MARK: - Single source of truth for the app's identity
// Change this one string to rename the whole app everywhere.
nonisolated let kAppName: String = "DriftIsland"

// MARK: - Derived identifiers

nonisolated enum AppConfig {

    /// Bare service name passed to `MCNearbyServiceBrowser` /
    /// `MCNearbyServiceAdvertiser`. Lowercase ASCII letters/digits/hyphens,
    /// 1..15 chars, NO underscore prefix, NO `._tcp` suffix.
    /// e.g. kAppName "DeskShelf" -> "deskshelf"
    static var bonjourServiceType: String {
        let lower = kAppName.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let sanitized = String(lower.unicodeScalars.filter { allowed.contains($0) })
        let trimmed = String(sanitized.prefix(15))
        return trimmed.isEmpty ? "app" : trimmed
    }

    /// Full Bonjour service string for the `NSBonjourServices` Info.plist
    /// entry — this one DOES need the leading `_` and the `._tcp` suffix.
    /// e.g. "_deskshelf._tcp"
    static var bonjourInfoPlistEntry: String {
        "_\(bonjourServiceType)._tcp"
    }

    /// The dictionary key inside `MCNearbyServiceAdvertiser.discoveryInfo`
    /// that carries the 4-digit pairing code.
    static let pairingCodeKey = "pairingCode"

    /// Generate a fresh 4-digit pairing code (zero-padded, 0000…9999).
    static func makePairingCode() -> String {
        String(format: "%04d", Int.random(in: 0...9999))
    }

    /// Convenience for log lines so every print is tagged with the app name.
    static func log(_ message: String) {
        print("[\(kAppName)] \(message)")
    }
}
