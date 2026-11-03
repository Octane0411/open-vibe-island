import Foundation
import OpenIslandCore

enum GraphWorkspaceBundledFixtures {
    static let compendiumResourceName =
        "dose-regulations-compendium.openisland-graph"
    static let fixtureExecutablePlaceholder =
        "${OPENISLAND_PROCESS_FIXTURE}"
    static let workspacePlaceholder =
        "${OPENISLAND_COMPENDIUM_WORKSPACE}"

    static func loadCompendium() throws -> GraphDefinitionDocument {
        try loadCompendium(
            executableURL: fixtureExecutableURL(),
            workspaceURL: compendiumWorkspaceURL()
        )
    }

    static func loadCompendium(
        executableURL: URL,
        workspaceURL: URL
    ) throws -> GraphDefinitionDocument {
        guard let url = Bundle.module.url(
            forResource: compendiumResourceName,
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let document = try GraphDefinitionDocumentCodec.load(url: url)
        return try materialize(
            document,
            executableURL: executableURL,
            workspaceURL: workspaceURL
        )
    }

    static func materialize(
        _ document: GraphDefinitionDocument,
        executableURL: URL,
        workspaceURL: URL
    ) throws -> GraphDefinitionDocument {
        try FileManager.default.createDirectory(
            at: workspaceURL,
            withIntermediateDirectories: true
        )
        var result = document
        for index in result.nodes.indices {
            var node = result.nodes[index]
            if node.specification.adapterKind
                == GraphLocalProcessSpecification.adapterKind {
                let source = try GraphLocalProcessSpecification(
                    immutableSpecification: node.specification
                )
                let executable = source.executable
                    == fixtureExecutablePlaceholder
                    ? executableURL.path : source.executable
                node.specification = try GraphLocalProcessSpecification(
                    executable: executable,
                    arguments: source.arguments,
                    workingDirectory: source.workingDirectory,
                    environment: source.environment,
                    inheritedEnvironment: source.inheritedEnvironment,
                    stdin: source.stdin,
                    outputArtifacts: source.outputArtifacts,
                    retryableExitCodes: source.retryableExitCodes,
                    logPolicy: source.logPolicy
                ).immutableSpecification()
            }
            if node.workspace.root == workspacePlaceholder {
                node.workspace = GraphExecutionWorkspaceContext(
                    root: workspaceURL.path,
                    writableRelativePaths: node.workspace.writableRelativePaths
                )
            }
            result.nodes[index] = node
        }
        try result.validate()
        return result
    }

    static func fixtureExecutableURL() throws -> URL {
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent("OpenIslandProcessFixtureAgent")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent("OpenIslandProcessFixtureAgent")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }
        let development = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath
        ).appendingPathComponent(
            ".build/debug/OpenIslandProcessFixtureAgent"
        )
        guard FileManager.default.isExecutableFile(
            atPath: development.path
        ) else {
            throw GraphLocalProcessSpecificationError
                .executableUnavailable(development.path)
        }
        return development
    }

    static func compendiumWorkspaceURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent(
                "compendium-process-workspace",
                isDirectory: true
            )
    }

    static func templateWorkspaceURL(graphID: String) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent("graph-template-workspaces", isDirectory: true)
            .appendingPathComponent(graphID, isDirectory: true)
    }
}
