//
//  QuickLookOpener.swift
//  macOS-only. Opens a file path in a floating Quick Look panel rather
//  than handing it off to the file's default app — that way a screenshot,
//  PDF, etc. overlays on top of whatever the user is currently doing
//  instead of activating a different app and (potentially) Spaces-switching
//  to a desktop with no other windows.
//

#if os(macOS)

import AppKit
import QuickLookUI

@MainActor
final class QuickLookOpener: NSResponder, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookOpener()

    private var url: URL?

    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) unavailable")
    }

    /// Show the QuickLook panel for `url`, floating above the user's
    /// current windows. The panel is the shared system Quick Look panel —
    /// we just point it at our URL and ask it to come forward.
    func show(url: URL) {
        self.url = url
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        url as NSURL?
    }

    // MARK: QLPreviewPanel control hooks
    //
    // Quick Look queries the responder chain via these methods to decide
    // who controls the panel. We claim control whenever asked so our
    // dataSource sticks.

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // Leave dataSource pointing at us; the URL is cleared on next show().
    }
}

#endif
