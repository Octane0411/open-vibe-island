import Foundation
import XCTest
@testable import OpenIslandApp
@testable import OpenIslandCore

@MainActor
final class GraphWorkspaceTemplateTests: XCTestCase {
    func testEveryBuiltInTemplateCreatesAnEditableDocumentWithoutGraphJSON()
        throws
    {
        let root = try temporaryDirectory()
        let executable = try GraphWorkspaceBundledFixtures.fixtureExecutableURL()

        for template in GraphWorkspaceTemplate.allCases {
            let request = GraphNewDocumentRequest(
                template: template,
                name: template.name,
                graphID: "template-\(template.rawValue)",
                definitionVersion: "1",
                workspaceDirectory: root.path
            )
            let document = try GraphWorkspaceTemplateFactory.make(
                request: request,
                executableURL: executable,
                workspaceURL: root,
                now: Date(timeIntervalSince1970: 1),
                author: "test"
            )

            XCTAssertEqual(document.name, template.name)
            XCTAssertEqual(document.graphID, "template-\(template.rawValue)")
            if template == .blank {
                XCTAssertTrue(document.nodes.isEmpty)
            } else {
                XCTAssertFalse(document.nodes.isEmpty)
                XCTAssertFalse(document.graphOutputs.isEmpty)
                XCTAssertNoThrow(try document.validate())
            }

            let encoded = try GraphDefinitionDocumentCodec.encode(document)
            XCTAssertEqual(
                try GraphDefinitionDocumentCodec.decode(encoded),
                document
            )
        }
    }

    func testTemplateTopologyMatchesDocumentedPatterns() throws {
        let root = try temporaryDirectory()
        let executable = try GraphWorkspaceBundledFixtures.fixtureExecutableURL()
        var documents: [GraphWorkspaceTemplate: GraphDefinitionDocument] = [:]
        for template in GraphWorkspaceTemplate.allCases where template != .blank {
            documents[template] = try GraphWorkspaceTemplateFactory.make(
                request: GraphNewDocumentRequest(
                    template: template,
                    name: template.name,
                    graphID: template.rawValue,
                    definitionVersion: "1"
                ),
                executableURL: executable,
                workspaceURL: root
            )
        }

        XCTAssertEqual(documents[.linearPipeline]?.nodes.count, 3)
        XCTAssertEqual(documents[.fanOutFanIn]?.edges.count, 4)
        XCTAssertEqual(documents[.reviewLoop]?.nodes.count, 5)
        XCTAssertEqual(
            documents[.compendiumFill]?.topologicalNodeIDs(),
            ["architect", "researcher", "graph", "reviewer"]
        )
        XCTAssertEqual(
            documents[.localProcessExample]?.topologicalNodeIDs(),
            ["generate", "transform", "verify"]
        )
    }

    func testNewGraphSheetAndWorkspaceSourceExposeTemplatesAndGuidance()
        throws
    {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent(
                "Sources/OpenIslandApp/Views/GraphWorkspaceView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("GraphWorkspaceTemplate.allCases"))
        XCTAssertTrue(source.contains("Create New Graph"))
        XCTAssertTrue(source.contains("Open Existing Graph"))
        XCTAssertTrue(source.contains("Open Recent Graph"))
        XCTAssertTrue(source.contains("Open Example Graph"))
        XCTAssertTrue(source.contains("Add your first node"))
        XCTAssertTrue(source.contains("Auto Layout"))
        XCTAssertTrue(source.contains("Reset Graph Zoom"))
        XCTAssertTrue(source.contains("Binding Source"))
        XCTAssertTrue(source.contains("Connect Upstream Output"))
        XCTAssertTrue(source.contains("Literal Value"))
        XCTAssertTrue(source.contains("File Reference"))
        XCTAssertTrue(source.contains("Secret Reference"))
        XCTAssertTrue(source.contains("Backoff Multiplier"))
        XCTAssertTrue(source.contains("selectedNodeValidationSection"))
    }

    func testLocalTemplatesCanBeEditedSavedAndRun() async throws {
        let root = try temporaryDirectory()
        let defaults = try XCTUnwrap(
            UserDefaults(suiteName: "TemplateRun-\(UUID().uuidString)")
        )
        let service = try GraphWorkspaceService.inMemory(
            rootURL: root.appendingPathComponent("runtime", isDirectory: true)
        )
        let viewModel = GraphWorkspaceViewModel(
            service: service,
            defaults: defaults
        )

        for template in [
            GraphWorkspaceTemplate.localProcessExample,
            .compendiumFill,
        ] {
            let graphID = "runnable-\(template.rawValue)"
            viewModel.newDocument(request: GraphNewDocumentRequest(
                template: template,
                name: template.name,
                graphID: graphID,
                definitionVersion: "1",
                workspaceDirectory: root.path
            ))
            let selected = try XCTUnwrap(viewModel.selectedNodeID)
            viewModel.updateSelectedNodeIdentity(
                name: "Edited \(viewModel.selectedNode?.name ?? selected)",
                description: "Template remains an ordinary editable document",
                tags: ["edited-template"]
            )
            let documentURL = root.appendingPathComponent("\(graphID).json")
            await viewModel.saveDocument(url: documentURL)
            XCTAssertTrue(FileManager.default.fileExists(atPath: documentURL.path))
            await viewModel.prepareCreateRun()
            await viewModel.confirmCreateRun()
            await viewModel.startRun()
            viewModel.run()
            await viewModel.waitForLocalOrchestration()
            XCTAssertEqual(
                viewModel.inspection?.summary.persistedState,
                .completed,
                "template=\(template.name) last=\(String(describing: viewModel.lastCommandResult))"
            )
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("artifacts", isDirectory: true),
            withIntermediateDirectories: true
        )
        return url
    }
}
