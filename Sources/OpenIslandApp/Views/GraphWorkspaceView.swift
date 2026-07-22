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
    @State private var isShowingNewGraph = false

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
        .sheet(isPresented: $isShowingNewGraph) {
            GraphNewDocumentSheet { request in
                viewModel.newDocument(request: request)
                isShowingNewGraph = false
            } onCancel: {
                isShowingNewGraph = false
            }
        }
        .confirmationDialog(
            "Save changes before closing?",
            isPresented: Binding(
                get: { viewModel.closeState == .confirmationRequired },
                set: { if !$0 { viewModel.closeState = .idle } }
            )
        ) {
            Button("Save") {
                GraphWorkspaceFilePanels.saveAndCloseDefinition(viewModel)
            }
            Button("Don't Save", role: .destructive) {
                Task { await viewModel.resolveCloseDocument(.discard) }
            }
            Button("Cancel", role: .cancel) {
                Task { await viewModel.resolveCloseDocument(.cancel) }
            }
        }
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
            if viewModel.isDirty {
                Text("Edited")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Document has unsaved changes")
            }
            if viewModel.isDraft {
                Text("Draft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

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
            Button {
                isShowingNewGraph = true
            } label: {
                Label("New Graph", systemImage: "doc.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command])
            .help("Create a blank graph or start from a template")

            Button {
                GraphWorkspaceFilePanels.openDefinition(viewModel)
            } label: {
                Label("Open Graph", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button {
                GraphWorkspaceFilePanels.saveDefinition(viewModel)
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.document == nil)
            .keyboardShortcut("s", modifiers: [.command])

            Menu {
                Button("Save As") {
                    GraphWorkspaceFilePanels.saveAsDefinition(viewModel)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Revert to Saved") {
                    Task { await viewModel.revertDocument() }
                }
                .disabled(viewModel.documentURL == nil)
                Divider()
                Button("Close Graph") { viewModel.requestCloseDocument() }
                    .disabled(viewModel.document == nil)
            } label: {
                Label("Document", systemImage: "ellipsis.circle")
            }

            Button {
                viewModel.validateDocument()
            } label: {
                Label("Validate", systemImage: "checkmark.seal")
            }
            .disabled(viewModel.document == nil)
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Menu {
                Menu("Add Node") {
                    Button("Local Process") { viewModel.addNode(type: .localProcess) }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                    Button("Deterministic Test") { viewModel.addNode(type: .deterministicTest) }
                    Button("Generic Agent") { viewModel.addNode(type: .genericAgent) }
                    Divider()
                    Button("Input Reference") { viewModel.addNode(type: .input) }
                    Button("Output Reference") { viewModel.addNode(type: .output) }
                    Button("Annotation") { viewModel.addNode(type: .annotation) }
                }
                Button("Connect Selected Nodes") {
                    viewModel.connectSelectedNodes()
                }
                .disabled(viewModel.selectedNodeIDs.count != 2)
                Divider()
                Button("Undo") { viewModel.undo() }
                    .disabled(!viewModel.canUndo)
                    .keyboardShortcut("z", modifiers: [.command])
                Button("Redo") { viewModel.redo() }
                    .disabled(!viewModel.canRedo)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                Divider()
                Button("Auto Layout") { viewModel.automaticLayout() }
                Button("Delete Selection", role: .destructive) {
                    viewModel.deleteSelection()
                }
                .disabled(viewModel.selectedNodeIDs.isEmpty)
            } label: {
                Label("Edit", systemImage: "slider.horizontal.3")
            }
            Button("Create Run") { Task { await viewModel.createRun() } }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.decision(.createRun).isEnabled)
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .controlSize(.small)
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
        if viewModel.document == nil && viewModel.mode == .definition {
            GraphWorkspaceEmptyState(
                recentURLs: viewModel.recentDocumentURLs,
                onNew: { isShowingNewGraph = true },
                onOpen: { GraphWorkspaceFilePanels.openDefinition(viewModel) },
                onOpenRecent: { url in
                    Task { await viewModel.openDocument(url: url) }
                },
                onOpenExample: { viewModel.openBundledCompendium() }
            )
        } else {
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

private struct GraphWorkspaceEmptyState: View {
    let recentURLs: [URL]
    let onNew: () -> Void
    let onOpen: () -> Void
    let onOpenRecent: (URL) -> Void
    let onOpenExample: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                "Build an Executable Graph",
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        } description: {
            Text("Create a graph, add executable nodes, connect dependencies, validate, and run it here.")
        } actions: {
            HStack {
                Button("Create New Graph", action: onNew)
                    .buttonStyle(.borderedProminent)
                Button("Open Existing Graph", action: onOpen)
                Menu("Open Recent Graph") {
                    if recentURLs.isEmpty {
                        Text("No Recent Graphs")
                    } else {
                        ForEach(recentURLs, id: \.path) { url in
                            Button(url.lastPathComponent) { onOpenRecent(url) }
                        }
                    }
                }
                Button("Open Example Graph", action: onOpenExample)
            }
        }
        .accessibilityLabel("Empty Graph Workspace")
    }
}

private struct GraphNewDocumentSheet: View {
    @State private var request = GraphNewDocumentRequest.defaults()
    let onCreate: (GraphNewDocumentRequest) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Graph").font(.title2.weight(.semibold))
            Form {
                Section("Identity") {
                    TextField("Graph Name", text: $request.name)
                        .accessibilityHint("The name shown in the workspace and run summary")
                    TextField("Stable Graph ID", text: $request.graphID)
                    TextField("Definition Version", text: $request.definitionVersion)
                    TextField("Description", text: $request.description, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Execution Defaults") {
                    Picker("Default Executor", selection: $request.defaultExecutorKind) {
                        Text("Supervised Local Process")
                            .tag(GraphLocalProcessSpecification.adapterKind)
                        Text("Deterministic Test").tag("deterministic")
                    }
                    Stepper(
                        "Maximum Attempts: \(request.defaultRetryMaximumAttempts)",
                        value: $request.defaultRetryMaximumAttempts,
                        in: 1...20
                    )
                    Stepper(
                        "Execution Timeout: \(request.defaultExecutionTimeoutSeconds)s",
                        value: $request.defaultExecutionTimeoutSeconds,
                        in: 1...86_400
                    )
                    HStack {
                        LabeledContent(
                            "Workspace",
                            value: request.workspaceDirectory ?? "Not selected"
                        )
                        Button("Choose") {
                            request.workspaceDirectory = GraphWorkspaceFilePanels
                                .chooseDirectory()?.path
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create Graph") { onCreate(request) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        request.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || request.graphID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || request.definitionVersion.isEmpty
                    )
            }
        }
        .padding(20)
        .frame(width: 560, height: 600)
        .accessibilityLabel("New Graph Configuration")
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
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.selectCanvas() }
                    .contextMenu {
                        Menu("Add Node") {
                            Button("Local Process") { viewModel.addNode(type: .localProcess) }
                            Button("Deterministic Test") { viewModel.addNode(type: .deterministicTest) }
                            Button("Generic Agent") { viewModel.addNode(type: .genericAgent) }
                            Button("Input Reference") { viewModel.addNode(type: .input) }
                            Button("Output Reference") { viewModel.addNode(type: .output) }
                            Button("Annotation") { viewModel.addNode(type: .annotation) }
                        }
                    }
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
                        "Add your first node",
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                } actions: {
                    if isEditable {
                        Menu("Add Node") {
                            Button("Local Process") { viewModel.addNode(type: .localProcess) }
                            Button("Deterministic Test") { viewModel.addNode(type: .deterministicTest) }
                            Button("Generic Agent") { viewModel.addNode(type: .genericAgent) }
                            Button("Input Reference") { viewModel.addNode(type: .input) }
                            Button("Output Reference") { viewModel.addNode(type: .output) }
                            Button("Annotation") { viewModel.addNode(type: .annotation) }
                        }
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
            Text(node.nodeType.rawValue.replacingOccurrences(of: "_", with: " "))
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            if let node = selectedNode {
                Section("Identity") {
                    LabeledContent("Stable ID", value: node.id)
                    TextField(
                        "Name",
                        text: Binding(
                            get: { selectedNode?.name ?? "" },
                            set: { updateIdentity(name: $0) }
                        )
                    )
                    TextField(
                        "Description",
                        text: Binding(
                            get: { selectedNode?.description ?? "" },
                            set: { updateIdentity(description: $0) }
                        ),
                        axis: .vertical
                    )
                    Picker(
                        "Node Type",
                        selection: Binding(
                            get: { selectedNode?.nodeType ?? .localProcess },
                            set: { viewModel.updateSelectedNodeType($0) }
                        )
                    ) {
                        Text("Local Process").tag(GraphDefinitionNodeType.localProcess)
                        Text("Deterministic Test").tag(GraphDefinitionNodeType.deterministicTest)
                        Text("Generic Agent").tag(GraphDefinitionNodeType.genericAgent)
                        Text("Input Reference").tag(GraphDefinitionNodeType.input)
                        Text("Output Reference").tag(GraphDefinitionNodeType.output)
                        Text("Annotation").tag(GraphDefinitionNodeType.annotation)
                    }
                    TextField(
                        "Tags",
                        text: Binding(
                            get: { selectedNode?.tags.joined(separator: ", ") ?? "" },
                            set: { updateIdentity(tags: csv($0)) }
                        )
                    )
                }
                if node.nodeType == .localProcess {
                    localProcessSection
                } else {
                    Section("Execution") {
                        LabeledContent("Adapter", value: node.specification.adapterKind)
                        LabeledContent("Operation", value: node.specification.operation)
                        if node.nodeType == .genericAgent {
                            Label("A provider adapter must be assigned before this node can run.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                capabilitiesSection
                inputsSection
                outputsSection
                retrySection
                timeoutSection
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
                    Button("Add Dependency") {
                        viewModel.connectSelectedNodes()
                    }
                    .disabled(viewModel.selectedNodeIDs.count != 2)
                }
            } else {
                graphInspector
            }
        }
        .formStyle(.grouped)
    }

    private var selectedNode: GraphDefinitionDocumentNode? {
        viewModel.selectedNode
    }

    @ViewBuilder
    private var graphInspector: some View {
        if let document = viewModel.document {
            Section("Graph") {
                TextField(
                    "Name",
                    text: Binding(
                        get: { viewModel.document?.name ?? "" },
                        set: { viewModel.updateGraphIdentity(
                            name: $0,
                            description: viewModel.document?.description ?? ""
                        ) }
                    )
                )
                TextField(
                    "Description",
                    text: Binding(
                        get: { viewModel.document?.description ?? "" },
                        set: { viewModel.updateGraphIdentity(
                            name: viewModel.document?.name ?? "",
                            description: $0
                        ) }
                    ),
                    axis: .vertical
                )
                LabeledContent("Graph ID", value: document.graphID)
                LabeledContent("Definition Version", value: document.definitionVersion)
                LabeledContent("State", value: viewModel.isDraft ? "Draft" : "Editable")
                LabeledContent("Associated Runs", value: "\(viewModel.associatedRunCount)")
                LabeledContent("Nodes", value: "\(document.nodes.count)")
                LabeledContent("Edges", value: "\(document.edges.count)")
                if viewModel.isDraft {
                    Button("Create New Definition Version") {
                        viewModel.createNewDefinitionVersion()
                    }
                }
            }
        } else {
            ContentUnavailableView("No Graph Open", systemImage: "doc")
        }
    }

    @ViewBuilder
    private var localProcessSection: some View {
        if let process = viewModel.selectedLocalProcessSpecification {
            Section("Execution") {
                HStack {
                    TextField(
                        "Executable Path",
                        text: Binding(
                            get: { viewModel.selectedLocalProcessSpecification?.executable ?? "" },
                            set: { updateProcess(executable: $0) }
                        )
                    )
                    Button("Choose") {
                        if let url = GraphWorkspaceFilePanels.chooseExecutable() {
                            updateProcess(executable: url.path)
                        }
                    }
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            URL(fileURLWithPath: process.executable),
                        ])
                    }
                }
                HStack {
                    TextField(
                        "Workspace Directory",
                        text: Binding(
                            get: { selectedNode?.workspace.root ?? "" },
                            set: { updateProcess(workspaceRoot: $0) }
                        )
                    )
                    Button("Choose") {
                        if let url = GraphWorkspaceFilePanels.chooseDirectory() {
                            updateProcess(workspaceRoot: url.path)
                        }
                    }
                }
                TextField(
                    "Working Directory (relative)",
                    text: Binding(
                        get: { viewModel.selectedLocalProcessSpecification?.workingDirectory ?? "." },
                        set: { updateProcess(workingDirectory: $0) }
                    )
                )
                Picker(
                    "Environment Inheritance",
                    selection: Binding(
                        get: {
                            viewModel.selectedLocalProcessSpecification?.inheritedEnvironment
                                ?? GraphLocalProcessEnvironmentInheritance.none
                        },
                        set: { updateProcess(inheritedEnvironment: $0) }
                    )
                ) {
                    Text("None").tag(GraphLocalProcessEnvironmentInheritance.none)
                    Text("Allowlisted Only").tag(GraphLocalProcessEnvironmentInheritance.allowlisted)
                }
                TextField(
                    "Allowed Environment Variables",
                    text: Binding(
                        get: { selectedNode?.environmentAllowlist.joined(separator: ", ") ?? "" },
                        set: { updateProcess(environmentAllowlist: csv($0)) }
                    )
                )
                Picker(
                    "Standard Input",
                    selection: Binding(
                        get: { viewModel.selectedLocalProcessSpecification?.stdin ?? .nullDevice },
                        set: { updateProcess(stdin: $0) }
                    )
                ) {
                    Text("Null Device").tag(GraphLocalProcessStdinPolicy.nullDevice)
                    Text("Closed").tag(GraphLocalProcessStdinPolicy.closed)
                }
                LabeledContent("Arguments") {
                    Button("Add Argument") { viewModel.addSelectedNodeArgument() }
                }
                ForEach(Array(process.arguments.enumerated()), id: \.offset) { index, _ in
                    HStack {
                        TextField(
                            "Argument \(index + 1)",
                            text: Binding(
                                get: {
                                    let values = viewModel.selectedLocalProcessSpecification?.arguments ?? []
                                    return values.indices.contains(index) ? values[index] : ""
                                },
                                set: { viewModel.updateSelectedNodeArgument(at: index, value: $0) }
                            )
                        )
                        Button { viewModel.moveSelectedNodeArgument(from: index, offset: -1) } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == 0)
                        .help("Move Argument Up")
                        Button { viewModel.moveSelectedNodeArgument(from: index, offset: 1) } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == process.arguments.count - 1)
                        .help("Move Argument Down")
                        Button(role: .destructive) {
                            viewModel.removeSelectedNodeArgument(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .help("Remove Argument")
                    }
                }
            }
        }
    }

    private var capabilitiesSection: some View {
        Section("Capabilities") {
            TextField(
                "Required",
                text: Binding(
                    get: { selectedNode?.requiredCapabilities.joined(separator: ", ") ?? "" },
                    set: { updateCapabilities(required: csv($0)) }
                )
            )
            TextField(
                "Preferred",
                text: Binding(
                    get: { selectedNode?.preferredCapabilities.joined(separator: ", ") ?? "" },
                    set: { updateCapabilities(preferred: csv($0)) }
                )
            )
            Picker(
                "Executor Kind",
                selection: Binding(
                    get: { selectedNode?.executorKind ?? GraphDefinitionExecutorKind.none },
                    set: { updateCapabilities(executor: $0) }
                )
            ) {
                ForEach(GraphDefinitionExecutorKind.allCases, id: \.rawValue) {
                    Text($0.displayName).tag($0)
                }
            }
            TextField(
                "Platform Constraints",
                text: Binding(
                    get: { selectedNode?.platformConstraints.joined(separator: ", ") ?? "" },
                    set: { updateCapabilities(platforms: csv($0)) }
                )
            )
        }
    }

    private var inputsSection: some View {
        Section("Inputs") {
            if selectedNode?.inputs.isEmpty != false {
                Text("No declared inputs").foregroundStyle(.secondary)
            }
            ForEach(selectedNode?.inputs ?? []) { input in
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "Input Name",
                        text: inputBinding(input.id, \.name, fallback: input.name)
                    )
                    TextField(
                        "Media Type",
                        text: inputBinding(input.id, \.mediaType, fallback: input.mediaType)
                    )
                    Toggle(
                        "Required",
                        isOn: inputBinding(input.id, \.isRequired, fallback: input.isRequired)
                    )
                    Toggle(
                        "Allow Multiple Providers",
                        isOn: inputBinding(input.id, \.allowsMultiple, fallback: input.allowsMultiple)
                    )
                    LabeledContent("Stable ID", value: input.id)
                    Button("Remove Input", role: .destructive) {
                        viewModel.removeSelectedNodeInput(input.id)
                    }
                }
            }
            Button("Add Input") { viewModel.addSelectedNodeInput() }
        }
    }

    private var outputsSection: some View {
        Section("Outputs") {
            if selectedNode?.outputs.isEmpty != false {
                Text("No declared outputs").foregroundStyle(.secondary)
            }
            ForEach(selectedNode?.outputs ?? []) { output in
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "Output Name",
                        text: outputBinding(output.id, \.name, fallback: output.name)
                    )
                    TextField(
                        "Relative Path",
                        text: outputBinding(output.id, \.relativePath, fallback: output.relativePath)
                    )
                    TextField(
                        "Media Type",
                        text: outputBinding(output.id, \.mediaType, fallback: output.mediaType)
                    )
                    Picker(
                        "Runtime Role",
                        selection: outputBinding(output.id, \.role, fallback: output.role)
                    ) {
                        ForEach(GraphArtifactRole.allCases, id: \.rawValue) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    Toggle(
                        "Required",
                        isOn: outputBinding(output.id, \.isRequired, fallback: output.isRequired)
                    )
                    Stepper(
                        "Maximum Size: \(output.maximumBytes / 1_024) KiB",
                        value: outputBinding(output.id, \.maximumBytes, fallback: output.maximumBytes),
                        in: 1_024...(1_024 * 1_024 * 1_024),
                        step: 1_024
                    )
                    Picker(
                        "Sensitivity",
                        selection: outputBinding(output.id, \.sensitivity, fallback: output.sensitivity)
                    ) {
                        Text("Unspecified").tag(GraphArtifactSensitivity.unspecified)
                        Text("Internal").tag(GraphArtifactSensitivity.internalUse)
                        Text("Confidential").tag(GraphArtifactSensitivity.confidential)
                        Text("Restricted").tag(GraphArtifactSensitivity.restricted)
                        Text("Redacted").tag(GraphArtifactSensitivity.redacted)
                    }
                    Picker(
                        "Downstream Visibility",
                        selection: outputBinding(
                            output.id,
                            \.downstreamVisibility,
                            fallback: output.downstreamVisibility
                        )
                    ) {
                        Text("Whole Graph").tag(GraphArtifactDownstreamVisibility.graph)
                        Text("Direct Dependents").tag(GraphArtifactDownstreamVisibility.directDependents)
                        Text("Private to Node").tag(GraphArtifactDownstreamVisibility.privateToNode)
                    }
                    LabeledContent("Stable ID", value: output.id)
                    Button("Remove Output", role: .destructive) {
                        viewModel.removeSelectedNodeOutput(output.id)
                    }
                }
            }
            Button("Add Output") { viewModel.addSelectedNodeOutput() }
        }
    }

    private var retrySection: some View {
        Section("Retry") {
            Toggle(
                "Inherit Graph Default",
                isOn: Binding(
                    get: { selectedNode?.retryConfiguration.inheritsGraphDefault ?? true },
                    set: { setRetryInheritance($0) }
                )
            )
            if selectedNode?.retryConfiguration.inheritsGraphDefault == false {
                let policy = retryPolicy
                Stepper(
                    "Maximum Attempts: \(policy.maximumAttempts)",
                    value: Binding(
                        get: { retryPolicy.maximumAttempts },
                        set: { updateRetry(maximumAttempts: $0) }
                    ),
                    in: 1...20
                )
                TextField(
                    "Retryable Categories",
                    text: Binding(
                        get: { retryPolicy.retryableFailureCategories.joined(separator: ", ") },
                        set: { updateRetry(retryable: csv($0)) }
                    )
                )
                TextField(
                    "Non-Retryable Categories",
                    text: Binding(
                        get: { retryPolicy.nonRetryableFailureCategories.joined(separator: ", ") },
                        set: { updateRetry(nonRetryable: csv($0)) }
                    )
                )
                Stepper(
                    "Base Delay: \(policy.initialBackoffSeconds)s",
                    value: Binding(
                        get: { retryPolicy.initialBackoffSeconds },
                        set: { updateRetry(baseDelay: $0) }
                    ),
                    in: 0...3_600
                )
                Stepper(
                    "Maximum Delay: \(policy.maximumBackoffSeconds)s",
                    value: Binding(
                        get: { retryPolicy.maximumBackoffSeconds },
                        set: { updateRetry(maximumDelay: $0) }
                    ),
                    in: 0...86_400
                )
                Picker(
                    "Timeout Failure",
                    selection: Binding(
                        get: { retryPolicy.timeoutBehavior },
                        set: { updateRetry(timeoutBehavior: $0) }
                    )
                ) {
                    Text("Retry").tag(GraphRetryTimeoutBehavior.retry)
                    Text("Do Not Retry").tag(GraphRetryTimeoutBehavior.suppress)
                }
            }
        }
    }

    private var timeoutSection: some View {
        Section("Timeout") {
            Toggle(
                "Inherit Graph Default",
                isOn: Binding(
                    get: { selectedNode?.timeoutConfiguration.inheritsGraphDefault ?? true },
                    set: { updateTimeout(inherits: $0) }
                )
            )
            if selectedNode?.timeoutConfiguration.inheritsGraphDefault == false {
                Stepper(
                    "Execution: \(timeout.executionSeconds)s",
                    value: Binding(
                        get: { timeout.executionSeconds },
                        set: { updateTimeout(execution: $0) }
                    ),
                    in: 1...86_400
                )
                Stepper(
                    "Cancellation Grace: \(timeout.cancellationAcknowledgementSeconds)s",
                    value: Binding(
                        get: { timeout.cancellationAcknowledgementSeconds },
                        set: { updateTimeout(cancellation: $0) }
                    ),
                    in: 1...3_600
                )
                Stepper(
                    "Claim Timeout: \(timeout.claimSeconds)s",
                    value: Binding(
                        get: { timeout.claimSeconds },
                        set: { updateTimeout(claim: $0) }
                    ),
                    in: 1...3_600
                )
            }
        }
    }

    private var retryPolicy: GraphRetryPolicy {
        selectedNode?.retryConfiguration.override
            ?? viewModel.document?.schedulerPolicy.retryPolicy
            ?? GraphRetryPolicy(maximumAttempts: 1, retryableFailureCategories: [])
    }

    private var timeout: GraphNodeTimeoutConfiguration {
        selectedNode?.timeoutConfiguration ?? .init()
    }

    private func csv(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updateIdentity(
        name: String? = nil,
        description: String? = nil,
        tags: [String]? = nil
    ) {
        guard let node = selectedNode else { return }
        viewModel.updateSelectedNodeIdentity(
            name: name ?? node.name,
            description: description ?? node.description,
            tags: tags ?? node.tags
        )
    }

    private func updateCapabilities(
        required: [String]? = nil,
        preferred: [String]? = nil,
        executor: GraphDefinitionExecutorKind? = nil,
        platforms: [String]? = nil
    ) {
        guard let node = selectedNode else { return }
        viewModel.updateSelectedNodeCapabilities(
            required: required ?? node.requiredCapabilities,
            preferred: preferred ?? node.preferredCapabilities,
            executorKind: executor ?? node.executorKind,
            platformConstraints: platforms ?? node.platformConstraints
        )
    }

    private func updateProcess(
        executable: String? = nil,
        arguments: [String]? = nil,
        workingDirectory: String? = nil,
        inheritedEnvironment: GraphLocalProcessEnvironmentInheritance? = nil,
        stdin: GraphLocalProcessStdinPolicy? = nil,
        environmentAllowlist: [String]? = nil,
        workspaceRoot: String? = nil
    ) {
        guard let process = viewModel.selectedLocalProcessSpecification,
              let node = selectedNode else { return }
        viewModel.updateSelectedLocalProcess(
            executable: executable ?? process.executable,
            arguments: arguments ?? process.arguments,
            workingDirectory: workingDirectory ?? process.workingDirectory,
            inheritedEnvironment: inheritedEnvironment ?? process.inheritedEnvironment,
            stdin: stdin ?? process.stdin,
            environmentAllowlist: environmentAllowlist ?? node.environmentAllowlist,
            workspaceRoot: workspaceRoot ?? node.workspace.root
        )
    }

    private func inputBinding<Value>(
        _ id: String,
        _ keyPath: WritableKeyPath<GraphNodeInputDefinition, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                viewModel.selectedNode?.inputs.first { $0.id == id }?[keyPath: keyPath]
                    ?? fallback
            },
            set: { value in
                guard var input = viewModel.selectedNode?.inputs.first(where: {
                    $0.id == id
                }) else { return }
                input[keyPath: keyPath] = value
                viewModel.updateSelectedNodeInput(input)
            }
        )
    }

    private func outputBinding<Value>(
        _ id: String,
        _ keyPath: WritableKeyPath<GraphNodeOutputDefinition, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                viewModel.selectedNode?.outputs.first { $0.id == id }?[keyPath: keyPath]
                    ?? fallback
            },
            set: { value in
                guard var output = viewModel.selectedNode?.outputs.first(where: {
                    $0.id == id
                }) else { return }
                output[keyPath: keyPath] = value
                viewModel.updateSelectedNodeOutput(output)
            }
        )
    }

    private func setRetryInheritance(_ inherits: Bool) {
        viewModel.updateSelectedNodeRetry(
            GraphNodeRetryConfiguration(
                inheritsGraphDefault: inherits,
                override: inherits ? nil : retryPolicy
            )
        )
    }

    private func updateRetry(
        maximumAttempts: Int? = nil,
        retryable: [String]? = nil,
        nonRetryable: [String]? = nil,
        baseDelay: UInt64? = nil,
        maximumDelay: UInt64? = nil,
        timeoutBehavior: GraphRetryTimeoutBehavior? = nil
    ) {
        let source = retryPolicy
        let updated = GraphRetryPolicy(
            maximumAttempts: maximumAttempts ?? source.maximumAttempts,
            retryableFailureCategories: retryable
                ?? source.retryableFailureCategories,
            nonRetryableFailureCategories: nonRetryable
                ?? source.nonRetryableFailureCategories,
            initialBackoffSeconds: baseDelay ?? source.initialBackoffSeconds,
            backoffMultiplier: source.backoffMultiplier,
            maximumBackoffSeconds: maximumDelay ?? source.maximumBackoffSeconds,
            jitterBasisPoints: source.jitterBasisPoints,
            jitterSeed: source.jitterSeed,
            timeoutBehavior: timeoutBehavior ?? source.timeoutBehavior,
            cancellationBehavior: source.cancellationBehavior,
            dependencyFailureBehavior: source.dependencyFailureBehavior
        )
        viewModel.updateSelectedNodeRetry(
            GraphNodeRetryConfiguration(
                inheritsGraphDefault: false,
                override: updated
            )
        )
    }

    private func updateTimeout(
        inherits: Bool? = nil,
        execution: UInt64? = nil,
        cancellation: UInt64? = nil,
        claim: UInt64? = nil
    ) {
        let source = timeout
        viewModel.updateSelectedNodeTimeout(
            GraphNodeTimeoutConfiguration(
                inheritsGraphDefault: inherits ?? source.inheritsGraphDefault,
                executionSeconds: execution ?? source.executionSeconds,
                cancellationAcknowledgementSeconds: cancellation
                    ?? source.cancellationAcknowledgementSeconds,
                claimSeconds: claim ?? source.claimSeconds
            )
        )
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

    static func saveAsDefinition(_ viewModel: GraphWorkspaceViewModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(viewModel.document?.graphID ?? "graph").openisland-graph.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.saveAsDocument(url: url) }
    }

    static func saveAndCloseDefinition(_ viewModel: GraphWorkspaceViewModel) {
        if viewModel.documentURL != nil {
            Task { await viewModel.resolveCloseDocument(.save) }
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(viewModel.document?.graphID ?? "graph").openisland-graph.json"
        guard panel.runModal() == .OK, let url = panel.url else {
            Task { await viewModel.resolveCloseDocument(.cancel) }
            return
        }
        Task { await viewModel.resolveCloseDocument(.save, saveURL: url) }
    }

    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExecutable() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func exportRun(_ viewModel: GraphWorkspaceViewModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(viewModel.inspection?.summary.runID ?? "graph-run").json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.exportRun(url: url) }
    }
}
