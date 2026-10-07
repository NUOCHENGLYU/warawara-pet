import Foundation

/// Developer controls, disabled by default. Enable for real-Mac testing:
///   defaults write com.birthday.warawarapet warawarapet.debug -bool true
/// or launch with the argument `-WarawaraPetDebug`. Remove/disable before
/// the final gift build by deleting the defaults key.
enum DebugControls {
    static let defaultsKey = "warawarapet.debug"
    static let launchArgument = "-WarawaraPetDebug"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
            || ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}
