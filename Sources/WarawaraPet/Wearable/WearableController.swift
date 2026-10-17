import CoreAudio
import Foundation
import Combine

/// Live wearable state observed by the pet view. The WearableController
/// mutates this; SwiftUI re-renders the character whenever it changes.
final class WearableRuntime: ObservableObject {
    @Published private(set) var state: WarawaraWearableState = .none
    @Published private(set) var motion: WearableRenderParameters = .default

    func update(state: WarawaraWearableState, motion: WearableRenderParameters) {
        if self.state != state { self.state = state }
        if self.motion != motion { self.motion = motion }
    }
}

/// Resolves and animates the final-gift wearables:
/// - birthday hat: October 17 (local) or during a celebration
/// - Christmas hat: December 24 18:00 through December 26
/// - headphones: audio playback detected (debounced)
/// - red scarf: Lunar New Year days 1-3
/// Precedence: birthday hat > Christmas hat > headphones. The scarf is
/// independent. Crossfades instead of hard switches.
final class WearableController {
    private let runtime: WearableRuntime
    private let audioMonitor: AudioActivityMonitor
    private let clock: BirthdayClock
    private var timer: Timer?
    private var tickCount = 0

    /// Headwear opacity easing state per kind (0...1).
    private var opacities: [WearableKind: CGFloat] = [:]

    /// Development overrides (--debug-wear) — win over calendar/audio.
    private var debugForced: Set<WearableKind> = []
    /// External celebration state (first-launch / birthday replay) can
    /// request the birthday hat.
    var celebrationRequestsBirthdayHat = false

    init(
        runtime: WearableRuntime,
        audioMonitor: AudioActivityMonitor = AudioActivityMonitor(),
        clock: BirthdayClock = SystemBirthdayClock()
    ) {
        self.runtime = runtime
        self.audioMonitor = audioMonitor
        self.clock = clock
    }

    func start() {
        audioMonitor.start()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        audioMonitor.stop()
        timer?.invalidate()
        timer = nil
    }

    func debugForce(kind: WearableKind) {
        debugForced.insert(kind)
        EventDiagnostics.wearableChanged(id: kind.displayName, active: true)
    }

    /// 4 Hz evaluation; the actual crossfade smoothing lives here with a
    /// ~0.35 s time constant.
    func tick() {
        tickCount += 1
        let now = clock.now()
        let calendar = clock.calendar

        var targetHeadwear: WearableKind?
        if debugForced.contains(.birthdayHat) || celebrationRequestsBirthdayHat
            || WearableEligibility.isBirthday(date: now, calendar: calendar) {
            targetHeadwear = .birthdayHat
        } else if debugForced.contains(.christmasHat)
            || WearableEligibility.isChristmas(date: now, calendar: calendar) {
            targetHeadwear = .christmasHat
        } else if debugForced.contains(.headphones)
            || audioMonitor.isAudioPlaying {
            targetHeadwear = .headphones
        }

        var targetScarf = false
        if debugForced.contains(.redScarf)
            || WearableEligibility.isLunarNewYear(date: now, calendar: calendar) {
            targetScarf = true
        }

        // Ease opacities toward targets.
        let dt: CGFloat = 0.25
        let tau: CGFloat = 0.35
        let factor = 1 - exp(-dt / tau)
        var newOpacities = opacities
        for kind in WearableKind.allCases {
            let target: CGFloat = (kind.isHeadwear ? (kind == targetHeadwear ? 1 : 0) : (targetScarf ? 1 : 0))
            let current = opacities[kind] ?? 0
            newOpacities[kind] = current + (target - current) * factor
        }
        opacities = newOpacities

        // Render state: headwear visible when its opacity is meaningful.
        let headwearOpacity = targetHeadwear.map { opacities[$0] ?? 0 } ?? 0
        let scarfOpacity = opacities[.redScarf] ?? 0
        let visibleHeadwear: WearableKind?
        if let targetHeadwear, headwearOpacity > 0.03 {
            visibleHeadwear = targetHeadwear
        } else {
            visibleHeadwear = nil
        }
        let state = WarawaraWearableState(
            headwear: visibleHeadwear,
            scarf: scarfOpacity > 0.03,
            headwearOpacity: min(max(headwearOpacity, 0), 1),
            scarfOpacity: min(max(scarfOpacity, 0), 1)
        )
        // Subtle tassel sway during hop/float/drag is added by the pet's
        // motion later; keep a gentle baseline here.
        let sway = CGFloat(sin(TimeInterval(tickCount) * 0.11)) * 0.4
        let motion = WearableRenderParameters(tasselSway: state.scarf ? sway : 0)
        runtime.update(state: state, motion: motion)

        if tickCount % 16 == 0 {
            for kind in WearableKind.allCases where (opacities[kind] ?? 0) > 0.5 {
                EventDiagnostics.wearableChanged(id: kind.displayName, active: true)
            }
        }
    }

    var isDebugging: Bool { !debugForced.isEmpty }
}

/// Public CoreAudio signal for output activity:
/// kAudioDevicePropertyDeviceIsRunningSomewhere on the default output
/// device. Polled at 1 Hz with a 2 s engage / 5 s release debounce.
/// This detects that SOME process is producing audio on the default
/// output — not that the stream is non-silent. Documented limitation.
final class AudioActivityMonitor {
    private var timer: Timer?
    private var activeSince: Date?
    private var inactiveSince: Date?
    private(set) var isAudioPlaying = false
    var engageDelay: TimeInterval = 2
    var releaseDelay: TimeInterval = 5

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let running = Self.isDefaultOutputRunningSomewhere()
        let now = Date()
        if running {
            inactiveSince = nil
            let since = activeSince ?? now
            activeSince = since
            if now.timeIntervalSince(since) >= engageDelay, !isAudioPlaying {
                isAudioPlaying = true
                EventDiagnostics.audio("HEADPHONES_ON")
            }
        } else {
            activeSince = nil
            let since = inactiveSince ?? now
            inactiveSince = since
            if now.timeIntervalSince(since) >= releaseDelay, isAudioPlaying {
                isAudioPlaying = false
                EventDiagnostics.audio("HEADPHONES_OFF")
            }
        }
    }

    /// Public CoreAudio query (no capture, no private API):
    /// DeviceIsRunningSomewhere on the default output device.
    static func isDefaultOutputRunningSomewhere() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != 0 else { return false }

        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var runningSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            deviceID, &runningAddress, 0, nil, &runningSize, &running
        )
        return status == noErr && running != 0
    }
}
