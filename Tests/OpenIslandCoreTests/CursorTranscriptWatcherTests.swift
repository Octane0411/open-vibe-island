import Foundation
import Testing
@testable import OpenIslandCore

struct CursorTranscriptWatcherTests {

    // MARK: - parseQuestionPrompt

    @Test
    func parseSingleQuestion() throws {
        let input: [String: Any] = [
            "title": "Pick a framework",
            "questions": [
                [
                    "id": "q1",
                    "prompt": "Which framework do you prefer?",
                    "options": [
                        ["id": "react", "label": "React"],
                        ["id": "vue", "label": "Vue"],
                    ],
                ] as [String: Any],
            ],
        ]

        let prompt = CursorTranscriptWatcher.parseQuestionPrompt(from: input)
        #expect(prompt != nil)
        #expect(prompt?.title == "Pick a framework")
        #expect(prompt?.questions.count == 1)
        #expect(prompt?.questions.first?.question == "Which framework do you prefer?")
        #expect(prompt?.questions.first?.options.count == 2)
        #expect(prompt?.questions.first?.options[0].label == "React")
        #expect(prompt?.questions.first?.options[1].label == "Vue")
        #expect(prompt?.questions.first?.multiSelect == false)
    }

    @Test
    func parseMultipleQuestions() throws {
        let input: [String: Any] = [
            "title": "Setup preferences",
            "questions": [
                [
                    "id": "lang",
                    "prompt": "Language?",
                    "options": [
                        ["id": "ts", "label": "TypeScript"],
                        ["id": "py", "label": "Python"],
                    ],
                ] as [String: Any],
                [
                    "id": "db",
                    "prompt": "Database?",
                    "options": [
                        ["id": "pg", "label": "PostgreSQL"],
                        ["id": "mysql", "label": "MySQL"],
                    ],
                    "allow_multiple": true,
                ] as [String: Any],
            ],
        ]

        let prompt = CursorTranscriptWatcher.parseQuestionPrompt(from: input)
        #expect(prompt != nil)
        #expect(prompt?.title == "Setup preferences")
        #expect(prompt?.questions.count == 2)
        #expect(prompt?.questions[1].multiSelect == true)
    }

    @Test
    func parseQuestionWithNoTitle() throws {
        let input: [String: Any] = [
            "questions": [
                [
                    "id": "q1",
                    "prompt": "Continue?",
                    "options": [
                        ["id": "yes", "label": "Yes"],
                        ["id": "no", "label": "No"],
                    ],
                ] as [String: Any],
            ],
        ]

        let prompt = CursorTranscriptWatcher.parseQuestionPrompt(from: input)
        #expect(prompt != nil)
        #expect(prompt?.title == "Continue?")
    }

    @Test
    func parseEmptyQuestionsReturnsNil() throws {
        let input: [String: Any] = ["questions": [] as [[String: Any]]]
        let prompt = CursorTranscriptWatcher.parseQuestionPrompt(from: input)
        #expect(prompt == nil)
    }

    @Test
    func parseMissingQuestionsReturnsNil() throws {
        let input: [String: Any] = ["title": "No questions here"]
        let prompt = CursorTranscriptWatcher.parseQuestionPrompt(from: input)
        #expect(prompt == nil)
    }

    @Test
    func parseQuestionWithEmptyOptionsReturnsNil() throws {
        let input: [String: Any] = [
            "questions": [
                [
                    "id": "q1",
                    "prompt": "Pick one",
                    "options": [] as [[String: Any]],
                ] as [String: Any],
            ],
        ]
        let prompt = CursorTranscriptWatcher.parseQuestionPrompt(from: input)
        #expect(prompt == nil)
    }

    // MARK: - File watching integration

    @Test
    func watcherDetectsAskQuestionInNewContent() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-watcher-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let transcriptPath = tmpDir.appendingPathComponent("transcript.jsonl").path

        FileManager.default.createFile(atPath: transcriptPath, contents: Data())

        let expectation = Expectation()
        var receivedPrompt: QuestionPrompt?
        var receivedSessionID: String?

        let watcher = CursorTranscriptWatcher(
            sessionID: "test-session-123",
            transcriptPath: transcriptPath
        ) { sessionID, prompt in
            receivedSessionID = sessionID
            receivedPrompt = prompt
            expectation.fulfill()
        }

        watcher.start()

        try await Task.sleep(for: .milliseconds(200))

        let askQuestionLine = """
        {"role":"assistant","message":{"content":[{"type":"tool_use","name":"AskQuestion","id":"tool-1","input":{"title":"Test Question","questions":[{"id":"q1","prompt":"Pick one","options":[{"id":"a","label":"Option A"},{"id":"b","label":"Option B"}]}]}}]}}
        """
        let handle = FileHandle(forWritingAtPath: transcriptPath)!
        handle.seekToEndOfFile()
        handle.write(Data((askQuestionLine + "\n").utf8))
        handle.closeFile()

        await expectation.fulfillment(within: .seconds(3))

        #expect(receivedSessionID == "test-session-123")
        #expect(receivedPrompt != nil)
        #expect(receivedPrompt?.title == "Test Question")
        #expect(receivedPrompt?.questions.count == 1)
        #expect(receivedPrompt?.questions.first?.options.count == 2)

        watcher.stop()
    }

    @Test
    func watcherIgnoresNonAskQuestionLines() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-watcher-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let transcriptPath = tmpDir.appendingPathComponent("transcript.jsonl").path
        FileManager.default.createFile(atPath: transcriptPath, contents: Data())

        var questionCount = 0

        let watcher = CursorTranscriptWatcher(
            sessionID: "test-session",
            transcriptPath: transcriptPath
        ) { _, _ in
            questionCount += 1
        }

        watcher.start()
        try await Task.sleep(for: .milliseconds(200))

        let shellLine = """
        {"role":"assistant","message":{"content":[{"type":"tool_use","name":"Shell","input":{"command":"ls"}}]}}
        """
        let readLine = """
        {"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"path":"/tmp/test.txt"}}]}}
        """
        let handle = FileHandle(forWritingAtPath: transcriptPath)!
        handle.seekToEndOfFile()
        handle.write(Data((shellLine + "\n" + readLine + "\n").utf8))
        handle.closeFile()

        try await Task.sleep(for: .seconds(1))
        #expect(questionCount == 0)

        watcher.stop()
    }

    @Test
    func watcherDoesNotDuplicateQuestions() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-watcher-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let transcriptPath = tmpDir.appendingPathComponent("transcript.jsonl").path
        FileManager.default.createFile(atPath: transcriptPath, contents: Data())

        var questionCount = 0

        let watcher = CursorTranscriptWatcher(
            sessionID: "test-session",
            transcriptPath: transcriptPath
        ) { _, _ in
            questionCount += 1
        }

        watcher.start()
        try await Task.sleep(for: .milliseconds(200))

        let askQuestionLine = """
        {"role":"assistant","message":{"content":[{"type":"tool_use","name":"AskQuestion","id":"tool-same-id","input":{"title":"Q","questions":[{"id":"q1","prompt":"Pick","options":[{"id":"a","label":"A"},{"id":"b","label":"B"}]}]}}]}}
        """

        let handle1 = FileHandle(forWritingAtPath: transcriptPath)!
        handle1.seekToEndOfFile()
        handle1.write(Data((askQuestionLine + "\n").utf8))
        handle1.closeFile()

        try await Task.sleep(for: .seconds(1))
        #expect(questionCount == 1)

        watcher.stop()
    }

    // MARK: - Expectation helper

    private final class Expectation: @unchecked Sendable {
        private var fulfilled = false
        private let lock = NSLock()

        func fulfill() {
            lock.lock()
            fulfilled = true
            lock.unlock()
        }

        func fulfillment(within duration: Duration) async {
            let deadline = ContinuousClock.now + duration
            while ContinuousClock.now < deadline {
                lock.lock()
                let done = fulfilled
                lock.unlock()
                if done { return }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}
