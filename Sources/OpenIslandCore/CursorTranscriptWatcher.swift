import Foundation

/// Watches a Cursor transcript JSONL file for AskQuestion tool-use entries.
///
/// Cursor does not fire hook events for its built-in AskQuestion tool, so this
/// watcher monitors the transcript file as an alternative detection path.
/// When an AskQuestion entry is found, the watcher emits a `QuestionPrompt`
/// through its callback so the caller can display it in the UI.
public final class CursorTranscriptWatcher: @unchecked Sendable {
    public typealias QuestionHandler = @Sendable (String, QuestionPrompt) -> Void

    private let sessionID: String
    private let filePath: String
    private let onQuestion: QuestionHandler

    private var fileOffset: UInt64 = 0
    private var dispatchSource: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "app.openisland.cursor-transcript-watcher")

    /// Set of AskQuestion tool_use_id values already processed, to avoid duplicates.
    private var seenToolUseIDs: Set<String> = []

    public init(sessionID: String, transcriptPath: String, onQuestion: @escaping QuestionHandler) {
        self.sessionID = sessionID
        self.filePath = transcriptPath
        self.onQuestion = onQuestion
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    public func start() {
        queue.async { [weak self] in
            self?.setupWatcher()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.dispatchSource?.cancel()
            self?.dispatchSource = nil
        }
    }

    // MARK: - File watching

    private func setupWatcher() {
        guard FileManager.default.fileExists(atPath: filePath) else { return }

        // Seek to the end so we only process new content from this point forward.
        if let handle = FileHandle(forReadingAtPath: filePath) {
            handle.seekToEndOfFile()
            fileOffset = handle.offsetInFile
            handle.closeFile()
        }

        guard let fd = open(filePath, O_RDONLY | O_EVTONLY) else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.readNewContent()
        }

        source.setCancelHandler {
            close(fd)
        }

        dispatchSource = source
        source.resume()
    }

    private func readNewContent() {
        guard let handle = FileHandle(forReadingAtPath: filePath) else { return }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: fileOffset)
        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty else { return }

        fileOffset = handle.offsetInFile

        guard let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            processLine(trimmed)
        }
    }

    // MARK: - Parsing

    private func processLine(_ jsonLine: String) {
        guard let lineData = jsonLine.data(using: .utf8),
              let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
              entry["role"] as? String == "assistant",
              let message = entry["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return
        }

        for block in content {
            guard block["type"] as? String == "tool_use",
                  block["name"] as? String == "AskQuestion",
                  let input = block["input"] as? [String: Any] else {
                continue
            }

            let toolUseID = block["id"] as? String ?? UUID().uuidString
            guard !seenToolUseIDs.contains(toolUseID) else { continue }
            seenToolUseIDs.insert(toolUseID)

            if let prompt = Self.parseQuestionPrompt(from: input) {
                onQuestion(sessionID, prompt)
            }
        }
    }

    /// Parses a Cursor AskQuestion tool input into a `QuestionPrompt`.
    ///
    /// The input shape mirrors Cursor's AskQuestion tool schema:
    /// ```json
    /// {
    ///   "title": "...",
    ///   "questions": [
    ///     {
    ///       "id": "...",
    ///       "prompt": "...",
    ///       "options": [{"id": "...", "label": "..."}],
    ///       "allow_multiple": false
    ///     }
    ///   ]
    /// }
    /// ```
    public static func parseQuestionPrompt(from input: [String: Any]) -> QuestionPrompt? {
        guard let rawQuestions = input["questions"] as? [[String: Any]],
              !rawQuestions.isEmpty else {
            return nil
        }

        let questions = rawQuestions.compactMap { rawQuestion -> QuestionPromptItem? in
            guard let prompt = rawQuestion["prompt"] as? String,
                  let rawOptions = rawQuestion["options"] as? [[String: Any]],
                  !rawOptions.isEmpty else {
                return nil
            }

            let header = rawQuestion["id"] as? String ?? ""
            let multiSelect = rawQuestion["allow_multiple"] as? Bool ?? false

            let options = rawOptions.compactMap { rawOption -> QuestionOption? in
                guard let label = rawOption["label"] as? String else { return nil }
                let description = rawOption["id"] as? String ?? ""
                return QuestionOption(label: label, description: description)
            }

            guard !options.isEmpty else { return nil }

            return QuestionPromptItem(
                question: prompt,
                header: header,
                options: options,
                multiSelect: multiSelect
            )
        }

        guard !questions.isEmpty else { return nil }

        let title: String
        if let explicitTitle = input["title"] as? String, !explicitTitle.isEmpty {
            title = explicitTitle
        } else if questions.count == 1, let firstQuestion = questions.first?.question {
            title = firstQuestion
        } else {
            title = "Cursor has \(questions.count) questions for you."
        }

        return QuestionPrompt(title: title, questions: questions)
    }
}

// MARK: - open() helper

private func open(_ path: String, _ flags: Int32) -> Int32? {
    let fd = Darwin.open(path, flags)
    return fd >= 0 ? fd : nil
}
