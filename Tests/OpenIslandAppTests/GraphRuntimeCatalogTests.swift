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


}
