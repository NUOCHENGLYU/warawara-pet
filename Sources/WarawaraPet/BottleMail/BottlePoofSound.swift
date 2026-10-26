import AppKit
import Foundation

/// The one-shot poof sound (soft_poof.wav from the v1 transition
/// pack). Played once per transition at the smoke "poof" instant.
/// Quiet (volume 0.25), goes through the system audio stack (so the
/// system mute applies), and honors the app's sound preference
/// (`warawarapet.sound.enabled`, default ON).
final class BottlePoofSound {
    static let shared = BottlePoofSound()

    static let soundEnabledDefaultsKey = "warawarapet.sound.enabled"

    private var sound: NSSound?
    private var lastURLResolutionAttempt = false

    /// The app-level sound preference (defaults to enabled).
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.soundEnabledDefaultsKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.soundEnabledDefaultsKey)
    }

    /// Plays the poof once (stops any previous play). No-op when the
    /// asset is missing, sound is disabled, or the system is muted
    /// (the system output handles the mute itself).
    func play() {
        guard isEnabled else { return }
        resolveSoundIfNeeded()
        guard let sound else { return }
        sound.stop()
        sound.play()
    }

    private func resolveSoundIfNeeded() {
        if sound != nil || lastURLResolutionAttempt { return }
        lastURLResolutionAttempt = true
        guard let url = BottleMailArtStore.shared.audioURL(named: "soft_poof.wav") else {
            EventDiagnostics.bottleMail("POOF_SOUND_MISSING")
            return
        }
        guard let sound = NSSound(contentsOf: url, byReference: false) else {
            EventDiagnostics.bottleMail("POOF_SOUND_LOAD_FAILED")
            return
        }
        sound.volume = 0.25
        self.sound = sound
    }

    /// Test seam: re-resolve after the store resets (previews/tests).
    func reset() {
        sound?.stop()
        sound = nil
        lastURLResolutionAttempt = false
    }
}
