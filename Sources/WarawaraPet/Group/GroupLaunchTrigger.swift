import Foundation

/// Temporary developer trigger for the group sequence (no NSMenu, no
/// visible UI). When the defaults key is true at launch, the app consumes
/// it and triggers one group sequence after a short random delay.
///
///     defaults write com.birthday.warawarapet warawarapet.forceGroupOnce -bool true
enum GroupLaunchTrigger {
    static let defaultsKey = "warawarapet.forceGroupOnce"

    /// Reads and consumes the one-shot flag. Pure enough to test with an
    /// injected UserDefaults suite.
    static func consumeOnceFlag(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: defaultsKey) else { return false }
        defaults.set(false, forKey: defaultsKey)
        return true
    }

    /// If the flag was set, schedules `perform` once after a bounded
    /// random delay (GroupTuning.triggerDelayRange).
    static func startIfRequested(
        defaults: UserDefaults = .standard,
        tuning: GroupTuning = .default,
        perform: @escaping () -> Void
    ) {
        guard consumeOnceFlag(defaults: defaults) else { return }
        var rng = SystemRandomSource()
        let delay = RandomBounds.randomDelay(in: tuning.triggerDelayRange, using: &rng)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: perform)
    }
}
