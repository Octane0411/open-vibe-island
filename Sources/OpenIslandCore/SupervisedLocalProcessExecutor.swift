import CryptoKit
import Darwin
import Foundation

public enum GraphLocalProcessCrashPoint: String, Codable, Sendable {
    case beforeSpawn = "before_spawn"
    case afterSpawnAcceptance = "after_spawn_acceptance"
}

public actor SupervisedLocalProcessExecutor: GraphExecutorAdapter {
    public nonisolated let capabilities: GraphExecutorCapabilities

    private let launchStore: GraphLocalProcessLaunchStore
    private let logStore: GraphProcessLogStore
    private let inspector: any GraphProcessInspecting
    private let executorInstanceID: String
    private let crashPoint: GraphLocalProcessCrashPoint?
    private var processes: [String: Process] = [:]
    private var exitWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    public init(
        executorID: String = "openisland.local-process",
        executorInstanceID: String = UUID().uuidString,
        hostID: String = Host.current().localizedName ?? "localhost",
        capabilities: [String] = ["local-process", "compendium"],
        launchStore: GraphLocalProcessLaunchStore,
        logStore: GraphProcessLogStore = GraphProcessLogStore(),
        inspector: any GraphProcessInspecting = DarwinGraphProcessInspector(),
        crashPoint: GraphLocalProcessCrashPoint? = nil
    ) {
        self.capabilities = GraphExecutorCapabilities(
            executorID: executorID,
            capabilityIdentity: "supervised-local-process-v1",
            capabilities: capabilities,
            hostID: hostID
        )
        self.executorInstanceID = executorInstanceID
        self.launchStore = launchStore
        self.logStore = logStore
        self.inspector = inspector
        self.crashPoint = crashPoint
    }

    public func prepare(
        _ request: GraphExecutorPrepareRequest
    ) async throws -> GraphExecutorPrepareResponse {
        do {
            let (_, record) = try await resolvedRecord(
                request.context,
                createIfMissing: true
            )
            return GraphExecutorPrepareResponse(
                observation: observation(
                    operation: .prepare,
                    status: .accepted,
                    context: request.context,
                    record: record
                )
            )
        } catch {
            return GraphExecutorPrepareResponse(
                observation: rejected(
                    operation: .prepare,
                    context: request.context,
                    error: error
                )
            )
        }
    }

    public func start(
        _ request: GraphExecutorStartRequest
    ) async throws -> GraphExecutorStartResponse {
        GraphExecutorStartResponse(
            observation: try await launch(
                request.context,
                operation: .start
            )
        )
    }

    public func observe(
        _ request: GraphExecutorObserveRequest
    ) async throws -> GraphExecutorObserveResponse {
        do {
            let (resolved, record) = try await resolvedRecord(
                request.context,
                createIfMissing: false
            )
            let refreshed = try await refreshExitIfNeeded(record)
            return GraphExecutorObserveResponse(
                observation: terminalOrRunningObservation(
                    operation: .observe,
                    context: request.context,
                    resolved: resolved,
                    record: refreshed
                )
            )
        } catch {
            return GraphExecutorObserveResponse(
                observation: rejected(
                    operation: .observe,
                    context: request.context,
                    error: error
                )
            )
        }
    }

    public func requestCancellation(
        _ request: GraphExecutorCancellationRequest
    ) async throws -> GraphExecutorCancellationResponse {
        do {
            let (resolved, current) = try await resolvedRecord(
                request.context,
                createIfMissing: false
            )
            var record = try await refreshExitIfNeeded(current)
            if record.exit != nil {
                return GraphExecutorCancellationResponse(
                    observation: observation(
                        operation: .requestCancellation,
                        status: .cancelled,
                        context: request.context,
                        record: record
                    )
                )
            }
            if record.cancellationRequestedAt == nil {
                record = try await launchStore.update(id: record.id) {
                    $0.cancellationRequestedAt = request.context.logicalTime
                }
                let classification = inspector.classify(record.identity)
                guard classification == .matchingRunning else {
                    return GraphExecutorCancellationResponse(
                        observation: recoveryFailureObservation(
                            operation: .requestCancellation,
                            classification: classification,
                            context: request.context,
                            record: record
                        )
                    )
                }
                try signal(record, signal: SIGTERM)
            }
            let deadline = record.cancellationRequestedAt!
                .addingTimeInterval(
                    TimeInterval(
                        request.context.timeoutPolicy
                            .cancellationAcknowledgementSeconds
                    )
                )
            if request.context.logicalTime >= deadline,
               record.cancellationEscalatedAt == nil {
                let classification = inspector.classify(record.identity)
                guard classification == .matchingRunning else {
                    record = try await refreshExitIfNeeded(record)
                    return GraphExecutorCancellationResponse(
                        observation: terminalOrRunningObservation(
                            operation: .requestCancellation,
                            context: request.context,
                            resolved: resolved,
                            record: record,
                            cancellationTerminal: true
                        )
                    )
                }
                try signal(record, signal: SIGKILL)
                record = try await launchStore.update(id: record.id) {
                    $0.cancellationEscalatedAt = request.context.logicalTime
                }
            }
            record = try await refreshExitIfNeeded(record)
            return GraphExecutorCancellationResponse(
                observation: observation(
                    operation: .requestCancellation,
                    status: record.exit == nil ? .stillRunning : .cancelled,
                    context: request.context,
                    record: record
                )
            )
        } catch {
            return GraphExecutorCancellationResponse(
                observation: rejected(
                    operation: .requestCancellation,
                    context: request.context,
                    error: error
                )
            )
        }
    }

    public func collectResult(
        _ request: GraphExecutorCollectResultRequest
    ) async throws -> GraphExecutorCollectResultResponse {
        do {
            let (resolved, current) = try await resolvedRecord(
                request.context,
                createIfMissing: false
            )
            let record = try await refreshExitIfNeeded(current)
            guard record.exit != nil else {
                return GraphExecutorCollectResultResponse(
                    observation: observation(
                        operation: .collectResult,
                        status: .stillRunning,
                        context: request.context,
                        record: record
                    )
                )
            }
            let terminal = terminalStatus(record: record, resolved: resolved)
            var artifacts = try collectLogs(record: record)
            do {
                artifacts.append(
                    contentsOf: try collectDeclaredArtifacts(resolved: resolved)
                )
            } catch {
                if terminal.status == .succeeded {
                    return GraphExecutorCollectResultResponse(
                        observation: observation(
                            operation: .collectResult,
                            status: .failed,
                            context: request.context,
                            record: record,
                            failure: GraphExecutorFailure(
                                category: "artifact_collection_failure",
                                retryable: false
                            ),
                            artifacts: artifacts
                        )
                    )
                }
            }
            return GraphExecutorCollectResultResponse(
                observation: observation(
                    operation: .collectResult,
                    status: terminal.status,
                    context: request.context,
                    record: record,
                    failure: terminal.failure,
                    artifacts: artifacts
                )
            )
        } catch {
            return GraphExecutorCollectResultResponse(
                observation: rejected(
                    operation: .collectResult,
                    context: request.context,
                    error: error
                )
            )
        }
    }

    public func cleanup(
        _ request: GraphExecutorCleanupRequest
    ) async throws -> GraphExecutorCleanupResponse {
        do {
            let (_, current) = try await resolvedRecord(
                request.context,
                createIfMissing: false
            )
            var record = try await refreshExitIfNeeded(current)
            if record.exit == nil,
               inspector.classify(record.identity) == .matchingRunning {
                try signal(record, signal: SIGKILL)
            }
            processes.removeValue(forKey: record.id)
            record = try await launchStore.update(id: record.id) {
                $0.lifecycle = .cleaned
                $0.cleanedAt = request.context.logicalTime
            }
            return GraphExecutorCleanupResponse(
                observation: observation(
                    operation: .cleanup,
                    status: .accepted,
                    context: request.context,
                    record: record
                )
            )
        } catch GraphLocalProcessRuntimeError.launchRecordMissing {
            return GraphExecutorCleanupResponse(
                observation: observation(
                    operation: .cleanup,
                    status: .accepted,
                    context: request.context
                )
            )
        } catch {
            return GraphExecutorCleanupResponse(
                observation: rejected(
                    operation: .cleanup,
                    context: request.context,
                    error: error
                )
            )
        }
    }

    public func recover(
        _ request: GraphExecutorRecoverRequest
    ) async throws -> GraphExecutorRecoverResponse {
        do {
            let (resolved, record) = try await resolvedRecord(
                request.context,
                createIfMissing: true
            )
            if record.lifecycle == .prepared,
               record.identity.process.processID == nil {
                return GraphExecutorRecoverResponse(
                    observation: try await launch(
                        request.context,
                        operation: .recover
                    )
                )
            }
            let refreshed = try await refreshExitIfNeeded(record)
            if refreshed.exit != nil {
                return GraphExecutorRecoverResponse(
                    observation: terminalOrRunningObservation(
                        operation: .recover,
                        context: request.context,
                        resolved: resolved,
                        record: refreshed
                    )
                )
            }
            let classification = inspector.classify(refreshed.identity)
            if classification == .matchingRunning {
                return GraphExecutorRecoverResponse(
                    observation: observation(
                        operation: .recover,
                        status: .started,
                        context: request.context,
                        record: refreshed
                    )
                )
            }
            return GraphExecutorRecoverResponse(
                observation: recoveryFailureObservation(
                    operation: .recover,
                    classification: classification,
                    context: request.context,
                    record: refreshed
                )
            )
        } catch {
            return GraphExecutorRecoverResponse(
                observation: rejected(
                    operation: .recover,
                    context: request.context,
                    error: error
                )
            )
        }
    }

    public func waitForExit(launchRecordID: String) async {
        if let record = try? await launchStore.record(id: launchRecordID),
           record.exit != nil {
            return
        }
        await withCheckedContinuation { continuation in
            exitWaiters[launchRecordID, default: []].append(continuation)
        }
    }

    public func launchRecord(
        id: String
    ) async throws -> GraphLocalProcessLaunchRecord? {
        try await launchStore.record(id: id)
    }

    public func logs(
        launchRecordID: String,
        channel: GraphProcessLogChannel? = nil,
        afterSequence: UInt64 = 0,
        limit: Int = 500
    ) async throws -> GraphProcessLogPage {
        guard let record = try await launchStore.record(id: launchRecordID) else {
            throw GraphLocalProcessRuntimeError
                .launchRecordMissing(launchRecordID)
        }
        return try logStore.read(
            indexURL: URL(fileURLWithPath: record.logIndexPath),
            channel: channel,
            afterSequence: afterSequence,
            limit: limit,
            redactionLabels: record.redactionLabels
        )
    }

    public func waitForLog(
        launchRecordID: String,
        containing text: String,
        timeout: TimeInterval = 5
    ) async throws -> Bool {
        guard let record = try await launchStore.record(id: launchRecordID) else {
            throw GraphLocalProcessRuntimeError
                .launchRecordMissing(launchRecordID)
        }
        let store = logStore
        let indexURL = URL(fileURLWithPath: record.logIndexPath)
        return await Task.detached {
            store.waitForText(
                indexURL: indexURL,
                containing: text,
                timeout: timeout
            )
        }.value
    }

    private func launch(
        _ context: GraphExecutorCommandContext,
        operation: GraphExecutorOperation
    ) async throws -> GraphExecutorObservation {
        do {
            let (resolved, existing) = try await resolvedRecord(
                context,
                createIfMissing: true
            )
            if existing.identity.process.processID != nil {
                let refreshed = try await refreshExitIfNeeded(existing)
                if refreshed.exit != nil {
                    return terminalOrRunningObservation(
                        operation: operation,
                        context: context,
                        resolved: resolved,
                        record: refreshed
                    )
                }
                let classification = inspector.classify(refreshed.identity)
                return classification == .matchingRunning
                    ? observation(
                        operation: operation,
                        status: .started,
                        context: context,
                        record: refreshed
                    )
                    : recoveryFailureObservation(
                        operation: operation,
                        classification: classification,
                        context: context,
                        record: refreshed
                    )
            }
            if crashPoint == .beforeSpawn {
                throw GraphExecutorAdapterError.simulatedCrash(
                    GraphLocalProcessCrashPoint.beforeSpawn.rawValue
                )
            }
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = resolved.executableURL
            process.arguments = resolved.arguments
            process.currentDirectoryURL = resolved.workingDirectoryURL
            process.environment = resolved.environment
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            configure(
                stdoutPipe.fileHandleForReading,
                channel: .stdout,
                record: existing,
                resolved: resolved
            )
            configure(
                stderrPipe.fileHandleForReading,
                channel: .stderr,
                record: existing,
                resolved: resolved
            )
            process.terminationHandler = { [weak self] terminated in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                let reason = terminated.terminationReason == .exit
                    ? "exit" : "uncaught_signal"
                Task {
                    await self?.didTerminate(
                        launchID: existing.id,
                        status: terminated.terminationStatus,
                        reason: reason
                    )
                }
            }
            try process.run()
            let pid = process.processIdentifier
            let processGroupID: Int32? = setpgid(pid, pid) == 0 ? pid : nil
            let snapshot = DarwinGraphProcessInspector.snapshot(pid: pid)
            let acceptedAt = Date(
                timeIntervalSince1970: floor(Date().timeIntervalSince1970)
            )
            let processIdentity = ProcessIdentity(
                hostID: capabilities.hostID ?? "localhost",
                launchID: existing.id,
                processID: pid,
                startedAt: acceptedAt
            )
            var durableIdentity = existing.identity
            durableIdentity = GraphDurableProcessIdentity(
                process: processIdentity,
                birthIdentity: snapshot?.birthIdentity,
                executablePath: snapshot?.executablePath
                    ?? resolved.executableURL.path,
                executableIdentity: existing.identity.executableIdentity,
                invocationDigest: existing.identity.invocationDigest,
                workspaceIdentity: existing.identity.workspaceIdentity,
                runID: existing.identity.runID,
                nodeID: existing.identity.nodeID,
                attemptID: existing.identity.attemptID,
                attemptOrdinal: existing.identity.attemptOrdinal,
                claimID: existing.identity.claimID,
                leaseGeneration: context.identity.leaseGeneration,
                executorID: existing.identity.executorID,
                executorInstanceID: executorInstanceID,
                processGroupID: processGroupID,
                launchRecordID: existing.id
            )
            let record = try await launchStore.update(id: existing.id) {
                $0.lifecycle = .running
                $0.identity = durableIdentity
                $0.acceptedAt = acceptedAt
            }
            processes[existing.id] = process
            if !process.isRunning {
                await didTerminate(
                    launchID: existing.id,
                    status: process.terminationStatus,
                    reason: process.terminationReason == .exit
                        ? "exit" : "uncaught_signal"
                )
            }
            if crashPoint == .afterSpawnAcceptance {
                throw GraphExecutorAdapterError.simulatedCrash(
                    GraphLocalProcessCrashPoint.afterSpawnAcceptance.rawValue
                )
            }
            return observation(
                operation: operation,
                status: .started,
                context: context,
                record: record
            )
        } catch let error as GraphExecutorAdapterError {
            throw error
        } catch {
            return rejected(operation: operation, context: context, error: error)
        }
    }

    private func configure(
        _ handle: FileHandle,
        channel: GraphProcessLogChannel,
        record: GraphLocalProcessLaunchRecord,
        resolved: GraphResolvedLocalProcessSpecification
    ) {
        let indexURL = URL(fileURLWithPath: record.logIndexPath)
        let streamPath = channel == .stdout
            ? record.stdoutLogPath : record.stderrLogPath
        let streamURL = URL(fileURLWithPath: streamPath)
        let maximumBytes = resolved.specification.logPolicy.maximumBytesPerStream
        let redactions = resolved.redactionValues
        let launchID = record.id
        let store = logStore
        handle.readabilityHandler = { readable in
            let data = readable.availableData
            guard !data.isEmpty else {
                readable.readabilityHandler = nil
                return
            }
            try? store.append(
                launchID: launchID,
                channel: channel,
                data: data,
                indexURL: indexURL,
                streamURL: streamURL,
                maximumBytes: maximumBytes,
                redactionValues: redactions
            )
        }
    }

    private func didTerminate(
        launchID: String,
        status: Int32,
        reason: String
    ) async {
        _ = try? await launchStore.update(id: launchID) { record in
            if record.exit == nil {
                record.lifecycle = .exited
                record.exit = GraphLocalProcessExitRecord(
                    terminationStatus: status,
                    terminationReason: reason,
                    observedAt: Date()
                )
            }
        }
        let waiters = exitWaiters.removeValue(forKey: launchID) ?? []
        waiters.forEach { $0.resume() }
    }

    private func resolvedRecord(
        _ context: GraphExecutorCommandContext,
        createIfMissing: Bool
    ) async throws -> (
        GraphResolvedLocalProcessSpecification,
        GraphLocalProcessLaunchRecord
    ) {
        let specification = try GraphLocalProcessSpecification(
            immutableSpecification: context.specification
        )
        let resolved = try GraphLocalProcessSpecificationResolver.resolve(
            specification,
            context: context
        )
        let launchID = Self.launchID(context.identity)
        let invocationDigest = try Self.invocationDigest(
            context: context,
            resolved: resolved
        )
        if var record = try await launchStore.record(id: launchID) {
            try validate(
                record,
                context: context,
                invocationDigest: invocationDigest
            )
            if context.identity.leaseGeneration > record.identity.leaseGeneration {
                record = try await launchStore.update(id: launchID) {
                    $0.identity.leaseGeneration = context.identity.leaseGeneration
                }
            }
            return (resolved, record)
        }
        guard createIfMissing else {
            throw GraphLocalProcessRuntimeError.launchRecordMissing(launchID)
        }
        let logDirectory = try await launchStore.logDirectory(id: launchID)
        let executableIdentity = try Self.executableIdentity(
            resolved.executableURL
        )
        let identity = GraphDurableProcessIdentity(
            process: ProcessIdentity(
                hostID: capabilities.hostID ?? "localhost",
                launchID: launchID
            ),
            birthIdentity: nil,
            executablePath: resolved.executableURL.path,
            executableIdentity: executableIdentity,
            invocationDigest: invocationDigest,
            workspaceIdentity: Self.digest(resolved.workspaceURL.path),
            runID: context.identity.runID,
            nodeID: context.identity.nodeID,
            attemptID: context.identity.attemptID,
            attemptOrdinal: context.identity.attemptOrdinal,
            claimID: context.identity.claimID,
            leaseGeneration: context.identity.leaseGeneration,
            executorID: context.identity.executorID,
            executorInstanceID: executorInstanceID,
            processGroupID: nil,
            launchRecordID: launchID
        )
        let record = GraphLocalProcessLaunchRecord(
            id: launchID,
            lifecycle: .prepared,
            identity: identity,
            preparedAt: context.logicalTime,
            stdoutLogPath: logDirectory
                .appendingPathComponent("stdout.log").path,
            stderrLogPath: logDirectory
                .appendingPathComponent("stderr.log").path,
            logIndexPath: logDirectory
                .appendingPathComponent("entries.jsonl").path,
            redactionLabels: specification.logPolicy.sensitiveEnvironmentKeys
        )
        try await launchStore.save(record)
        return (resolved, record)
    }

    private func validate(
        _ record: GraphLocalProcessLaunchRecord,
        context: GraphExecutorCommandContext,
        invocationDigest: String
    ) throws {
        let identity = record.identity
        guard identity.runID == context.identity.runID,
              identity.nodeID == context.identity.nodeID,
              identity.attemptID == context.identity.attemptID,
              identity.attemptOrdinal == context.identity.attemptOrdinal,
              identity.claimID == context.identity.claimID,
              identity.executorID == context.identity.executorID,
              identity.invocationDigest == invocationDigest else {
            throw GraphLocalProcessRuntimeError.launchRecordConflict(record.id)
        }
        guard context.identity.leaseGeneration >= identity.leaseGeneration else {
            throw GraphLocalProcessRuntimeError.staleLeaseGeneration(
                expectedAtLeast: identity.leaseGeneration,
                actual: context.identity.leaseGeneration
            )
        }
    }

    private func refreshExitIfNeeded(
        _ record: GraphLocalProcessLaunchRecord
    ) async throws -> GraphLocalProcessLaunchRecord {
        if record.exit != nil { return record }
        if let process = processes[record.id], !process.isRunning {
            await didTerminate(
                launchID: record.id,
                status: process.terminationStatus,
                reason: process.terminationReason == .exit
                    ? "exit" : "uncaught_signal"
            )
            return try await launchStore.record(id: record.id) ?? record
        }
        if processes[record.id] == nil,
           inspector.classify(record.identity) == .matchingExited {
            return try await launchStore.update(id: record.id) {
                $0.lifecycle = .exited
                $0.exit = GraphLocalProcessExitRecord(
                    terminationStatus: -1,
                    terminationReason: "exit_not_observed_after_restart",
                    observedAt: Date()
                )
            }
        }
        return record
    }

    private func signal(
        _ record: GraphLocalProcessLaunchRecord,
        signal: Int32
    ) throws {
        guard inspector.classify(record.identity) == .matchingRunning,
              let pid = record.identity.process.processID else {
            throw GraphLocalProcessRuntimeError.identityMismatch(record.id)
        }
        let result: Int32
        if let group = record.identity.processGroupID, group == pid {
            result = Darwin.kill(-group, signal)
        } else {
            result = Darwin.kill(pid, signal)
        }
        guard result == 0 || errno == ESRCH else {
            throw GraphLocalProcessRuntimeError.identityMismatch(record.id)
        }
    }

    private func terminalOrRunningObservation(
        operation: GraphExecutorOperation,
        context: GraphExecutorCommandContext,
        resolved: GraphResolvedLocalProcessSpecification,
        record: GraphLocalProcessLaunchRecord,
        cancellationTerminal: Bool = false
    ) -> GraphExecutorObservation {
        guard record.exit != nil else {
            let classification = inspector.classify(record.identity)
            return classification == .matchingRunning
                ? observation(
                    operation: operation,
                    status: .stillRunning,
                    context: context,
                    record: record
                )
                : recoveryFailureObservation(
                    operation: operation,
                    classification: classification,
                    context: context,
                    record: record
                )
        }
        if cancellationTerminal || record.cancellationRequestedAt != nil {
            return observation(
                operation: operation,
                status: .cancelled,
                context: context,
                record: record
            )
        }
        let terminal = terminalStatus(record: record, resolved: resolved)
        return observation(
            operation: operation,
            status: terminal.status,
            context: context,
            record: record,
            failure: terminal.failure
        )
    }

    private func terminalStatus(
        record: GraphLocalProcessLaunchRecord,
        resolved: GraphResolvedLocalProcessSpecification
    ) -> (status: GraphExecutorResponseStatus, failure: GraphExecutorFailure?) {
        guard let exit = record.exit else { return (.stillRunning, nil) }
        if record.cancellationRequestedAt != nil { return (.cancelled, nil) }
        if exit.terminationStatus == 0, exit.terminationReason == "exit" {
            return (.succeeded, nil)
        }
        if exit.terminationStatus == -1 {
            return (
                .interrupted,
                GraphExecutorFailure(
                    category: "process_exit_unobserved",
                    retryable: true
                )
            )
        }
        let retryable = resolved.specification.retryableExitCodes
            .contains(exit.terminationStatus)
        let category = exit.terminationReason == "uncaught_signal"
            ? "process_signal_\(exit.terminationStatus)"
            : "process_exit_\(exit.terminationStatus)"
        return (
            .failed,
            GraphExecutorFailure(category: category, retryable: retryable)
        )
    }

    private func recoveryFailureObservation(
        operation: GraphExecutorOperation,
        classification: GraphProcessRecoveryClassification,
        context: GraphExecutorCommandContext,
        record: GraphLocalProcessLaunchRecord
    ) -> GraphExecutorObservation {
        let status: GraphExecutorResponseStatus = classification == .identityMismatch
            ? .identityMismatch : .interrupted
        return observation(
            operation: operation,
            status: status,
            context: context,
            record: record,
            failure: GraphExecutorFailure(
                category: "process_\(classification.rawValue)",
                retryable: classification != .identityMismatch
            )
        )
    }

    private func collectDeclaredArtifacts(
        resolved: GraphResolvedLocalProcessSpecification
    ) throws -> [GraphExecutorProducedArtifact] {
        try resolved.specification.outputArtifacts.compactMap { declaration in
            guard let url = resolved.artifactURLs[declaration.role],
                  FileManager.default.fileExists(atPath: url.path) else {
                throw GraphLocalProcessRuntimeError
                    .artifactMissing(declaration.relativePath)
            }
            let attributes = try FileManager.default.attributesOfItem(
                atPath: url.path
            )
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size <= declaration.maximumBytes else {
                throw GraphLocalProcessRuntimeError.artifactTooLarge(
                    declaration.relativePath,
                    declaration.maximumBytes
                )
            }
            return try producedArtifact(
                url: url,
                mediaType: declaration.mediaType,
                role: declaration.role,
                sensitivity: declaration.sensitivity
            )
        }
    }

    private func collectLogs(
        record: GraphLocalProcessLaunchRecord
    ) throws -> [GraphExecutorProducedArtifact] {
        try [record.stdoutLogPath, record.stderrLogPath].compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                return nil
            }
            return try producedArtifact(
                url: url,
                mediaType: "text/plain; charset=utf-8",
                role: .executionLog,
                sensitivity: record.redactionLabels.isEmpty
                    ? .internalUse : .redacted
            )
        }
    }

    private func producedArtifact(
        url: URL,
        mediaType: String,
        role: GraphArtifactRole,
        sensitivity: GraphArtifactSensitivity
    ) throws -> GraphExecutorProducedArtifact {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return GraphExecutorProducedArtifact(
            contentDigest: GraphContentDigest(
                algorithm: "sha256",
                value: Self.digest(data)
            ),
            mediaType: mediaType,
            role: role,
            storage: GraphArtifactStorageLocator(
                scheme: "file",
                opaqueReference: url.standardizedFileURL.path
            ),
            sensitivity: sensitivity
        )
    }

    private func rejected(
        operation: GraphExecutorOperation,
        context: GraphExecutorCommandContext,
        error: Error
    ) -> GraphExecutorObservation {
        let status: GraphExecutorResponseStatus
        if case GraphLocalProcessRuntimeError.staleLeaseGeneration = error {
            status = .staleClaim
        } else if case GraphLocalProcessRuntimeError.identityMismatch = error {
            status = .identityMismatch
        } else {
            status = .rejected
        }
        return observation(
            operation: operation,
            status: status,
            context: context,
            failure: GraphExecutorFailure(
                category: error is GraphLocalProcessSpecificationError
                    ? "invalid_process_specification"
                    : "local_process_runtime_error",
                retryable: false
            )
        )
    }

    private func observation(
        operation: GraphExecutorOperation,
        status: GraphExecutorResponseStatus,
        context: GraphExecutorCommandContext,
        record: GraphLocalProcessLaunchRecord? = nil,
        failure: GraphExecutorFailure? = nil,
        artifacts: [GraphExecutorProducedArtifact] = []
    ) -> GraphExecutorObservation {
        let material = [
            context.identity.runID,
            context.identity.nodeID,
            context.identity.attemptID,
            context.identity.claimID,
            String(context.identity.leaseGeneration),
            operation.rawValue,
            String(context.priorObservationCount),
            status.rawValue,
            record?.exit.map { "\($0.terminationReason):\($0.terminationStatus)" }
                ?? "active",
        ].joined(separator: "|")
        return GraphExecutorObservation(
            id: "local-\(DefaultGraphMutationService.stableID(material))",
            operation: operation,
            identity: context.identity,
            status: status,
            observedAt: context.logicalTime,
            processIdentity: record?.identity.process.processID == nil
                ? nil : record?.identity.process,
            failure: failure,
            artifacts: artifacts
        )
    }

    public nonisolated static func launchID(
        _ identity: GraphExecutorInteractionIdentity
    ) -> String {
        let material = [
            identity.runID,
            identity.nodeID,
            identity.attemptID,
            String(identity.attemptOrdinal),
            identity.claimID,
            identity.executorID,
        ].joined(separator: "|")
        return "launch-\(DefaultGraphMutationService.stableID(material))"
    }

    private static func invocationDigest(
        context: GraphExecutorCommandContext,
        resolved: GraphResolvedLocalProcessSpecification
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let specData = try encoder.encode(context.specification)
        let material = [
            specData.base64EncodedString(),
            resolved.executableURL.path,
            resolved.workingDirectoryURL.path,
            resolved.arguments.joined(separator: "\u{0}"),
            context.inputArtifacts.map {
                "\($0.logicalRole):\($0.contentDigest.value)"
            }.sorted().joined(separator: "|"),
        ].joined(separator: "|")
        return digest(material)
    }

    private static func executableIdentity(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let material = [
            url.standardizedFileURL.path,
            String(describing: attributes[.systemNumber] ?? ""),
            String(describing: attributes[.systemFileNumber] ?? ""),
            String(describing: attributes[.size] ?? ""),
            String(describing: attributes[.modificationDate] ?? ""),
        ].joined(separator: "|")
        return digest(material)
    }

    private static func digest(_ value: String) -> String {
        digest(Data(value.utf8))
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
