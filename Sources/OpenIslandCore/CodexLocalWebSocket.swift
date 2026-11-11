import CryptoKit
import Foundation

/// WebSocket framing for the existing local daemon socket. No network listener
/// is created and no session is resumed or subscribed on the user's behalf.
struct CodexLocalWebSocket {
    enum Frame { case text(Data), ping(Data), closed }
    enum ProtocolError: Error { case invalidHandshake, invalidFrame, oversizedMessage }
    static let maximumMessageSize = 16 * 1_024 * 1_024
    private var buffer = Data()
    private var fragments = Data()
    private var isFragmented = false
    private var upgraded = false
    var isUpgraded: Bool { upgraded }
    private let key = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()

    var upgradeRequest: Data {
        Data("GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n".utf8)
    }

    static func encode(_ payload: Data, opcode: UInt8 = 1) -> Data {
        let mask = (0..<4).map { _ in UInt8.random(in: .min ... .max) }
        var result = Data([0x80 | opcode])
        let size = payload.count
        if size < 126 {
            result.append(0x80 | UInt8(size))
        } else if size <= 65_535 {
            result.append(0xfe)
            result.append(contentsOf: [UInt8(size >> 8), UInt8(size & 0xff)])
        } else {
            result.append(0xff)
            result.append(contentsOf: (0..<8).reversed().map { UInt8((UInt64(size) >> ($0 * 8)) & 0xff) })
        }
        result.append(contentsOf: mask)
        result.append(contentsOf: payload.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        return result
    }

    mutating func receive(_ data: Data) throws -> [Frame] {
        buffer.append(data)
        if !upgraded {
            guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if buffer.count > 8_192 { throw ProtocolError.invalidHandshake }
                return []
            }
            let header = String(decoding: buffer[..<end.upperBound], as: UTF8.self)
            let expected = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
            guard header.hasPrefix("HTTP/1.1 101 "),
                  header.components(separatedBy: "\r\n").contains(where: {
                      $0.lowercased().hasPrefix("sec-websocket-accept:")
                          && $0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespacesAndNewlines) == expected
                  }) else { throw ProtocolError.invalidHandshake }
            buffer.removeSubrange(..<end.upperBound)
            upgraded = true
        }
        var frames: [Frame] = []
        while buffer.count >= 2 {
            let bytes = Array(buffer.prefix(10))
            let opcode = bytes[0] & 0x0f
            let final = bytes[0] & 0x80 != 0
            guard bytes[0] & 0x70 == 0, bytes[1] & 0x80 == 0 else { throw ProtocolError.invalidFrame }
            var length = UInt64(bytes[1] & 0x7f)
            var headerSize = 2
            if length == 126 {
                guard bytes.count >= 4 else { break }
                length = UInt64(bytes[2]) << 8 | UInt64(bytes[3])
                headerSize = 4
            } else if length == 127 {
                guard bytes.count >= 10 else { break }
                length = bytes[2..<10].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                headerSize = 10
            }
            guard length <= Self.maximumMessageSize,
                  UInt64(fragments.count) + length <= Self.maximumMessageSize else { throw ProtocolError.oversizedMessage }
            guard opcode < 8 || (final && length <= 125) else { throw ProtocolError.invalidFrame }
            guard buffer.count >= headerSize + Int(length) else { break }
            let payload = Data(buffer.dropFirst(headerSize).prefix(Int(length)))
            buffer.removeFirst(headerSize + Int(length))
            switch opcode {
            case 1:
                guard !isFragmented else { throw ProtocolError.invalidFrame }
                if final { frames.append(.text(payload)) }
                else { fragments = payload; isFragmented = true }
            case 0:
                guard isFragmented else { throw ProtocolError.invalidFrame }
                fragments.append(payload)
                if final { frames.append(.text(fragments)); fragments.removeAll(); isFragmented = false }
            case 8: frames.append(.closed)
            case 9: frames.append(.ping(payload))
            case 10: break
            default: throw ProtocolError.invalidFrame
            }
        }
        return frames
    }
}
