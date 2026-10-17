import CryptoKit
import Foundation

public struct OpenAICompatibleGraphExecutor:
    GraphExecutorAdapter,
    Sendable
{
    public static let adapterKind = "openai_compatible"

    public let capabilities: GraphExecutorCapabilities

    private let session: URLSession
    private let environment: [String: String]
    private let state: OpenAICompatibleExecutionState

    public init(
        executorID: String = "openisland.openai-compatible",
        capabilityIdentity: String = "openai-compatible-v1",
        capabilities: [String] = ["agent", "model-inference"],
        session: URLSession = .shared,
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) {
        self.capabilities = GraphExecutorCapabilities(
            executorID: executorID,
            capabilityIdentity: capabilityIdentity,
            capabilities: capabilities,
            hostID: "local-http"
        )
        self.session = session
        self.environment = environment
        state = OpenAICompatibleExecutionState()
    }

    public func prepare(
        _ request: GraphExecutorPrepareRequest
    ) async throws -> GraphExecutorPrepareResponse {
        let validation = validate(request.context)

        return GraphExecutorPrepareResponse(
            observation: observation(
                operation: .prepare,
                status: validation == nil ? .accepted : .rejected,
                context: request.context,
                failure: validation
            )
        )
    }

    public func start(
        _ request: GraphExecutorStartRequest
    ) async throws -> GraphExecutorStartResponse {
        if let failure = validate(request.context) {
            return GraphExecutorStartResponse(
                observation: observation(
                    operation: .start,
                    status: .rejected,
                    context: request.context,
                    failure: failure
                )
            )
        }

        let context = request.context
        let key = executionKey(context)

        await state.start(key: key) {
            await performRequest(context)
        }

        return GraphExecutorStartResponse(
            observation: observation(
                operation: .start,
                status: .started,
                context: context
            )
        )
    }

    public func observe(
        _ request: GraphExecutorObserveRequest
    ) async throws -> GraphExecutorObserveResponse {
        let result = await state.result(for: executionKey(request.context))

        return GraphExecutorObserveResponse(
            observation: observation(
                operation: .observe,
                status: result.status,
                context: request.context,
                failure: result.failure
            )
        )
    }

    public func requestCancellation(
        _ request: GraphExecutorCancellationRequest
    ) async throws -> GraphExecutorCancellationResponse {
        await state.cancel(key: executionKey(request.context))

        return GraphExecutorCancellationResponse(
            observation: observation(
                operation: .requestCancellation,
                status: .cancelled,
                context: request.context
            )
        )
    }

    public func collectResult(
        _ request: GraphExecutorCollectResultRequest
    ) async throws -> GraphExecutorCollectResultResponse {
        let result = await state.result(for: executionKey(request.context))

        let artifacts: [GraphExecutorProducedArtifact]
        if result.status == .succeeded, let data = result.data {
            artifacts = [artifact(data: data)]
        } else {
            artifacts = []
        }

        return GraphExecutorCollectResultResponse(
            observation: observation(
                operation: .collectResult,
                status: result.status,
                context: request.context,
                failure: result.failure,
                artifacts: artifacts
            )
        )
    }

    public func cleanup(
        _ request: GraphExecutorCleanupRequest
    ) async throws -> GraphExecutorCleanupResponse {
        await state.remove(key: executionKey(request.context))

        return GraphExecutorCleanupResponse(
            observation: observation(
                operation: .cleanup,
                status: .accepted,
                context: request.context
            )
        )
    }

    public func recover(
        _ request: GraphExecutorRecoverRequest
    ) async throws -> GraphExecutorRecoverResponse {
        let result = await state.result(for: executionKey(request.context))

        return GraphExecutorRecoverResponse(
            observation: observation(
                operation: .recover,
                status: result.status == .unavailable
                    ? .interrupted
                    : result.status,
                context: request.context,
                failure: result.status == .unavailable
                    ? GraphExecutorFailure(
                        category: "http_execution_state_unavailable",
                        retryable: true
                    )
                    : result.failure
            )
        )
    }

    private func validate(
        _ context: GraphExecutorCommandContext
    ) -> GraphExecutorFailure? {
        guard context.specification.adapterKind == Self.adapterKind else {
            return GraphExecutorFailure(
                category: "invalid_adapter_kind",
                retryable: false
            )
        }

        guard context.specification.operation == "chat_completion" else {
            return GraphExecutorFailure(
                category: "unsupported_http_operation",
                retryable: false
            )
        }

        guard stringParameter("endpoint", context: context)
            .flatMap(URL.init(string:)) != nil
        else {
            return GraphExecutorFailure(
                category: "invalid_http_endpoint",
                retryable: false
            )
        }

        guard let model = stringParameter("model", context: context),
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return GraphExecutorFailure(
                category: "missing_model",
                retryable: false
            )
        }

        do {
            _ = try prompt(context)
        } catch {
            return GraphExecutorFailure(
                category: "missing_or_unreadable_prompt",
                retryable: false
            )
        }

        return nil
    }

    private func performRequest(
        _ context: GraphExecutorCommandContext
    ) async -> OpenAICompatibleExecutionResult {
        do {
            guard let endpointString = stringParameter(
                "endpoint",
                context: context
            ), let baseURL = URL(string: endpointString),
              let model = stringParameter("model", context: context)
            else {
                return .failed(
                    category: "invalid_http_configuration",
                    retryable: false
                )
            }

            let url = chatCompletionsURL(baseURL)
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = TimeInterval(
                context.timeoutPolicy.executionSeconds
            )
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Accept"
            )

            if let apiKey = environment["OPENAI_API_KEY"],
               !apiKey.isEmpty {
                request.setValue(
                    "Bearer \(apiKey)",
                    forHTTPHeaderField: "Authorization"
                )
            }

            var messages: [[String: String]] = []

            if let system = stringParameter("system", context: context),
               !system.trimmingCharacters(
                    in: .whitespacesAndNewlines
               ).isEmpty {
                messages.append([
                    "role": "system",
                    "content": system,
                ])
            }

            messages.append([
                "role": "user",
                "content": try prompt(context),
            ])

            request.httpBody = try JSONSerialization.data(
                withJSONObject: [
                    "model": model,
                    "messages": messages,
                    "stream": false,
                ],
                options: [.sortedKeys]
            )

            let (data, response) = try await session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                return .failed(
                    category: "non_http_response",
                    retryable: true
                )
            }

            guard (200 ... 299).contains(http.statusCode) else {
                return .failed(
                    category: "http_status_\(http.statusCode)",
                    retryable: http.statusCode == 408
                        || http.statusCode == 429
                        || (500 ... 599).contains(http.statusCode)
                )
            }

            guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
                return .failed(
                    category: "invalid_chat_completion_response",
                    retryable: false
                )
            }

            return .succeeded(data)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError {
            return .failed(
                category: "url_error_\(error.code.rawValue)",
                retryable: true
            )
        } catch {
            return .failed(
                category: "http_executor_error",
                retryable: false
            )
        }
    }

    private func prompt(
        _ context: GraphExecutorCommandContext
    ) throws -> String {
        var sections: [String] = []

        if let literal = stringParameter("prompt", context: context) {
            let trimmed = literal.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !trimmed.isEmpty {
                sections.append(trimmed)
            }
        }

        for artifact in context.inputArtifacts {
            switch artifact.storage.scheme {
            case "inline":
                sections.append(artifact.storage.opaqueReference)

            case "file":
                let data = try Data(
                    contentsOf: URL(
                        fileURLWithPath:
                            artifact.storage.opaqueReference
                    ),
                    options: .mappedIfSafe
                )
                guard let text = String(data: data, encoding: .utf8) else {
                    throw OpenAICompatibleExecutorError
                        .nonTextInputArtifact(artifact.id)
                }
                sections.append(text)

            default:
                continue
            }
        }

        let result = sections
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        guard !result.isEmpty else {
            throw OpenAICompatibleExecutorError.missingPrompt
        }

        return result
    }

    private func stringParameter(
        _ name: String,
        context: GraphExecutorCommandContext
    ) -> String? {
        guard case let .string(value) =
            context.specification.parameters[name]
        else {
            return nil
        }

        return value
    }

    private func chatCompletionsURL(_ baseURL: URL) -> URL {
        if baseURL.path.hasSuffix("/chat/completions") {
            return baseURL
        }

        return baseURL
            .appendingPathComponent("chat")
            .appendingPathComponent("completions")
    }

    private func executionKey(
        _ context: GraphExecutorCommandContext
    ) -> String {
        [
            context.identity.runID,
            context.identity.nodeID,
            context.identity.attemptID,
            context.identity.claimID,
            String(context.identity.leaseGeneration),
        ].joined(separator: "|")
    }

    private func observation(
        operation: GraphExecutorOperation,
        status: GraphExecutorResponseStatus,
        context: GraphExecutorCommandContext,
        failure: GraphExecutorFailure? = nil,
        artifacts: [GraphExecutorProducedArtifact] = []
    ) -> GraphExecutorObservation {
        let material = [
            executionKey(context),
            operation.rawValue,
            String(context.priorObservationCount),
            status.rawValue,
        ].joined(separator: "|")

        return GraphExecutorObservation(
            id: "http-\(DefaultGraphMutationService.stableID(material))",
            operation: operation,
            identity: context.identity,
            status: status,
            observedAt: context.logicalTime,
            failure: failure,
            artifacts: artifacts
        )
    }

    private func artifact(
        data: Data
    ) -> GraphExecutorProducedArtifact {
        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()

        return GraphExecutorProducedArtifact(
            contentDigest: GraphContentDigest(
                algorithm: "sha256",
                value: digest
            ),
            mediaType: "application/json",
            role: .nodeOutput,
            storage: GraphArtifactStorageLocator(
                scheme: "inline",
                opaqueReference:
                    String(data: data, encoding: .utf8) ?? "{}"
            )
        )
    }
}

private enum OpenAICompatibleExecutorError: Error {
    case missingPrompt
    case nonTextInputArtifact(String)
}

private struct OpenAICompatibleExecutionResult: Sendable {
    let status: GraphExecutorResponseStatus
    let data: Data?
    let failure: GraphExecutorFailure?

    static let running = OpenAICompatibleExecutionResult(
        status: .stillRunning,
        data: nil,
        failure: nil
    )

    static let unavailable = OpenAICompatibleExecutionResult(
        status: .unavailable,
        data: nil,
        failure: nil
    )

    static let cancelled = OpenAICompatibleExecutionResult(
        status: .cancelled,
        data: nil,
        failure: nil
    )

    static func succeeded(
        _ data: Data
    ) -> OpenAICompatibleExecutionResult {
        OpenAICompatibleExecutionResult(
            status: .succeeded,
            data: data,
            failure: nil
        )
    }

    static func failed(
        category: String,
        retryable: Bool
    ) -> OpenAICompatibleExecutionResult {
        OpenAICompatibleExecutionResult(
            status: .failed,
            data: nil,
            failure: GraphExecutorFailure(
                category: category,
                retryable: retryable
            )
        )
    }
}

private actor OpenAICompatibleExecutionState {
    private var results:
        [String: OpenAICompatibleExecutionResult] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]

    func start(
        key: String,
        operation: @escaping @Sendable () async
            -> OpenAICompatibleExecutionResult
    ) {
        guard tasks[key] == nil, results[key] == nil else {
            return
        }

        results[key] = .running

        tasks[key] = Task {
            let result = await operation()
            complete(key: key, result: result)
        }
    }

    func result(
        for key: String
    ) -> OpenAICompatibleExecutionResult {
        results[key] ?? .unavailable
    }

    func cancel(key: String) {
        tasks[key]?.cancel()
        tasks[key] = nil
        results[key] = .cancelled
    }

    func remove(key: String) {
        tasks[key]?.cancel()
        tasks[key] = nil
        results[key] = nil
    }

    private func complete(
        key: String,
        result: OpenAICompatibleExecutionResult
    ) {
        guard results[key]?.status != .cancelled else {
            tasks[key] = nil
            return
        }

        results[key] = result
        tasks[key] = nil
    }
}
