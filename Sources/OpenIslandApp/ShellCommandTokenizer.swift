import Foundation
import SwiftUI

/// A lightweight, dependency-free lexer for the shell commands that appear in
/// permission bodies (AB-328 / draft T10).
///
/// The permission hero in all three redesign mockups syntax-highlights the
/// command awaiting approval — `swift`=command, `build`=subcommand, `-c`=flag,
/// `"fetch("`=string, `packages/ui/src`=path. Today those previews render as one
/// flat mono `Text`, so this type gives later theme tickets (T15 / T16 / T26) a
/// pure classifier plus a SwiftUI ``AttributedString`` builder to consume. No
/// existing view changes in this PR.
///
/// ## Design contract
///
/// - **Pure + total.** ``tokenize(_:)`` never throws and never crashes. For
///   *any* input — empty, emoji, ten-thousand characters, an unbalanced quote —
///   it returns a list of ``Span``s that tile the whole string edge to edge:
///   contiguous, non-overlapping, gap-free, and reassembling to the exact input.
///   The property test in `ShellCommandTokenizerTests` pins that invariant over
///   seeded random inputs.
/// - **No theme colours here.** The tokenizer only assigns *kinds*; callers own
///   the `[Kind: Color]` palette. ``attributed(_:palette:weights:baseFont:)`` is
///   the SwiftUI-facing convenience that turns a command + a theme's palette
///   into an ``AttributedString``.
///
/// Kept as an `enum` of `static` members for the same reason
/// `IslandClosedLabelResolver` is: every input is an argument, so results depend
/// only on their arguments and tests can pin exact output without any UI.
enum ShellCommandTokenizer {

    // MARK: - Output types

    /// The classification assigned to a stretch of the command string.
    ///
    /// The set is deliberately small — enough for the permission hero's
    /// highlighting, no more. Anything the rules can't describe falls back to
    /// ``plain`` (which also absorbs the whitespace between tokens), so the
    /// kinds never leave a gap.
    enum Kind: String, Sendable, CaseIterable, Codable {
        /// The first word — the program being invoked (`swift`, `rtk`, `git`).
        case command
        /// A bare second word after a command (`build`, `grep`, `commit`).
        case subcommand
        /// A `-x` / `--long` option token.
        case flag
        /// A single- or double-quoted run, including one left unbalanced to the
        /// end of the string.
        case string
        /// A token that reads like a file/URL path — contains `/` or ends in a
        /// known file extension.
        case path
        /// Everything else, plus every run of inter-token whitespace.
        case plain
    }

    /// A single classified stretch of the input, addressed by `String.Index`
    /// range so the caller can slice the *original* string (no copies, no lost
    /// bytes). Spans are returned in source order and tile the whole input.
    struct Span: Equatable, Sendable {
        let range: Range<String.Index>
        let kind: Kind

        init(range: Range<String.Index>, kind: Kind) {
            self.range = range
            self.kind = kind
        }
    }

    // MARK: - Tokenization

    /// Split `command` into ordered, gap-free ``Span``s.
    ///
    /// The scan alternates between whitespace runs (folded into ``Kind/plain``)
    /// and non-whitespace "words". A word is quote-aware: once a `'` or `"`
    /// opens, the scan runs to the matching quote — or to the end of the string
    /// if the quote is never closed — so a quoted argument with internal spaces
    /// (`--msg="hi there"`) stays a single token.
    ///
    /// Empty input yields an empty array (which still satisfies the coverage
    /// invariant: the reassembly of no spans is the empty string).
    static func tokenize(_ command: String) -> [Span] {
        var spans: [Span] = []
        var index = command.startIndex
        let end = command.endIndex

        // 0-based position of the *word* being classified (whitespace runs do
        // not advance it), plus the kind assigned to word 0 so the subcommand
        // rule can require an actual command in front of it.
        var wordIndex = 0
        var firstWordKind: Kind?

        while index < end {
            if command[index].isWhitespace {
                let segmentStart = index
                while index < end, command[index].isWhitespace {
                    index = command.index(after: index)
                }
                spans.append(Span(range: segmentStart..<index, kind: .plain))
            } else {
                let segmentStart = index
                index = wordEnd(in: command, from: index, end: end)
                let word = command[segmentStart..<index]
                let kind = classify(word: word, wordIndex: wordIndex, firstWordKind: firstWordKind)
                if wordIndex == 0 { firstWordKind = kind }
                wordIndex += 1
                spans.append(Span(range: segmentStart..<index, kind: kind))
            }
        }

        return spans
    }

    /// A debugging / test convenience: the same tokenization as ``tokenize(_:)``
    /// but with each span materialized as `(text, kind)`. Consumers that need
    /// zero-copy slicing should use ``tokenize(_:)`` directly.
    static func labeledTokens(_ command: String) -> [(text: String, kind: Kind)] {
        tokenize(command).map { (String(command[$0.range]), $0.kind) }
    }

    // MARK: - AttributedString builder

    /// Build a SwiftUI ``AttributedString`` for `command`, colouring each span
    /// with the caller's palette and, optionally, weighting it.
    ///
    /// - Parameters:
    ///   - command: the raw command text.
    ///   - palette: per-kind foreground colours. A kind absent from the table
    ///     is left uncoloured (it inherits the ambient `Text` colour), so a
    ///     theme can highlight only the tokens it cares about.
    ///   - weights: optional per-kind font weight. A weight is folded onto
    ///     `baseFont`; when `baseFont` is `nil` it is applied over the system
    ///     body font (themes always pass their mono `baseFont`, so this fallback
    ///     is only for palette-only previews).
    ///   - baseFont: the font every run starts from, e.g. a theme's monospaced
    ///     hero font. `nil` leaves runs at the ambient `Text` font unless a
    ///     weight forces one.
    /// - Returns: an ``AttributedString`` whose characters are exactly `command`.
    static func attributed(
        _ command: String,
        palette: [Kind: Color],
        weights: [Kind: Font.Weight] = [:],
        baseFont: Font? = nil
    ) -> AttributedString {
        var result = AttributedString()

        for span in tokenize(command) {
            var piece = AttributedString(String(command[span.range]))

            if let color = palette[span.kind] {
                piece.foregroundColor = color
            }

            let weight = weights[span.kind]
            if let baseFont {
                piece.font = weight.map { baseFont.weight($0) } ?? baseFont
            } else if let weight {
                piece.font = Font.body.weight(weight)
            }

            result.append(piece)
        }

        return result
    }

    // MARK: - Scanning

    /// The end index of the non-whitespace word starting at `start`.
    ///
    /// Advances one character at a time until whitespace or the end, except that
    /// an opening quote (`'` or `"`) fast-forwards to the matching close quote
    /// (or the end of the string if unbalanced). Always advances at least one
    /// character, so callers never emit an empty span or spin.
    private static func wordEnd(
        in string: String,
        from start: String.Index,
        end: String.Index
    ) -> String.Index {
        var index = start
        while index < end {
            let character = string[index]
            if character.isWhitespace { break }

            if character == "\"" || character == "'" {
                let quote = character
                index = string.index(after: index)
                while index < end, string[index] != quote {
                    index = string.index(after: index)
                }
                if index < end {
                    index = string.index(after: index) // consume the closing quote
                }
            } else {
                index = string.index(after: index)
            }
        }
        return index
    }

    // MARK: - Classification

    /// Assign a ``Kind`` to one word. Structural cues (quote, dash, path shape)
    /// win over position, so a bare URL preview classifies as ``Kind/path`` and
    /// not ``Kind/command``. Precedence, high to low:
    ///
    /// 1. leading `'`/`"` → ``Kind/string``
    /// 2. leading `-` → ``Kind/flag``
    /// 3. contains `/` or a known extension → ``Kind/path``
    /// 4. first word → ``Kind/command``
    /// 5. second word after a command → ``Kind/subcommand``
    /// 6. otherwise → ``Kind/plain``
    private static func classify(
        word: Substring,
        wordIndex: Int,
        firstWordKind: Kind?
    ) -> Kind {
        guard let first = word.first else { return .plain }

        if first == "\"" || first == "'" { return .string }
        if first == "-" { return .flag }
        if isPathLike(word) { return .path }
        if wordIndex == 0 { return .command }
        if wordIndex == 1, firstWordKind == .command { return .subcommand }
        return .plain
    }

    /// A word "reads like a path" when it carries a separator or a recognised
    /// file extension. Callers reach here only for unquoted, non-flag words.
    private static func isPathLike(_ word: Substring) -> Bool {
        if word.contains("/") { return true }
        return hasKnownExtension(word)
    }

    /// True when the word ends in `.<ext>` for a known `ext` (case-insensitive).
    private static func hasKnownExtension(_ word: Substring) -> Bool {
        guard let dot = word.lastIndex(of: ".") else { return false }
        let ext = word[word.index(after: dot)...].lowercased()
        guard !ext.isEmpty else { return false }
        return knownFileExtensions.contains(ext)
    }

    /// A curated, intentionally finite set of file extensions common in coding
    /// sessions. Not exhaustive — anything unrecognised without a `/` simply
    /// stays ``Kind/plain``, which is the safe fallback.
    private static let knownFileExtensions: Set<String> = [
        // Swift / Apple
        "swift", "h", "m", "mm", "plist", "xcconfig", "entitlements", "storyboard", "xib",
        // Web / JS / TS
        "js", "mjs", "cjs", "jsx", "ts", "tsx", "vue", "svelte", "html", "htm", "css", "scss", "sass", "less",
        // Systems / compiled
        "c", "cc", "cpp", "cxx", "hpp", "hh", "rs", "go", "java", "kt", "kts", "scala", "cs", "zig",
        // Scripting
        "py", "rb", "php", "pl", "lua", "sh", "zsh", "bash", "fish", "ps1", "r",
        // Data / config
        "json", "yml", "yaml", "toml", "ini", "cfg", "conf", "env", "lock", "xml", "sql", "csv", "tsv", "proto", "graphql", "gql",
        // Docs / text
        "md", "markdown", "mdx", "txt", "rst", "adoc", "tex", "log",
        // Assets
        "png", "jpg", "jpeg", "gif", "svg", "webp", "pdf", "ico", "icns",
        // Archives
        "zip", "tar", "gz", "tgz", "bz2", "xz",
        // Common dotfiles (extension-form)
        "gitignore", "gitattributes", "dockerignore", "editorconfig",
    ]
}
