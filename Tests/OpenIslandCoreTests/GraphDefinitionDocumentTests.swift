import Foundation
import XCTest
@testable import OpenIslandCore

final class GraphDefinitionDocumentTests: XCTestCase {
    func testRoundTripAndSerializationAreDeterministic() throws {
        let document = try makeDocument()
        let first = try GraphDefinitionDocumentCodec.encode(document)
        let decoded = try GraphDefinitionDocumentCodec.decode(first)
        let second = try GraphDefinitionDocumentCodec.encode(decoded)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(first, second)
    }

    func testRenamePreservesStableNodeIdentity() throws {
        var document = try makeDocument()
        let originalID = try XCTUnwrap(document.nodes.first?.id)
        try GraphDefinitionDocumentEditor.renameNode(
            id: originalID,
            name: "Renamed",
            description: "Updated",
            in: &document,
            modifiedAt: document.metadata.modifiedAt.addingTimeInterval(1),
            modifiedBy: "test"
        )

        XCTAssertEqual(document.nodes.first?.id, originalID)
        XCTAssertEqual(document.nodes.first?.name, "Renamed")
    }

    func testAddAndRemoveNodeAlsoMaintainsEdgesAndLayout() throws {
        var document = try makeDocument()
        let node = testNode(id: "reviewer", name: "Reviewer")
        try GraphDefinitionDocumentEditor.addNode(
            node,
            to: &document,
            position: GraphCanvasPoint(x: 500, y: 0),
            modifiedAt: graphTestTime.addingTimeInterval(1),
            modifiedBy: "test"
        )
        try GraphDefinitionDocumentEditor.addEdge(
            GraphDefinitionEdge(
                sourceNodeID: "researcher",
                targetNodeID: "reviewer"
            ),
            to: &document,
            modifiedAt: graphTestTime.addingTimeInterval(2),
            modifiedBy: "test"
        )
        XCTAssertNotNil(document.layout.position(nodeID: "reviewer"))

        try GraphDefinitionDocumentEditor.removeNode(
            id: "reviewer",
            from: &document,
            modifiedAt: graphTestTime.addingTimeInterval(3),
            modifiedBy: "test"
        )
        XCTAssertFalse(document.nodes.contains { $0.id == "reviewer" })
        XCTAssertFalse(document.edges.contains {
            $0.sourceNodeID == "reviewer" || $0.targetNodeID == "reviewer"
        })
        XCTAssertNil(document.layout.position(nodeID: "reviewer"))
    }

    func testDuplicateSelfUnknownAndCycleEdgesAreRejected() throws {
        var document = try makeDocument()
        let duplicate = document.edges[0]
        XCTAssertThrowsError(
            try GraphDefinitionDocumentEditor.addEdge(
                duplicate,
                to: &document,
                modifiedAt: graphTestTime,
                modifiedBy: "test"
            )
        ) { error in
            XCTAssertEqual(
                error as? GraphDefinitionDocumentError,
                .duplicateEdge(duplicate.id)
            )
        }
        XCTAssertThrowsError(
            try GraphDefinitionDocumentEditor.addEdge(
                GraphDefinitionEdge(
                    sourceNodeID: "architect",
                    targetNodeID: "architect"
                ),
                to: &document,
                modifiedAt: graphTestTime,
                modifiedBy: "test"
            )
        )
        XCTAssertThrowsError(
            try GraphDefinitionDocumentEditor.addEdge(
                GraphDefinitionEdge(
                    sourceNodeID: "missing",
                    targetNodeID: "architect"
                ),
                to: &document,
                modifiedAt: graphTestTime,
                modifiedBy: "test"
            )
        )
        XCTAssertThrowsError(
            try GraphDefinitionDocumentEditor.addEdge(
                GraphDefinitionEdge(
                    sourceNodeID: "researcher",
                    targetNodeID: "architect"
                ),
                to: &document,
                modifiedAt: graphTestTime,
                modifiedBy: "test"
            )
        ) { error in
            XCTAssertEqual(error as? GraphDefinitionDocumentError, .cycle)
        }
    }

    func testLayoutIsIndependentFromExecutionDigest() throws {
        var document = try makeDocument()
        let original = try document.semanticDigest()
        try GraphDefinitionDocumentEditor.setPosition(
            nodeID: "architect",
            position: GraphCanvasPoint(x: 900, y: 450),
            in: &document,
            modifiedAt: graphTestTime.addingTimeInterval(10),
            modifiedBy: "test"
        )

        XCTAssertEqual(try document.semanticDigest(), original)
    }

    func testAutomaticLayoutIsDeterministic() throws {
        var first = try makeDocument()
        var second = try makeDocument()
        try GraphDefinitionDocumentEditor.applyAutomaticLayout(
            to: &first,
            modifiedAt: graphTestTime,
            modifiedBy: "test"
        )
        try GraphDefinitionDocumentEditor.applyAutomaticLayout(
            to: &second,
            modifiedAt: graphTestTime,
            modifiedBy: "test"
        )
        XCTAssertEqual(first.layout, second.layout)
        XCTAssertLessThan(
            try XCTUnwrap(first.layout.position(nodeID: "architect")?.x),
            try XCTUnwrap(first.layout.position(nodeID: "researcher")?.x)
        )
    }

    func testRunRetainsImmutableExecutableDefinitionAfterDocumentEdit()
        async throws
    {
        var document = try makeDocument()
        let immutable = try document.executableDefinition()
        let store = InMemoryGraphExecutionEventStore()
        let mutator = DefaultGraphMutationService(
            eventStore: store,
            readStore: store
        )
        _ = try await mutator.create(
            GraphCreateRequest(
                runID: "immutable-run",
                definition: immutable,
                idempotencyKey: "immutable-create",
                occurredAt: graphTestTime,
                producer: graphTestProducer
            )
        )
        try GraphDefinitionDocumentEditor.renameNode(
            id: "architect",
            name: "Changed Later",
            description: "",
            in: &document,
            modifiedAt: graphTestTime.addingTimeInterval(1),
            modifiedBy: "test"
        )
        let stream = try await store.read(
            runID: "immutable-run",
            afterVersion: 0
        )
        let projection = try GraphExecutionProjector.replay(
            runID: "immutable-run",
            events: stream.events
        ).projection

        XCTAssertEqual(
            projection.executableDefinition?.scheduling.nodes.first {
                $0.id == "architect"
            }?.title,
            "Architect"
        )
    }

    func testUnknownTopLevelFieldIsRetained() throws {
        let data = try GraphDefinitionDocumentCodec.encode(makeDocument())
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        json["futureFeature"] = ["enabled": true]
        let extended = try JSONSerialization.data(
            withJSONObject: json,
            options: [.sortedKeys]
        )
        let decoded = try GraphDefinitionDocumentCodec.decode(extended)
        let encoded = try GraphDefinitionDocumentCodec.encode(decoded)
        let roundTrip = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertNotNil(decoded.extensionFields["futureFeature"])
        XCTAssertNotNil(roundTrip["futureFeature"])
    }

    func testSensitiveEnvironmentValuesAreRejected() throws {
        let process = GraphLocalProcessSpecification(
            executable: "/usr/bin/true",
            environment: ["API_KEY": "must-not-be-persisted"]
        )
        var document = try makeDocument()
        document.nodes[0].specification = try process.immutableSpecification()

        XCTAssertThrowsError(try document.validate()) { error in
            XCTAssertEqual(
                error as? GraphDefinitionDocumentError,
                .embeddedSecret("API_KEY")
            )
        }
    }
}

private func makeDocument() throws -> GraphDefinitionDocument {
    let document = GraphDefinitionDocument(
        graphID: "document-test",
        definitionVersion: "1",
        name: "Document Test",
        description: "Graph document fixture",
        nodes: [
            testNode(id: "researcher", name: "Researcher"),
            testNode(id: "architect", name: "Architect"),
        ],
        edges: [
            GraphDefinitionEdge(
                sourceNodeID: "architect",
                targetNodeID: "researcher"
            ),
        ],
        schedulerPolicy: GraphSchedulerPolicy(
            policyID: "document-test-policy",
            version: "1",
            retryPolicy: GraphRetryPolicy(
                maximumAttempts: 2,
                retryableFailureCategories: ["transient"]
            )
        ),
        layout: GraphLayoutMetadata(
            nodes: [
                GraphNodeLayoutMetadata(
                    nodeID: "architect",
                    position: GraphCanvasPoint(x: 0, y: 0)
                ),
                GraphNodeLayoutMetadata(
                    nodeID: "researcher",
                    position: GraphCanvasPoint(x: 280, y: 0)
                ),
            ]
        ),
        metadata: GraphDefinitionDocumentMetadata(
            createdAt: graphTestTime,
            modifiedAt: graphTestTime,
            createdBy: "test",
            modifiedBy: "test"
        ),
        extensionFields: ["fixture": .bool(true)]
    )
    try document.validate()
    return document
}

private func testNode(
    id: String,
    name: String
) -> GraphDefinitionDocumentNode {
    GraphDefinitionDocumentNode(
        id: id,
        name: name,
        requiredCapabilities: ["compendium"],
        specification: GraphImmutableExecutionSpecification(
            adapterKind: "deterministic",
            operation: "test"
        ),
        timeoutPolicy: GraphExecutionTimeoutPolicy(
            executionSeconds: 30,
            cancellationAcknowledgementSeconds: 5
        )
    )
}
