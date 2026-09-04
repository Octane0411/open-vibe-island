import XCTest
import OpenIslandCore
@testable import OpenIslandApp

final class GraphRuntimeCatalogTests: XCTestCase {
    func testBuiltInProvidersExposeExecutableBindings() throws {
        let providers = GraphRuntimeCatalogDiscovery.builtInProviders

        let local = try XCTUnwrap(
            providers.first { $0.id == .localProcess }
        )
        XCTAssertEqual(local.adapterKind, "local_process")
        XCTAssertEqual(local.operation, "execute")
        XCTAssertEqual(local.requiredCapabilities, ["local-process"])

        let ollama = try XCTUnwrap(
            providers.first { $0.id == .ollama }
        )
        XCTAssertEqual(ollama.adapterKind, "openai_compatible")
        XCTAssertEqual(ollama.operation, "chat_completion")
        XCTAssertEqual(ollama.endpoint, "http://127.0.0.1:11434/v1")
        XCTAssertTrue(ollama.supportsModelDiscovery)

        let qwen = try XCTUnwrap(
            providers.first { $0.id == .qwenCode }
        )
        XCTAssertEqual(qwen.adapterKind, "local_process")
        XCTAssertEqual(qwen.operation, "execute")
        XCTAssertTrue(qwen.executableNames.contains("qwen"))
    }

    func testSnapshotFiltersModelsAndAgentsByProvider() {
        let snapshot = GraphRuntimeCatalogSnapshot(
            providers: GraphRuntimeCatalogDiscovery.builtInProviders,
            models: [
                GraphRuntimeModel(
                    id: "ollama:qwen3.5:9b",
                    name: "qwen3.5:9b",
                    providerID: .ollama,
                    details: "9B"
                ),
                GraphRuntimeModel(
                    id: "other",
                    name: "other",
                    providerID: .openAICompatible,
                    details: nil
                ),
            ],
            agents: [
                GraphRuntimeAgentProfile(
                    id: "qwen:/usr/local/bin/qwen",
                    name: "Qwen Code",
                    providerID: .qwenCode,
                    executable: "/usr/local/bin/qwen",
                    details: nil
                ),
            ],
            diagnostics: []
        )

        XCTAssertEqual(
            snapshot.models(for: .ollama).map(\.name),
            ["qwen3.5:9b"]
        )
        XCTAssertEqual(
            snapshot.agents(for: .qwenCode).map(\.name),
            ["Qwen Code"]
        )
        XCTAssertTrue(snapshot.agents(for: .ollama).isEmpty)
    }

    func testDiscoveredCLIProfileBindsToLocalProcessExecutor()
        throws
    {
        let provider = try XCTUnwrap(
            GraphRuntimeCatalogDiscovery.builtInProviders.first {
                $0.id == .qwenCode
            }
        )

        let agent = GraphRuntimeAgentProfile(
            id: "qwen:/opt/homebrew/bin/qwen",
            name: "Qwen Code",
            providerID: .qwenCode,
            executable: "/opt/homebrew/bin/qwen",
            details: nil
        )

        let catalog = GraphRuntimeCatalogSnapshot(
            providers: [provider],
            models: [],
            agents: [agent],
            diagnostics: []
        )

        let binding = try GraphRuntimeNodeBindingFactory.make(
            provider: provider,
            model: "qwen3.5:9b",
            agentProfileID: agent.id,
            catalog: catalog
        )

        XCTAssertEqual(
            binding.specification.adapterKind,
            GraphLocalProcessSpecification.adapterKind
        )
        XCTAssertEqual(
            binding.specification.operation,
            GraphLocalProcessSpecification.operation
        )
        XCTAssertEqual(
            binding.executorKind,
            .supervisedLocalProcess
        )
        XCTAssertTrue(
            binding.requiredCapabilities.contains("agent")
        )

        let process = try GraphLocalProcessSpecification(
            immutableSpecification: binding.specification
        )
        XCTAssertEqual(
            process.executable,
            "/opt/homebrew/bin/qwen"
        )
        XCTAssertEqual(
            process.inheritedEnvironment,
            .allowlisted
        )
        XCTAssertTrue(
            binding.environmentAllowlist.contains("PATH")
        )
    }

    func testMissingCLIProfileRemainsExplicitlyUnbound()
        throws
    {
        let provider = try XCTUnwrap(
            GraphRuntimeCatalogDiscovery.builtInProviders.first {
                $0.id == .geminiCLI
            }
        )

        let binding = try GraphRuntimeNodeBindingFactory.make(
            provider: provider,
            model: "",
            agentProfileID: "",
            catalog: .empty
        )

        XCTAssertEqual(
            binding.specification.adapterKind,
            "generic_agent"
        )
        XCTAssertEqual(
            binding.specification.operation,
            "unbound"
        )
        XCTAssertEqual(
            binding.executorKind,
            .unboundAgent
        )
    }

    func testOllamaBindingProducesOpenAICompatibleSpecification()
        throws
    {
        let provider = try XCTUnwrap(
            GraphRuntimeCatalogDiscovery.builtInProviders.first {
                $0.id == .ollama
            }
        )

        let binding = try GraphRuntimeNodeBindingFactory.make(
            provider: provider,
            model: "qwen3.5:9b",
            agentProfileID: "",
            catalog: .empty
        )

        XCTAssertEqual(
            binding.specification.adapterKind,
            "openai_compatible"
        )
        XCTAssertEqual(
            binding.specification.operation,
            "chat_completion"
        )
        XCTAssertEqual(
            binding.executorKind,
            .openAICompatible
        )
        XCTAssertEqual(
            binding.specification.parameters["model"],
            .string("qwen3.5:9b")
        )
        XCTAssertEqual(
            binding.specification.parameters["endpoint"],
            .string("http://127.0.0.1:11434/v1")
        )
    }

    func testMiniMaxProviderIsCataloguedAsOpenAICompatible()
        throws
    {
        let providers = GraphRuntimeCatalogDiscovery.builtInProviders

        let minimax = try XCTUnwrap(
            providers.first { $0.id == .minimax }
        )

        XCTAssertEqual(minimax.transport, .openAICompatible)
        XCTAssertEqual(minimax.adapterKind, "openai_compatible")
        XCTAssertEqual(minimax.operation, "chat_completion")
        XCTAssertEqual(
            minimax.endpoint,
            "https://api.minimax.io/v1"
        )
        XCTAssertEqual(
            minimax.regionalEndpoints,
            [
                GraphRuntimeRegionalEndpoint(
                    region: "global_en",
                    openAIBaseURL: "https://api.minimax.io/v1",
                    anthropicBaseURL: "https://api.minimax.io/anthropic",
                    docsRoot: "https://platform.minimax.io/docs"
                ),
                GraphRuntimeRegionalEndpoint(
                    region: "cn_zh",
                    openAIBaseURL: "https://api.minimaxi.com/v1",
                    anthropicBaseURL: "https://api.minimaxi.com/anthropic",
                    docsRoot: "https://platform.minimaxi.com/docs"
                ),
            ]
        )
        XCTAssertEqual(
            minimax.requiredCapabilities,
            ["agent", "model-inference"]
        )
        XCTAssertTrue(minimax.executableNames.isEmpty)
        XCTAssertFalse(minimax.supportsModelDiscovery)
        XCTAssertFalse(minimax.supportsAgentProfiles)
        XCTAssertEqual(minimax.displayName, "MiniMax")
    }

    func testMiniMaxCataloguedModelsExposeCurrentMetadata()
        throws
    {
        let models = GraphRuntimeCatalogDiscovery.minimaxModels
        let primary = try XCTUnwrap(
            models.first { $0.name == "MiniMax-M3" }
        )
        let secondary = try XCTUnwrap(
            models.first { $0.name == "MiniMax-M2.7" }
        )

        XCTAssertEqual(
            models.map(\.name).sorted(),
            ["MiniMax-M2.7", "MiniMax-M3"]
        )
        XCTAssertEqual(primary.providerID, .minimax)
        XCTAssertEqual(primary.contextWindow, 1_000_000)
        XCTAssertEqual(
            primary.pricingUSDPerMillionTokens,
            GraphRuntimeTokenPricing(
                input: 0.6,
                output: 2.4,
                cacheRead: 0.12,
                cacheWrite: nil
            )
        )
        XCTAssertEqual(primary.inputModalities, [.text, .image, .video])
        XCTAssertEqual(primary.thinking, [.adaptive, .disabled])

        XCTAssertEqual(secondary.providerID, .minimax)
        XCTAssertEqual(secondary.contextWindow, 204_800)
        XCTAssertEqual(
            secondary.pricingUSDPerMillionTokens,
            GraphRuntimeTokenPricing(
                input: 0.3,
                output: 1.2,
                cacheRead: 0.06,
                cacheWrite: 0.375
            )
        )
        XCTAssertEqual(secondary.inputModalities, [.text])
        XCTAssertEqual(secondary.thinking, [.alwaysOn])
    }

    func testMiniMaxBindingProducesOpenAICompatibleSpecification()
        throws
    {
        let provider = try XCTUnwrap(
            GraphRuntimeCatalogDiscovery.builtInProviders.first {
                $0.id == .minimax
            }
        )

        let binding = try GraphRuntimeNodeBindingFactory.make(
            provider: provider,
            model: "MiniMax-M3",
            agentProfileID: "",
            catalog: .empty
        )

        XCTAssertEqual(
            binding.specification.adapterKind,
            "openai_compatible"
        )
        XCTAssertEqual(
            binding.specification.operation,
            "chat_completion"
        )
        XCTAssertEqual(
            binding.executorKind,
            .openAICompatible
        )
        XCTAssertEqual(
            binding.specification.parameters["model"],
            .string("MiniMax-M3")
        )
        XCTAssertEqual(
            binding.specification.parameters["endpoint"],
            .string("https://api.minimax.io/v1")
        )
    }

    func testDiscoverySnapshotsMiniMaxModels() async {
        let discovery = GraphRuntimeCatalogDiscovery(
            environment: ["PATH": ""],
            isExecutableFile: { _ in false },
            session: .shared
        )

        let snapshot = await discovery.discover()

        let minimaxModels = snapshot.models(for: .minimax)
            .map(\.name)
            .sorted()
        XCTAssertEqual(
            minimaxModels,
            ["MiniMax-M2.7", "MiniMax-M3"]
        )
        XCTAssertNotNil(
            snapshot.provider(.minimax)
        )
    }
}
