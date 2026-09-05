import Foundation

public struct HermesHookInstallationManifest: Equatable, Codable, Sendable {
    public static let fileName = "open-island-hermes-hooks-install.json"

    public var hookCommand: String
    public var installedAt: Date

    public init(hookCommand: String, installedAt: Date = .now) {
        self.hookCommand = hookCommand
        self.installedAt = installedAt
    }
}

public struct HermesHookFileMutation: Equatable, Sendable {
    public var contents: Data?
    public var changed: Bool
    public var managedHooksPresent: Bool

    public init(contents: Data?, changed: Bool, managedHooksPresent: Bool) {
        self.contents = contents
        self.changed = changed
        self.managedHooksPresent = managedHooksPresent
    }
}

public enum HermesHookInstallerError: Error, LocalizedError {
    case invalidConfigYAML
    case unsupportedYAMLStructure

    public var errorDescription: String? {
        switch self {
        case .invalidConfigYAML:
            "The existing Hermes config.yaml is not valid YAML."
        case .unsupportedYAMLStructure:
            "The Hermes config.yaml uses a hooks structure Open Island cannot safely edit."
        }
    }
}

/// Installs Open Island shell hooks into `~/.hermes/config.yaml`.
///
/// Hermes shell hooks live under a top-level `hooks:` mapping keyed by hook
/// event name; each value is a list of `{matcher?, command, timeout?}` entries
/// (see hermes_agent website/docs/user-guide/features/hooks.md). Editing the
/// whole document with a YAML parser would risk reformatting the user's file
/// and would need a YAML dependency; instead we do a conservative
/// indentation-aware block edit confined to the `hooks:` mapping. Anything
/// outside that mapping is byte-preserved. If `hooks:` is missing it is
/// appended at the end of the document (top-level `hooks:` is optional in the
/// Hermes schema, and appending at the end is order-safe).
///
/// Inside the block, entries under managed events (the Hermes events Open
/// Island subscribes to) are edited per entry: Open Island's own entries are
/// replaced or removed, foreign entries survive verbatim, and non-managed
/// event keys are never touched.
public enum HermesHookInstaller {
    /// Hermes events Open Island consumes. `post_llm_call` fires once per
    /// completed turn (the Stop equivalent); the rest are session lifecycle
    /// and human-in-the-loop interception (`clarify` questions and approval
    /// requests surface as notch cards).
    private static let eventNames = [
        "on_session_start",
        "on_session_end",
        "post_llm_call",
        "subagent_stop",
        "pre_tool_call",
        "pre_approval_request",
    ]

    /// Indent of an event key directly under `hooks:`.

    public static func hookCommand(for binaryPath: String) -> String {
        "\(binaryPath) --source hermes"
    }

    // MARK: - Install

    public static func installConfigYAML(
        existingData: Data?,
        hookCommand: String
    ) throws -> HermesHookFileMutation {
        let text = existingData.map { String(decoding: $0, as: UTF8.self) } ?? ""

        if let existingHooksRange = topLevelHooksBlockRange(in: text) {
            let blockText = String(text[existingHooksRange])
            let rebuilt = installIntoHooksBlock(blockText, hookCommand: hookCommand)

            // The located block range excludes a document-final newline, so
            // compare normalized forms before declaring the file changed.
            if rebuilt == blockText
                || rebuilt == normalizeTrailingNewline(blockText) {
                return HermesHookFileMutation(
                    contents: existingData,
                    changed: false,
                    managedHooksPresent: true
                )
            }

            var full = text
            full.replaceSubrange(existingHooksRange, with: rebuilt)
            return HermesHookFileMutation(
                contents: Data(full.utf8),
                changed: true,
                managedHooksPresent: true
            )
        }

        // No top-level `hooks:` block — append a fresh one.
        var appended = text
        if !appended.isEmpty && !appended.hasSuffix("\n") {
            appended += "\n"
        }
        appended += managedHooksBlock(hookCommand: hookCommand)
        return HermesHookFileMutation(
            contents: Data(appended.utf8),
            changed: true,
            managedHooksPresent: true
        )
    }

    /// Ensures every managed event carries exactly one Open Island entry.
    /// Foreign entries under managed events and every unmanaged line survive
    /// verbatim; Open Island's own (possibly stale) entries are replaced.
    private static func installIntoHooksBlock(
        _ blockText: String,
        hookCommand: String
    ) -> String {
        let blockLines = splitLines(blockText)
        let eventIndent = detectEventIndent(in: blockLines) ?? defaultEventIndent
        var output: [String] = []
        var eventsSeen = Set<String>()

        var index = 0
        while index < blockLines.count {
            let line = blockLines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = leadingIndent(of: line) ?? 0

            guard indent == eventIndent, isEventKeyLine(trimmed) else {
                output.append(line)
                index += 1
                continue
            }

            let event = eventKey(of: trimmed)
            guard eventNames.contains(event) else {
                output.append(line)
                index += 1
                continue
            }

            let body = eventBody(blockLines, from: index + 1, eventIndent: eventIndent)
            let (foreignLines, _) = foreignEntryLines(body)

            output.append(line)
            output.append(contentsOf: foreignLines)
            output.append(eventEntry(command: hookCommand, indent: eventIndent))

            eventsSeen.insert(event)
            index += body.lineCount + 1
        }

        // Managed events missing from the block are appended to it so the
        // mapping stays single (only when the block already carries at least
        // one managed event; otherwise the untouched lines fall through to
        // the plain append path below).
        if !eventsSeen.isEmpty {
            for event in eventNames where !eventsSeen.contains(event) {
                output.append("\(indentation(eventIndent))\(event):")
                output.append(eventEntry(command: hookCommand, indent: eventIndent))
            }
            return normalizeTrailingNewline(output.joined(separator: "\n"))
        }

        // The block carries none of our events — append them after stripping
        // trailing blanks.
        var lines = blockLines
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        for event in eventNames {
            lines.append("\(indentation(eventIndent))\(event):")
            lines.append(eventEntry(command: hookCommand, indent: eventIndent))
        }
        return normalizeTrailingNewline(lines.joined(separator: "\n"))
    }

    // MARK: - Uninstall

    public static func uninstallConfigYAML(
        existingData: Data?,
        managedCommand: String?
    ) throws -> HermesHookFileMutation {
        guard let existingData else {
            return HermesHookFileMutation(contents: nil, changed: false, managedHooksPresent: false)
        }

        let text = String(decoding: existingData, as: UTF8.self)
        guard let existingHooksRange = topLevelHooksBlockRange(in: text) else {
            return HermesHookFileMutation(contents: existingData, changed: false, managedHooksPresent: false)
        }

        let blockText = String(text[existingHooksRange])
        let (rebuilt, removedAny) = uninstallFromHooksBlock(blockText, hookCommand: managedCommand)

        if !removedAny {
            return HermesHookFileMutation(
                contents: existingData,
                changed: false,
                managedHooksPresent: blockHasOpenIslandEntries(blockText)
            )
        }

        // Only the `hooks:` key (and blanks) left — the block existed solely
        // for Open Island, so remove it whole.
        let remainingMeaningful = rebuilt
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && trimmed != "hooks:"
            }

        var full = text
        if remainingMeaningful.isEmpty {
            full.removeSubrange(existingHooksRange)
            var cleaned = String(full)
            while cleaned.hasSuffix("\n") {
                cleaned.removeLast()
            }
            if !cleaned.isEmpty {
                cleaned += "\n"
            }
            return HermesHookFileMutation(
                contents: cleaned.isEmpty ? nil : Data(cleaned.utf8),
                changed: true,
                managedHooksPresent: false
            )
        }

        full.replaceSubrange(existingHooksRange, with: rebuilt)
        return HermesHookFileMutation(
            contents: Data(full.utf8),
            changed: true,
            managedHooksPresent: blockHasOpenIslandEntries(rebuilt)
        )
    }

    /// Removes Open Island entries from managed events. Foreign entries and
    /// unmanaged lines survive verbatim. Returns the rebuilt block and whether
    /// anything was removed.
    private static func uninstallFromHooksBlock(
        _ blockText: String,
        hookCommand: String?
    ) -> (rebuilt: String, removedAny: Bool) {
        let blockLines = splitLines(blockText)
        let eventIndent = detectEventIndent(in: blockLines) ?? defaultEventIndent
        var output: [String] = []
        var removedAny = false

        var index = 0
        while index < blockLines.count {
            let line = blockLines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = leadingIndent(of: line) ?? 0

            guard indent == eventIndent, isEventKeyLine(trimmed) else {
                output.append(line)
                index += 1
                continue
            }

            let event = eventKey(of: trimmed)
            guard eventNames.contains(event) else {
                output.append(line)
                index += 1
                continue
            }

            let body = eventBody(blockLines, from: index + 1, eventIndent: eventIndent)
            let (keptLines, hasOpenIslandEntry) = foreignEntryLines(body, hookCommand: hookCommand)

            if hasOpenIslandEntry {
                removedAny = true
                if keptLines.isEmpty {
                    // The event now has no entries — drop the key entirely.
                    index += body.lineCount + 1
                    continue
                }
                output.append(line)
                output.append(contentsOf: keptLines)
            } else {
                output.append(line)
                output.append(contentsOf: body.lines)
            }

            index += body.lineCount + 1
        }

        while output.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            output.removeLast()
        }

        return (normalizeTrailingNewline(output.joined(separator: "\n")), removedAny)
    }

    // MARK: - Command recognition

    /// Read-only probe: whether the top-level `hooks:` block carries any
    /// Open Island Hermes entries right now. Unlike the uninstall round-trip
    /// this never mutates or rewrites the document.
    public static func configYAMLHasOpenIslandHooks(existingData: Data?) throws -> Bool {
        guard let existingData else {
            return false
        }

        let text = String(decoding: existingData, as: UTF8.self)
        guard let existingHooksRange = topLevelHooksBlockRange(in: text) else {
            return false
        }

        return blockHasOpenIslandEntries(String(text[existingHooksRange]))
    }

    public static func isOpenIslandHermesHookCommand(_ command: String) -> Bool {
        let normalized = command.lowercased()
        return (normalized.contains("openislandhooks") || normalized.contains("vibeislandhooks"))
            && normalized.contains("hermes")
    }

    // MARK: - Block location

    /// Enumerates `(line, fullLineRange)` pairs including their terminating
    /// newline. `String.lineRanges()` is Substring-only on this toolchain, so
    /// lines are split manually.
    private static func documentLines(in text: String) -> [(content: Substring, range: Range<String.Index>)] {
        var lines: [(Substring, Range<String.Index>)] = []
        var index = text.startIndex

        while index < text.endIndex {
            let newlineIndex = text[index...].firstIndex(of: "\n") ?? text.endIndex
            let contentEnd = newlineIndex == text.endIndex ? text.endIndex : newlineIndex
            lines.append((text[index..<contentEnd], index..<contentEnd))
            index = newlineIndex == text.endIndex ? text.endIndex : text.index(after: newlineIndex)
        }

        if lines.isEmpty {
            lines.append(("", text.startIndex..<text.startIndex))
        }

        return lines
    }

    /// Finds the range of the top-level `hooks:` mapping (through end of its
    /// last indented line), or nil when absent/commented-out.
    private static func topLevelHooksBlockRange(in text: String) -> Range<String.Index>? {
        let lines = documentLines(in: text)

        for (lineIndex, entry) in lines.enumerated() {
            let line = String(entry.content)
            guard let indent = leadingIndent(of: line), indent == 0 else {
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("hooks:") else {
                continue
            }

            var end = entry.range.upperBound
            for probe in lines.dropFirst(lineIndex + 1) {
                let probeLine = String(probe.content)
                guard !probeLine.trimmingCharacters(in: .whitespaces).isEmpty else {
                    continue
                }

                let probeIndent = leadingIndent(of: probeLine) ?? 0
                if probeIndent == 0 {
                    break
                }
                end = probe.range.upperBound
            }

            return entry.range.lowerBound..<end
        }

        return nil
    }

    private static func leadingIndent(of line: String) -> Int? {
        var count = 0
        for ch in line {
            if ch == " " {
                count += 1
            } else if ch == "\t" {
                count += 4
            } else {
                break
            }
        }
        // A line that is only whitespace has no meaningful indent.
        return line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : count
    }

    // MARK: - Block scanning helpers

    private static func splitLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private static func isEventKeyLine(_ trimmed: String) -> Bool {
        !eventKey(of: trimmed).isEmpty
    }

    /// Key of a mapping line like `post_llm_call:` or `post_llm_call: # note` —
    /// the text before the first `:`, with any trailing comment removed.
    private static func eventKey(of trimmed: String) -> String {
        guard let colon = trimmed.firstIndex(of: ":") else { return "" }
        let rawKey = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !rawKey.isEmpty, !rawKey.hasPrefix("#"), !rawKey.hasPrefix("- ") else { return "" }
        guard !rawKey.hasPrefix("\""), !rawKey.hasPrefix("'") else { return "" }
        return rawKey
    }

    /// Indent used by the block's own event keys: taken from the first
    /// event-key-shaped line deeper than the `hooks:` key itself, so YAML
    /// files that indent with 4 spaces (or any other consistent amount) are
    /// matched and extended in place instead of producing duplicate keys.
    private static func detectEventIndent(in blockLines: [String]) -> Int? {
        for line in blockLines {
            let indent = leadingIndent(of: line) ?? 0
            guard indent > 0 else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard isEventKeyLine(trimmed) else { continue }
            return indent
        }
        return nil
    }

    private static let defaultEventIndent = 2

    private static func indentation(_ width: Int) -> String {
        String(repeating: " ", count: width)
    }

    /// One managed list entry under an event key, at the block's own event
    /// indent (key indent + 2). The managed command is `<binary> --source hermes`;
    /// only the binary path takes a shell-level quote so that Hermes'
    /// `shlex.split` yields the binary as `argv[0]` and `--source` / `hermes`
    /// as separate arguments. The shell-quoted form is wrapped in a YAML
    /// double-quoted scalar (single quotes inside stay literal, so the
    /// shell layer survives the YAML round-trip).
    private static func eventEntry(command: String, indent: Int) -> String {
        let quoted = quotedManagedCommand(command)
        return "\(indentation(indent + 2))- command: \(yamlQuote(quoted))"
    }

    /// Shell-quotes just the binary portion of a managed command, leaving
    /// its arguments bare. The managed command's shape is
    /// `<binary path> --source hermes` (see `hookCommand(for:)`), so the
    /// split point is the known trailing flag — a binary path may itself
    /// contain spaces, so splitting at the first space would be wrong.
    private static func quotedManagedCommand(_ command: String) -> String {
        let argumentsSuffix = " --source hermes"
        guard command.hasSuffix(argumentsSuffix) else {
            return shellQuote(command)
        }
        let binary = String(command.dropLast(argumentsSuffix.count))
        return "\(shellQuote(binary)) --source hermes"
    }

    /// Body of an event: every line after the key until the next event key or
    /// any other non-blank line at `eventIndent` or shallower. Returns the
    /// body lines and how many of them (including the terminating blanks) were
    /// consumed.
    private static func eventBody(
        _ blockLines: [String],
        from start: Int,
        eventIndent: Int
    ) -> (lines: [String], lineCount: Int) {
        var body: [String] = []
        var index = start

        while index < blockLines.count {
            let line = blockLines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                body.append(line)
                index += 1
                continue
            }

            if (leadingIndent(of: line) ?? 0) > eventIndent {
                body.append(line)
                index += 1
                continue
            }

            break
        }

        // Trailing blanks belong between events, not to this body.
        while body.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            body.removeLast()
            index -= 1
        }

        return (body, body.count)
    }

    /// Splits an event body into YAML list entries and keeps only the foreign
    /// ones verbatim. Returns the kept lines and whether the body carried any
    /// Open Island entry. With `hookCommand == nil` the Open Island marker
    /// alone decides ownership.
    private static func foreignEntryLines(
        _ body: (lines: [String], lineCount: Int),
        hookCommand: String? = nil
    ) -> (kept: [String], hasOpenIslandEntry: Bool) {
        var kept: [String] = []
        var currentEntry: [String] = []
        var hasOpenIslandEntry = false

        func flush() {
            guard !currentEntry.isEmpty else { return }
            if entryIsOpenIsland(currentEntry, hookCommand: hookCommand) {
                hasOpenIslandEntry = true
            } else {
                kept.append(contentsOf: currentEntry)
            }
            currentEntry = []
        }

        for line in body.lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // Blank lines stay attached to whatever entry they follow.
                if currentEntry.isEmpty {
                    kept.append(line)
                } else {
                    currentEntry.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("-\t") {
                flush()
            }
            currentEntry.append(line)
        }
        flush()

        return (kept, hasOpenIslandEntry)
    }

    private static func entryIsOpenIsland(_ entryLines: [String], hookCommand: String?) -> Bool {
        for line in entryLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let rest = trimmed.hasPrefix("- ")
                ? trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                : trimmed

            guard let kv = parseKeyValue(rest), kv.key == "command" else {
                continue
            }

            let command = unquote(kv.value)
            if let hookCommand, command == hookCommand {
                return true
            }
            if isOpenIslandHermesHookCommand(command) {
                return true
            }
        }
        return false
    }

    private static func blockHasOpenIslandEntries(_ blockText: String) -> Bool {
        let blockLines = splitLines(blockText)
        let eventIndent = detectEventIndent(in: blockLines) ?? defaultEventIndent

        var index = 0
        while index < blockLines.count {
            let line = blockLines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = leadingIndent(of: line) ?? 0

            guard indent == eventIndent, isEventKeyLine(trimmed) else {
                index += 1
                continue
            }

            let event = eventKey(of: trimmed)
            if eventNames.contains(event) {
                let body = eventBody(blockLines, from: index + 1, eventIndent: eventIndent)
                if foreignEntryLines(body).hasOpenIslandEntry {
                    return true
                }
                index += body.lineCount + 1
            } else {
                index += 1
            }
        }

        return false
    }

    // MARK: - Parsing helpers

    private static func parseKeyValue(_ line: String) -> (key: String, value: String)? {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return nil
        }

        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            return nil
        }

        return (key, value)
    }

    /// Wraps an already shell-quoted command in a YAML single-quoted scalar.
    /// YAML single-quote escaping doubles `'`; the shell layer's `'\''`
    /// sequences survive inside the YAML scalar and are decoded by
    /// `shlex.split` when Hermes runs the hook.
    private static func yamlQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }

    private static func unquote(_ value: String) -> String {
        var text = value
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            text = String(text.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        } else if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast())
        }
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            text = String(text.dropFirst().dropLast())
                .replacingOccurrences(of: "\\'", with: "'")
        }
        return text
    }

    // MARK: - Serialization

    private static func normalizeTrailingNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? text : text + "\n"
    }

    private static func managedHooksBlock(hookCommand: String) -> String {
        var lines = ["hooks:"]
        for event in eventNames {
            lines.append("\(indentation(defaultEventIndent))\(event):")
            lines.append(eventEntry(command: hookCommand, indent: defaultEventIndent))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
