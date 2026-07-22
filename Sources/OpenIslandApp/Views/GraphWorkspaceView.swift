import AppKit
import OpenIslandCore
import SwiftUI

struct GraphWorkspaceWindowContent: View {
    var model: AppModel
    @State private var viewModel: GraphWorkspaceViewModel

    init(model: AppModel, service: any GraphWorkspaceServicing) {
        self.model = model
        _viewModel = State(
            initialValue: GraphWorkspaceViewModel(service: service)
        )
    }

    var body: some View {
        GraphWorkspaceView(viewModel: viewModel)
            .onAppear {
                model.newGraphDefinitionAction = { [weak viewModel] in
                    viewModel?.newDocument()
                }
                model.openGraphDefinitionAction = { [weak viewModel] in
                    guard let viewModel else { return }
                    GraphWorkspaceFilePanels.openDefinition(viewModel)
                }
                viewModel.start()
            }
            .onDisappear { viewModel.stop() }
    }
}

struct GraphWorkspaceView: View {
    @Bindable var viewModel: GraphWorkspaceViewModel
    @State private var canvasZoom = 1.0

    var body: some View {
        VStack(spacing: 0) {
            workspaceToolbar
            Divider()
            NavigationSplitView {
                workspaceSidebar
                    .navigationSplitViewColumnWidth(
                        min: 190,
                        ideal: 220,
                        max: 280
                    )
            } content: {
                workspaceContent
                    .navigationSplitViewColumnWidth(
                        min: 560,
                        ideal: 760
                    )
            } detail: {
                workspaceInspector
                    .navigationSplitViewColumnWidth(
                        min: 260,
                        ideal: 310,
                        max: 380
                    )
            }
            if viewModel.isShowingLogs {
                Divider()
                GraphLogViewer(viewModel: viewModel)
                    .frame(minHeight: 170, idealHeight: 220, maxHeight: 300)
            }
            statusBar
        }
        .frame(minWidth: 1_000, idealWidth: 1_240, minHeight: 680, idealHeight: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Graph Workspace")
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 10) {
            Picker("Workspace mode", selection: $viewModel.mode) {
                ForEach(GraphWorkspaceMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 270)

            Divider().frame(height: 20)

            Text(viewModel.document?.name ?? "Graph Workspace")
                .font(.headline)
                .lineLimit(1)

            Spacer()

            switch viewModel.mode {
            case .definition:
                definitionToolbar
            case .run:
                runToolbar
            case .history:
                historyToolbar
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    private var definitionToolbar: some View {
        HStack(spacing: 6) {
            iconButton("doc.badge.plus", help: "New Graph") {
                viewModel.newDocument()
            }
            iconButton("folder", help: "Open Graph Definition") {
                GraphWorkspaceFilePanels.openDefinition(viewModel)
            }
            iconButton("square.and.arrow.down", help: "Save Graph Definition") {
                GraphWorkspaceFilePanels.saveDefinition(viewModel)
            }
            iconButton("checkmark.seal", help: "Validate Graph") {
                viewModel.validateDocument()
            }
            iconButton("plus", help: "Add Node") { viewModel.addNode() }
            iconButton("arrow.triangle.branch", help: "Connect Selected Nodes") {
                viewModel.connectSelectedNodes()
            }
            .disabled(viewModel.selectedNodeIDs.count != 2)
            iconButton("wand.and.stars", help: "Automatic Layout") {
                viewModel.automaticLayout()
            }
            iconButton("trash", help: "Delete Selection", role: .destructive) {
                viewModel.deleteSelection()
            }
            .disabled(viewModel.selectedNodeIDs.isEmpty)
            Button("Create Run") { Task { await viewModel.createRun() } }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.decision(.createRun).isEnabled)
        }
    }

    private var runToolbar: some View {
        HStack(spacing: 6) {
            commandButton("play", "Start", .start) {
                await viewModel.startRun()
            }
            commandButton("forward.frame", "Step", .step) {
                await viewModel.step()
            }
            Button {
                viewModel.run()
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.decision(.run).isEnabled)
            iconButton("pause.fill", help: "Pause Local Orchestration") {
                viewModel.pauseOrchestration()
            }
            .disabled(!viewModel.decision(.pauseLocal).isEnabled)
            Menu {
                Button("Cancel Run", role: .destructive) {
                    Task { await viewModel.cancelRun() }
                }
                .disabled(!viewModel.decision(.cancelRun).isEnabled)
                Button("Cancel Selected Node", role: .destructive) {
                    Task { await viewModel.cancelSelectedNode() }
                }
                .disabled(!viewModel.decision(.cancelNode).isEnabled)
                Button("Retry Selected Node") {
                    Task { await viewModel.retrySelectedNode() }
                }
                .disabled(!viewModel.decision(.retryNode).isEnabled)
            } label: {
                Label("Run Actions", systemImage: "ellipsis.circle")
            }
            iconButton("text.alignleft", help: "Open Logs") {
                Task { await viewModel.openLogs() }
            }
            .disabled(!viewModel.decision(.openLogs).isEnabled)
            iconButton("clock.arrow.circlepath", help: "Inspect History") {
                Task { await viewModel.inspectHistory() }
            }
            .disabled(!viewModel.decision(.inspectHistory).isEnabled)
            iconButton("square.and.arrow.up", help: "Export Run") {
                GraphWorkspaceFilePanels.exportRun(viewModel)
            }
            .disabled(!viewModel.decision(.export).isEnabled)
        }
    }

    private var historyToolbar: some View {
        HStack(spacing: 8) {
            Text("Replay boundary: head")
                .font(.caption)
                .foregroundStyle(.secondary)
            iconButton("arrow.clockwise", help: "Refresh History") {
                Task { await viewModel.refreshRunAndHistory() }
            }
            iconButton("square.and.arrow.up", help: "Export Run") {
                GraphWorkspaceFilePanels.exportRun(viewModel)
            }
            .disabled(!viewModel.decision(.export).isEnabled)
        }
    }

    private var workspaceSidebar: some View {
        List {
            Section("Workspace") {
                ForEach(GraphWorkspaceMode.allCases) { mode in
                    Button {
                        viewModel.mode = mode
                    } label: {
                        Label(mode.rawValue, systemImage: modeIcon(mode))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(mode.rawValue) mode")
                }
            }
            Section("Durable Runs") {
                if viewModel.runs.isEmpty {
                    ContentUnavailableView(
                        "No Runs",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                } else {
                    ForEach(viewModel.runs) { run in
                        Button {
                            Task { await viewModel.openRun(run.runID) }
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.graphID)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                HStack {
                                    GraphStateBadge(state: run.reconciledState)
                                    Text("v\(run.streamVersion)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            "Run \(run.graphID), \(run.reconciledState.rawValue)"
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch viewModel.mode {
        case .definition, .run:
            GraphCanvasView(
                viewModel: viewModel,
                zoom: $canvasZoom,
                isEditable: viewModel.mode == .definition
            )
        case .history:
            GraphHistoryView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var workspaceInspector: some View {
        switch viewModel.mode {
        case .definition:
            GraphDefinitionInspector(viewModel: viewModel)
        case .run:
            GraphRunInspector(viewModel: viewModel)
        case .history:
            GraphHistoryInspector(viewModel: viewModel)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if viewModel.isLoading || viewModel.isOrchestrating {
                ProgressView().controlSize(.small)
            }
            Text(
                viewModel.errorMessage
                    ?? viewModel.lastCommandResult?.reasonCode
                    ?? "Ready"
            )
            .lineLimit(1)
            .foregroundStyle(
                viewModel.errorMessage == nil
                    ? Color.secondary : Color.red
            )
            Spacer()
            if let inspection = viewModel.inspection {
                Text("stream \(inspection.summary.streamVersion)")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func iconButton(
        _ systemName: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
        .frame(width: 28, height: 28)
    }

    private func commandButton(
        _ systemName: String,
        _ title: String,
        _ command: GraphWorkspaceCommand,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: systemName)
        }
        .disabled(!viewModel.decision(command).isEnabled)
        .help(viewModel.decision(command).reasonCode)
    }

    private func modeIcon(_ mode: GraphWorkspaceMode) -> String {
        switch mode {
        case .definition: "square.and.pencil"
        case .run: "play.rectangle"
        case .history: "clock.arrow.circlepath"
        }
    }
}

private struct GraphCanvasView: View {
    @Bindable var viewModel: GraphWorkspaceViewModel
    @Binding var zoom: Double
    let isEditable: Bool
    @State private var dragOrigins: [String: GraphCanvasPoint] = [:]

    private let canvasSize = CGSize(width: 1_800, height: 1_200)
    private let origin = CGPoint(x: 180, y: 180)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    zoom = 0.75
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fit Graph to View")
                .accessibilityLabel("Fit Graph to View")
                Slider(value: $zoom, in: 0.4...1.6, step: 0.05)
                    .frame(width: 140)
                    .accessibilityLabel("Graph zoom")
                Text("\(Int(zoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 38, alignment: .trailing)
                Spacer()
                if viewModel.selectedNodeIDs.count > 1 {
                    Text("\(viewModel.selectedNodeIDs.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color(nsColor: .controlBackgroundColor))

            if let document = viewModel.document, !document.nodes.isEmpty {
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        GraphEdgeCanvas(
                            document: document,
                            origin: origin,
                            nodeSize: GraphNodeView.nodeSize
                        )
                        ForEach(document.nodes) { node in
                            let position = document.layout.position(nodeID: node.id)
                                ?? GraphCanvasPoint(x: 0, y: 0)
                            GraphNodeView(
                                node: node,
                                state: viewModel.inspection?.nodes.first {
                                    $0.id == node.id
                                }?.reconciledState,
                                attemptOrdinal: viewModel.inspection?.attempts
                                    .filter { $0.nodeID == node.id }
                                    .map(\.ordinal).max(),
                                selected: viewModel.selectedNodeIDs.contains(node.id),
                                isEditable: isEditable,
                                onSelect: { extending in
                                    viewModel.selectNode(node.id, extending: extending)
                                },
                                onDelete: { viewModel.deleteSelection() }
                            )
                            .position(
                                x: origin.x + position.x
                                    + GraphNodeView.nodeSize.width / 2,
                                y: origin.y + position.y
                                    + GraphNodeView.nodeSize.height / 2
                            )
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        guard isEditable else { return }
                                        let start = dragOrigins[node.id] ?? position
                                        dragOrigins[node.id] = start
                                        viewModel.moveNode(
                                            node.id,
                                            to: GraphCanvasPoint(
                                                x: start.x + value.translation.width / zoom,
                                                y: start.y + value.translation.height / zoom
                                            )
                                        )
                                    }
                                    .onEnded { _ in
                                        dragOrigins.removeValue(forKey: node.id)
                                    }
                            )
                        }
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(
                        width: canvasSize.width * zoom,
                        height: canvasSize.height * zoom,
                        alignment: .topLeading
                    )
                }
                .background(Color(nsColor: .textBackgroundColor))
                .focusable()
                .onDeleteCommand {
                    if isEditable { viewModel.deleteSelection() }
                }
            } else {
                ContentUnavailableView {
                    Label(
                        "Empty Graph",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                } actions: {
                    if isEditable {
                        Button("Add Node") { viewModel.addNode() }
                    }
                }
            }
        }
        .accessibilityLabel("Graph canvas")
    }
}

private struct GraphEdgeCanvas: View {
    let document: GraphDefinitionDocument
    let origin: CGPoint
    let nodeSize: CGSize

    var body: some View {
        Canvas { context, _ in
            for edge in document.edges {
                guard let source = document.layout.position(
                    nodeID: edge.sourceNodeID
                ), let target = document.layout.position(
                    nodeID: edge.targetNodeID
                ) else { continue }
                let start = CGPoint(
                    x: origin.x + source.x + nodeSize.width,
                    y: origin.y + source.y + nodeSize.height / 2
                )
                let end = CGPoint(
                    x: origin.x + target.x,
                    y: origin.y + target.y + nodeSize.height / 2
                )
                var path = Path()
                path.move(to: start)
                let middleX = (start.x + end.x) / 2
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: middleX, y: start.y),
                    control2: CGPoint(x: middleX, y: end.y)
                )
                context.stroke(
                    path,
                    with: .color(.secondary.opacity(0.65)),
                    lineWidth: 1.5
                )
                var arrow = Path()
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - 9, y: end.y - 5))
                arrow.addLine(to: CGPoint(x: end.x - 9, y: end.y + 5))
                arrow.closeSubpath()
                context.fill(arrow, with: .color(.secondary.opacity(0.8)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct GraphNodeView: View {
    static let nodeSize = CGSize(width: 210, height: 94)

    let node: GraphDefinitionDocumentNode
    let state: ReconciledExecutionState?
    let attemptOrdinal: Int?
    let selected: Bool
    let isEditable: Bool
    let onSelect: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            nodeHeader
            Text(node.id)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            portRow
        }
        .padding(10)
        .frame(width: Self.nodeSize.width, height: Self.nodeSize.height)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: selected ? 2 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { onSelect(false) }
        .contextMenu {
            Button(selected ? "Remove from Selection" : "Add to Selection") {
                onSelect(true)
            }
            if isEditable {
                Button("Delete Node", role: .destructive) { onDelete() }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Node \(node.name), ID \(node.id), state \(state?.rawValue ?? "definition")"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var capabilitySummary: String {
        node.requiredCapabilities.joined(separator: ", ")
    }

    private var nodeHeader: some View {
        HStack(alignment: .top) {
            Text(node.name)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 6)
            if let state { GraphStateBadge(state: state) }
        }
    }

    private var portRow: some View {
        HStack {
            Circle()
                .fill(Color.secondary)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Dependency input port")
            Text(capabilitySummary)
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
            Spacer()
            if let attemptOrdinal {
                Text("attempt \(attemptOrdinal)")
                    .font(.caption2.monospacedDigit())
            }
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .accessibilityLabel("Dependency output port")
        }
    }
}

struct GraphStateBadge: View {
    let state: ReconciledExecutionState

    var body: some View {
        Text(state.rawValue)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .accessibilityLabel("State \(state.rawValue)")
    }

    private var color: Color {
        switch state {
        case .completed: .green
        case .running: .blue
        case .failed, .orphaned, .interrupted: .red
        case .blocked, .cancelled: .orange
        case .pending, .ready: .secondary
        }
    }
}

private struct GraphDefinitionInspector: View {
    @Bindable var viewModel: GraphWorkspaceViewModel

    var body: some View {
        Form {
            Section("Definition") {
                LabeledContent("Graph ID", value: viewModel.document?.graphID ?? "")
                LabeledContent("Version", value: viewModel.document?.definitionVersion ?? "")
                LabeledContent("Nodes", value: "\(viewModel.document?.nodes.count ?? 0)")
                LabeledContent("Edges", value: "\(viewModel.document?.edges.count ?? 0)")
            }
            if let node = selectedNode {
                Section("Selected Node") {
                    LabeledContent("Stable ID", value: node.id)
                    TextField(
                        "Name",
                        text: Binding(
                            get: { selectedNode?.name ?? "" },
                            set: { viewModel.updateSelectedNode(
                                name: $0,
                                description: selectedNode?.description ?? ""
                            ) }
                        )
                    )
                    TextField(
                        "Description",
                        text: Binding(
                            get: { selectedNode?.description ?? "" },
                            set: { viewModel.updateSelectedNode(
                                name: selectedNode?.name ?? "",
                                description: $0
                            ) }
                        ),
                        axis: .vertical
                    )
                    TextField(
                        "Capabilities",
                        text: Binding(
                            get: {
                                selectedNode?.requiredCapabilities
                                    .joined(separator: ", ") ?? ""
                            },
                            set: {
                                viewModel.updateSelectedNodeExecution(
                                    capabilities: $0.split(separator: ",")
                                        .map { $0.trimmingCharacters(in: .whitespaces) }
                                        .filter { !$0.isEmpty },
                                    executionSeconds: selectedNode?
                                        .timeoutPolicy.executionSeconds ?? 300
                                )
                            }
                        )
                    )
                    Stepper(
                        "Timeout: \(node.timeoutPolicy.executionSeconds)s",
                        value: Binding(
                            get: { Int(selectedNode?.timeoutPolicy.executionSeconds ?? 300) },
                            set: {
                                viewModel.updateSelectedNodeExecution(
                                    capabilities: selectedNode?.requiredCapabilities ?? [],
                                    executionSeconds: UInt64(max(1, $0))
                                )
                            }
                        ),
                        in: 1...86_400
                    )
                }
                Section("Execution Specification") {
                    LabeledContent("Adapter", value: node.specification.adapterKind)
                    LabeledContent("Operation", value: node.specification.operation)
                    LabeledContent(
                        "Workspace",
                        value: node.workspace.root ?? "Not assigned"
                    )
                }
                Section("Dependencies") {
                    let incoming = viewModel.document?.edges.filter {
                        $0.targetNodeID == node.id
                    } ?? []
                    if incoming.isEmpty {
                        Text("No dependencies").foregroundStyle(.secondary)
                    }
                    ForEach(incoming) { edge in
                        HStack {
                            Text(edge.sourceNodeID)
                            Spacer()
                            Button {
                                viewModel.removeEdge(edge.id)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove dependency")
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Node Selected",
                    systemImage: "cursorarrow.click"
                )
            }
        }
        .formStyle(.grouped)
    }

    private var selectedNode: GraphDefinitionDocumentNode? {
        guard let nodeID = viewModel.selectedNodeID else { return nil }
        return viewModel.document?.nodes.first { $0.id == nodeID }
    }
}

private struct GraphRunInspector: View {
    @Bindable var viewModel: GraphWorkspaceViewModel

    var body: some View {
        Form {
            if let inspection = viewModel.inspection {
                Section("Run") {
                    LabeledContent("Run ID", value: inspection.summary.runID)
                    LabeledContent("State") {
                        GraphStateBadge(state: inspection.summary.reconciledState)
                    }
                    LabeledContent("Stream", value: "\(inspection.summary.streamVersion)")
                    LabeledContent("Artifacts", value: "\(inspection.summary.artifactCount)")
                }
                if let node = selectedNode(inspection) {
                    Section("Node") {
                        LabeledContent("Name", value: node.title)
                        LabeledContent("State") {
                            GraphStateBadge(state: node.reconciledState)
                        }
                        LabeledContent("Executor", value: node.executorID ?? "Unclaimed")
                        LabeledContent(
                            "Blockers",
                            value: node.dependencyNodeIDs.joined(separator: ", ")
                        )
                    }
                    if let attempt = inspection.attempts
                        .filter({ $0.nodeID == node.id })
                        .max(by: { $0.ordinal < $1.ordinal }) {
                        Section("Attempt") {
                            LabeledContent("Ordinal", value: "\(attempt.ordinal)")
                            LabeledContent("Process identity", value: attempt.hasProcessIdentity ? "Recorded" : "Pending")
                            LabeledContent("Reason", value: attempt.statusReason ?? "None")
                            LabeledContent("Started", value: attempt.startedAt?.formatted() ?? "Pending")
                            LabeledContent("Finished", value: attempt.finishedAt?.formatted() ?? "Pending")
                        }
                    }
                    if let claim = inspection.scheduling?.claimHistory
                        .filter({ $0.nodeID == node.id })
                        .last {
                        Section("Claim and Lease") {
                            LabeledContent("Claim", value: claim.id)
                            LabeledContent("Generation", value: "\(claim.leaseGeneration)")
                            LabeledContent("Status", value: claim.status.rawValue)
                            LabeledContent("Expires", value: claim.leaseExpiry.formatted())
                        }
                    }
                }
                Section("Artifacts") {
                    ForEach(inspection.artifacts) { artifact in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(artifact.logicalRole).font(.callout.weight(.medium))
                            Text(artifact.digest).font(.caption2.monospaced()).lineLimit(1)
                            Text("\(artifact.mediaType) · \(artifact.sensitivity.rawValue)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Run Selected",
                    systemImage: "play.rectangle"
                )
            }
        }
        .formStyle(.grouped)
    }

    private func selectedNode(
        _ inspection: GraphRunInspection
    ) -> GraphNodeInspection? {
        guard let id = viewModel.selectedNodeID else { return nil }
        return inspection.nodes.first { $0.id == id }
    }
}

private struct GraphHistoryView: View {
    @Bindable var viewModel: GraphWorkspaceViewModel

    var body: some View {
        List {
            if let history = viewModel.history {
                ForEach(history.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("#\(event.streamSequence)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(event.eventType)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Text(event.occurredAt.formatted())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let nodeID = event.nodeID {
                            Text("node \(nodeID)")
                                .font(.caption.monospaced())
                        }
                        Text("\(event.factClass.rawValue) · producer \(event.producerID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath"
                )
            }
        }
        .accessibilityLabel("Graph execution event history")
    }
}

private struct GraphHistoryInspector: View {
    @Bindable var viewModel: GraphWorkspaceViewModel

    var body: some View {
        Form {
            if let explanation = viewModel.explanation {
                Section("Causal Explanation") {
                    LabeledContent("State", value: explanation.state.rawValue)
                    Text(explanation.summary)
                    if !explanation.blockingDependencyNodeIDs.isEmpty {
                        LabeledContent(
                            "Blocking dependencies",
                            value: explanation.blockingDependencyNodeIDs
                                .joined(separator: ", ")
                        )
                    }
                }
                Section("Reasons") {
                    ForEach(explanation.reasons) { reason in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reason.code.rawValue).font(.caption.weight(.medium))
                            Text(reason.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !explanation.ignoredInputs.isEmpty {
                    Section("Ignored Evidence") {
                        ForEach(explanation.ignoredInputs) { input in
                            Text(input.message).font(.caption)
                        }
                    }
                }
                Section("Scheduler") {
                    ForEach(
                        viewModel.inspection?.scheduling?.records ?? [],
                        id: \.id
                    ) { record in
                        Text(record.eventType).font(.caption)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Explanation",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct GraphLogViewer: View {
    @Bindable var viewModel: GraphWorkspaceViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("Log stream", selection: $viewModel.selectedLogChannel) {
                    Text("stdout").tag(GraphProcessLogChannel.stdout)
                    Text("stderr").tag(GraphProcessLogChannel.stderr)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                Toggle("Follow", isOn: $viewModel.isFollowingLogs)
                    .toggleStyle(.switch)
                if let page = viewModel.logPage,
                   !page.redactionLabels.isEmpty {
                    Label(
                        "Redacted: \(page.redactionLabels.joined(separator: ", "))",
                        systemImage: "eye.slash"
                    )
                    .font(.caption)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy Log Text")
                .accessibilityLabel("Copy Log Text")
                Button {
                    Task { await viewModel.refreshLogs() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Logs")
                .accessibilityLabel("Refresh Logs")
                Button {
                    viewModel.isShowingLogs = false
                    viewModel.isFollowingLogs = false
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Close Logs")
                .accessibilityLabel("Close Logs")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            ScrollView {
                Text(logText.isEmpty ? "No log output for this stream." : logText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .accessibilityLabel("Node process logs")
    }

    private var logText: String {
        viewModel.logPage?.entries
            .filter { $0.channel == viewModel.selectedLogChannel }
            .map(\.text)
            .joined() ?? ""
    }
}

@MainActor
enum GraphWorkspaceFilePanels {
    static func openDefinition(_ viewModel: GraphWorkspaceViewModel) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.openDocument(url: url) }
    }

    static func saveDefinition(_ viewModel: GraphWorkspaceViewModel) {
        if viewModel.documentURL != nil {
            Task { await viewModel.saveDocument() }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(viewModel.document?.graphID ?? "graph").openisland-graph.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.saveDocument(url: url) }
    }

    static func exportRun(_ viewModel: GraphWorkspaceViewModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(viewModel.inspection?.summary.runID ?? "graph-run").json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.exportRun(url: url) }
    }
}
