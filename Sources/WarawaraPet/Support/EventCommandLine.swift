import Foundation

/// Command-line surface for the final gift build (testable without
/// AppKit).
enum EventCommandLine {
    /// Human-readable usage.
    static var usage: String {
        """
        WarawaraPet final gift usage:
          --replay-birthday              replay the birthday event
          --replay-meteor                replay the meteor event
          --show-letter                  open the birthday letter
          --debug-wear <kind>            force a wearable (development):
            <kind> = birthday-hat | christmas-hat | headphones | red-scarf
          --verify-gift-assets           headless packaged-art verification
          --help-events                  show this usage
        """
    }
}
