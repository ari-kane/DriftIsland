//
//  HapticPour.swift
//  iOS-only. A continuous "pour" haptic that ramps with file-transfer
//  progress, then thuds on completion. Wraps Core Haptics so the rest of
//  the app can just call .startPour() / .updatePour(progress:) / .stopWithThunk().
//
//  Robustness:
//    * The underlying continuous pattern is only ~6 seconds long. As
//      long as updates keep arriving the pattern is restarted before it
//      expires, so the user gets a continuous buzz. If updates STOP
//      arriving (transfer stalled, item removed, peer dropped, etc.),
//      a watchdog cancels the haptic after ~4 seconds of silence — so
//      the phone can't be left buzzing forever.
//    * Falls back silently on hardware without haptics (iPad, simulator).
//

#if os(iOS)

import Foundation
import Combine
import CoreHaptics
import UIKit

@MainActor
final class HapticPour: ObservableObject {

    // Explicitly declared so the protocol witness is reachable from any actor
    // context — @MainActor on the class otherwise isolates the synthesized
    // `objectWillChange`, which breaks ObservableObject conformance.
    nonisolated let objectWillChange = ObservableObjectPublisher()

    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?
    private var running: Bool = false
    private var startTime: Date?
    private var watchdog: Task<Void, Never>?

    private let pourDuration: TimeInterval = 6.0
    private let watchdogTimeout: TimeInterval = 4.0

    init() {
        prepareEngine()
    }

    /// Build (or rebuild) the Core Haptics engine.
    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let e = try CHHapticEngine()
            e.resetHandler = { [weak self] in
                Task { @MainActor in
                    self?.cancel()
                    self?.prepareEngine()
                }
            }
            e.stoppedHandler = { _ in }
            try e.start()
            engine = e
        } catch {
            engine = nil
        }
    }

    /// Begin a continuous, low-intensity pour. Safe to no-op if already running.
    func startPour() {
        guard !running else { return }
        if engine == nil { prepareEngine() }
        guard let engine else { return }
        startContinuous(engine: engine)
    }

    private func startContinuous(engine: CHHapticEngine) {
        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.28)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [intensity, sharpness],
                relativeTime: 0,
                duration: pourDuration
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let p = try engine.makeAdvancedPlayer(with: pattern)
            try p.start(atTime: 0)
            player = p
            running = true
            startTime = Date()
            armWatchdog()
        } catch {
            running = false
        }
    }

    /// Live-modulate the pour intensity and sharpness to match transfer progress.
    func updatePour(progress: Double) {
        guard running else { return }

        // If we're nearing the end of the current pattern, restart it so
        // the haptic doesn't audibly cut out mid-transfer.
        if let start = startTime,
           Date().timeIntervalSince(start) > pourDuration * 0.8,
           let engine
        {
            try? player?.stop(atTime: CHHapticTimeImmediate)
            player = nil
            startContinuous(engine: engine)
        }

        guard let player else { return }
        let clamped = min(1.0, max(0.0, progress))
        let i = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: Float(0.22 + clamped * 0.55),
            relativeTime: 0
        )
        let s = CHHapticDynamicParameter(
            parameterID: .hapticSharpnessControl,
            value: Float(0.10 + clamped * 0.35),
            relativeTime: 0
        )
        try? player.sendParameters([i, s], atTime: CHHapticTimeImmediate)
        armWatchdog()
    }

    /// Cut the continuous pour and fire a satisfying "landed" transient.
    func stopWithThunk() {
        watchdog?.cancel()
        watchdog = nil
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        running = false
        startTime = nil

        guard let engine else {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            return
        }
        do {
            let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9)
            let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.55)
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [intensity, sharpness],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let p = try engine.makePlayer(with: pattern)
            try p.start(atTime: 0)
        } catch {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    /// Hard stop without a closing thunk — used when the host is dismissed
    /// or progress stops arriving.
    func cancel() {
        watchdog?.cancel()
        watchdog = nil
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
        running = false
        startTime = nil
    }

    /// (Re-)arm the inactivity watchdog. If no further progress arrives
    /// within `watchdogTimeout`, the haptic is cancelled — so a stalled
    /// or aborted transfer can never leave the phone vibrating forever.
    private func armWatchdog() {
        watchdog?.cancel()
        let timeout = watchdogTimeout
        watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.cancel()
        }
    }
}

#endif
