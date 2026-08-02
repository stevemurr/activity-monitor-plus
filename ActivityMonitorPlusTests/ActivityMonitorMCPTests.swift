import Foundation
import LocalMCPConsumer
import LocalMCPContracts
import LocalMCPDiscovery
import LocalMCPProducer
import LocalMCPTesting
import XCTest
@testable import ActivityMonitorPlus

final class ActivityMonitorMCPDefinitionTests: XCTestCase {
    func testDefinitionsPublishReadOnlyBoundedContractsAndRegister() async throws {
        let status = ActivityMonitorStatusCommandHandler.definition
        let cpu = ActivityMonitorCPUProcessesCommandHandler.definition
        let network = ActivityMonitorNetworkProcessesCommandHandler.definition
        let disks = ActivityMonitorDisksCommandHandler.definition
        let definitions = [status, cpu, network, disks]
        let readOnly = CommandAnnotations(
            readOnly: true,
            idempotent: true,
            destructive: false,
            openWorld: false
        )

        XCTAssertEqual(definitions.map(\.name), [
            "activity_monitor.status",
            "activity_monitor.cpu_processes",
            "activity_monitor.network_processes",
            "activity_monitor.disks",
        ])
        XCTAssertTrue(definitions.allSatisfy(\.isValid))
        XCTAssertTrue(definitions.allSatisfy { $0.annotations == readOnly })

        XCTAssertEqual(status.inputSchema["additionalProperties"], .bool(false))
        XCTAssertEqual(status.outputSchema?["required"], .array([
            .string("ready"), .string("stale"), .string("cpu"),
            .string("network"), .string("processCount"), .string("diskCount"),
        ]))
        XCTAssertEqual(
            status.outputSchema?["properties"]?["cpu"]?["properties"]?["totalPercent"]?["maximum"],
            .integer(100)
        )

        XCTAssertEqual(
            cpu.inputSchema["properties"]?["query"]?["maxLength"],
            .integer(Int64(ActivityMonitorMCPLimits.maximumQueryLength))
        )
        XCTAssertEqual(
            cpu.inputSchema["properties"]?["limit"]?["maximum"],
            .integer(Int64(ActivityMonitorMCPLimits.maximumLimit))
        )
        XCTAssertEqual(
            cpu.inputSchema["properties"]?["sortBy"]?["enum"],
            .array([.string("cpu"), .string("memory"), .string("name"), .string("pid")])
        )
        XCTAssertEqual(
            cpu.outputSchema?["properties"]?["processes"]?["maxItems"],
            .integer(Int64(ActivityMonitorMCPLimits.maximumLimit))
        )

        XCTAssertEqual(
            network.inputSchema["properties"]?["connectionsPerProcess"]?["minimum"],
            .integer(0)
        )
        XCTAssertEqual(
            network.inputSchema["properties"]?["connectionsPerProcess"]?["maximum"],
            .integer(Int64(ActivityMonitorMCPLimits.maximumConnectionsPerProcess))
        )
        XCTAssertEqual(
            network.outputSchema?["properties"]?["processes"]?["items"]?["properties"]?["connections"]?["maxItems"],
            .integer(Int64(ActivityMonitorMCPLimits.maximumConnectionsPerProcess))
        )

        XCTAssertEqual(disks.inputSchema["additionalProperties"], .bool(false))
        XCTAssertEqual(
            disks.outputSchema?["properties"]?["disks"]?["maxItems"],
            .integer(Int64(ActivityMonitorMCPLimits.maximumLimit))
        )

        // Registration exercises LocalMCPKit's supported-schema validation as
        // well as each command's typed input signature.
        let registry = CommandRegistry()
        try await registry.register(status) {
            (_: ActivityMonitorMCPEmptyInput, _: CommandContext) async throws in
            CommandResult.text("ok")
        }
        try await registry.register(cpu) {
            (_: ActivityMonitorMCPCPUProcessesInput, _: CommandContext) async throws in
            CommandResult.text("ok")
        }
        try await registry.register(network) {
            (_: ActivityMonitorMCPNetworkProcessesInput, _: CommandContext) async throws in
            CommandResult.text("ok")
        }
        try await registry.register(disks) {
            (_: ActivityMonitorMCPDisksInput, _: CommandContext) async throws in
            CommandResult.text("ok")
        }

        let registered = await registry.definitions()
        XCTAssertEqual(registered.map(\.name), [
            "activity_monitor.cpu_processes",
            "activity_monitor.disks",
            "activity_monitor.network_processes",
            "activity_monitor.status",
        ])
    }
}

final class ActivityMonitorMCPCommandTests: XCTestCase {
    func testStatusReturnsTheProviderSnapshotAndReadinessGuidance() async throws {
        let fixture = FixtureActivityMonitorMCPData.standard
        let handler = ActivityMonitorStatusCommandHandler(data: fixture)

        let sampled = try await handler.call(
            input: ActivityMonitorMCPEmptyInput(),
            context: activityMonitorCommandContext()
        )
        let sampledOutput = try sampled.decode(as: ActivityMonitorMCPStatusOutput.self)
        XCTAssertEqual(sampledOutput, fixture.statusOutput)
        XCTAssertEqual(sampled.text, "System status sampled successfully.")
        XCTAssertFalse(sampled.isError)

        var collectingFixture = fixture
        collectingFixture.statusOutput.ready = false
        collectingFixture.statusOutput.sampledAt = nil
        collectingFixture.statusOutput.sampleAgeSeconds = nil
        let collecting = try await ActivityMonitorStatusCommandHandler(data: collectingFixture).call(
            input: ActivityMonitorMCPEmptyInput(),
            context: activityMonitorCommandContext()
        )
        let collectingOutput = try collecting.decode(as: ActivityMonitorMCPStatusOutput.self)
        XCTAssertFalse(collectingOutput.ready)
        XCTAssertEqual(
            collecting.text,
            "Activity Monitor Plus is still collecting its first system sample."
        )
    }

    func testCPUProcessesFilterSortLimitAndReportTotalMatches() async throws {
        let fixture = FixtureActivityMonitorMCPData.standard
        let handler = ActivityMonitorCPUProcessesCommandHandler(data: fixture)

        let result = try await handler.call(
            input: ActivityMonitorMCPCPUProcessesInput(
                query: "  XCODE  ",
                minimumCPUPercent: 40,
                sortBy: .memory,
                limit: 1
            ),
            context: activityMonitorCommandContext()
        )
        let output = try result.decode(as: ActivityMonitorMCPCPUProcessesOutput.self)
        XCTAssertTrue(output.ready)
        XCTAssertEqual(output.sampledAt, fixture.cpuSnapshot.sampledAt)
        XCTAssertEqual(output.totalMatches, 2)
        XCTAssertEqual(output.processes.map(\.pid), [41])
        XCTAssertEqual(output.processes.first?.name, "xcodebuild")
        XCTAssertEqual(result.text, "Found 2 matching CPU processes; returned 1.")

        let pidQuery = try await handler.call(
            input: ActivityMonitorMCPCPUProcessesInput(query: "7", sortBy: .pid),
            context: activityMonitorCommandContext()
        )
        let pidOutput = try pidQuery.decode(as: ActivityMonitorMCPCPUProcessesOutput.self)
        XCTAssertEqual(pidOutput.totalMatches, 1)
        XCTAssertEqual(pidOutput.processes.map(\.name), ["Safari"])

        let exactPID = try await handler.call(
            input: ActivityMonitorMCPCPUProcessesInput(pid: 42, sortBy: .name),
            context: activityMonitorCommandContext()
        )
        XCTAssertEqual(
            try exactPID.decode(as: ActivityMonitorMCPCPUProcessesOutput.self).processes.map(\.pid),
            [42]
        )
    }

    func testCPUProcessesApplyDefaultLimitAndRejectInvalidBounds() async throws {
        var fixture = FixtureActivityMonitorMCPData.standard
        fixture.cpuSnapshot.processes = (0..<30).map { index in
            ActivityMonitorMCPCPUProcess(
                pid: Int32(index + 1),
                name: "Process \(index)",
                cpuPercent: Double(100 - index),
                residentBytes: UInt64(index)
            )
        }
        let handler = ActivityMonitorCPUProcessesCommandHandler(data: fixture)
        let defaultResult = try await handler.call(
            input: ActivityMonitorMCPCPUProcessesInput(),
            context: activityMonitorCommandContext()
        )
        let defaultOutput = try defaultResult.decode(as: ActivityMonitorMCPCPUProcessesOutput.self)
        XCTAssertEqual(defaultOutput.totalMatches, 30)
        XCTAssertEqual(defaultOutput.processes.count, ActivityMonitorMCPLimits.defaultLimit)

        fixture.cpuSnapshot.processes = [
            ActivityMonitorMCPCPUProcess(
                pid: 1,
                name: "unreadable",
                cpuPercent: 1,
                residentBytes: nil
            ),
            ActivityMonitorMCPCPUProcess(
                pid: 2,
                name: "zero-resident",
                cpuPercent: 1,
                residentBytes: 0
            ),
        ]
        let memorySorted = try await ActivityMonitorCPUProcessesCommandHandler(data: fixture).call(
            input: ActivityMonitorMCPCPUProcessesInput(sortBy: .memory),
            context: activityMonitorCommandContext()
        )
        XCTAssertEqual(
            try memorySorted.decode(as: ActivityMonitorMCPCPUProcessesOutput.self)
                .processes.map(\.pid),
            [2, 1],
            "A measured zero resident-byte count must sort ahead of unavailable data"
        )

        await assertActivityMonitorInvalidInput {
            try await handler.call(
                input: ActivityMonitorMCPCPUProcessesInput(
                    query: String(
                        repeating: "e\u{301}",
                        count: ActivityMonitorMCPLimits.maximumQueryLength / 2 + 1
                    )
                ),
                context: activityMonitorCommandContext()
            )
        }
        for invalidLimit in [0, -1, ActivityMonitorMCPLimits.maximumLimit + 1, Int.max] {
            await assertActivityMonitorInvalidInput {
                try await handler.call(
                    input: ActivityMonitorMCPCPUProcessesInput(limit: invalidLimit),
                    context: activityMonitorCommandContext()
                )
            }
        }
        for invalidMinimum in [-1.0, 100.1, .infinity, .nan] {
            await assertActivityMonitorInvalidInput {
                try await handler.call(
                    input: ActivityMonitorMCPCPUProcessesInput(
                        minimumCPUPercent: invalidMinimum
                    ),
                    context: activityMonitorCommandContext()
                )
            }
        }
        await assertActivityMonitorInvalidInput {
            try await handler.call(
                input: ActivityMonitorMCPCPUProcessesInput(pid: -1),
                context: activityMonitorCommandContext()
            )
        }
    }

    func testNetworkProcessesFilterEndpointsSortAndBoundDetails() async throws {
        var fixture = FixtureActivityMonitorMCPData.standard
        // Put the matching endpoint last to prove a bounded response promotes
        // the detail that caused the process to match.
        let originalConnections = fixture.networkSnapshot.processes[0].connections
        fixture.networkSnapshot.processes[0].connections = [
            originalConnections[1], originalConnections[2], originalConnections[0],
        ]
        let handler = ActivityMonitorNetworkProcessesCommandHandler(data: fixture)

        let endpointResult = try await handler.call(
            input: ActivityMonitorMCPNetworkProcessesInput(
                query: "  API.EXAMPLE  ",
                limit: 1,
                connectionsPerProcess: 1
            ),
            context: activityMonitorCommandContext()
        )
        let endpointOutput = try endpointResult.decode(
            as: ActivityMonitorMCPNetworkProcessesOutput.self
        )
        XCTAssertEqual(endpointOutput.throughput, fixture.networkSnapshot.throughput)
        XCTAssertEqual(endpointOutput.totalMatches, 1)
        XCTAssertEqual(endpointOutput.processes.map(\.pid), [300])
        XCTAssertEqual(endpointOutput.processes.first?.connectionCount, 3)
        XCTAssertEqual(endpointOutput.processes.first?.connections.count, 1)
        XCTAssertEqual(
            endpointOutput.processes.first?.connections.first?.remoteEndpoint,
            "api.example:443"
        )
        XCTAssertEqual(endpointResult.text, "Found 1 matching network process; returned 1.")

        let summaries = try await handler.call(
            input: ActivityMonitorMCPNetworkProcessesInput(
                limit: 2,
                connectionsPerProcess: 0
            ),
            context: activityMonitorCommandContext()
        )
        let summaryOutput = try summaries.decode(
            as: ActivityMonitorMCPNetworkProcessesOutput.self
        )
        XCTAssertEqual(summaryOutput.totalMatches, 3)
        XCTAssertEqual(summaryOutput.processes.map(\.pid), [200, 300])
        XCTAssertTrue(summaryOutput.processes.allSatisfy(\.connections.isEmpty))

        let pidResult = try await handler.call(
            input: ActivityMonitorMCPNetworkProcessesInput(pid: 100),
            context: activityMonitorCommandContext()
        )
        XCTAssertEqual(
            try pidResult.decode(as: ActivityMonitorMCPNetworkProcessesOutput.self)
                .processes.map(\.name),
            ["syncd"]
        )
    }

    func testNetworkProcessesRejectInvalidBounds() async {
        let handler = ActivityMonitorNetworkProcessesCommandHandler(
            data: FixtureActivityMonitorMCPData.standard
        )
        await assertActivityMonitorInvalidInput {
            try await handler.call(
                input: ActivityMonitorMCPNetworkProcessesInput(
                    query: String(
                        repeating: "é",
                        count: ActivityMonitorMCPLimits.maximumQueryLength + 1
                    )
                ),
                context: activityMonitorCommandContext()
            )
        }
        for invalidLimit in [0, ActivityMonitorMCPLimits.maximumLimit + 1] {
            await assertActivityMonitorInvalidInput {
                try await handler.call(
                    input: ActivityMonitorMCPNetworkProcessesInput(limit: invalidLimit),
                    context: activityMonitorCommandContext()
                )
            }
        }
        for invalidConnectionLimit in [
            -1,
            ActivityMonitorMCPLimits.maximumConnectionsPerProcess + 1,
        ] {
            await assertActivityMonitorInvalidInput {
                try await handler.call(
                    input: ActivityMonitorMCPNetworkProcessesInput(
                        connectionsPerProcess: invalidConnectionLimit
                    ),
                    context: activityMonitorCommandContext()
                )
            }
        }
        await assertActivityMonitorInvalidInput {
            try await handler.call(
                input: ActivityMonitorMCPNetworkProcessesInput(pid: -1),
                context: activityMonitorCommandContext()
            )
        }
    }

    func testDisksFilterSortLimitAndRejectInvalidBounds() async throws {
        let fixture = FixtureActivityMonitorMCPData.standard
        let handler = ActivityMonitorDisksCommandHandler(data: fixture)
        let result = try await handler.call(
            input: ActivityMonitorMCPDisksInput(query: "  data  ", limit: 1),
            context: activityMonitorCommandContext()
        )
        let output = try result.decode(as: ActivityMonitorMCPDisksOutput.self)
        XCTAssertTrue(output.ready)
        XCTAssertEqual(output.sampledAt, fixture.diskSnapshotValue.sampledAt)
        XCTAssertEqual(output.totalMatches, 2)
        XCTAssertEqual(output.disks.map(\.path), ["/Volumes/Data-Archive"])
        XCTAssertEqual(output.disks.first?.usedBytes, 600)
        XCTAssertEqual(output.disks.first?.usedPercent, 60)
        XCTAssertEqual(result.text, "Found 2 matching disks; returned 1.")

        let byPath = try await handler.call(
            input: ActivityMonitorMCPDisksInput(query: "/volumes/external"),
            context: activityMonitorCommandContext()
        )
        XCTAssertEqual(
            try byPath.decode(as: ActivityMonitorMCPDisksOutput.self).disks.map(\.name),
            ["Media"]
        )

        await assertActivityMonitorInvalidInput {
            try await handler.call(
                input: ActivityMonitorMCPDisksInput(
                    query: String(
                        repeating: "é",
                        count: ActivityMonitorMCPLimits.maximumQueryLength + 1
                    )
                ),
                context: activityMonitorCommandContext()
            )
        }
        for invalidLimit in [0, -1, ActivityMonitorMCPLimits.maximumLimit + 1] {
            await assertActivityMonitorInvalidInput {
                try await handler.call(
                    input: ActivityMonitorMCPDisksInput(limit: invalidLimit),
                    context: activityMonitorCommandContext()
                )
            }
        }
    }
}

final class ActivityMonitorMCPLiveRuntimeTests: XCTestCase {
    func testLiveRuntimeDoesNotAdvertiseWhenGrantStorageIsUnavailable() async throws {
        let catalog = DiscoveryCatalog()
        let grantStore = UnavailableActivityMonitorProducerGrantStore()
        let producer = LocalMCPProducer(
            identity: ProducerIdentity(
                stableID: ActivityMonitorMCPRuntimeFactory.producerID,
                displayName: "Activity Monitor Plus",
                version: "1.0.0"
            ),
            instanceID: "3c9b77fe-618a-4d24-a4be-0eeb94bcc433",
            transport: LocalMCPHTTPProducerTransport(),
            advertiser: catalog,
            grantStore: grantStore,
            approval: RecordingPairingApprover()
        )
        let runtime = LiveActivityMonitorMCPRuntime(
            producer: producer,
            data: FixtureActivityMonitorMCPData.standard,
            grantStore: grantStore
        )

        do {
            try await runtime.start()
            XCTFail("An unusable grant store must prevent producer startup")
        } catch let error as LocalMCPError {
            XCTAssertEqual(error, .credentialStoreFailed)
        }
        let advertisedInstances = await catalog.snapshot()
        XCTAssertTrue(advertisedInstances.isEmpty)
        await runtime.stop()
    }

    func testLiveRuntimeServesAllActivityMonitorCommandsOverHTTPAndRestarts() async throws {
        let fixture = FixtureActivityMonitorMCPData.standard
        let catalog = DiscoveryCatalog()
        let grantStore = InMemoryProducerGrantStore()
        let producer = LocalMCPProducer(
            identity: ProducerIdentity(
                stableID: ActivityMonitorMCPRuntimeFactory.producerID,
                displayName: "Activity Monitor Plus",
                version: "1.0.0"
            ),
            instanceID: "90a8ad3c-cce2-4c8d-975e-69bd9db16ee8",
            transport: LocalMCPHTTPProducerTransport(),
            advertiser: catalog,
            grantStore: grantStore,
            approval: RecordingPairingApprover(),
            random: SequenceRandomBytesGenerator(fallback: 40)
        )
        let runtime = LiveActivityMonitorMCPRuntime(
            producer: producer,
            data: fixture,
            grantStore: grantStore
        )

        do {
            // Concurrent callers must coalesce the multi-command registration
            // and the producer's idempotent start lifecycle.
            async let firstStart: Void = runtime.start()
            async let secondStart: Void = runtime.start()
            _ = try await (firstStart, secondStart)
            try await exerciseLiveActivityMonitorRuntime(
                catalog: catalog,
                expected: fixture,
                consumerRandomFallback: 80
            )
            await runtime.stop()
            let firstStoppedSnapshot = await catalog.snapshot()
            XCTAssertTrue(firstStoppedSnapshot.isEmpty)

            // A second start must reuse the command registrations while
            // publishing a fresh endpoint.
            try await runtime.start()
            try await exerciseLiveActivityMonitorRuntime(
                catalog: catalog,
                expected: fixture,
                consumerRandomFallback: 120
            )
            await runtime.stop()
            let secondStoppedSnapshot = await catalog.snapshot()
            XCTAssertTrue(secondStoppedSnapshot.isEmpty)
        } catch {
            await runtime.stop()
            throw error
        }
    }

    private func exerciseLiveActivityMonitorRuntime(
        catalog: DiscoveryCatalog,
        expected: FixtureActivityMonitorMCPData,
        consumerRandomFallback: UInt8
    ) async throws {
        let instances = await catalog.snapshot()
        let instance = try XCTUnwrap(instances.first)
        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(instance.identity.stableID, ActivityMonitorMCPRuntimeFactory.producerID)

        let consumer = LocalMCPConsumer(
            instance: instance,
            identity: ConsumerIdentity(
                stableID: "com.example.activity-monitor-test-consumer",
                displayName: "Activity Monitor Test Consumer",
                version: "1.0.0",
                installationID: "8ab68c14-eef4-4661-a942-1c93f9a2ed42"
            ),
            connector: LocalMCPHTTPConnector(),
            grantStore: InMemoryConsumerGrantStore(),
            random: SequenceRandomBytesGenerator(fallback: consumerRandomFallback)
        )
        let grant = try await consumer.pair()
        let tools = try await consumer.listTools(grant: grant)
        XCTAssertEqual(tools.map(\.name), [
            "activity_monitor.cpu_processes",
            "activity_monitor.disks",
            "activity_monitor.network_processes",
            "activity_monitor.status",
        ])

        let status: ActivityMonitorMCPStatusOutput = try await consumer.call(
            "activity_monitor.status",
            input: ActivityMonitorMCPEmptyInput(),
            as: ActivityMonitorMCPStatusOutput.self,
            grant: grant
        )
        XCTAssertEqual(status, expected.statusOutput)

        let cpu: ActivityMonitorMCPCPUProcessesOutput = try await consumer.call(
            "activity_monitor.cpu_processes",
            input: ActivityMonitorMCPCPUProcessesInput(
                query: "Xcode",
                minimumCPUPercent: 40,
                sortBy: .cpu,
                limit: 5
            ),
            as: ActivityMonitorMCPCPUProcessesOutput.self,
            grant: grant
        )
        XCTAssertEqual(cpu.totalMatches, 2)
        XCTAssertEqual(cpu.processes.map(\.pid), [42, 41])

        let network: ActivityMonitorMCPNetworkProcessesOutput = try await consumer.call(
            "activity_monitor.network_processes",
            input: ActivityMonitorMCPNetworkProcessesInput(
                query: "api.example",
                connectionsPerProcess: 1
            ),
            as: ActivityMonitorMCPNetworkProcessesOutput.self,
            grant: grant
        )
        XCTAssertEqual(network.totalMatches, 1)
        XCTAssertEqual(network.processes.first?.pid, 300)
        XCTAssertEqual(network.processes.first?.connections.count, 1)

        let disks: ActivityMonitorMCPDisksOutput = try await consumer.call(
            "activity_monitor.disks",
            input: ActivityMonitorMCPDisksInput(query: "Data", limit: 5),
            as: ActivityMonitorMCPDisksOutput.self,
            grant: grant
        )
        XCTAssertEqual(disks.totalMatches, 2)
        XCTAssertEqual(disks.disks.map(\.path), [
            "/Volumes/Data-Archive",
            "/Volumes/Data-Backup",
        ])

        await consumer.close()
    }
}

private struct UnavailableActivityMonitorProducerGrantStore: ProducerGrantStoring {
    func stagePendingGrant(_ record: ProducerGrantRecord) async throws {
        throw LocalMCPError.credentialStoreFailed
    }

    func activatePendingGrant(
        matching digest: CredentialDigest,
        binding: AuthorizationEndpointBinding?
    ) async throws -> ProducerGrantRecord? {
        throw LocalMCPError.credentialStoreFailed
    }

    func saveReplacingActiveGrant(_ record: ProducerGrantRecord) async throws {
        throw LocalMCPError.credentialStoreFailed
    }

    func record(matching digest: CredentialDigest) async throws -> ProducerGrantRecord? {
        throw LocalMCPError.credentialStoreFailed
    }

    func record(grantID: String) async throws -> ProducerGrantRecord? {
        throw LocalMCPError.credentialStoreFailed
    }

    func records() async throws -> [ProducerGrantRecord] {
        throw LocalMCPError.credentialStoreFailed
    }

    func remove(grantID: String) async throws {
        throw LocalMCPError.credentialStoreFailed
    }
}

@MainActor
final class ActivityMonitorMCPBridgeTests: XCTestCase {
    func testBridgeMapsFixtureSamplesAndLiveSocketAvailability() async {
        var samplers = SamplerSet.fixtures()
        samplers.makeConnections = { FixedActivityMonitorConnectionProvider() }
        let model = AppModel(samplers: samplers, autoStart: false)
        model.start()
        for _ in 0..<200 {
            if model.lastUpdate != .distantPast { break }
            try? await Task.sleep(for: .milliseconds(10))
        }

        let bridge = AppModelMCPBridge(model: model)
        let status = await bridge.status()
        let cpu = await bridge.cpuProcessSnapshot()
        let network = await bridge.networkProcessSnapshot()
        let disks = await bridge.diskSnapshot()

        XCTAssertTrue(status.ready)
        XCTAssertFalse(status.stale)
        XCTAssertEqual(status.cpu.totalPercent, 62, accuracy: 0.0001)
        XCTAssertEqual(status.memory?.usedBytes, 18_000_000_000)
        XCTAssertEqual(status.network.activeConnectionCount, 3)
        XCTAssertEqual(status.processCount, 7)
        XCTAssertEqual(status.diskCount, 2)

        XCTAssertEqual(cpu.processes.first?.name, "FixtureProcA")
        XCTAssertEqual(cpu.processes.first?.cpuPercent ?? -1, 30, accuracy: 0.0001)

        let mixed = network.processes.first { $0.pid == 4242 }
        XCTAssertEqual(mixed?.connectionCount, 2, "duplicate socket keys must collapse")
        XCTAssertEqual(mixed?.tcpConnectionCount, 1)
        XCTAssertEqual(mixed?.udpConnectionCount, 1)
        XCTAssertEqual(mixed?.byteCountersAvailable, false)
        XCTAssertNil(mixed?.receivedBytes, "partial aggregate counters must not mislead")
        XCTAssertEqual(mixed?.connections.first?.remoteEndpoint, "api.example.443")
        XCTAssertEqual(mixed?.connections.first?.receivedBytes, 500)

        XCTAssertEqual(disks.disks.map(\.name), ["Fixture HD", "Fixture External"])
        XCTAssertEqual(disks.disks.first?.usedBytes, 300_000_000_000)

        await model.shutdown()
    }
}

@MainActor
final class ActivityMonitorMCPControllerTests: XCTestCase {
    func testDisabledStartEnableDisableAndShutdownDriveRuntimeLifecycle() async {
        let defaults = isolatedActivityMonitorDefaults()
        let runtime = RecordingActivityMonitorMCPRuntime()
        let controller = ActivityMonitorMCPController(runtime: runtime, defaults: defaults)

        XCTAssertFalse(controller.isEnabled)
        controller.startAfterMonitoringReady()
        await controller.waitForTransitions()
        XCTAssertEqual(controller.status, .stopped)

        controller.setEnabled(true)
        await controller.waitForTransitions()
        XCTAssertEqual(controller.status, .running)
        XCTAssertTrue(defaults.bool(forKey: ActivityMonitorMCPController.enabledDefaultsKey))

        controller.setEnabled(false)
        await controller.waitForTransitions()
        XCTAssertEqual(controller.status, .stopped)
        XCTAssertFalse(defaults.bool(forKey: ActivityMonitorMCPController.enabledDefaultsKey))

        await controller.shutdown()
        XCTAssertEqual(controller.status, .stopped)
        let events = await runtime.events
        XCTAssertEqual(events, ["stop", "start", "stop", "stop"])
    }

    func testControllerLoadsAndRevokesGrantAndKeepsDiagnosticsMetadataOnly() async throws {
        let metadata = activityMonitorGrantMetadata()
        let defaults = isolatedActivityMonitorDefaults()
        defaults.set(true, forKey: ActivityMonitorMCPController.enabledDefaultsKey)
        let runtime = RecordingActivityMonitorMCPRuntime(grants: [metadata])
        let controller = ActivityMonitorMCPController(runtime: runtime, defaults: defaults)

        controller.startAfterMonitoringReady()
        await controller.waitForTransitions()
        let grant = try XCTUnwrap(controller.grants.first)
        XCTAssertEqual(grant.consumerName, "Example Consumer")
        XCTAssertEqual(grant.installationSuffix, "00000042")

        controller.revoke(grantID: grant.id)
        for _ in 0..<100 where controller.grants.first?.revokedAt == nil {
            await Task.yield()
        }
        XCTAssertNotNil(controller.grants.first?.revokedAt)
        XCTAssertFalse(controller.revokingGrantIDs.contains(grant.id))
        XCTAssertTrue(controller.diagnostics.contains("Unrevoked grants: 0"))
        XCTAssertTrue(controller.diagnostics.contains("Revoked grants: 1"))
        XCTAssertFalse(controller.diagnostics.contains("00000000-0000-0000-0000-000000000042"))

        await controller.shutdown()
    }

    func testFailedStartDisablesPreferenceAndPreservesStartupDiagnostic() async {
        let defaults = isolatedActivityMonitorDefaults()
        defaults.set(true, forKey: ActivityMonitorMCPController.enabledDefaultsKey)
        let controller = ActivityMonitorMCPController(
            runtime: FailingActivityMonitorMCPRuntime(),
            defaults: defaults
        )

        controller.startAfterMonitoringReady()
        await controller.waitForTransitions()

        XCTAssertEqual(controller.status, .failed)
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: ActivityMonitorMCPController.enabledDefaultsKey))
        XCTAssertTrue(controller.diagnostics.contains("Last issue: listener_start_failed"))

        await controller.shutdown()
    }

    func testRapidDisableAndReenableConvergesOnRunningRuntime() async {
        let defaults = isolatedActivityMonitorDefaults()
        let runtime = GatedStartActivityMonitorMCPRuntime()
        let controller = ActivityMonitorMCPController(runtime: runtime, defaults: defaults)
        controller.startAfterMonitoringReady()
        await controller.waitForTransitions()

        controller.setEnabled(true)
        for _ in 0..<1_000 {
            if await runtime.startCallCount > 0 { break }
            await Task.yield()
        }
        let firstStartCount = await runtime.startCallCount
        XCTAssertEqual(firstStartCount, 1)

        controller.setEnabled(false)
        controller.setEnabled(true)
        await runtime.openStartGate()
        await controller.waitForTransitions()

        XCTAssertEqual(controller.status, .running)
        XCTAssertTrue(controller.isEnabled)
        let isRunning = await runtime.isRunning
        let finalStartCount = await runtime.startCallCount
        XCTAssertTrue(isRunning)
        XCTAssertEqual(finalStartCount, 2)

        await controller.shutdown()
    }

    func testShutdownDrainsAnInFlightGrantRevocationBeforeStopping() async throws {
        let defaults = isolatedActivityMonitorDefaults()
        defaults.set(true, forKey: ActivityMonitorMCPController.enabledDefaultsKey)
        let runtime = GatedRevokeActivityMonitorMCPRuntime(
            grant: activityMonitorGrantMetadata()
        )
        let controller = ActivityMonitorMCPController(runtime: runtime, defaults: defaults)
        controller.startAfterMonitoringReady()
        await controller.waitForTransitions()
        let grantID = try XCTUnwrap(controller.grants.first?.id)

        controller.revoke(grantID: grantID)
        for _ in 0..<1_000 {
            if await runtime.revokeDidStart { break }
            await Task.yield()
        }
        let revokeDidStart = await runtime.revokeDidStart
        XCTAssertTrue(revokeDidStart)

        let shutdown = Task { @MainActor in
            await controller.shutdown()
        }
        await Task.yield()
        let stoppedBeforeRevoke = await runtime.stopDidRun
        XCTAssertFalse(stoppedBeforeRevoke)

        await runtime.finishRevoke()
        await shutdown.value
        let stoppedAfterRevoke = await runtime.stopDidRun
        let revokedAt = await runtime.revokedAt
        XCTAssertTrue(stoppedAfterRevoke)
        XCTAssertNotNil(revokedAt)
    }
}

private struct FixtureActivityMonitorMCPData: ActivityMonitorMCPDataProviding {
    var statusOutput: ActivityMonitorMCPStatusOutput
    var cpuSnapshot: ActivityMonitorMCPCPUProcessSnapshot
    var networkSnapshot: ActivityMonitorMCPNetworkProcessSnapshot
    var diskSnapshotValue: ActivityMonitorMCPDiskSnapshot

    func status() async -> ActivityMonitorMCPStatusOutput { statusOutput }

    func cpuProcessSnapshot() async -> ActivityMonitorMCPCPUProcessSnapshot {
        cpuSnapshot
    }

    func networkProcessSnapshot() async -> ActivityMonitorMCPNetworkProcessSnapshot {
        networkSnapshot
    }

    func diskSnapshot() async -> ActivityMonitorMCPDiskSnapshot { diskSnapshotValue }

    static let standard = FixtureActivityMonitorMCPData(
        statusOutput: ActivityMonitorMCPStatusOutput(
            ready: true,
            stale: false,
            sampledAt: "2026-08-01T19:00:00.000Z",
            sampleAgeSeconds: 0.25,
            cpu: ActivityMonitorMCPCPUStatus(
                totalPercent: 45,
                userPercent: 30,
                systemPercent: 15,
                idlePercent: 55,
                coreCount: 10
            ),
            memory: ActivityMonitorMCPMemoryStatus(
                totalBytes: 1_000,
                appBytes: 300,
                wiredBytes: 100,
                compressedBytes: 50,
                usedBytes: 450,
                freeBytes: 550,
                usedPercent: 45
            ),
            network: ActivityMonitorMCPNetworkStatus(
                bytesInPerSecond: 1_250,
                bytesOutPerSecond: 750,
                activeConnectionCount: 8
            ),
            processCount: 4,
            diskCount: 4
        ),
        cpuSnapshot: ActivityMonitorMCPCPUProcessSnapshot(
            ready: true,
            sampledAt: "2026-08-01T19:00:00.000Z",
            processes: [
                ActivityMonitorMCPCPUProcess(
                    pid: 42,
                    name: "Xcode Helper",
                    cpuPercent: 72,
                    residentBytes: 800
                ),
                ActivityMonitorMCPCPUProcess(
                    pid: 41,
                    name: "xcodebuild",
                    cpuPercent: 44,
                    residentBytes: 1_200
                ),
                ActivityMonitorMCPCPUProcess(
                    pid: 7,
                    name: "Safari",
                    cpuPercent: 12,
                    residentBytes: 2_000
                ),
                ActivityMonitorMCPCPUProcess(
                    pid: 99,
                    name: "kernel_task",
                    cpuPercent: nil,
                    residentBytes: nil
                ),
            ]
        ),
        networkSnapshot: ActivityMonitorMCPNetworkProcessSnapshot(
            ready: true,
            sampledAt: "2026-08-01T19:00:00.000Z",
            throughput: ActivityMonitorMCPNetworkStatus(
                bytesInPerSecond: 1_250,
                bytesOutPerSecond: 750,
                activeConnectionCount: 8
            ),
            processes: [
                ActivityMonitorMCPNetworkProcess(
                    pid: 300,
                    name: "Safari Networking",
                    connectionCount: 3,
                    tcpConnectionCount: 2,
                    udpConnectionCount: 1,
                    byteCountersAvailable: true,
                    receivedBytes: 500,
                    sentBytes: 250,
                    connections: [
                        ActivityMonitorMCPConnection(
                            proto: "tcp",
                            localEndpoint: "127.0.0.1:52000",
                            remoteEndpoint: "api.example:443",
                            state: "ESTABLISHED",
                            byteCountersAvailable: true,
                            receivedBytes: 300,
                            sentBytes: 100
                        ),
                        ActivityMonitorMCPConnection(
                            proto: "udp",
                            localEndpoint: "*:5353",
                            remoteEndpoint: "224.0.0.251:5353",
                            state: nil,
                            byteCountersAvailable: true,
                            receivedBytes: 100,
                            sentBytes: 100
                        ),
                        ActivityMonitorMCPConnection(
                            proto: "tcp",
                            localEndpoint: "127.0.0.1:52001",
                            remoteEndpoint: "assets.example:443",
                            state: "ESTABLISHED",
                            byteCountersAvailable: true,
                            receivedBytes: 100,
                            sentBytes: 50
                        ),
                    ]
                ),
                ActivityMonitorMCPNetworkProcess(
                    pid: 100,
                    name: "syncd",
                    connectionCount: 4,
                    tcpConnectionCount: 4,
                    udpConnectionCount: 0,
                    byteCountersAvailable: false,
                    receivedBytes: nil,
                    sentBytes: nil,
                    connections: [
                        ActivityMonitorMCPConnection(
                            proto: "tcp",
                            localEndpoint: "127.0.0.1:53000",
                            remoteEndpoint: "cloud.example:443",
                            state: "ESTABLISHED",
                            byteCountersAvailable: false,
                            receivedBytes: nil,
                            sentBytes: nil
                        ),
                    ]
                ),
                ActivityMonitorMCPNetworkProcess(
                    pid: 200,
                    name: "Downloader",
                    connectionCount: 1,
                    tcpConnectionCount: 1,
                    udpConnectionCount: 0,
                    byteCountersAvailable: true,
                    receivedBytes: 900,
                    sentBytes: 100,
                    connections: [
                        ActivityMonitorMCPConnection(
                            proto: "tcp",
                            localEndpoint: "127.0.0.1:54000",
                            remoteEndpoint: "downloads.example:443",
                            state: "ESTABLISHED",
                            byteCountersAvailable: true,
                            receivedBytes: 900,
                            sentBytes: 100
                        ),
                    ]
                ),
            ]
        ),
        diskSnapshotValue: ActivityMonitorMCPDiskSnapshot(
            ready: true,
            sampledAt: "2026-08-01T19:00:00.000Z",
            disks: [
                ActivityMonitorMCPDisk(
                    path: "/Volumes/Data-Backup",
                    name: "Data Backup",
                    totalBytes: 2_000,
                    availableBytes: 1_500,
                    usedBytes: 500,
                    usedPercent: 25
                ),
                ActivityMonitorMCPDisk(
                    path: "/",
                    name: "Macintosh HD",
                    totalBytes: 1_000,
                    availableBytes: 250,
                    usedBytes: 750,
                    usedPercent: 75
                ),
                ActivityMonitorMCPDisk(
                    path: "/Volumes/Data-Archive",
                    name: "Data Archive",
                    totalBytes: 1_000,
                    availableBytes: 400,
                    usedBytes: 600,
                    usedPercent: 60
                ),
                ActivityMonitorMCPDisk(
                    path: "/Volumes/External",
                    name: "Media",
                    totalBytes: 4_000,
                    availableBytes: 3_000,
                    usedBytes: 1_000,
                    usedPercent: 25
                ),
            ]
        )
    )
}

private actor RecordingActivityMonitorMCPRuntime: ActivityMonitorMCPRuntimeControlling {
    private(set) var events: [String] = []
    private var storedGrants: [AuthorizationGrantMetadata]

    init(grants: [AuthorizationGrantMetadata] = []) {
        storedGrants = grants
    }

    func start() async throws {
        events.append("start")
    }

    func stop() async {
        events.append("stop")
    }

    func grants() async throws -> [AuthorizationGrantMetadata] {
        storedGrants
    }

    func revoke(grantID: String) async throws {
        events.append("revoke:\(grantID)")
        guard let index = storedGrants.firstIndex(where: { $0.grantID == grantID }) else {
            return
        }
        storedGrants[index].revokedAt = Date(timeIntervalSince1970: 99)
    }
}

private actor FailingActivityMonitorMCPRuntime: ActivityMonitorMCPRuntimeControlling {
    func start() async throws {
        throw LocalMCPError.bindFailed
    }

    func stop() async {}

    func grants() async throws -> [AuthorizationGrantMetadata] {
        // A secondary failure must not replace listener_start_failed.
        throw LocalMCPError.credentialStoreFailed
    }

    func revoke(grantID: String) async throws {}
}

private actor GatedStartActivityMonitorMCPRuntime: ActivityMonitorMCPRuntimeControlling {
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var startGateIsOpen = false
    private(set) var startCallCount = 0
    private(set) var isRunning = false

    func start() async throws {
        startCallCount += 1
        if !startGateIsOpen {
            await withCheckedContinuation { continuation in
                startWaiters.append(continuation)
            }
        }
        // Deliberately ignore caller cancellation. The controller must still
        // serialize and converge when a runtime operation returns late.
        isRunning = true
    }

    func openStartGate() {
        startGateIsOpen = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func stop() async {
        isRunning = false
    }

    func grants() async throws -> [AuthorizationGrantMetadata] { [] }

    func revoke(grantID: String) async throws {}
}

private actor GatedRevokeActivityMonitorMCPRuntime: ActivityMonitorMCPRuntimeControlling {
    private var grant: AuthorizationGrantMetadata
    private var revokeWaiter: CheckedContinuation<Void, Never>?
    private(set) var revokeDidStart = false
    private(set) var stopDidRun = false

    init(grant: AuthorizationGrantMetadata) {
        self.grant = grant
    }

    var revokedAt: Date? { grant.revokedAt }

    func start() async throws {}

    func stop() async {
        stopDidRun = true
    }

    func grants() async throws -> [AuthorizationGrantMetadata] { [grant] }

    func revoke(grantID: String) async throws {
        revokeDidStart = true
        await withCheckedContinuation { continuation in
            revokeWaiter = continuation
        }
        grant.revokedAt = Date(timeIntervalSince1970: 123)
    }

    func finishRevoke() {
        revokeWaiter?.resume()
        revokeWaiter = nil
    }
}

private struct FixedActivityMonitorConnectionProvider: ConnectionSnapshotProviding {
    func snapshot() async -> [ConnectionSnapshot] {
        let primary = ConnectionSnapshot(
            key: ConnectionKey(
                proto: .tcp,
                local: "192.168.1.10.50000",
                remote: "api.example.443",
                pid: 4242
            ),
            processName: "FixtureNet",
            state: "ESTABLISHED",
            rxBytes: 500,
            txBytes: 200
        )
        return [
            primary,
            // Same identity with smaller counters: bridge keeps the larger row.
            ConnectionSnapshot(
                key: primary.key,
                processName: primary.processName,
                state: primary.state,
                rxBytes: 100,
                txBytes: 50
            ),
            ConnectionSnapshot(
                key: ConnectionKey(
                    proto: .udp,
                    local: "192.168.1.10.5353",
                    remote: "224.0.0.251.5353",
                    pid: 4242
                ),
                processName: "FixtureNet",
                state: nil,
                rxBytes: 0,
                txBytes: 0,
                byteCountersAvailable: false
            ),
            ConnectionSnapshot(
                key: ConnectionKey(
                    proto: .tcp,
                    local: "192.168.1.10.50001",
                    remote: "downloads.example.443",
                    pid: 5252
                ),
                processName: "FixtureDownloader",
                state: "ESTABLISHED",
                rxBytes: 900,
                txBytes: 100
            ),
        ]
    }
}

private func activityMonitorCommandContext() -> CommandContext {
    CommandContext(
        consumer: ConsumerIdentity(
            stableID: "com.example.consumer",
            displayName: "Example Consumer",
            version: "1.0",
            installationID: "00000000-0000-0000-0000-000000000042"
        ),
        grantID: "grant",
        requestID: "request",
        deadline: nil
    )
}

private func assertActivityMonitorInvalidInput(
    _ operation: () async throws -> CommandResult,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await operation()
        XCTFail("Expected invalid command input", file: file, line: line)
    } catch let error as LocalMCPError {
        XCTAssertEqual(error, .invalidCommandInput, file: file, line: line)
    } catch {
        XCTFail("Unexpected error type: \(type(of: error))", file: file, line: line)
    }
}

private func isolatedActivityMonitorDefaults() -> UserDefaults {
    let suite = "ActivityMonitorMCPControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private func activityMonitorGrantMetadata() -> AuthorizationGrantMetadata {
    AuthorizationGrantMetadata(
        grantID: "grant-1",
        producerID: ActivityMonitorMCPRuntimeFactory.producerID,
        consumer: ConsumerIdentity(
            stableID: "com.example.consumer",
            displayName: "Example Consumer",
            version: "1.0",
            installationID: "00000000-0000-0000-0000-000000000042"
        ),
        issuedAt: Date(timeIntervalSince1970: 10)
    )
}
