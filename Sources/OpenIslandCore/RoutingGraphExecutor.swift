import Foundation

public struct RoutingGraphExecutor: GraphExecutorAdapter, Sendable {
    public let capabilities: GraphExecutorCapabilities
    private let adapters: [String: any GraphExecutorAdapter]

    public init(adapters: [String: any GraphExecutorAdapter]) {
        self.adapters = adapters
        capabilities = GraphExecutorCapabilities(
            executorID: "openisland.workspace-router",
            capabilityIdentity: "workspace-router-v1",
            capabilities: Array(Set(adapters.values.flatMap {
                $0.capabilities.capabilities
            })),
            hostID: "local"
        )
    }

    public func prepare(_ request: GraphExecutorPrepareRequest) async throws
        -> GraphExecutorPrepareResponse
    {
        try await adapter(request.context).prepare(request)
    }

    public func start(_ request: GraphExecutorStartRequest) async throws
        -> GraphExecutorStartResponse
    {
        try await adapter(request.context).start(request)
    }

    public func observe(_ request: GraphExecutorObserveRequest) async throws
        -> GraphExecutorObserveResponse
    {
        try await adapter(request.context).observe(request)
    }

    public func requestCancellation(
        _ request: GraphExecutorCancellationRequest
    ) async throws -> GraphExecutorCancellationResponse {
        try await adapter(request.context).requestCancellation(request)
    }

    public func collectResult(
        _ request: GraphExecutorCollectResultRequest
    ) async throws -> GraphExecutorCollectResultResponse {
        try await adapter(request.context).collectResult(request)
    }

    public func cleanup(_ request: GraphExecutorCleanupRequest) async throws
        -> GraphExecutorCleanupResponse
    {
        try await adapter(request.context).cleanup(request)
    }

    public func recover(_ request: GraphExecutorRecoverRequest) async throws
        -> GraphExecutorRecoverResponse
    {
        try await adapter(request.context).recover(request)
    }

    private func adapter(
        _ context: GraphExecutorCommandContext
    ) throws -> any GraphExecutorAdapter {
        guard let adapter = adapters[context.specification.adapterKind] else {
            throw GraphExecutorAdapterError.unsupportedAdapter(
                context.specification.adapterKind
            )
        }
        return adapter
    }
}

public struct RoutingGraphExecutionConfirmationPolicy:
    GraphExecutionConfirmationPolicy,
    Sendable
{
    private let supportedAdapterKinds: Set<String>

    public init(supportedAdapterKinds: Set<String>) {
        self.supportedAdapterKinds = supportedAdapterKinds
    }

    public func permits(
        operation: GraphExecutorOperation,
        context: GraphExecutorCommandContext
    ) -> Bool {
        supportedAdapterKinds.contains(context.specification.adapterKind)
    }
}
