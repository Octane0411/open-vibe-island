import Foundation
import Testing
@testable import OpenIslandCore

/// Pins the incremental line scan of `BridgeCodec.decodeLines`:
///
/// 1. A large line that arrives as many small reads is scanned once, not
///    re-scanned from the front on every read. The previous implementation
///    restarted at `buffer.startIndex` each call (O(n²)) and burned seconds
///    of CPU per multi-megabyte hook payload.
/// 2. `scanCursor` resumes where the previous scan stopped, and resets to zero
///    once a line is consumed. Callers reset it when they clear the buffer.
/// 3. Multi-line bursts, empty lines, and malformed input behave as before.
struct BridgeCodecLineScanTests {
    @Test
    func envelopesArrivingInSmallReadsDecodeInOrder() throws {
        let envelopes: [BridgeEnvelope] = [
            .hello(BridgeHello()),
            .response(.acknowledged),
            .event(
                .sessionCompleted(
                    SessionCompleted(
                        sessionID: "chunked-session",
                        summary: "done",
                        timestamp: Date(timeIntervalSince1970: 5_000)
                    )
                )
            ),
        ]

        var stream = Data()
        for envelope in envelopes {
            stream.append(try BridgeCodec.encodeLine(envelope))
        }

        let bytes = [UInt8](stream)
        let chunkSize = 512
        var buffer = Data()
        var scanCursor = 0
        var decoded: [BridgeEnvelope] = []

        var offset = 0
        while offset < bytes.count {
            let upperBound = min(offset + chunkSize, bytes.count)
            buffer.append(contentsOf: bytes[offset..<upperBound])

            decoded.append(contentsOf: try BridgeCodec.decodeLines(from: &buffer, scanCursor: &scanCursor))

            #expect(scanCursor <= buffer.count)
            offset = upperBound
        }

        #expect(decoded == envelopes)
        #expect(buffer.isEmpty)
        #expect(scanCursor == 0)
    }

    @Test
    func scanCursorAdvancesAcrossPartialReadsAndResetsWhenLineCompletes() throws {
        let line = try BridgeCodec.encodeLine(.hello(BridgeHello()))
        let splitIndex = line.count / 2

        var buffer = Data(line.prefix(splitIndex))
        var scanCursor = 0

        let firstPass = try BridgeCodec.decodeLines(from: &buffer, scanCursor: &scanCursor)
        #expect(firstPass.isEmpty)
        #expect(buffer.count == splitIndex)
        #expect(scanCursor == splitIndex)

        buffer.append(Data(line.suffix(from: splitIndex)))
        let secondPass = try BridgeCodec.decodeLines(from: &buffer, scanCursor: &scanCursor)
        #expect(secondPass == [.hello(BridgeHello())])
        #expect(buffer.isEmpty)
        #expect(scanCursor == 0)
    }

    @Test
    func trailingPartialLineStaysBufferedWhileCompleteLinesDecode() throws {
        let first = try BridgeCodec.encodeLine(.hello(BridgeHello()))
        let second = try BridgeCodec.encodeLine(.response(.acknowledged))
        let partial = Data(#"{"type":"hello","hello":{"protocol_version""#.utf8)

        var buffer = first + second + partial
        var scanCursor = 0

        let decoded = try BridgeCodec.decodeLines(from: &buffer, scanCursor: &scanCursor)

        #expect(decoded == [.hello(BridgeHello()), .response(.acknowledged)])
        #expect(buffer == partial)
        #expect(scanCursor == partial.count)
    }

    @Test
    func emptyLinesAreSkippedWithoutDisturbingCursor() throws {
        var buffer = Data("\n\n".utf8)
            + (try BridgeCodec.encodeLine(.hello(BridgeHello())))
            + Data("\n".utf8)
        var scanCursor = 0

        let decoded = try BridgeCodec.decodeLines(from: &buffer, scanCursor: &scanCursor)

        #expect(decoded == [.hello(BridgeHello())])
        #expect(buffer.isEmpty)
        #expect(scanCursor == 0)
    }

    @Test
    func malformedLineStillThrowsMalformedEnvelope() {
        var buffer = Data("not-json\n".utf8)
        var scanCursor = 0

        do {
            let decoded = try BridgeCodec.decodeLines(from: &buffer, scanCursor: &scanCursor)
            Issue.record("expected malformedEnvelope, decoded \(decoded)")
        } catch let error as BridgeTransportError {
            guard case .malformedEnvelope = error else {
                Issue.record("expected malformedEnvelope, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type \(error)")
        }
    }

    /// A multi-megabyte single line must cross the bridge in linear time.
    /// Hook payloads are newline-delimited JSON on one line and routinely reach
    /// several MB (a tool input carrying a large blob), so front-rescanning the
    /// buffer per 8 KB read cost seconds of CPU per event: 7.4s for 4 MB. The
    /// resume cursor brings it under 100 ms.
    @Test
    func multiMegabytePayloadCrossesRealBridgeInLinearTime() throws {
        let socketURL = BridgeSocketLocation.uniqueTestURL()
        let server = BridgeServer(socketURL: socketURL)
        try server.start()
        defer { server.stop() }

        let blob = String(repeating: "x", count: 4 * 1_024 * 1_024)
        let payload = ClaudeHookPayload(
            cwd: "/tmp/e2e",
            hookEventName: .preToolUse,
            sessionID: "e2e-linear-scan",
            toolName: "Bash",
            toolInput: .object(["command": .string(blob)]),
            toolUseID: "tool-use-linear-scan"
        )

        let startedAt = Date()
        let response = try BridgeCommandClient(socketURL: socketURL).send(.processClaudeHook(payload))
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(response == .acknowledged)
        #expect(elapsed < 3.0)
    }
}
