import Foundation
import LocalMCPContracts
import LocalMCPProducer

enum ActivityMonitorMCPLimits {
    static let defaultLimit = 25
    static let maximumLimit = 100
    static let maximumQueryLength = 256
    static let defaultConnectionsPerProcess = 10
    static let maximumConnectionsPerProcess = 25
    static let staleAfterSeconds: TimeInterval = 5
}

private func activityMonitorMCPISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func activityMonitorMCPPercent(_ fraction: Double) -> Double {
    guard fraction.isFinite else { return 0 }
    return min(max(fraction * 100, 0), 100)
}

private func activityMonitorMCPNonnegative(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return max(value, 0)
}

private func activityMonitorMCPSaturatingSum<S: Sequence>(_ values: S) -> UInt64
where S.Element == UInt64 {
    values.reduce(0) { total, value in
        let (sum, overflow) = total.addingReportingOverflow(value)
        return overflow ? UInt64.max : sum
    }
}

struct ActivityMonitorMCPEmptyInput: Codable, Equatable, Sendable {
    init() {}
}

struct ActivityMonitorMCPCPUStatus: Codable, Equatable, Sendable {
    var totalPercent: Double
    var userPercent: Double
    var systemPercent: Double
    var idlePercent: Double
    var coreCount: Int
}

struct ActivityMonitorMCPMemoryStatus: Codable, Equatable, Sendable {
    var totalBytes: UInt64
    var appBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var usedBytes: UInt64
    var freeBytes: UInt64
    var usedPercent: Double
}

struct ActivityMonitorMCPNetworkStatus: Codable, Equatable, Sendable {
    var bytesInPerSecond: Double
    var bytesOutPerSecond: Double
    var activeConnectionCount: Int
}

struct ActivityMonitorMCPStatusOutput: Codable, Equatable, Sendable {
    var ready: Bool
    var stale: Bool
    var sampledAt: String?
    var sampleAgeSeconds: Double?
    var cpu: ActivityMonitorMCPCPUStatus
    var memory: ActivityMonitorMCPMemoryStatus?
    var network: ActivityMonitorMCPNetworkStatus
    var processCount: Int
    var diskCount: Int
}

enum ActivityMonitorMCPCPUProcessSort: String, Codable, CaseIterable, Sendable {
    case cpu
    case memory
    case name
    case pid
}

struct ActivityMonitorMCPCPUProcessesInput: Codable, Equatable, Sendable {
    var query: String?
    var pid: Int32?
    var minimumCPUPercent: Double?
    var sortBy: ActivityMonitorMCPCPUProcessSort?
    var limit: Int?

    init(
        query: String? = nil,
        pid: Int32? = nil,
        minimumCPUPercent: Double? = nil,
        sortBy: ActivityMonitorMCPCPUProcessSort? = nil,
        limit: Int? = nil
    ) {
        self.query = query
        self.pid = pid
        self.minimumCPUPercent = minimumCPUPercent
        self.sortBy = sortBy
        self.limit = limit
    }
}

struct ActivityMonitorMCPCPUProcess: Codable, Equatable, Sendable {
    var pid: Int32
    var name: String
    var cpuPercent: Double?
    var residentBytes: UInt64?
}

struct ActivityMonitorMCPCPUProcessSnapshot: Equatable, Sendable {
    var ready: Bool
    var sampledAt: String?
    var processes: [ActivityMonitorMCPCPUProcess]
}

struct ActivityMonitorMCPCPUProcessesOutput: Codable, Equatable, Sendable {
    var ready: Bool
    var sampledAt: String?
    var totalMatches: Int
    var processes: [ActivityMonitorMCPCPUProcess]
}

struct ActivityMonitorMCPNetworkProcessesInput: Codable, Equatable, Sendable {
    var query: String?
    var pid: Int32?
    var limit: Int?
    var connectionsPerProcess: Int?

    init(
        query: String? = nil,
        pid: Int32? = nil,
        limit: Int? = nil,
        connectionsPerProcess: Int? = nil
    ) {
        self.query = query
        self.pid = pid
        self.limit = limit
        self.connectionsPerProcess = connectionsPerProcess
    }
}

struct ActivityMonitorMCPConnection: Codable, Equatable, Sendable {
    var proto: String
    var localEndpoint: String
    var remoteEndpoint: String
    var state: String?
    var byteCountersAvailable: Bool
    var receivedBytes: UInt64?
    var sentBytes: UInt64?
}

struct ActivityMonitorMCPNetworkProcess: Codable, Equatable, Sendable {
    var pid: Int32
    var name: String
    var connectionCount: Int
    var tcpConnectionCount: Int
    var udpConnectionCount: Int
    var byteCountersAvailable: Bool
    var receivedBytes: UInt64?
    var sentBytes: UInt64?
    var connections: [ActivityMonitorMCPConnection]
}

struct ActivityMonitorMCPNetworkProcessSnapshot: Equatable, Sendable {
    var ready: Bool
    var sampledAt: String?
    var throughput: ActivityMonitorMCPNetworkStatus
    var processes: [ActivityMonitorMCPNetworkProcess]
}

struct ActivityMonitorMCPNetworkProcessesOutput: Codable, Equatable, Sendable {
    var ready: Bool
    var sampledAt: String?
    var throughput: ActivityMonitorMCPNetworkStatus
    var totalMatches: Int
    var processes: [ActivityMonitorMCPNetworkProcess]
}

struct ActivityMonitorMCPDisksInput: Codable, Equatable, Sendable {
    var query: String?
    var limit: Int?

    init(query: String? = nil, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

struct ActivityMonitorMCPDisk: Codable, Equatable, Sendable {
    var path: String
    var name: String
    var totalBytes: UInt64
    var availableBytes: UInt64
    var usedBytes: UInt64
    var usedPercent: Double
}

struct ActivityMonitorMCPDiskSnapshot: Equatable, Sendable {
    var ready: Bool
    var sampledAt: String?
    var disks: [ActivityMonitorMCPDisk]
}

struct ActivityMonitorMCPDisksOutput: Codable, Equatable, Sendable {
    var ready: Bool
    var sampledAt: String?
    var totalMatches: Int
    var disks: [ActivityMonitorMCPDisk]
}

/// Sendable boundary between LocalMCPProducer's actor and AppModel's live,
/// MainActor-owned state. Only stable wire DTOs cross this boundary.
protocol ActivityMonitorMCPDataProviding: Sendable {
    func status() async -> ActivityMonitorMCPStatusOutput
    func cpuProcessSnapshot() async -> ActivityMonitorMCPCPUProcessSnapshot
    func networkProcessSnapshot() async -> ActivityMonitorMCPNetworkProcessSnapshot
    func diskSnapshot() async -> ActivityMonitorMCPDiskSnapshot
}

struct AppModelMCPBridge: ActivityMonitorMCPDataProviding {
    let model: AppModel

    @MainActor
    func status() async -> ActivityMonitorMCPStatusOutput {
        let sample = sampleMetadata()
        let cpu = model.cpu
        let memory = model.memory.map {
            ActivityMonitorMCPMemoryStatus(
                totalBytes: $0.totalBytes,
                appBytes: $0.appBytes,
                wiredBytes: $0.wiredBytes,
                compressedBytes: $0.compressedBytes,
                usedBytes: $0.usedBytes,
                freeBytes: $0.freeBytes,
                usedPercent: activityMonitorMCPPercent($0.usedFraction)
            )
        }
        return ActivityMonitorMCPStatusOutput(
            ready: sample.ready,
            stale: sample.stale,
            sampledAt: sample.sampledAt,
            sampleAgeSeconds: sample.age,
            cpu: ActivityMonitorMCPCPUStatus(
                totalPercent: activityMonitorMCPPercent(cpu.totalUsedFraction),
                userPercent: activityMonitorMCPPercent(cpu.userFraction),
                systemPercent: activityMonitorMCPPercent(cpu.systemFraction),
                idlePercent: activityMonitorMCPPercent(cpu.idleFraction),
                coreCount: max(cpu.coreCount, 1)
            ),
            memory: memory,
            network: networkStatus(),
            processCount: model.cpu.processes.count,
            diskCount: model.volumes.count
        )
    }

    func cpuProcessSnapshot() async -> ActivityMonitorMCPCPUProcessSnapshot {
        let (sample, processes) = await MainActor.run {
            (sampleMetadata(), model.cpu.processes)
        }
        return ActivityMonitorMCPCPUProcessSnapshot(
            ready: sample.ready,
            sampledAt: sample.sampledAt,
            processes: processes.map {
                ActivityMonitorMCPCPUProcess(
                    pid: $0.pid,
                    name: $0.name,
                    cpuPercent: $0.cpuFraction.map(activityMonitorMCPPercent),
                    residentBytes: $0.residentBytes
                )
            }
        )
    }

    func networkProcessSnapshot() async -> ActivityMonitorMCPNetworkProcessSnapshot {
        // Copy the small Sendable state boundary on MainActor, then perform
        // deduplication/grouping/sorting on the caller's executor. A busy
        // socket table must not stall SwiftUI's one-second updates.
        let (sample, status, currentConnections) = await MainActor.run {
            (sampleMetadata(), networkStatus(), model.currentConnections)
        }
        let uniqueConnections = Dictionary(
            currentConnections.map { ($0.key, $0) },
            uniquingKeysWith: { first, second in
                let firstTotal = activityMonitorMCPSaturatingSum([first.rxBytes, first.txBytes])
                let secondTotal = activityMonitorMCPSaturatingSum([second.rxBytes, second.txBytes])
                return firstTotal >= secondTotal ? first : second
            }
        ).values
        let grouped = Dictionary(grouping: uniqueConnections) {
            NetworkProcessKey(name: $0.processName, pid: $0.key.pid)
        }
        let processes = grouped.map { key, sockets in
            let countersAvailable = sockets.allSatisfy(\.byteCountersAvailable)
            let connections = sockets.map {
                ActivityMonitorMCPConnection(
                    proto: $0.key.proto.rawValue,
                    localEndpoint: $0.key.local,
                    remoteEndpoint: $0.key.remote,
                    state: $0.state,
                    byteCountersAvailable: $0.byteCountersAvailable,
                    receivedBytes: $0.byteCountersAvailable ? $0.rxBytes : nil,
                    sentBytes: $0.byteCountersAvailable ? $0.txBytes : nil
                )
            }
            .sorted(by: Self.networkConnectionPrecedes)
            return ActivityMonitorMCPNetworkProcess(
                pid: key.pid,
                name: key.name,
                connectionCount: sockets.count,
                tcpConnectionCount: sockets.lazy.filter { $0.key.proto == .tcp }.count,
                udpConnectionCount: sockets.lazy.filter { $0.key.proto == .udp }.count,
                byteCountersAvailable: countersAvailable,
                receivedBytes: countersAvailable
                    ? activityMonitorMCPSaturatingSum(sockets.map(\.rxBytes)) : nil,
                sentBytes: countersAvailable
                    ? activityMonitorMCPSaturatingSum(sockets.map(\.txBytes)) : nil,
                connections: connections
            )
        }
        return ActivityMonitorMCPNetworkProcessSnapshot(
            ready: sample.ready,
            sampledAt: sample.sampledAt,
            throughput: status,
            processes: processes
        )
    }

    @MainActor
    func diskSnapshot() async -> ActivityMonitorMCPDiskSnapshot {
        let sample = sampleMetadata()
        return ActivityMonitorMCPDiskSnapshot(
            ready: sample.ready,
            sampledAt: sample.sampledAt,
            disks: model.volumes.map {
                ActivityMonitorMCPDisk(
                    path: $0.path,
                    name: $0.name,
                    totalBytes: $0.totalBytes,
                    availableBytes: $0.availableBytes,
                    usedBytes: $0.usedBytes,
                    usedPercent: activityMonitorMCPPercent($0.usedFraction)
                )
            }
        )
    }

    @MainActor
    private func sampleMetadata(now: Date = Date()) -> (
        ready: Bool, stale: Bool, sampledAt: String?, age: Double?
    ) {
        guard model.lastUpdate != .distantPast else {
            return (false, true, nil, nil)
        }
        let age = max(0, now.timeIntervalSince(model.lastUpdate))
        return (
            model.cpu.isReady,
            age > ActivityMonitorMCPLimits.staleAfterSeconds,
            activityMonitorMCPISO8601(model.lastUpdate),
            age
        )
    }

    @MainActor
    private func networkStatus() -> ActivityMonitorMCPNetworkStatus {
        ActivityMonitorMCPNetworkStatus(
            bytesInPerSecond: activityMonitorMCPNonnegative(model.throughput.bytesInPerSecond),
            bytesOutPerSecond: activityMonitorMCPNonnegative(model.throughput.bytesOutPerSecond),
            activeConnectionCount: model.activeConnectionCount
        )
    }

    private static func networkConnectionPrecedes(
        _ lhs: ActivityMonitorMCPConnection,
        _ rhs: ActivityMonitorMCPConnection
    ) -> Bool {
        let lhsBytes = activityMonitorMCPSaturatingSum([
            lhs.receivedBytes ?? 0, lhs.sentBytes ?? 0,
        ])
        let rhsBytes = activityMonitorMCPSaturatingSum([
            rhs.receivedBytes ?? 0, rhs.sentBytes ?? 0,
        ])
        if lhsBytes != rhsBytes { return lhsBytes > rhsBytes }
        if lhs.remoteEndpoint != rhs.remoteEndpoint {
            return lhs.remoteEndpoint < rhs.remoteEndpoint
        }
        if lhs.localEndpoint != rhs.localEndpoint {
            return lhs.localEndpoint < rhs.localEndpoint
        }
        return lhs.proto < rhs.proto
    }
}

private func activityMonitorMCPValidatedQuery(_ query: String?) throws -> String? {
    guard let query else { return nil }
    guard query.unicodeScalars.count <= ActivityMonitorMCPLimits.maximumQueryLength else {
        throw LocalMCPError.invalidCommandInput
    }
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func activityMonitorMCPValidatedLimit(_ limit: Int?) throws -> Int {
    let value = limit ?? ActivityMonitorMCPLimits.defaultLimit
    guard (1...ActivityMonitorMCPLimits.maximumLimit).contains(value) else {
        throw LocalMCPError.invalidCommandInput
    }
    return value
}

struct ActivityMonitorStatusCommandHandler: Sendable {
    let data: any ActivityMonitorMCPDataProviding

    func call(
        input: ActivityMonitorMCPEmptyInput,
        context: CommandContext
    ) async throws -> CommandResult {
        try context.checkCancellation()
        let output = await data.status()
        try context.checkCancellation()
        let text = output.ready
            ? "System status sampled successfully."
            : "Activity Monitor Plus is still collecting its first system sample."
        return try CommandResult.structured(output, text: text)
    }

    static let definition = CommandDefinition(
        name: "activity_monitor.status",
        title: "Get system status",
        description: "Return Activity Monitor Plus's latest system summary: sample freshness, CPU utilization, memory use when available, network throughput, active connection count, process count, and mounted-disk count. Percent fields use 0...100. This reads the app's current sample and does not mutate the system.",
        inputSchema: ActivityMonitorMCPSchemas.emptyInput,
        outputSchema: ActivityMonitorMCPSchemas.statusOutput,
        annotations: ActivityMonitorMCPSchemas.readOnlyAnnotations
    )
}

struct ActivityMonitorCPUProcessesCommandHandler: Sendable {
    let data: any ActivityMonitorMCPDataProviding

    func call(
        input: ActivityMonitorMCPCPUProcessesInput,
        context: CommandContext
    ) async throws -> CommandResult {
        try context.checkCancellation()
        let query = try activityMonitorMCPValidatedQuery(input.query)
        let limit = try activityMonitorMCPValidatedLimit(input.limit)
        if let pid = input.pid, pid < 0 {
            throw LocalMCPError.invalidCommandInput
        }
        if let minimum = input.minimumCPUPercent {
            guard minimum.isFinite, (0...100).contains(minimum) else {
                throw LocalMCPError.invalidCommandInput
            }
        }
        let snapshot = await data.cpuProcessSnapshot()
        try context.checkCancellation()

        let matches = snapshot.processes.filter { process in
            if let pid = input.pid, process.pid != pid { return false }
            if let minimum = input.minimumCPUPercent,
               (process.cpuPercent ?? -1) < minimum { return false }
            guard let query else { return true }
            return process.name.localizedCaseInsensitiveContains(query)
                || String(process.pid) == query
        }
        .sorted { Self.precedes($0, $1, by: input.sortBy ?? .cpu) }
        let output = ActivityMonitorMCPCPUProcessesOutput(
            ready: snapshot.ready,
            sampledAt: snapshot.sampledAt,
            totalMatches: matches.count,
            processes: Array(matches.prefix(limit))
        )
        let noun = output.totalMatches == 1 ? "process" : "processes"
        return try CommandResult.structured(
            output,
            text: "Found \(output.totalMatches) matching CPU \(noun); returned \(output.processes.count)."
        )
    }

    private static func precedes(
        _ lhs: ActivityMonitorMCPCPUProcess,
        _ rhs: ActivityMonitorMCPCPUProcess,
        by sort: ActivityMonitorMCPCPUProcessSort
    ) -> Bool {
        switch sort {
        case .cpu:
            if lhs.cpuPercent != rhs.cpuPercent {
                return (lhs.cpuPercent ?? -1) > (rhs.cpuPercent ?? -1)
            }
        case .memory:
            switch (lhs.residentBytes, rhs.residentBytes) {
            case let (.some(left), .some(right)) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
        case .name:
            let left = lhs.name.lowercased()
            let right = rhs.name.lowercased()
            if left != right { return left < right }
        case .pid:
            if lhs.pid != rhs.pid { return lhs.pid < rhs.pid }
        }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.pid < rhs.pid
    }

    static let definition = CommandDefinition(
        name: "activity_monitor.cpu_processes",
        title: "Query CPU processes",
        description: "Query the latest process sample by name or PID and return bounded CPU and resident-memory information. CPU values are exponentially smoothed whole-machine percentages; ready is false during the initial delta-sampling warm-up, and individual cpuPercent or residentBytes values can be omitted when macOS denies access. Results default to the top 25 by CPU.",
        inputSchema: ActivityMonitorMCPSchemas.cpuProcessesInput,
        outputSchema: ActivityMonitorMCPSchemas.cpuProcessesOutput,
        annotations: ActivityMonitorMCPSchemas.readOnlyAnnotations
    )
}

struct ActivityMonitorNetworkProcessesCommandHandler: Sendable {
    let data: any ActivityMonitorMCPDataProviding

    func call(
        input: ActivityMonitorMCPNetworkProcessesInput,
        context: CommandContext
    ) async throws -> CommandResult {
        try context.checkCancellation()
        let query = try activityMonitorMCPValidatedQuery(input.query)
        let limit = try activityMonitorMCPValidatedLimit(input.limit)
        if let pid = input.pid, pid < 0 {
            throw LocalMCPError.invalidCommandInput
        }
        let connectionLimit = input.connectionsPerProcess
            ?? ActivityMonitorMCPLimits.defaultConnectionsPerProcess
        guard (0...ActivityMonitorMCPLimits.maximumConnectionsPerProcess)
            .contains(connectionLimit) else {
            throw LocalMCPError.invalidCommandInput
        }
        let snapshot = await data.networkProcessSnapshot()
        try context.checkCancellation()

        let matches = snapshot.processes.filter { process in
            if let pid = input.pid, process.pid != pid { return false }
            guard let query else { return true }
            return process.name.localizedCaseInsensitiveContains(query)
                || String(process.pid) == query
                || process.connections.contains { Self.connection($0, matches: query) }
        }
        .sorted(by: Self.precedes)
        let returned = matches.prefix(limit).map { process in
            var process = process
            let rankedConnections = process.connections.enumerated().sorted { lhs, rhs in
                let lhsMatches = query.map {
                    Self.connection(lhs.element, matches: $0)
                } ?? false
                let rhsMatches = query.map {
                    Self.connection(rhs.element, matches: $0)
                } ?? false
                if lhsMatches != rhsMatches { return lhsMatches }
                return lhs.offset < rhs.offset
            }
            process.connections = rankedConnections.prefix(connectionLimit).map(\.element)
            return process
        }
        let output = ActivityMonitorMCPNetworkProcessesOutput(
            ready: snapshot.ready,
            sampledAt: snapshot.sampledAt,
            throughput: snapshot.throughput,
            totalMatches: matches.count,
            processes: Array(returned)
        )
        let noun = output.totalMatches == 1 ? "process" : "processes"
        return try CommandResult.structured(
            output,
            text: "Found \(output.totalMatches) matching network \(noun); returned \(output.processes.count)."
        )
    }

    private static func precedes(
        _ lhs: ActivityMonitorMCPNetworkProcess,
        _ rhs: ActivityMonitorMCPNetworkProcess
    ) -> Bool {
        let lhsBytes = activityMonitorMCPSaturatingSum([
            lhs.receivedBytes ?? 0, lhs.sentBytes ?? 0,
        ])
        let rhsBytes = activityMonitorMCPSaturatingSum([
            rhs.receivedBytes ?? 0, rhs.sentBytes ?? 0,
        ])
        if lhsBytes != rhsBytes { return lhsBytes > rhsBytes }
        if lhs.connectionCount != rhs.connectionCount {
            return lhs.connectionCount > rhs.connectionCount
        }
        let left = lhs.name.lowercased()
        let right = rhs.name.lowercased()
        if left != right { return left < right }
        return lhs.pid < rhs.pid
    }

    private static func connection(
        _ connection: ActivityMonitorMCPConnection,
        matches query: String
    ) -> Bool {
        connection.localEndpoint.localizedCaseInsensitiveContains(query)
            || connection.remoteEndpoint.localizedCaseInsensitiveContains(query)
    }

    static let definition = CommandDefinition(
        name: "activity_monitor.network_processes",
        title: "Query network processes",
        description: "Query processes with currently active non-listening, non-loopback sockets. Returns current throughput, per-process connection totals, and bounded endpoint details. Socket byte counters are cumulative and omitted when the native fallback cannot read them. Results default to 25 processes and 10 connections per process.",
        inputSchema: ActivityMonitorMCPSchemas.networkProcessesInput,
        outputSchema: ActivityMonitorMCPSchemas.networkProcessesOutput,
        annotations: ActivityMonitorMCPSchemas.readOnlyAnnotations
    )
}

struct ActivityMonitorDisksCommandHandler: Sendable {
    let data: any ActivityMonitorMCPDataProviding

    func call(
        input: ActivityMonitorMCPDisksInput,
        context: CommandContext
    ) async throws -> CommandResult {
        try context.checkCancellation()
        let query = try activityMonitorMCPValidatedQuery(input.query)
        let limit = try activityMonitorMCPValidatedLimit(input.limit)
        let snapshot = await data.diskSnapshot()
        try context.checkCancellation()
        let matches = snapshot.disks.filter { disk in
            guard let query else { return true }
            return disk.name.localizedCaseInsensitiveContains(query)
                || disk.path.localizedCaseInsensitiveContains(query)
        }
        .sorted {
            if $0.path != $1.path { return $0.path < $1.path }
            return $0.name < $1.name
        }
        let output = ActivityMonitorMCPDisksOutput(
            ready: snapshot.ready,
            sampledAt: snapshot.sampledAt,
            totalMatches: matches.count,
            disks: Array(matches.prefix(limit))
        )
        let noun = output.totalMatches == 1 ? "disk" : "disks"
        return try CommandResult.structured(
            output,
            text: "Found \(output.totalMatches) matching \(noun); returned \(output.disks.count)."
        )
    }

    static let definition = CommandDefinition(
        name: "activity_monitor.disks",
        title: "Query disk information",
        description: "Query mounted-volume capacity information from Activity Monitor Plus's latest sample. Returns volume name and path plus total, available, and used bytes and used percent. This is an immediate metadata query and does not start the app's expensive directory scanner.",
        inputSchema: ActivityMonitorMCPSchemas.disksInput,
        outputSchema: ActivityMonitorMCPSchemas.disksOutput,
        annotations: ActivityMonitorMCPSchemas.readOnlyAnnotations
    )
}

extension LocalMCPProducer {
    func registerActivityMonitorCommands(
        data: any ActivityMonitorMCPDataProviding
    ) async throws {
        let status = ActivityMonitorStatusCommandHandler(data: data)
        try await register(ActivityMonitorStatusCommandHandler.definition) {
            (input: ActivityMonitorMCPEmptyInput, context: CommandContext) in
            try await status.call(input: input, context: context)
        }
        let cpu = ActivityMonitorCPUProcessesCommandHandler(data: data)
        try await register(ActivityMonitorCPUProcessesCommandHandler.definition) {
            (input: ActivityMonitorMCPCPUProcessesInput, context: CommandContext) in
            try await cpu.call(input: input, context: context)
        }
        let network = ActivityMonitorNetworkProcessesCommandHandler(data: data)
        try await register(ActivityMonitorNetworkProcessesCommandHandler.definition) {
            (input: ActivityMonitorMCPNetworkProcessesInput, context: CommandContext) in
            try await network.call(input: input, context: context)
        }
        let disks = ActivityMonitorDisksCommandHandler(data: data)
        try await register(ActivityMonitorDisksCommandHandler.definition) {
            (input: ActivityMonitorMCPDisksInput, context: CommandContext) in
            try await disks.call(input: input, context: context)
        }
    }
}

private enum ActivityMonitorMCPSchemas {
    static let readOnlyAnnotations = CommandAnnotations(
        readOnly: true,
        idempotent: true,
        destructive: false,
        openWorld: false
    )

    static let emptyInput: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
    ])

    static let sampleProperties: [String: JSONValue] = [
        "ready": .object(["type": .string("boolean")]),
        "sampledAt": .object(["type": .string("string")]),
    ]

    static let queryProperty: JSONValue = .object([
        "type": .string("string"),
        "maxLength": .integer(Int64(ActivityMonitorMCPLimits.maximumQueryLength)),
        "description": .string("Optional case-insensitive name, path, endpoint, or PID query as applicable."),
    ])

    static let pidProperty: JSONValue = .object([
        "type": .string("integer"),
        "minimum": .integer(0),
        "maximum": .integer(Int64(Int32.max)),
        "description": .string("Optional exact process ID."),
    ])

    static let limitProperty: JSONValue = .object([
        "type": .string("integer"),
        "minimum": .integer(1),
        "maximum": .integer(Int64(ActivityMonitorMCPLimits.maximumLimit)),
        "description": .string("Maximum returned records. Defaults to 25."),
    ])

    static let networkStatus: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("bytesInPerSecond"), .string("bytesOutPerSecond"),
            .string("activeConnectionCount"),
        ]),
        "properties": .object([
            "bytesInPerSecond": .object(["type": .string("number"), "minimum": .integer(0)]),
            "bytesOutPerSecond": .object(["type": .string("number"), "minimum": .integer(0)]),
            "activeConnectionCount": .object(["type": .string("integer"), "minimum": .integer(0)]),
        ]),
    ])

    static let statusOutput: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("ready"), .string("stale"), .string("cpu"),
            .string("network"), .string("processCount"), .string("diskCount"),
        ]),
        "properties": .object([
            "ready": .object(["type": .string("boolean")]),
            "stale": .object(["type": .string("boolean")]),
            "sampledAt": .object(["type": .string("string")]),
            "sampleAgeSeconds": .object(["type": .string("number"), "minimum": .integer(0)]),
            "cpu": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([
                    .string("totalPercent"), .string("userPercent"),
                    .string("systemPercent"), .string("idlePercent"),
                    .string("coreCount"),
                ]),
                "properties": .object([
                    "totalPercent": percentProperty,
                    "userPercent": percentProperty,
                    "systemPercent": percentProperty,
                    "idlePercent": percentProperty,
                    "coreCount": .object(["type": .string("integer"), "minimum": .integer(1)]),
                ]),
            ]),
            "memory": .object([
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([
                    .string("totalBytes"), .string("appBytes"), .string("wiredBytes"),
                    .string("compressedBytes"), .string("usedBytes"),
                    .string("freeBytes"), .string("usedPercent"),
                ]),
                "properties": .object([
                    "totalBytes": byteProperty,
                    "appBytes": byteProperty,
                    "wiredBytes": byteProperty,
                    "compressedBytes": byteProperty,
                    "usedBytes": byteProperty,
                    "freeBytes": byteProperty,
                    "usedPercent": percentProperty,
                ]),
            ]),
            "network": networkStatus,
            "processCount": .object(["type": .string("integer"), "minimum": .integer(0)]),
            "diskCount": .object(["type": .string("integer"), "minimum": .integer(0)]),
        ]),
    ])

    static let cpuProcessesInput: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "properties": .object([
            "query": queryProperty,
            "pid": pidProperty,
            "minimumCPUPercent": .object([
                "type": .string("number"),
                "minimum": .integer(0),
                "maximum": .integer(100),
                "description": .string("Optional minimum whole-machine CPU percent."),
            ]),
            "sortBy": .object([
                "type": .string("string"),
                "enum": .array(ActivityMonitorMCPCPUProcessSort.allCases.map { .string($0.rawValue) }),
                "description": .string("Sort by cpu (default), memory, name, or pid."),
            ]),
            "limit": limitProperty,
        ]),
    ])

    static let cpuProcess: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([.string("pid"), .string("name")]),
        "properties": .object([
            "pid": pidProperty,
            "name": .object(["type": .string("string")]),
            "cpuPercent": percentProperty,
            "residentBytes": byteProperty,
        ]),
    ])

    static let cpuProcessesOutput: JSONValue = listOutput(
        collectionName: "processes",
        item: cpuProcess
    )

    static let networkProcessesInput: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "properties": .object([
            "query": queryProperty,
            "pid": pidProperty,
            "limit": limitProperty,
            "connectionsPerProcess": .object([
                "type": .string("integer"),
                "minimum": .integer(0),
                "maximum": .integer(Int64(ActivityMonitorMCPLimits.maximumConnectionsPerProcess)),
                "description": .string("Maximum endpoint details per returned process. Pass 0 for summaries only; defaults to 10."),
            ]),
        ]),
    ])

    static let connection: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("proto"), .string("localEndpoint"), .string("remoteEndpoint"),
            .string("byteCountersAvailable"),
        ]),
        "properties": .object([
            "proto": .object([
                "type": .string("string"),
                "enum": .array([.string("tcp"), .string("udp")]),
            ]),
            "localEndpoint": .object(["type": .string("string")]),
            "remoteEndpoint": .object(["type": .string("string")]),
            "state": .object(["type": .string("string")]),
            "byteCountersAvailable": .object(["type": .string("boolean")]),
            "receivedBytes": byteProperty,
            "sentBytes": byteProperty,
        ]),
    ])

    static let networkProcess: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("pid"), .string("name"), .string("connectionCount"),
            .string("tcpConnectionCount"), .string("udpConnectionCount"),
            .string("byteCountersAvailable"), .string("connections"),
        ]),
        "properties": .object([
            "pid": pidProperty,
            "name": .object(["type": .string("string")]),
            "connectionCount": .object(["type": .string("integer"), "minimum": .integer(0)]),
            "tcpConnectionCount": .object(["type": .string("integer"), "minimum": .integer(0)]),
            "udpConnectionCount": .object(["type": .string("integer"), "minimum": .integer(0)]),
            "byteCountersAvailable": .object(["type": .string("boolean")]),
            "receivedBytes": byteProperty,
            "sentBytes": byteProperty,
            "connections": .object([
                "type": .string("array"),
                "maxItems": .integer(Int64(ActivityMonitorMCPLimits.maximumConnectionsPerProcess)),
                "items": connection,
            ]),
        ]),
    ])

    static let networkProcessesOutput: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("ready"), .string("throughput"), .string("totalMatches"),
            .string("processes"),
        ]),
        "properties": .object([
            "ready": sampleProperties["ready"]!,
            "sampledAt": sampleProperties["sampledAt"]!,
            "throughput": networkStatus,
            "totalMatches": .object(["type": .string("integer"), "minimum": .integer(0)]),
            "processes": .object([
                "type": .string("array"),
                "maxItems": .integer(Int64(ActivityMonitorMCPLimits.maximumLimit)),
                "items": networkProcess,
            ]),
        ]),
    ])

    static let disksInput: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "properties": .object([
            "query": queryProperty,
            "limit": limitProperty,
        ]),
    ])

    static let disk: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(false),
        "required": .array([
            .string("path"), .string("name"), .string("totalBytes"),
            .string("availableBytes"), .string("usedBytes"), .string("usedPercent"),
        ]),
        "properties": .object([
            "path": .object(["type": .string("string")]),
            "name": .object(["type": .string("string")]),
            "totalBytes": byteProperty,
            "availableBytes": byteProperty,
            "usedBytes": byteProperty,
            "usedPercent": percentProperty,
        ]),
    ])

    static let disksOutput: JSONValue = listOutput(
        collectionName: "disks",
        item: disk
    )

    private static let percentProperty: JSONValue = .object([
        "type": .string("number"),
        "minimum": .integer(0),
        "maximum": .integer(100),
    ])

    private static let byteProperty: JSONValue = .object([
        "type": .string("integer"),
        "minimum": .integer(0),
    ])

    private static func listOutput(collectionName: String, item: JSONValue) -> JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([
                .string("ready"), .string("totalMatches"), .string(collectionName),
            ]),
            "properties": .object([
                "ready": sampleProperties["ready"]!,
                "sampledAt": sampleProperties["sampledAt"]!,
                "totalMatches": .object(["type": .string("integer"), "minimum": .integer(0)]),
                collectionName: .object([
                    "type": .string("array"),
                    "maxItems": .integer(Int64(ActivityMonitorMCPLimits.maximumLimit)),
                    "items": item,
                ]),
            ]),
        ])
    }
}
