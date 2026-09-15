import Foundation

struct WatchHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: String?

    static func parse(_ data: Data) throws -> WatchHTTPRequest? {
        guard data.count <= 73_728 else { throw ParseError.invalid }
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else {
            if data.count > 8_192 { throw ParseError.invalid }
            return nil
        }
        guard split.lowerBound <= 8_192,
              let header = String(data: data[..<split.lowerBound], encoding: .utf8) else { throw ParseError.invalid }
        let lines = header.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, first[2] == "HTTP/1.1" else { throw ParseError.invalid }
        let headers = try parseHeaders(Array(lines.dropFirst()))
        guard headers["transfer-encoding"] == nil,
              let length = Int(headers["content-length"] ?? "0"), (0...65_536).contains(length) else { throw ParseError.invalid }
        let bytes = Data(data[split.upperBound...])
        guard bytes.count >= length else { return nil }
        guard bytes.count == length, let body = String(data: bytes, encoding: .utf8) else { throw ParseError.invalid }
        return WatchHTTPRequest(method: String(first[0]), path: String(first[1]), headers: headers, body: body.isEmpty ? nil : body)
    }

    private static func parseHeaders(_ lines: [String]) throws -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.invalid }
            let name = String(line[..<colon]).lowercased()
            guard !name.isEmpty, !name.contains(where: \.isWhitespace), headers[name] == nil else { throw ParseError.invalid }
            headers[name] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        return headers
    }

    enum ParseError: Error { case invalid }
}
