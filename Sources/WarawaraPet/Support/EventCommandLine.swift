import Foundation

/// Command-line surface for the final gift build (testable without
/// AppKit).
enum EventCommandLine {
    /// Human-readable usage.
    static var usage: String {
        """
        WarawaraPet usage:
          --replay-birthday              replay the birthday event
          --replay-meteor                replay the meteor event
          --show-letter                  open the birthday letter
          --verify-gift-assets           headless packaged-art verification
          --debug-reset-first-launch     development: clear first-launch state
          --help-events                  show this usage
        """
    }
}
