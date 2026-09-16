import AppKit
import ClaudeMenuCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class UsageStore {
    static let usageInterval: TimeInterval = 120
    static let maxBackoff: TimeInterval = 900
    static let localInterval: TimeInterval = 60

    private(set) var usage: UsageResponse?
    private(set) var usageFetchedAt: Date?
    private(set) var usageError: UsageFetchError?
    private(set) var isFetchingUsage = false
    private(set) var local: LocalUsageSummary?
    private(set) var localScannedAt: Date?
    private(set) var isScanningLocal = false
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var loginItemError: String?

    var titleMode: TitleMode {
        didSet {
            UserDefaults.standard.set(titleMode.rawValue, forKey: "titleMode")
            onChange?()
        }
    }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let client = UsageClient()
    @ObservationIgnored private let scanner = SessionLogScanner()
    @ObservationIgnored private let scanQueue = DispatchQueue(label: "dk.ulrik.claude-menu.scan", qos: .utility)
    @ObservationIgnored private var nextUsageFetch = Date.distantPast
    @ObservationIgnored private var transientFailures = 0
    @ObservationIgnored private var timer: Timer?

    init() {
        titleMode = TitleMode(storedValue: UserDefaults.standard.string(forKey: "titleMode"))
    }

    var limits: [UsageLimit] { usage?.effectiveLimits ?? [] }

    func start() {
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func popoverOpened() {
        refreshUsage()
        refreshLocal()
    }

    func refreshAll() {
        refreshUsage(force: true)
        refreshLocal()
    }

    private func tick() {
        let now = Date()
        let passedReset = limits.contains { reset in
            guard let at = reset.resetsAt, let fetched = usageFetchedAt else { return false }
            return fetched < at && at <= now
        }
        if now >= nextUsageFetch || (passedReset && usageError == nil) { refreshUsage() }
        if now.timeIntervalSince(localScannedAt ?? .distantPast) >= Self.localInterval { refreshLocal() }
    }

    func refreshUsage(force: Bool = false) {
        guard !isFetchingUsage else { return }
        isFetchingUsage = true
        Task {
            do {
                let result = try await client.fetch(force: force)
                usage = result.usage
                usageFetchedAt = result.fetchedAt
                usageError = nil
                transientFailures = 0
                nextUsageFetch = result.fetchedAt.addingTimeInterval(Self.usageInterval)
            } catch {
                let failure = error as? UsageFetchError ?? .network(error.localizedDescription)
                usageError = failure
                if failure.isTransient {
                    transientFailures += 1
                    let delay = min(Self.usageInterval * pow(2, Double(transientFailures)), Self.maxBackoff)
                    nextUsageFetch = Date().addingTimeInterval(delay)
                } else {
                    nextUsageFetch = Date().addingTimeInterval(Self.usageInterval)
                }
            }
            isFetchingUsage = false
            onChange?()
        }
    }

    func refreshLocal() {
        guard !isScanningLocal else { return }
        isScanningLocal = true
        let scanner = self.scanner
        scanQueue.async { [weak self] in
            scanner.scan()
            let summary = scanner.summary()
            Task { @MainActor in
                self?.local = summary
                self?.localScannedAt = Date()
                self?.isScanningLocal = false
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
