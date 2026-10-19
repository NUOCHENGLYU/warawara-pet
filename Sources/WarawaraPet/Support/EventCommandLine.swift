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
          --diagnose-first-launch        inspect the first-launch decision
          --debug-reset-first-launch     development: clear first-launch state
          --fault-inject <name>          development: window-recovery fault
            <name> = offscreen-frame | hidden-panel | screen-change | wake-recovery
          --help-events                  show this usage
        """
    }
}
