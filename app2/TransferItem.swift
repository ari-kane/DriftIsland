//
//  TransferItem.swift
//  Shared payload model. The Mac sends one of these as JSON to the iPhone
//  the moment a drop is detected, so the iPhone can pop a card up under 5ms.
//  The actual binary data (if any) follows over `sendResource`.
//

import Foundation

/// A lightweight metadata package — small enough to deliver instantly.
nonisolated struct TransferItem: Codable, Identifiable, Hashable, Sendable {

    enum Kind: String, Codable, Sendable {
        case file
        case url
    }

    var id: UUID
    var name: String
    var kind: Kind
    /// Bytes total for files; nil for URLs.
    var byteCount: Int64?
    /// For URLs: the full link. For files: nil (resource is streamed separately).
    var urlString: String?
    /// PNG-encoded thumbnail / icon preview, small (<= ~16 KB).
    var iconPNG: Data?
    /// Live progress 0...1 — mutated locally on each side as the resource streams.
    var progress: Double = 0
    /// For files only: the ORIGINAL file:// URL on the Mac. Sent along with
    /// the metadata so that when the user taps the card on the iPhone, the
    /// phone can ask the Mac to re-open the file at this path.
    var macSourcePath: String?

    init(
        id: UUID = UUID(),
        name: String,
        kind: Kind,
        byteCount: Int64? = nil,
        urlString: String? = nil,
        iconPNG: Data? = nil,
        progress: Double = 0,
        macSourcePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.byteCount = byteCount
        self.urlString = urlString
        self.iconPNG = iconPNG
        self.progress = progress
        self.macSourcePath = macSourcePath
    }
}

extension TransferItem {
    /// Human-friendly size string. Used by the iPhone card.
    var formattedSize: String {
        guard let bytes = byteCount else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

/// Wire-level envelope. Every byte sent through MCSession.send is one of
/// these. Adding new message kinds = add a new case + handle it on both sides.
nonisolated enum WirePayload: Codable, Sendable {
    /// A brand new item is being announced (Mac -> iPhone direction).
    case item(TransferItem)
    /// Please open this URL on the OTHER device (iPhone -> Mac, primarily).
    case open(String)
}
