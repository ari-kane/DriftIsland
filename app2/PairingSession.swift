//
//  PairingSession.swift
//  All networking lives in this one class. The UI reads @Published state
//  and calls a tiny surface of methods — start(), submitCode(), sendDrop().
//
//  Architecture:
//    * Mac runs as the ADVERTISER. On launch it picks a fresh 4-digit code,
//      stuffs it into MCNearbyServiceAdvertiser.discoveryInfo, and waits.
//    * iPhone runs as the BROWSER. As it finds nearby Macs, it caches them
//      keyed by their advertised 4-digit code. When the user types a code,
//      it invites the matching peer.
//    * Once connected, the Mac sends instant JSON metadata via .send(),
//      then streams the heavy binary via .sendResource() in parallel.
//
//  IMPORTANT — Info.plist requirements (set in Xcode > target > Info):
//    NSBonjourServices            = ["_<sanitized-kAppName>._tcp"]
//    NSLocalNetworkUsageDescription = "Used to pair with your nearby <kAppName> devices."
//

import Foundation
import Combine
import SwiftUI
import MultipeerConnectivity

#if os(iOS)
import UIKit
#endif

#if os(macOS)
import AppKit
#endif

@MainActor
final class PairingSession: NSObject, ObservableObject {

    enum Role { case mac, phone }
    enum ConnectionState: Equatable { case idle, searching, connecting, connected }

    // MARK: Published UI state

    /// 4-digit code. On Mac: the one we advertise. On iPhone: what the user typed.
    @Published var pairingCode: String = ""
    @Published var state: ConnectionState = .idle
    @Published var peerName: String?
    /// Items delivered TO the iPhone, or sent FROM the Mac (mirrored for UI).
    @Published var items: [TransferItem] = []
    /// One-shot signal the iPhone UI uses to fire a haptic on every new card.
    @Published var lastReceivedID: UUID?
    /// Per-item iPhone-local customizations (SF Symbol icon override and
    /// bead-icon colour). Not synced to the Mac — they're cosmetic.
    @Published var customIcons: [UUID: String] = [:]
    @Published var customColors: [UUID: Color] = [:]
    /// Brief informational message shown as a toast (e.g. "Copied to
    /// Mac clipboard"). Reset to nil automatically after a short delay.
    @Published var toastText: String?

    private var toastClearTask: Task<Void, Never>?

    func showToast(_ text: String) {
        toastClearTask?.cancel()
        toastText = text
        toastClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.toastText = nil
        }
    }

    // MARK: Internal

    private let role: Role
    // peerID and session are immutable after init and accessed from
    // nonisolated MultipeerConnectivity delegate callbacks — mark nonisolated
    // so the compiler permits cross-actor access without a hop.
    nonisolated private let peerID: MCPeerID
    nonisolated private let session: MCSession

    #if os(macOS)
    private var advertiser: MCNearbyServiceAdvertiser?
    #else
    private var browser: MCNearbyServiceBrowser?
    /// peers found nearby, keyed by their advertised 4-digit code
    private var peersByCode: [String: MCPeerID] = [:]
    #endif

    // MARK: Init

    init(role: Role) {
        self.role = role

        #if os(macOS)
        let displayName = Host.current().localizedName ?? "Mac"
        #else
        let displayName = UIDevice.current.name
        #endif

        self.peerID = MCPeerID(displayName: displayName)
        self.session = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        super.init()
        session.delegate = self
    }

    // MARK: Lifecycle

    /// Start advertising (Mac) or browsing (iPhone).
    func start() {
        switch role {
        case .mac:
            #if os(macOS)
            let code = AppConfig.makePairingCode()
            self.pairingCode = code
            let info = [AppConfig.pairingCodeKey: code]
            let adv = MCNearbyServiceAdvertiser(
                peer: peerID,
                discoveryInfo: info,
                serviceType: AppConfig.bonjourServiceType
            )
            adv.delegate = self
            adv.startAdvertisingPeer()
            self.advertiser = adv
            self.state = .searching
            AppConfig.log("Advertising with code \(code)")
            #endif
        case .phone:
            #if os(iOS)
            let b = MCNearbyServiceBrowser(
                peer: peerID,
                serviceType: AppConfig.bonjourServiceType
            )
            b.delegate = self
            b.startBrowsingForPeers()
            self.browser = b
            self.state = .searching
            AppConfig.log("Browsing for nearby \(kAppName) Macs")
            #endif
        }
    }

    func stop() {
        #if os(macOS)
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        #endif
        #if os(iOS)
        browser?.stopBrowsingForPeers()
        browser = nil
        peersByCode.removeAll()
        #endif
        session.disconnect()
        state = .idle
        peerName = nil
    }

    // MARK: iPhone — submit a 4-digit code

    #if os(iOS)
    /// Called when the user finishes typing 4 digits. If a matching Mac was
    /// discovered, we invite it immediately.
    func submitCode(_ code: String) {
        pairingCode = code
        guard code.count == 4, let target = peersByCode[code] else {
            AppConfig.log("No nearby Mac with code \(code) yet — will keep listening")
            return
        }
        state = .connecting
        browser?.invitePeer(target, to: session, withContext: nil, timeout: 15)
    }
    #endif

    // MARK: Mac — send a dropped item

    #if os(macOS)
    /// Step 1: send the lightweight metadata card so the phone shows an
    /// instant glass card. Step 2: stream the heavy file in the background.
    func sendDrop(_ item: TransferItem, fileURL: URL?) {
        guard !session.connectedPeers.isEmpty else {
            AppConfig.log("No connected peer — drop ignored")
            return
        }
        // Step 1 — instant metadata (wrapped in WirePayload envelope)
        do {
            let json = try JSONEncoder().encode(WirePayload.item(item))
            try session.send(json, toPeers: session.connectedPeers, with: .reliable)
            // Mirror locally so the Mac UI can show a "sent" list
            items.append(item)
            AppConfig.log("Sent metadata for \(item.name)")
        } catch {
            AppConfig.log("Failed to encode metadata: \(error)")
            return
        }

        // Step 2 — heavy resource stream (files only)
        guard item.kind == .file, let fileURL else { return }
        for peer in session.connectedPeers {
            session.sendResource(
                at: fileURL,
                withName: item.id.uuidString,  // matches the metadata ID
                toPeer: peer
            ) { error in
                Task { @MainActor [weak self] in
                    if let error {
                        AppConfig.log("Resource send failed: \(error)")
                    } else {
                        AppConfig.log("Resource send complete: \(item.name)")
                        self?.updateProgress(for: item.id, to: 1.0)
                    }
                }
            }
        }
    }
    #endif

    // MARK: iPhone — send an item TO the Mac
    //
    // The "shake to paste" feature: the iPhone packs whatever the user has
    // in their clipboard into a TransferItem and ships it to the Mac, which
    // auto-opens URLs on arrival (see didReceive handler below).

    #if os(iOS)
    func sendToMac(_ item: TransferItem) {
        guard !session.connectedPeers.isEmpty else {
            AppConfig.log("No connected peer — sendToMac ignored")
            return
        }
        do {
            let json = try JSONEncoder().encode(WirePayload.item(item))
            try session.send(json, toPeers: session.connectedPeers, with: .reliable)
            AppConfig.log("iPhone -> Mac item sent: \(item.name)")
        } catch {
            AppConfig.log("Failed to encode iPhone->Mac item: \(error)")
        }
    }
    #endif

    // MARK: Remove an item locally
    //
    // Used by the iPhone's toss-back gesture: after the bead is animated
    // off the island, the underlying record is dropped from the list.
    func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    // MARK: Either side — ask the OTHER device to open a URL

    /// Bidirectional. iPhone calls this on tap; Mac receives and opens
    /// the URL in the default browser (e.g. Google Chrome). Mac could
    /// also call this in the other direction if needed.
    func requestOpen(_ urlString: String) {
        guard !session.connectedPeers.isEmpty else {
            AppConfig.log("No connected peer — open request ignored")
            return
        }
        do {
            let json = try JSONEncoder().encode(WirePayload.open(urlString))
            try session.send(json, toPeers: session.connectedPeers, with: .reliable)
            AppConfig.log("Sent open request for \(urlString)")
        } catch {
            AppConfig.log("Failed to encode open request: \(error)")
        }
    }

    // MARK: Receiver-side: open a URL locally on this device
    //
    // If the payload parses as a real URL with a scheme (http, https,
    // file, etc.) we open it in the system handler. Otherwise — colour
    // hex strings, plain text, anything without a scheme — we copy the
    // string to the system clipboard so EVERY bead does something useful.

    fileprivate func handleOpenRequest(_ urlString: String) {
        if tryOpenAsURL(urlString) { return }
        copyToSystemClipboard(urlString)
    }

    private func tryOpenAsURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              !scheme.isEmpty
        else { return false }

        #if os(macOS)
        // Local files → Quick Look so the preview floats on top of the
        // current windows. Other URLs (http/https/etc.) go through the
        // normal launch path.
        if url.isFileURL {
            QuickLookOpener.shared.show(url: url)
            AppConfig.log("Quick-Look on Mac: \(urlString)")
            return true
        }
        let ok = NSWorkspace.shared.open(url)
        if ok { AppConfig.log("Opened on Mac: \(urlString)") }
        return ok
        #else
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        AppConfig.log("Opened on iPhone: \(urlString)")
        return true
        #endif
    }

    private func copyToSystemClipboard(_ text: String) {
        #if os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        AppConfig.log("Copied to Mac clipboard: \(text)")
        #else
        UIPasteboard.general.string = text
        AppConfig.log("Copied to iPhone clipboard: \(text)")
        #endif
    }

    // MARK: Progress helper

    fileprivate func updateProgress(for id: UUID, to value: Double) {
        if let i = items.firstIndex(where: { $0.id == id }) {
            items[i].progress = value
        }
    }
}

// MARK: - MCSessionDelegate

extension PairingSession: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connecting:
                self.state = .connecting
            case .connected:
                self.state = .connected
                self.peerName = peerID.displayName
                AppConfig.log("Connected to \(peerID.displayName)")
            case .notConnected:
                if self.state == .connected {
                    AppConfig.log("Disconnected from \(peerID.displayName)")
                }
                self.peerName = nil
                self.state = .searching
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // All wire data is a WirePayload envelope. Decode then dispatch.
        guard let payload = try? JSONDecoder().decode(WirePayload.self, from: data) else { return }
        Task { @MainActor in
            switch payload {
            case .item(let item):
                self.items.append(item)
                self.lastReceivedID = item.id
                AppConfig.log("Received metadata for \(item.name)")
                // On the Mac, items received from the iPhone (shake-to-paste)
                // should auto-open if they parse as a real URL — that's the
                // payoff of the feature.
                #if os(macOS)
                if self.role == .mac,
                   item.kind == .url,
                   let s = item.urlString,
                   let url = URL(string: s),
                   url.scheme != nil {
                    NSWorkspace.shared.open(url)
                }
                #endif
            case .open(let urlString):
                self.handleOpenRequest(urlString)
            }
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        // Bind progress KVO -> @Published. Match the resource name (UUID string)
        // back to the metadata card already on screen.
        guard let id = UUID(uuidString: resourceName) else { return }

        // Observe and pump updates back to main. [weak self] lives on the
        // Task's capture list (not the KVO block) so Swift 6 strict
        // concurrency is happy.
        let observation = progress.observe(\.fractionCompleted, options: [.new]) { p, _ in
            let value = p.fractionCompleted
            Task { @MainActor [weak self] in
                self?.updateProgress(for: id, to: value)
            }
        }
        // Hold the observation until the resource finishes — stash it on the
        // progress object so ARC keeps it alive for the duration.
        objc_setAssociatedObject(progress, &progressObsKey, observation, .OBJC_ASSOCIATION_RETAIN)
    }

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        guard let id = UUID(uuidString: resourceName) else { return }
        Task { @MainActor in
            self.updateProgress(for: id, to: 1.0)
            if let error {
                AppConfig.log("Resource receive failed: \(error)")
            } else if let localURL {
                AppConfig.log("Resource received at \(localURL.path)")
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used — we use resources, not streams.
    }
}

// Sidecar key for objc-associated KVO observation storage.
// nonisolated(unsafe) — this is just an address sentinel used by objc, never
// read or written as data, so the global is safe to use from any actor.
nonisolated(unsafe) private var progressObsKey: UInt8 = 0

// MARK: - Advertiser delegate (Mac only)

#if os(macOS)
extension PairingSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        // We trust any iPhone that knew our 4-digit code — auto-accept.
        invitationHandler(true, self.session)
        AppConfig.log("Accepted invitation from \(peerID.displayName)")
    }
}
#endif

// MARK: - Browser delegate (iPhone only)

#if os(iOS)
extension PairingSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String : String]?
    ) {
        let code = info?[AppConfig.pairingCodeKey] ?? ""
        Task { @MainActor in
            guard !code.isEmpty else { return }
            self.peersByCode[code] = peerID
            AppConfig.log("Discovered \(peerID.displayName) advertising code \(code)")

            // If the user already typed this exact code, connect immediately.
            if code == self.pairingCode, self.state != .connected {
                self.state = .connecting
                browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.peersByCode = self.peersByCode.filter { $0.value != peerID }
        }
    }
}
#endif
