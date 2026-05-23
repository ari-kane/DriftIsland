//
//  EdgeDropWindow.swift
//  macOS-only. Creates an always-on-top NSPanel shaped as a tall
//  vertical drop pill anchored against the RIGHT edge of the primary
//  screen, vertically centered. Drop a URL or file onto it and it
//  instantly relays to the paired iPhone.
//
//  Technical notes:
//    * We use NSPanel (not NSWindow) so it can float without stealing
//      focus from the user's current app.
//    * Pill is ~70×176 pt, 5 pt inset from the right edge.
//    * `ignoresMouseEvents = false` is required — macOS routes drag
//      tracking through the mouse event system, so flipping this off
//      would also kill drag detection.
//

#if os(macOS)

import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

@MainActor
final class EdgeDropWindowController {

    private var panel: NSPanel?
    private weak var session: PairingSession?

    /// Install the edge panel for the primary screen. Re-install on screen
    /// changes (display attached/detached) by calling this again.
    func install(session: PairingSession) {
        self.session = session
        rebuildPanel()

        // Re-anchor on screen layout changes.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in self?.rebuildPanel() }
        }
    }

    private func rebuildPanel() {
        panel?.orderOut(nil)
        panel = nil

        guard let screen = NSScreen.main, let session else { return }

        // Tall, very narrow drop strip flush against the right edge.
        // Kept thin so it intercepts as little of the user's normal
        // right-edge clicking as possible — the OS still needs the
        // panel to receive mouse events for drag-and-drop to fire, so
        // some blockage is unavoidable, but 18pt is barely noticeable.
        let boxWidth: CGFloat = 18
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.maxX - boxWidth,
            y: visible.minY,
            width: boxWidth,
            height: visible.height
        )

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.isMovable = false
        // Must be false — drag-and-drop tracking is plumbed through the mouse
        // event system, so ignoring mouse events also ignores drags. The
        // .nonactivatingPanel style mask keeps the panel from stealing focus
        // when content lands on it.
        p.ignoresMouseEvents = false

        // Host the SwiftUI strip inside.
        let rootView = EdgeStripView(session: session)
        let hosting = EdgeHostingView(rootView: rootView, session: session)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        p.contentView = hosting

        p.orderFrontRegardless()
        self.panel = p

        AppConfig.log("Edge drop panel anchored on \(screen.localizedName)")
    }
}

// MARK: - NSHostingView subclass that handles drag-and-drop
//
// SwiftUI's `.onDrop` works inside windows of your own process, but for an
// unobtrusive system-wide drop target on a clear panel, the most reliable
// path is to register drag types directly on the NSHostingView itself and
// forward the dropped item to the session.
private final class EdgeHostingView: NSHostingView<EdgeStripView> {
    weak var session: PairingSession?

    init(rootView: EdgeStripView, session: PairingSession) {
        self.session = session
        super.init(rootView: rootView)
        registerForDraggedTypes([
            .fileURL, .URL, .string, .rtf, .html, .tiff, .png, .pdf, .color,
        ])
    }

    @MainActor required dynamic init(rootView: EdgeStripView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([
            .fileURL, .URL, .string, .rtf, .html, .tiff, .png, .pdf, .color,
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        rootView.activate(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        rootView.activate(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { rootView.activate(false) }
        let pb = sender.draggingPasteboard

        // (1) File URLs — may be MULTIPLE files at once.
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            for url in urls { ingestFileURL(url) }
            return true
        }

        // (2) Raw image data — drag an image directly out of a webpage,
        //     Photos, Preview, etc. (not a file reference).
        let imageTypes: [NSPasteboard.PasteboardType] = [.tiff, .png]
        if pb.types?.contains(where: { imageTypes.contains($0) }) == true,
           let image = NSImage(pasteboard: pb) {
            ingestImage(image)
            return true
        }

        // (3) PDF data dragged from Preview, etc.
        if let pdfData = pb.data(forType: .pdf) {
            ingestPDFData(pdfData)
            return true
        }

        // (4) Web URLs (Safari tab drag, multi-link, etc.)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            for url in urls { ingestWebURL(url) }
            return true
        }

        // (5) Colour swatch from the Color Picker — sent as a #RRGGBB string.
        if let color = NSColor(from: pb) {
            ingestColor(color)
            return true
        }

        // (6) Rich text — flatten to plain text.
        if let rtfData = pb.data(forType: .rtf),
           let attr = try? NSAttributedString(data: rtfData, options: [:],
                                              documentAttributes: nil) {
            ingestPlainText(attr.string)
            return true
        }

        // (7) HTML — strip tags to plain text.
        if let html = pb.string(forType: .html) {
            ingestPlainText(plainText(fromHTML: html))
            return true
        }

        // (8) Plain text fallback.
        if let s = pb.string(forType: .string), !s.isEmpty {
            ingestPlainText(s)
            return true
        }

        return false
    }

    // MARK: ingestion helpers

    private func ingestFileURL(_ url: URL) {
        guard let session else { return }

        // Lightweight metadata first.
        let resources = try? url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        let bytes: Int64? = resources?.fileSize.map { Int64($0) }
        let name = resources?.name ?? url.lastPathComponent

        // Quick icon thumbnail via NSWorkspace — fast (cached by the system).
        let nsIcon = NSWorkspace.shared.icon(forFile: url.path)
        nsIcon.size = NSSize(width: 96, height: 96)
        let png = pngData(from: nsIcon)

        let item = TransferItem(
            name: name,
            kind: .file,
            byteCount: bytes,
            urlString: nil,
            iconPNG: png,
            macSourcePath: url.absoluteString  // for tap-back-to-open
        )
        session.sendDrop(item, fileURL: url)
    }

    private func ingestWebURL(_ url: URL) {
        guard let session else { return }
        let item = TransferItem(
            name: url.host ?? url.absoluteString,
            kind: .url,
            urlString: url.absoluteString
        )
        session.sendDrop(item, fileURL: nil)
    }

    private func ingestPlainText(_ s: String) {
        guard let session else { return }
        let item = TransferItem(
            name: String(s.prefix(60)),
            kind: .url,
            urlString: s
        )
        session.sendDrop(item, fileURL: nil)
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: extended types

    /// Raw image data (not a file). Writes a temp PNG and reuses the
    /// file-drop flow, but the iPhone bead gets the actual image as its
    /// thumbnail instead of a generic icon.
    private func ingestImage(_ image: NSImage) {
        guard let session else { return }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let bytes = rep.representation(using: .png, properties: [:])
        else { return }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Image-\(UUID().uuidString.prefix(8)).png")
        do { try bytes.write(to: tempURL) } catch {
            AppConfig.log("Failed to write dropped image: \(error)")
            return
        }

        // Downscaled copy for the bead thumbnail.
        let thumb = NSImage(size: NSSize(width: 96, height: 96))
        thumb.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: 96, height: 96))
        thumb.unlockFocus()

        let item = TransferItem(
            name: tempURL.lastPathComponent,
            kind: .file,
            byteCount: Int64(bytes.count),
            urlString: nil,
            iconPNG: pngData(from: thumb),
            macSourcePath: tempURL.absoluteString
        )
        session.sendDrop(item, fileURL: tempURL)
    }

    /// PDF data dragged from Preview, browser, etc. Saved as a temp file
    /// and shipped through the normal file flow.
    private func ingestPDFData(_ data: Data) {
        guard let session else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Document-\(UUID().uuidString.prefix(8)).pdf")
        do { try data.write(to: tempURL) } catch {
            AppConfig.log("Failed to write dropped PDF: \(error)")
            return
        }
        let icon = NSWorkspace.shared.icon(forFile: tempURL.path)
        icon.size = NSSize(width: 96, height: 96)
        let item = TransferItem(
            name: tempURL.lastPathComponent,
            kind: .file,
            byteCount: Int64(data.count),
            urlString: nil,
            iconPNG: pngData(from: icon),
            macSourcePath: tempURL.absoluteString
        )
        session.sendDrop(item, fileURL: tempURL)
    }

    /// Colour swatch from the macOS Color Picker. Lands on the island as
    /// a #RRGGBB hex string so the user can copy / reference it on phone.
    private func ingestColor(_ color: NSColor) {
        guard let session else { return }
        guard let rgb = color.usingColorSpace(.sRGB) else { return }
        let r = Int(round(rgb.redComponent   * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent  * 255))
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        let item = TransferItem(
            name: hex,
            kind: .url,
            urlString: hex
        )
        session.sendDrop(item, fileURL: nil)
    }

    /// Convert an HTML string to plain text by routing through
    /// NSAttributedString; falls back to the raw HTML if parsing fails.
    private func plainText(fromHTML html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType:      NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        if let attr = try? NSAttributedString(data: data, options: opts,
                                              documentAttributes: nil) {
            return attr.string
        }
        return html
    }
}

// MARK: - SwiftUI body of the invisible drop strip
//
// The panel is a tall, transparent column running down the right edge of
// the screen. At rest it renders nothing at all (just a hit-test surface
// for AppKit's drag tracking). When a drag enters, a soft lagoon-blue
// light bar fades in at the inner edge — the only visual confirmation
// that the cursor has found the drop zone.

struct EdgeStripView: View {
    @ObservedObject private var model: EdgeStripModel

    init(session: PairingSession) {
        _model = ObservedObject(initialValue: EdgeStripModel(session: session))
    }

    func activate(_ active: Bool) { model.isActive = active }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Invisible hit-test surface — AppKit routes drag tracking here.
            Color.clear

            // Drag-active light bar, pinned to the inner edge of the strip.
            ActiveEdgeBar(isActive: model.isActive)
                .padding(.trailing, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

// A vertical lagoon-blue light bar that fades in only while a drag is
// hovering over the drop strip. Bar width + shadow are tuned to fit
// inside the narrow 18pt panel without their shadow getting clipped
// into a sharp tinted box.
private struct ActiveEdgeBar: View {
    let isActive: Bool
    @State private var pulse: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Palette.lagoonBlue)
            .frame(width: 4, height: isActive ? 300 : 180)
            .shadow(color: Palette.lagoonBlue.opacity(0.95), radius: 5)
            .shadow(color: Palette.lagoonBlue.opacity(0.55), radius: 10)
            .opacity(isActive ? 1.0 : 0.0)
            .scaleEffect(x: isActive ? 1.0 : 0.5, y: pulse && isActive ? 1.04 : 0.98, anchor: .center)
            .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isActive)
            .onChange(of: isActive) { _, a in
                if a {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                } else {
                    pulse = false
                }
            }
    }
}

// MARK: - Model

@MainActor
final class EdgeStripModel: ObservableObject {
    @Published var isActive: Bool = false
    init(session: PairingSession) { _ = session }
}

#endif
