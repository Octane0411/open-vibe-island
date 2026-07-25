import Foundation

/// Shared "resets in …" countdown formatter (AB-324).
///
/// Consolidates the five near-identical `remainingDurationString(until:)` copies
/// that lived on Classic / Flight Deck / Instrument / Poured / Annual into one
/// tested implementation, exposed for both the header usage `.help()` tooltips
/// and the upcoming inline reset readouts every 2.0 theme renders
/// (`resets 2h 10m` / `RESET 2H 10M` / `Claude 5h · 34% · 2h 10m`).
///
/// Grammar: `2h 10m`, `3d 4h`, `19h`, `45m`, and `<1m` for any sub-minute
/// remainder; `nil` for a nil / now / past target — a past date never renders a
/// negative. The clock is injected (`asOf:` / a raw interval), never read
/// internally, so views and tests can freeze time for determinism.
///
/// Divergence from the retired copies (both sanctioned by the ticket grammar,
/// "ticket grammar wins for the NEW shared API"):
///  - the day bucket now carries the trailing hours — `3d 4h`, where the old
///    `[.day]`-only config rendered `3d` (so a weekly window reads `6d 4h`, not
///    `6d`); a whole-day remainder still drops the zero and reads `3d`.
///  - sub-minute renders `<1m` where the old `[.minute]` config rendered the
///    misleading `0m` for an all-but-elapsed window.
/// In-band remainders (`2h 10m`, `19h`, `45m`) and the nil / past cases stay
/// byte-identical to the retired `DateComponentsFormatter` output.
enum UsageCountdownFormatter {
    /// The remaining-time label for `resetsAt` measured from `now`, or `nil`
    /// when `resetsAt` is already at/past `now`.
    static func remainingLabel(until resetsAt: Date, asOf now: Date) -> String? {
        remainingLabel(forRemaining: resetsAt.timeIntervalSince(now))
    }

    /// The remaining-time label for a raw remaining interval in seconds, or
    /// `nil` when the interval is zero or negative.
    static func remainingLabel(forRemaining interval: TimeInterval) -> String? {
        guard interval > 0 else { return nil }

        // Sub-minute never reads as the retired `0m`: the grammar renders it as
        // `<1m` so an all-but-elapsed window can't look already-reset.
        if interval < 60 { return "<1m" }

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated

        if interval >= 86_400 {
            // Day bucket carries the trailing hours (`3d 4h`); a whole-day
            // remainder drops the zero and reads `3d`.
            formatter.allowedUnits = [.day, .hour]
            formatter.maximumUnitCount = 2
        } else if interval >= 3_600 {
            formatter.allowedUnits = [.hour, .minute]
            formatter.maximumUnitCount = 2
        } else {
            formatter.allowedUnits = [.minute]
            formatter.maximumUnitCount = 1
        }

        return formatter.string(from: interval)
    }
}

extension UsageWindowPresentation {
    /// This window's "resets in …" label as of `now`, or `nil` when the window
    /// carries no reset time or it is already at/past `now`. The single source
    /// the header tooltips and the upcoming theme inline readouts both call.
    func remainingLabel(asOf now: Date) -> String? {
        guard let resetsAt else { return nil }
        return UsageCountdownFormatter.remainingLabel(until: resetsAt, asOf: now)
    }
}
