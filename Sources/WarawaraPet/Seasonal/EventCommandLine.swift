import Foundation

/// Pure command-line handling for event replays (testable without
/// touching AppKit).
enum EventCommandLine {
    static let replayEventFlag = "--replay-event"
    static let replaySmokeFlag = "--replay-smoke"
    static let helpEventsFlag = "--help-events"

    /// Extracts the event kind from a full argument list. Returns nil
    /// when the flag is absent or the identifier is unknown.
    static func parseReplayEvent(arguments: [String]) -> SeasonalEventKind? {
        guard let flagIndex = arguments.firstIndex(of: replayEventFlag),
              arguments.count > flagIndex + 1 else { return nil }
        return SeasonalEventKind.fromReplayArgument(arguments[flagIndex + 1])
    }

    /// The raw identifier string after the flag (empty when malformed).
    static func rawReplayIdentifier(arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: replayEventFlag),
              arguments.count > flagIndex + 1 else { return nil }
        return arguments[flagIndex + 1]
    }

    /// Same for the smoke-test variant.
    static func parseReplaySmoke(arguments: [String]) -> SeasonalEventKind? {
        guard let flagIndex = arguments.firstIndex(of: replaySmokeFlag),
              arguments.count > flagIndex + 1 else { return nil }
        return SeasonalEventKind.fromReplayArgument(arguments[flagIndex + 1])
    }

    static func rawSmokeIdentifier(arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: replaySmokeFlag),
              arguments.count > flagIndex + 1 else { return nil }
        return arguments[flagIndex + 1]
    }

    /// Human-readable usage for event replays.
    static var usage: String {
        let kinds = SeasonalEventKind.allCases.map(\.replayArgument).joined(separator: " | ")
        return """
        WarawaraPet event replay usage:
          --replay-event <kind>   replay a seasonal/daily event now (any date)
            <kind> = \(kinds)
          --replay-smoke <kind>   like --replay-event, exits after completion (CI)
          --replay-birthday       replay the birthday event
          --show-letter           open the birthday letter
          --help-events           show this usage
        """
    }
}
