import AppKit
import Foundation
import LocalMCPContracts
import LocalMCPDiscoveryBonjour
import LocalMCPProducer
import Observation

struct ActivityMonitorPairingPrompt: Equatable, Sendable {
    var consumerName: String
    var consumerStableID: String
    var installationSuffix: String
    var verificationCode: String
    var expiresAt: Date
}

@MainActor
protocol ActivityMonitorPairingPromptPresenting: Sendable {
    func present(_ prompt: ActivityMonitorPairingPrompt) async -> PairingDecision
}

struct ActivityMonitorPairingPresentationGate: Sendable {
    private(set) var activeID: UUID?

    mutating func begin(_ id: UUID) -> Bool {
        guard activeID == nil else { return false }
        activeID = id
        return true
    }

    func acceptsCancellation(for id: UUID) -> Bool {
        activeID == id
    }

    mutating func finish(_ id: UUID) {
        if activeID == id { activeID = nil }
    }
}

@MainActor
final class AppKitActivityMonitorPairingPromptPresenter:
    ActivityMonitorPairingPromptPresenting {
    private var gate = ActivityMonitorPairingPresentationGate()
    private weak var activeWindow: NSWindow?

    func present(_ prompt: ActivityMonitorPairingPrompt) async -> PairingDecision {
        guard Date() < prompt.expiresAt else { return .deny }
        let presentationID = UUID()
        guard gate.begin(presentationID) else { return .deny }
        defer {
            gate.finish(presentationID)
            activeWindow = nil
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Allow local access to system activity?"
        alert.informativeText = """
            \(prompt.consumerName) claims the identity \(prompt.consumerStableID).
            Installation …\(prompt.installationSuffix)
            Verification code: \(prompt.verificationCode)

            Discovery is not proof of identity. Allow only if this code matches the consumer. Access stays on this Mac and exposes current CPU, process, network endpoint, and disk-capacity metadata. It cannot quit processes or change files, and access can be revoked immediately in Activity Monitor Plus Settings.
            """
        // Pairing must never default to approval.
        alert.addButton(withTitle: "Deny")
        alert.addButton(withTitle: "Allow")

        NSApp.activate(ignoringOtherApps: true)
        activeWindow = alert.window
        let remaining = max(prompt.expiresAt.timeIntervalSinceNow, 0)
        let expiryTimer = Timer.scheduledTimer(
            withTimeInterval: remaining,
            repeats: false
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.abortPresentation(presentationID)
            }
        }
        defer { expiryTimer.invalidate() }

        let response = await withTaskCancellationHandler {
            alert.runModal()
        } onCancel: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.abortPresentation(presentationID)
                }
            }
        }
        guard !Task.isCancelled, Date() < prompt.expiresAt else { return .deny }
        return response == .alertSecondButtonReturn ? .approve : .deny
    }

    private func abortPresentation(_ id: UUID) {
        guard gate.acceptsCancellation(for: id),
              let activeWindow,
              NSApp.modalWindow === activeWindow
        else { return }
        NSApp.abortModal()
    }
}

struct ActivityMonitorPairingApprover: PairingApproving {
    let presenter: any ActivityMonitorPairingPromptPresenting

    func decide(_ challenge: PairingChallenge) async throws -> PairingDecision {
        try Task.checkCancellation()
        let code = challenge.verificationCode.withUnsafeDisplayValue { $0 }
        let prompt = ActivityMonitorPairingPrompt(
            consumerName: challenge.consumer.displayName,
            consumerStableID: challenge.consumer.stableID,
            installationSuffix: String(challenge.consumer.installationID.suffix(8)),
            verificationCode: code,
            expiresAt: challenge.expiresAt
        )
        let decision = await presenter.present(prompt)
        try Task.checkCancellation()
        return decision
    }
}

protocol ActivityMonitorMCPRuntimeControlling: Sendable {
    func start() async throws
    func stop() async
    func grants() async throws -> [AuthorizationGrantMetadata]
    func revoke(grantID: String) async throws
}

actor LiveActivityMonitorMCPRuntime: ActivityMonitorMCPRuntimeControlling {
    private let producer: LocalMCPProducer
    private let data: any ActivityMonitorMCPDataProviding
    private let grantStore: any ProducerGrantStoring
    private var commandsRegistered = false
    /// Registration spans four actor calls and therefore has reentrancy
    /// points. Coalesce every starter onto one task so rapid toggles cannot
    /// attempt the same command registration twice.
    private var registrationTask: Task<Void, any Error>?

    init(
        producer: LocalMCPProducer,
        data: any ActivityMonitorMCPDataProviding,
        grantStore: any ProducerGrantStoring
    ) {
        self.producer = producer
        self.data = data
        self.grantStore = grantStore
    }

    func start() async throws {
        // Grant persistence is part of the producer's security boundary. Do
        // not advertise a listener that can accept an approval but cannot
        // durably stage the resulting credential.
        _ = try await grantStore.records()
        try await ensureCommandsRegistered()
        try Task.checkCancellation()
        try await producer.start()
    }

    private func ensureCommandsRegistered() async throws {
        guard !commandsRegistered else { return }
        let task: Task<Void, any Error>
        if let registrationTask {
            task = registrationTask
        } else {
            task = Task { [producer, data] in
                try await producer.registerActivityMonitorCommands(data: data)
            }
            registrationTask = task
        }
        // Keep a failed task cached: a partially registered command set cannot
        // safely be retried one definition at a time.
        try await task.value
        commandsRegistered = true
    }

    func stop() async {
        await producer.stop()
    }

    func grants() async throws -> [AuthorizationGrantMetadata] {
        try await producer.grantRecords().map(\.metadata)
    }

    func revoke(grantID: String) async throws {
        try await producer.revokeGrant(grantID)
    }
}

enum ActivityMonitorMCPRuntimeFactory {
    /// LocalMCPKit stable IDs are lowercase reverse-DNS identifiers and form
    /// the permanent grant namespace. Keep this value stable across releases.
    static let producerID = "com.stevemurr.activity-monitor-plus"
    static let keychainService =
        "com.stevemurr.activity-monitor-plus.localmcp.producer-grants.v1"

    @MainActor
    static func makeLive(
        data: any ActivityMonitorMCPDataProviding
    ) throws -> any ActivityMonitorMCPRuntimeControlling {
        let version = (Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String) ?? "1.0"
        // The legacy login-Keychain query used for grant enumeration is not
        // accepted on current macOS, and per-item ACLs from an ad-hoc build do
        // not survive its next signature. Team signing plus the explicit
        // access-group entitlement lets the data-protection Keychain remain
        // usable across rebuilds.
        let grantStore = try KeychainProducerGrantStore(
            configuration: .init(
                service: keychainService,
                useDataProtectionKeychain: true
            )
        )
        let approval = ActivityMonitorPairingApprover(
            presenter: AppKitActivityMonitorPairingPromptPresenter()
        )
        let producer = LocalMCPProducer(
            identity: ProducerIdentity(
                stableID: producerID,
                displayName: "Activity Monitor Plus",
                version: version
            ),
            configuration: .localOnly(),
            transport: LocalMCPHTTPProducerTransport(),
            advertiser: BonjourLocalMCPDiscovery(),
            grantStore: grantStore,
            approval: approval
        )
        return LiveActivityMonitorMCPRuntime(
            producer: producer,
            data: data,
            grantStore: grantStore
        )
    }
}

enum ActivityMonitorMCPStatus: Equatable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case failed

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting…"
        case .running: "Running on this Mac"
        case .stopping: "Stopping…"
        case .failed: "Unavailable"
        }
    }
}

struct ActivityMonitorGrantViewState: Identifiable, Equatable, Sendable {
    var id: String
    var consumerName: String
    var consumerStableID: String
    var installationSuffix: String
    var issuedAt: Date
    var revokedAt: Date?

    init(metadata: AuthorizationGrantMetadata) {
        id = metadata.grantID
        consumerName = metadata.consumer.displayName
        consumerStableID = metadata.consumer.stableID
        installationSuffix = String(metadata.consumer.installationID.suffix(8))
        issuedAt = metadata.issuedAt
        revokedAt = metadata.revokedAt
    }
}

@MainActor
@Observable
final class ActivityMonitorMCPController {
    static let enabledDefaultsKey = "localMCPProducerEnabled"

    private let runtime: any ActivityMonitorMCPRuntimeControlling
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var transitionTask: Task<Void, Never>?
    @ObservationIgnored private var grantTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var shutdownTask: Task<Void, Never>?
    @ObservationIgnored private var transitionGeneration: UInt64 = 0
    @ObservationIgnored private var monitoringDidStart = false
    @ObservationIgnored private var isShuttingDown = false

    private(set) var isEnabled: Bool
    private(set) var status: ActivityMonitorMCPStatus = .stopped
    private(set) var grants: [ActivityMonitorGrantViewState] = []
    private(set) var revokingGrantIDs: Set<String> = []
    private(set) var lastIssueCode: String?

    init(
        runtime: any ActivityMonitorMCPRuntimeControlling,
        defaults: UserDefaults = .standard
    ) {
        self.runtime = runtime
        self.defaults = defaults
        isEnabled = defaults.bool(forKey: Self.enabledDefaultsKey)
    }

    func startAfterMonitoringReady() {
        guard !monitoringDidStart, !isShuttingDown else { return }
        monitoringDidStart = true
        scheduleTransition()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled, !isShuttingDown else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledDefaultsKey)
        scheduleTransition()
    }

    func refreshGrants() {
        guard !isShuttingDown else { return }
        trackGrantTask { [weak self] in
            await self?.loadGrants()
        }
    }

    func revoke(grantID: String) {
        guard grants.contains(where: { $0.id == grantID && $0.revokedAt == nil }),
              !revokingGrantIDs.contains(grantID),
              !isShuttingDown
        else { return }
        revokingGrantIDs.insert(grantID)
        trackGrantTask { [weak self] in
            guard let self else { return }
            do {
                try await runtime.revoke(grantID: grantID)
            } catch {
                lastIssueCode = "grant_revoke_failed"
            }
            revokingGrantIDs.remove(grantID)
            await loadGrants()
        }
    }

    func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        isShuttingDown = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performShutdown()
        }
        shutdownTask = task
        await task.value
    }

    private func performShutdown() async {
        transitionGeneration &+= 1
        transitionTask?.cancel()
        await transitionTask?.value
        // A Revoke click immediately followed by Quit must still persist the
        // Keychain tombstone before the process exits.
        let pendingGrantTasks = Array(grantTasks.values)
        for task in pendingGrantTasks {
            await task.value
        }
        status = .stopping
        await runtime.stop()
        status = .stopped
    }

    func waitForTransitions() async {
        await transitionTask?.value
    }

    var diagnostics: String {
        let unrevokedCount = grants.lazy.filter { $0.revokedAt == nil }.count
        let revokedCount = grants.count - unrevokedCount
        return [
            "Producer: \(ActivityMonitorMCPRuntimeFactory.producerID)",
            "State: \(status.label)",
            "Listener: IPv4 loopback only",
            "Discovery: LocalOnly",
            "Grant storage: data-protection Keychain",
            "Commands: status, cpu_processes, network_processes, disks",
            "Unrevoked grants: \(unrevokedCount)",
            "Revoked grants: \(revokedCount)",
            "Last issue: \(lastIssueCode ?? "none")",
            "Sensitive payload logging: disabled",
        ].joined(separator: "\n")
    }

    private func scheduleTransition() {
        transitionGeneration &+= 1
        let generation = transitionGeneration
        let previous = transitionTask
        previous?.cancel()
        transitionTask = Task { [weak self] in
            // Serializing transitions prevents a stale start from stopping a
            // listener that a newer enable operation already owns.
            await previous?.value
            guard !Task.isCancelled else { return }
            guard let self else { return }
            await applyDesiredState(generation: generation)
        }
    }

    private func applyDesiredState(generation: UInt64) async {
        guard generation == transitionGeneration,
              monitoringDidStart,
              !isShuttingDown
        else { return }
        if isEnabled {
            status = .starting
            do {
                try await runtime.start()
                guard generation == transitionGeneration, isEnabled, !isShuttingDown else {
                    await runtime.stop()
                    return
                }
                status = .running
                lastIssueCode = nil
            } catch is CancellationError {
                guard generation == transitionGeneration else { return }
                status = .stopped
            } catch let error as LocalMCPError {
                guard generation == transitionGeneration else { return }
                status = .failed
                lastIssueCode = Self.issueCode(for: error)
                isEnabled = false
                defaults.set(false, forKey: Self.enabledDefaultsKey)
            } catch {
                guard generation == transitionGeneration else { return }
                status = .failed
                lastIssueCode = "producer_start_failed"
                isEnabled = false
                defaults.set(false, forKey: Self.enabledDefaultsKey)
            }
        } else {
            status = status == .stopped ? .stopped : .stopping
            await runtime.stop()
            guard generation == transitionGeneration else { return }
            status = .stopped
        }
        await loadGrants()
    }

    private func loadGrants() async {
        do {
            let metadata = try await runtime.grants()
            grants = metadata.map(ActivityMonitorGrantViewState.init(metadata:)).sorted {
                if $0.issuedAt == $1.issuedAt { return $0.id < $1.id }
                return $0.issuedAt > $1.issuedAt
            }
            if lastIssueCode == "grant_list_failed" { lastIssueCode = nil }
        } catch {
            // Do not hide the more useful listener/discovery/startup category.
            if lastIssueCode == nil { lastIssueCode = "grant_list_failed" }
        }
    }

    private func trackGrantTask(
        _ operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        let id = UUID()
        let task = Task { [weak self] in
            await operation()
            self?.grantTasks[id] = nil
        }
        grantTasks[id] = task
    }

    private static func issueCode(for error: LocalMCPError) -> String {
        switch error {
        case .bindFailed: "listener_start_failed"
        case .advertisementFailed: "discovery_start_failed"
        case .credentialStoreFailed: "credential_store_failed"
        case .cancelled: "cancelled"
        default: "producer_start_failed"
        }
    }
}
