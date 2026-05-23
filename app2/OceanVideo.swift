//
//  OceanVideo.swift
//  iOS-only. Loops a muted bird's-eye-view ocean video as the background
//  for IslandScene. A single AVPlayerLooper plays the clip; a black
//  CALayer overlay above the video dims toward 0.55 opacity around each
//  loop boundary and back to 0 mid-cycle — so every loop is hidden under
//  a clearly visible fade-down / fade-up, no matter how seamless or not
//  the underlying clip is.
//
//  Playback rate is fixed at 0.6× for a calmer feel.
//
//  To enable: drop a video file named `ocean_loop.mp4` (or `.mov`) into
//  the `app2/app2/` folder. The file-system-synced project group picks
//  it up automatically on the next build.
//

#if os(iOS)

import SwiftUI
import AVFoundation
import UIKit

struct LoopingVideoPlayer: UIViewRepresentable {
    let resourceName: String

    func makeUIView(context: Context) -> OceanPlayerView {
        let v = OceanPlayerView()
        v.configure(resourceName: resourceName)
        return v
    }

    func updateUIView(_ uiView: OceanPlayerView, context: Context) {}

    static func dismantleUIView(_ uiView: OceanPlayerView, coordinator: ()) {
        uiView.cleanup()
    }

    static func hasResource(named name: String) -> Bool {
        Bundle.main.url(forResource: name, withExtension: "mp4") != nil
            || Bundle.main.url(forResource: name, withExtension: "mov") != nil
    }
}

final class OceanPlayerView: UIView {
    private let videoLayer = AVPlayerLayer()
    private let dimLayer = CALayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    private var itemDuration: Double = 0
    private var displayLink: CADisplayLink?
    private let playbackRate: Float = 0.6

    // Dim window: 18% of the cycle on each side of the seam fades down
    // to a heavy darken, then back up. Half the cycle stays at full
    // video brightness with no dim.
    private let fadeRange: Double = 0.18
    private let maxDim: Float = 0.55

    override init(frame: CGRect) {
        super.init(frame: frame)
        player.isMuted = true

        videoLayer.player = player
        videoLayer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(videoLayer)

        // Dim overlay sits ABOVE the video. opacity 0 = no dim, opacity
        // 1 = fully black. Animated by CADisplayLink near each loop seam.
        dimLayer.backgroundColor = UIColor.black.cgColor
        dimLayer.opacity = 0
        self.layer.addSublayer(dimLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoLayer.frame = bounds
        dimLayer.frame = bounds
    }

    func configure(resourceName: String) {
        let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "mov")
        guard let url else { return }

        Task { @MainActor [weak self] in
            let asset = AVURLAsset(url: url)
            guard let d = try? await asset.load(.duration) else { return }
            guard let self else { return }
            self.itemDuration = d.seconds
            self.start(url: url)
        }
    }

    func cleanup() {
        displayLink?.invalidate()
        displayLink = nil
        player.pause()
        looper = nil
    }

    private func start(url: URL) {
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.playImmediately(atRate: playbackRate)

        let dl = CADisplayLink(target: self, selector: #selector(tickDim))
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    @objc private func tickDim() {
        guard itemDuration > 0 else { return }
        let t = player.currentTime().seconds
        let phase = t.truncatingRemainder(dividingBy: itemDuration) / itemDuration
        let seamProximity = min(phase, 1.0 - phase)   // 0 at seam, 0.5 mid

        let dim: Float
        if seamProximity < fadeRange {
            // Cosine bell: 1 at the seam itself, 0 at the edge of the fade
            // window. Smooth fade-down on approach, smooth fade-up after.
            let normalized = seamProximity / fadeRange   // 0..1
            let bell = 0.5 + 0.5 * cos(.pi * normalized)
            dim = Float(bell) * maxDim
        } else {
            dim = 0
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.opacity = dim
        CATransaction.commit()
    }
}

#endif
