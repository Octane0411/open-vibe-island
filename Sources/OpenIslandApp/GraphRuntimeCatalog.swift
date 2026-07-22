import Foundation
import OpenIslandCore

enum GraphRuntimeProviderKind:
    String,
    Codable,
    CaseIterable,
    Identifiable,
    Sendable
{
    case localProcess = "local_process"
    case ollama
    case qwenCode = "qwen_code"
    case geminiCLI = "gemini_cli"
    case openCode = "open_code"
    case openAICompatible = "openai_compatible"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localProcess: "Local Process"
        case .ollama: "Ollama"
        case .qwenCode: "Qwen Code"
        case .geminiCLI: "Gemini CLI"
        case .openCode: "OpenCode"
        case .openAICompatible: "OpenAI-Compatible Endpoint"
        case .custom: "Custom Runtime"
        }
    }
}

enum GraphRuntimeTransport:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case localProcess = "local_process"
    case openAICompatible = "openai_compatible"
}

struct GraphRuntimeModel:
    Identifiable,
    Equatable,
    Codable,
    Sendable
{
    let id: String
    let name: String
    let providerID: GraphRuntimeProviderKind
    let details: String?
}

struct GraphRuntimeAgentProfile:
    Identifiable,
    Equatable,
    Codable,
    Sendable
{
    let id: String
    let name: String
    let providerID: GraphRuntimeProviderKind
    let executable: String?
    let details: String?
}

struct GraphRuntimeProvider:
    Identifiable,
    Equatable,
    Codable,
    Sendable
{
    let id: GraphRuntimeProviderKind
    let transport: GraphRuntimeTransport
    let endpoint: String?
    let adapterKind: String
    let operation: String
    let requiredCapabilities: [String]
    let executableNames: [String]
    let supportsModelDiscovery: Bool
    let supportsAgentProfiles: Bool

    var displayName: String { id.displayName }
}

struct GraphRuntimeCatalogSnapshot:
    Equatable,
    Sendable
{
    var providers: [GraphRuntimeProvider]
    var models: [GraphRuntimeModel]
    var agents: [GraphRuntimeAgentProfile]
    var diagnostics: [String]

    static let empty = GraphRuntimeCatalogSnapshot(
        providers: [],
        models: [],
        agents: [],
        diagnostics: []
    )

    func provider(
        _ id: GraphRuntimeProviderKind
    ) -> GraphRuntimeProvider? {
        providers.first { $0.id == id }
    }

    func models(
        for providerID: GraphRuntimeProviderKind
    ) -> [GraphRuntimeModel] {
        models
            .filter { $0.providerID == providerID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func agents(
        for providerID: GraphRuntimeProviderKind
    ) -> [GraphRuntimeAgentProfile] {
        agents
            .filter { $0.providerID == providerID }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct GraphRuntimeNodeBinding: Equatable, Sendable {
    let specification: GraphImmutableExecutionSpecification
    let executorKind: GraphDefinitionExecutorKind
    let requiredCapabilities: [String]
    let environmentAllowlist: [String]
}

enum GraphRuntimeNodeBindingFactory {
    static func make(
        provider: GraphRuntimeProvider,
        model: String,
        agentProfileID: String,
        catalog: GraphRuntimeCatalogSnapshot
    ) throws -> GraphRuntimeNodeBinding {
        switch provider.transport {
        case .localProcess:
            if provider.id == .localProcess {
                return GraphRuntimeNodeBinding(
                    specification: try GraphLocalProcessSpecification(
                        executable: "/usr/bin/true"
                    ).immutableSpecification(),
                    executorKind: .supervisedLocalProcess,
                    requiredCapabilities: provider.requiredCapabilities,
                    environmentAllowlist: []
                )
            }

            guard let agent = catalog.agents.first(where: {
                $0.id == agentProfileID && $0.providerID == provider.id
            }),
            let executable = agent.executable else {
                return GraphRuntimeNodeBinding(
                    specification: GraphImmutableExecutionSpecification(
                        adapterKind: "generic_agent",
                        operation: "unbound",
                        parameters: [
                            "provider": .string(provider.id.rawValue),
                            "model": .string(model),
                            "agentProfile": .string(agentProfileID),
                        ]
                    ),
                    executorKind: .unboundAgent,
                    requiredCapabilities: provider.requiredCapabilities,
                    environmentAllowlist: []
                )
            }

            let process = GraphLocalProcessSpecification(
                executable: executable,
                arguments: [],
                workingDirectory: ".",
                inheritedEnvironment: .allowlisted,
                stdin: .nullDevice
            )

            return GraphRuntimeNodeBinding(
                specification: try process.immutableSpecification(),
                executorKind: .supervisedLocalProcess,
                requiredCapabilities: provider.requiredCapabilities,
                environmentAllowlist: defaultEnvironmentAllowlist(
                    for: provider.id
                )
            )

        case .openAICompatible:
            var parameters: [String: GraphJSONValue] = [
                "provider": .string(provider.id.rawValue),
                "model": .string(model),
            ]

            if let endpoint = provider.endpoint {
                parameters["endpoint"] = .string(endpoint)
            }

            return GraphRuntimeNodeBinding(
                specification: GraphImmutableExecutionSpecification(
                    adapterKind: provider.adapterKind,
                    operation: provider.operation,
                    parameters: parameters
                ),
                executorKind: .openAICompatible,
                requiredCapabilities: provider.requiredCapabilities,
                environmentAllowlist: []
            )
        }
    }

    private static func defaultEnvironmentAllowlist(
        for provider: GraphRuntimeProviderKind
    ) -> [String] {
        switch provider {
        case .qwenCode:
            [
                "HOME",
                "PATH",
                "LANG",
                "LC_ALL",
                "TERM",
                "OLLAMA_HOST",
                "OPENAI_API_KEY",
                "OPENAI_BASE_URL",
                "GOOGLE_GENERATIVE_AI_API_KEY",
            ]
        case .geminiCLI:
            [
                "HOME",
                "PATH",
                "LANG",
                "LC_ALL",
                "TERM",
                "GEMINI_API_KEY",
                "GOOGLE_API_KEY",
                "GOOGLE_GENERATIVE_AI_API_KEY",
            ]
        case .openCode:
            [
                "HOME",
                "PATH",
                "LANG",
                "LC_ALL",
                "TERM",
                "OPENAI_API_KEY",
                "OPENAI_BASE_URL",
                "GOOGLE_GENERATIVE_AI_API_KEY",
                "ANTHROPIC_API_KEY",
            ]
        case .localProcess, .ollama, .openAICompatible, .custom:
            []
        }
    }
}


protocol GraphRuntimeCatalogDiscovering: Sendable {
    func discover() async -> GraphRuntimeCatalogSnapshot
}

struct GraphRuntimeCatalogDiscovery:
    GraphRuntimeCatalogDiscovering,
    Sendable
{
    var environment: [String: String]
    var isExecutableFile: @Sendable (String) -> Bool
    var session: URLSession

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutableFile: @escaping @Sendable (String) -> Bool = {
            FileManager.default.isExecutableFile(atPath: $0)
        },
        session: URLSession = .shared
    ) {
        self.environment = environment
        self.isExecutableFile = isExecutableFile
        self.session = session
    }

    func discover() async -> GraphRuntimeCatalogSnapshot {
        let providers = Self.builtInProviders
        var models: [GraphRuntimeModel] = []
        var agents: [GraphRuntimeAgentProfile] = []
        var diagnostics: [String] = []

        for provider in providers {
            for executableName in provider.executableNames {
                if let path = resolveExecutable(executableName) {
                    agents.append(
                        GraphRuntimeAgentProfile(
                            id: "\(provider.id.rawValue):\(path)",
                            name: provider.displayName,
                            providerID: provider.id,
                            executable: path,
                            details: "Installed at \(path)"
                        )
                    )
                    break
                }
            }
        }

        do {
            models.append(contentsOf: try await discoverOllamaModels())
        } catch {
            diagnostics.append(
                "Ollama model discovery failed: \(error.localizedDescription)"
            )
        }

        return GraphRuntimeCatalogSnapshot(
            providers: providers,
            models: models,
            agents: agents,
            diagnostics: diagnostics.sorted()
        )
    }

    private func resolveExecutable(_ name: String) -> String? {
        let path = environment["PATH"] ?? ""
        for directory in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(name)
                .path
            if isExecutableFile(candidate) {
                return candidate
            }
        }

        let commonDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(NSHomeDirectory())/.local/bin",
        ]

        for directory in commonDirectories {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(name)
                .path
            if isExecutableFile(candidate) {
                return candidate
            }
        }

        return nil
    }

    private func discoverOllamaModels() async throws
        -> [GraphRuntimeModel]
    {
        let url = URL(string: "http://127.0.0.1:11434/api/tags")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200 ... 299).contains(http.statusCode)
        else {
            throw GraphRuntimeCatalogError.invalidOllamaResponse
        }

        let payload = try JSONDecoder().decode(
            OllamaTagsResponse.self,
            from: data
        )

        return payload.models.map {
            GraphRuntimeModel(
                id: "ollama:\($0.name)",
                name: $0.name,
                providerID: .ollama,
                details: $0.details?.parameterSize
            )
        }
    }

    static let builtInProviders: [GraphRuntimeProvider] = [
        GraphRuntimeProvider(
            id: .localProcess,
            transport: .localProcess,
            endpoint: nil,
            adapterKind: "local_process",
            operation: "execute",
            requiredCapabilities: ["local-process"],
            executableNames: [],
            supportsModelDiscovery: false,
            supportsAgentProfiles: false
        ),
        GraphRuntimeProvider(
            id: .ollama,
            transport: .openAICompatible,
            endpoint: "http://127.0.0.1:11434/v1",
            adapterKind: "openai_compatible",
            operation: "chat_completion",
            requiredCapabilities: ["agent", "model-inference"],
            executableNames: ["ollama"],
            supportsModelDiscovery: true,
            supportsAgentProfiles: false
        ),
        GraphRuntimeProvider(
            id: .qwenCode,
            transport: .localProcess,
            endpoint: nil,
            adapterKind: "local_process",
            operation: "execute",
            requiredCapabilities: [
                "agent",
                "local-process",
                "workspace-read",
                "workspace-write",
            ],
            executableNames: ["qwen"],
            supportsModelDiscovery: false,
            supportsAgentProfiles: true
        ),
        GraphRuntimeProvider(
            id: .geminiCLI,
            transport: .localProcess,
            endpoint: nil,
            adapterKind: "local_process",
            operation: "execute",
            requiredCapabilities: [
                "agent",
                "local-process",
                "workspace-read",
                "workspace-write",
            ],
            executableNames: ["gemini"],
            supportsModelDiscovery: false,
            supportsAgentProfiles: true
        ),
        GraphRuntimeProvider(
            id: .openCode,
            transport: .localProcess,
            endpoint: nil,
            adapterKind: "local_process",
            operation: "execute",
            requiredCapabilities: [
                "agent",
                "local-process",
                "workspace-read",
                "workspace-write",
            ],
            executableNames: ["opencode"],
            supportsModelDiscovery: false,
            supportsAgentProfiles: true
        ),
        GraphRuntimeProvider(
            id: .openAICompatible,
            transport: .openAICompatible,
            endpoint: nil,
            adapterKind: "openai_compatible",
            operation: "chat_completion",
            requiredCapabilities: ["agent", "model-inference"],
            executableNames: [],
            supportsModelDiscovery: true,
            supportsAgentProfiles: false
        ),
        GraphRuntimeProvider(
            id: .custom,
            transport: .localProcess,
            endpoint: nil,
            adapterKind: "generic_agent",
            operation: "unbound",
            requiredCapabilities: ["agent"],
            executableNames: [],
            supportsModelDiscovery: false,
            supportsAgentProfiles: true
        ),
    ]
}

private struct OllamaTagsResponse: Decodable {
    let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    let name: String
    let details: OllamaModelDetails?
}

private struct OllamaModelDetails: Decodable {
    let parameterSize: String?

    enum CodingKeys: String, CodingKey {
        case parameterSize = "parameter_size"
    }
}

enum GraphRuntimeCatalogError: Error, LocalizedError {
    case invalidOllamaResponse

    var errorDescription: String? {
        switch self {
        case .invalidOllamaResponse:
            "Ollama returned an invalid model-list response."
        }
    }
}
