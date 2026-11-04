import CryptoKit
import Foundation
import Testing
@testable import OpenIslandCore

struct CodexLocalWebSocketTests {
    private func handshake(_ socket: CodexLocalWebSocket) -> Data {
        let request = String(decoding: socket.upgradeRequest, as: UTF8.self)
        let key = request.components(separatedBy: "Sec-WebSocket-Key: ")[1].components(separatedBy: "\r\n")[0]
        let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
        return Data("HTTP/1.1 101 Switching Protocols\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n".utf8)
    }

    private func frame(_ text: String, opcode: UInt8 = 1, final: Bool = true) -> Data {
        let payload = Data(text.utf8)
        return Data([(final ? 0x80 : 0) | opcode, UInt8(payload.count)]) + payload
    }

    @Test
    func acceptsSplitHandshakeAndCoalescedMessages() throws {
        var socket = CodexLocalWebSocket()
        let response = handshake(socket)
        #expect(try socket.receive(response.prefix(8)).isEmpty)
        let messages = try socket.receive(response.dropFirst(8) + frame("one") + frame("two"))
        let texts = messages.compactMap { message -> String? in
            if case let .text(data) = message { return String(decoding: data, as: UTF8.self) }
            return nil
        }
        #expect(texts == ["one", "two"])
    }

    @Test
    func fragmentedTextAllowsInterleavedPingAndPartialReads() throws {
        var socket = CodexLocalWebSocket()
        _ = try socket.receive(handshake(socket))
        let input = frame("hello ", final: false) + frame("ping", opcode: 9) + frame("world", opcode: 0)
        var texts: [String] = []
        var pings: [String] = []
        for byte in input {
            for message in try socket.receive(Data([byte])) {
                switch message {
                case let .text(data): texts.append(String(decoding: data, as: UTF8.self))
                case let .ping(data): pings.append(String(decoding: data, as: UTF8.self))
                case .closed: break
                }
            }
        }
        #expect(texts == ["hello world"])
        #expect(pings == ["ping"])
    }

    @Test(arguments: [5, 200, 70_000])
    func clientFramesAreMaskedAndRoundTripExtendedLengths(size: Int) {
        let payload = Data(repeating: 42, count: size)
        let encoded = Array(CodexLocalWebSocket.encode(payload))
        #expect(encoded[0] == 0x81)
        #expect(encoded[1] & 0x80 != 0)
        let maskOffset = size < 126 ? 2 : (size <= 65_535 ? 4 : 10)
        let mask = Array(encoded[maskOffset..<(maskOffset + 4)])
        let decoded = encoded.dropFirst(maskOffset + 4).enumerated().map { $0.element ^ mask[$0.offset % 4] }
        #expect(Data(decoded) == payload)
    }

    @Test
    func rejectsInvalidHandshakeAndOversizedFrames() throws {
        var bad = CodexLocalWebSocket()
        #expect(throws: CodexLocalWebSocket.ProtocolError.self) {
            try bad.receive(Data("HTTP/1.1 101 Switching Protocols\r\nSec-WebSocket-Accept: wrong\r\n\r\n".utf8))
        }
        var socket = CodexLocalWebSocket()
        _ = try socket.receive(handshake(socket))
        #expect(throws: CodexLocalWebSocket.ProtocolError.self) {
            try socket.receive(Data([0x81, 127, 0, 0, 0, 0, 2, 0, 0, 0]))
        }
    }
}
