import Foundation

public struct WatchHTTPResponse: Sendable {
    public let status: Int
    public let body: Data
}

public enum WatchHTTPClient {
    public static func request(
        baseURL: URL, key: Data, path: String, method: String = "GET",
        token: String? = nil, body: Data = Data()
    ) async throws -> WatchHTTPResponse {
        let stream = try WatchHTTPStream(baseURL: baseURL, key: key)
        let collector = WatchResponseCollector(stream: stream)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                collector.start(path: path, method: method, token: token, body: body, continuation: continuation)
            }
        } onCancel: { stream.cancel() }
    }
}

private final class WatchResponseCollector: @unchecked Sendable {
    private let stream: WatchHTTPStream
    // All callbacks run on WatchHTTPStream's serial queue.
    private var status = 0
    private var data = Data()
    private var overflow = false

    init(stream: WatchHTTPStream) { self.stream = stream }

    func start(
        path: String, method: String, token: String?, body: Data,
        continuation: CheckedContinuation<WatchHTTPResponse, any Error>
    ) {
        stream.start(path: path, method: method, token: token, body: body, onResponse: { [self] in
            status = $0
        }, onData: { [self] chunk in
            guard data.count + chunk.count <= 262_144 else {
                overflow = true
                stream.cancel()
                return
            }
            data.append(chunk)
        }, onComplete: { [self] error in
            if overflow { continuation.resume(throwing: WatchTransportError.oversizedMessage) }
            else if let error { continuation.resume(throwing: error) }
            else { continuation.resume(returning: WatchHTTPResponse(status: status, body: data)) }
        })
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { [weak stream] in stream?.cancel() }
    }
}
