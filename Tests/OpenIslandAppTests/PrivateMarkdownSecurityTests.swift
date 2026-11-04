import AppKit
import Foundation
import MarkdownUI
import Network
import SwiftUI
import Testing
@testable import OpenIslandApp

@MainActor
struct PrivateMarkdownSecurityTests {
    @Test func renderingAgentImagesDoesNotMakeNetworkRequests() async throws {
        _ = NSApplication.shared
        let probe = try MarkdownImageProbe()
        defer { probe.stop() }
        for _ in 0..<100 where probe.port == nil { try await Task.sleep(for: .milliseconds(10)) }
        let port = try #require(probe.port)
        // A positive control proves this harness actually executes image-loading tasks.
        let control = host(Markdown(markup(port: port, prefix: "control")))
        defer { control.close() }
        for _ in 0..<200 where probe.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(probe.count >= 2)
        let before = probe.count
        let privateView = host(PrivateMarkdown(text: markup(port: port, prefix: "private")))
        defer { privateView.close() }
        try await Task.sleep(for: .milliseconds(500))
        #expect(probe.count == before)
    }

    private func markup(port: UInt16, prefix: String) -> String {
        "![block](http://127.0.0.1:\(port)/\(prefix)-block.png)\n\nText ![inline](http://127.0.0.1:\(port)/\(prefix)-inline.png) text."
    }

    private func host(_ content: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: content)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        return window
    }
}

private final class MarkdownImageProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "open-island.test.markdown")
    private let listener: NWListener
    private var requests = 0
    var count: Int { queue.sync { requests } }
    var port: UInt16? {
        queue.sync { if case .ready = listener.state { listener.port?.rawValue } else { nil } }
    }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            if data?.isEmpty == false { self?.requests += 1 }
            let response = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
            connection.send(content: response, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
