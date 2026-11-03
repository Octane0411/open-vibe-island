import Foundation
import XCTest
import OpenIslandCore
@testable import OpenIslandApp

final class MiniMaxGraphRequestTests: XCTestCase {
    func testMiniMaxChoicesAreAvailableBeforeDiscovery() {
        XCTAssertEqual(
            GraphRuntimeCatalogSnapshot.empty.models(for: .minimax).map(\.name),
            ["MiniMax-M3.1-Flash", "MiniMax-M3"]
        )
    }

    func testMiniMaxBindingsSerializeDefaultsAndSavedModelsInBothRegions()
        async throws
    {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MiniMaxRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let original = try XCTUnwrap(
            GraphRuntimeCatalogDiscovery.builtInProviders.first { $0.id == .minimax }
        )
        for endpoint in original.regionalEndpoints {
            let provider = GraphRuntimeProvider(
                id: original.id,
                transport: original.transport,
                endpoint: endpoint.openAIBaseURL,
                adapterKind: original.adapterKind,
                operation: original.operation,
                requiredCapabilities: original.requiredCapabilities,
                executableNames: [],
                supportsModelDiscovery: false,
                supportsAgentProfiles: false
            )
            for selectedModel in ["", "MiniMax-M3.1-Flash", "MiniMax-M3", "MiniMax-M2.7", "saved-custom-model"] {
                let binding = try GraphRuntimeNodeBindingFactory.make(
                    provider: provider,
                    model: selectedModel,
                    agentProfileID: "",
                    catalog: .empty
                )
                let expectedModel = selectedModel.isEmpty ? "MiniMax-M3.1-Flash" : selectedModel
                XCTAssertEqual(binding.specification.parameters["model"], .string(expectedModel))
                var parameters = binding.specification.parameters
                parameters["system"] = .string("Keep the supplied text.")
                parameters["prompt"] = .string("A saved graph prompt.")
                let specification = GraphImmutableExecutionSpecification(
                    adapterKind: binding.specification.adapterKind,
                    operation: binding.specification.operation,
                    parameters: parameters
                )
                // Exercise the saved graph round trip before the real HTTP boundary.
                let saved = try JSONDecoder().decode(
                    GraphImmutableExecutionSpecification.self,
                    from: JSONEncoder().encode(specification)
                )
                XCTAssertEqual(saved, specification)
                let context = GraphExecutorCommandContext(
                    identity: GraphExecutorInteractionIdentity(
                        runID: UUID().uuidString,
                        nodeID: "text",
                        attemptID: "attempt",
                        attemptOrdinal: 1,
                        claimID: "claim",
                        leaseGeneration: 1,
                        executorID: "openisland.openai-compatible"
                    ),
                    capabilityRequirement: binding.requiredCapabilities,
                    specification: saved,
                    workspace: GraphExecutionWorkspaceContext(),
                    environmentAllowlist: [],
                    inputArtifacts: [],
                    cancellation: nil,
                    timeoutPolicy: GraphExecutionTimeoutPolicy(
                        executionSeconds: 5,
                        cancellationAcknowledgementSeconds: 1
                    ),
                    correlation: GraphExecutorCorrelationMetadata(correlationID: "test"),
                    priorObservationCount: 0,
                    logicalTime: Date(timeIntervalSince1970: 0)
                )
                let executor = OpenAICompatibleGraphExecutor(
                    session: session,
                    environment: [:]
                )
                let prepared = try await executor.prepare(GraphExecutorPrepareRequest(context: context))
                XCTAssertEqual(prepared.observation.status, .accepted)
                let started = try await executor.start(GraphExecutorStartRequest(context: context))
                XCTAssertEqual(started.observation.status, .started)

                var status = GraphExecutorResponseStatus.stillRunning
                for _ in 0..<200 {
                    status = try await executor.observe(
                        GraphExecutorObserveRequest(context: context)
                    ).observation.status
                    if status != .stillRunning { break }
                    try await Task.sleep(for: .milliseconds(10))
                }
                XCTAssertEqual(status, .succeeded)
                let request = try XCTUnwrap(MiniMaxRequestProtocol.requests.take())
                XCTAssertEqual(request.url?.absoluteString, endpoint.openAIBaseURL + "/chat/completions")
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let body = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
                )
                XCTAssertEqual(body["model"] as? String, expectedModel)
                XCTAssertEqual(body["stream"] as? Bool, false)
                XCTAssertEqual(body["messages"] as? [[String: String]], [
                    ["role": "system", "content": "Keep the supplied text."],
                    ["role": "user", "content": "A saved graph prompt."],
                ])
                // The executor leaves thinking and effort to the API defaults.
                XCTAssertEqual(Set(body.keys), Set(["model", "messages", "stream"]))
                _ = try await executor.cleanup(GraphExecutorCleanupRequest(context: context))
            }
        }
    }

    func testNonMiniMaxBindingsKeepExplicitAndEmptyModelIDs() throws {
        let provider = try XCTUnwrap(
            GraphRuntimeCatalogDiscovery.builtInProviders.first { $0.id == .openAICompatible }
        )
        for model in ["", "custom-model"] {
            let binding = try GraphRuntimeNodeBindingFactory.make(
                provider: provider,
                model: model,
                agentProfileID: "",
                catalog: .empty
            )
            XCTAssertEqual(binding.specification.parameters["model"], .string(model))
        }
    }
}

private final class MiniMaxCapturedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
    }

    func take() -> URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return requests.isEmpty ? nil : requests.removeFirst()
    }
}

private final class MiniMaxRequestProtocol: URLProtocol, @unchecked Sendable {
    static let requests = MiniMaxCapturedRequests()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = body
        }
        Self.requests.append(captured)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"choices\":[]}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
