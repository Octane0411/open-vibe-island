import AppKit

/// Per-state session counts for the menu bar breakdown.
struct MenuBarStateCounts {
    var total: Int
    var waiting: Int
    var running: Int
    var done: Int
    var idle: Int
}

/// Aggregate session state shown as a colored dot in the menu bar.
enum MenuBarStatusLevel {
    case none      // no surfaced sessions
    case idle      // sessions present, none running or needing attention
    case running   // at least one running
    case waiting   // at least one needs attention (approval / answer)

    /// Dot color, matching `IslandDesignPalette.Status`.
    var dotColor: NSColor {
        switch self {
        case .waiting:
            return NSColor(srgbRed: 231 / 255, green: 167 / 255, blue: 98 / 255, alpha: 1)
        case .running:
            return NSColor(srgbRed: 110 / 255, green: 167 / 255, blue: 255 / 255, alpha: 1)
        case .idle:
            return NSColor(srgbRed: 111 / 255, green: 185 / 255, blue: 130 / 255, alpha: 1)
        case .none:
            return NSColor.tertiaryLabelColor
        }
    }
}

/// Minimal-validation menu bar entry point.
///
/// Adds a standard `NSStatusItem` to the system menu bar. The button shows a
/// state-colored dot plus a compact live status string (e.g. "bash ×3"), so the
/// current session state previews without opening anything. Clicking it toggles
/// the existing overlay panel, which drops down underneath the icon.
///
/// This deliberately reuses the whole `IslandPanelView` / `OverlayUICoordinator`
/// stack — it is a prototype to feel out the "menu bar icon" placement, not a
/// full second presentation path.
@MainActor
final class StatusItemController {
    private var statusItem: NSStatusItem?
    weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    /// The status item button's frame in global screen coordinates.
    var buttonScreenFrame: NSRect? {
        guard let button = statusItem?.button, let window = button.window else {
            return nil
        }
        let rectInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(rectInWindow)
    }

    /// Horizontal center of the status item button in global screen
    /// coordinates, used to anchor the dropped-down panel under the icon.
    var anchorScreenX: CGFloat? {
        buttonScreenFrame?.midX
    }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imageHugsTitle = true
            button.target = self
            button.action = #selector(handleClick)
            button.toolTip = "Open Island"
        }
        statusItem = item

        refreshStatus()
    }

    func remove() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    @objc private func handleClick() {
        model?.toggleOverlay()
    }

    // MARK: - Live status

    /// Refresh the button title from the model's current status summary.
    /// Pushed by `AppModel` whenever session state changes (the `state`
    /// mutation funnel) — reliable, unlike observing the cached buckets.
    func refreshStatus() {
        guard let button = statusItem?.button else { return }

        let counts = model?.menuBarStateCounts ?? MenuBarStateCounts(total: 0, waiting: 0, running: 0, done: 0, idle: 0)
        if counts.total == 0 {
            // No sessions: show a single neutral dot as the clickable icon.
            let level = model?.menuBarStatusLevel ?? .none
            button.image = Self.makeStatusDot(color: level.dotColor)
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        } else {
            // The per-state chips already carry their own colored dots, so the
            // aggregate status dot would just be a redundant leading dot.
            button.image = nil
            button.attributedTitle = Self.makeBreakdownTitle(counts)
            button.imagePosition = .noImage
        }
        let summary = model?.menuBarStatusSummary ?? ""
        button.toolTip = summary.isEmpty ? "Open Island" : "Open Island — \(summary)"
    }

    // MARK: - Breakdown title

    private static let breakdownTextColor = NSColor.labelColor
    // Chip colors match IslandDesignPalette.Status (and the panel overview).
    private static let waitingColor = NSColor(srgbRed: 231 / 255, green: 167 / 255, blue: 98 / 255, alpha: 1)
    private static let runningColor = NSColor(srgbRed: 110 / 255, green: 167 / 255, blue: 255 / 255, alpha: 1)
    private static let doneColor = NSColor(srgbRed: 111 / 255, green: 185 / 255, blue: 130 / 255, alpha: 1)
    private static let idleColor = NSColor.tertiaryLabelColor

    /// "●1 ●1 ●1" — a colored dot + count for each non-zero state (waiting,
    /// running, done, idle), ordered by urgency. The aggregate total is omitted:
    /// it's redundant with the leading status dot and the per-state breakdown.
    private static func makeBreakdownTitle(_ counts: MenuBarStateCounts) -> NSAttributedString {
        let textFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let dotFont = NSFont.systemFont(ofSize: 8, weight: .black)

        let title = NSMutableAttributedString()

        func appendChip(_ count: Int, _ color: NSColor) {
            guard count > 0 else { return }
            // No leading pad on the first chip (no icon precedes it); gap between.
            title.append(NSAttributedString(
                string: title.length == 0 ? "" : "   ",
                attributes: [.font: textFont]
            ))
            title.append(NSAttributedString(
                string: "●",
                attributes: [.font: dotFont, .foregroundColor: color, .baselineOffset: 1]
            ))
            title.append(NSAttributedString(
                string: " \(count)",
                attributes: [.font: textFont, .foregroundColor: breakdownTextColor]
            ))
        }

        appendChip(counts.waiting, waitingColor)
        appendChip(counts.running, runningColor)
        appendChip(counts.done, doneColor)
        appendChip(counts.idle, idleColor)

        return title
    }

    // MARK: - Icon

    /// A filled colored circle. Non-template so the state color is preserved
    /// (template images get tinted monochrome by the menu bar).
    private static func makeStatusDot(color: NSColor) -> NSImage {
        let diameter: CGFloat = 9
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
