import AppKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class DiagnosticsStore: ObservableObject {
    @Published private(set) var verboseEnabled: Bool
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var storageBytes = 0
    @Published private(set) var statusMessage: String?

    private let logger: DiagnosticLogger
    private let defaults: UserDefaults
    private var operationError: String?

    init(logger: DiagnosticLogger = .shared, defaults: UserDefaults = .standard) {
        self.logger = logger
        self.defaults = defaults
        verboseEnabled = defaults.bool(forKey: DiagnosticLogger.verboseKey)
    }

    func refresh() {
        storageBytes = logger.storedBytes
        errorMessage = operationError ?? logger.errorMessage
    }

    func setVerboseEnabled(_ value: Bool) {
        verboseEnabled = value
        defaults.set(value, forKey: DiagnosticLogger.verboseKey)
        logger.setVerboseEnabled(value)
        refresh()
    }

    func showInFinder() {
        errorMessage = nil
        operationError = nil
        statusMessage = nil
        guard let directory = logger.directory else {
            errorMessage = DiagnosticStorageError.unavailable.localizedDescription
            operationError = errorMessage
            logger.log(.warning, .logsFolderFailed, reason: .system)
            return
        }
        if !NSWorkspace.shared.open(directory) {
            errorMessage = "Could not open the log folder in Finder."
            operationError = errorMessage
            logger.log(.warning, .logsFolderFailed, reason: .system)
        }
    }

    func clear() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        operationError = nil
        statusMessage = nil
        defer { isWorking = false }
        do {
            let logger = logger
            try await Task.detached(priority: .utility) { try logger.clear() }.value
            refresh()
            statusMessage = "Logs cleared. Current startup metadata is retained."
        } catch {
            errorMessage = DiagnosticStorageError.unavailable.localizedDescription
            operationError = errorMessage
        }
    }

    func export() {
        guard !isWorking else { return }
        isWorking = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "LeetBar-Logs.zip"
        panel.title = "Export LeetBar Logs"
        panel.message = "Logs contain diagnostic timestamps and system versions. Review them before sharing."
        panel.begin { [weak self] response in
            self?.isWorking = false
            guard response == .OK, let destination = panel.url else { return }
            Task { @MainActor in await self?.export(to: destination) }
        }
    }

    func export(to destination: URL) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        operationError = nil
        statusMessage = nil
        defer { isWorking = false }
        do {
            let logger = logger
            try await Task.detached(priority: .utility) { try logger.export(to: destination) }.value
            refresh()
            statusMessage = "Logs exported. Nothing was uploaded or sent automatically."
        } catch {
            errorMessage = DiagnosticStorageError.exportFailed.localizedDescription
            operationError = errorMessage
        }
    }
}

@MainActor
final class DiagnosticsAppDelegate: NSObject, NSApplicationDelegate {
    private let logger: DiagnosticLogger
    private let defaults: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private var signals: [DispatchSourceSignal] = []
    private var reopenAction: (@MainActor () -> Void)?
    private var pendingReopen = false
    private var startupAction: (@MainActor () -> Void)?
    private var didLaunch = false
    private var launchedAtLogin = false
    private var handledStartup = false
    private var menuBarController: MenuBarController?
    private static let activeSessionKey = "diagnosticsSessionActive"

    override convenience init() {
        self.init(logger: .shared, defaults: .standard)
    }

    init(logger: DiagnosticLogger, defaults: UserDefaults) {
        self.logger = logger
        self.defaults = defaults
        super.init()
    }

    func recordStartup() {
        logger.start(previousSessionUnclean: defaults.bool(forKey: Self.activeSessionKey))
        defaults.set(true, forKey: Self.activeSessionKey)
        logger.flush()
    }

    func setReopenAction(_ action: @escaping @MainActor () -> Void) {
        reopenAction = action
        if pendingReopen {
            pendingReopen = false
            // Scene setup may still be rendering when the status-item bridge registers its action.
            DispatchQueue.main.async { [weak self] in self?.reopenAction?() }
        }
    }

    func setMenuBarController(_ controller: MenuBarController) {
        menuBarController = controller
        if didLaunch { controller.start() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logger.log(.info, .appReopened)
        if let reopenAction {
            reopenAction()
        } else {
            pendingReopen = true
        }
        return false
    }

    func setStartupAction(_ action: @escaping @MainActor () -> Void) {
        startupAction = action
        presentStartupIfReady()
    }

    func completeLaunch(isLoginItem: Bool) {
        didLaunch = true
        launchedAtLogin = isLoginItem
        presentStartupIfReady()
    }

    private func presentStartupIfReady() {
        guard didLaunch, !handledStartup, let startupAction else { return }
        handledStartup = true
        guard !launchedAtLogin else { return }
        DispatchQueue.main.async { startupAction() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        recordStartup()
        menuBarController?.start()
        let launchReason = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        completeLaunch(isLoginItem: launchReason == keyAELaunchedAsLogInItem)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) {
                [logger] _ in
                logger.log(.info, .sleep)
                logger.flush()
            })
        observers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) {
                [logger] _ in logger.log(.info, .wake)
            })
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: nil
            ) { [logger] _ in
                logger.log(.debug, .inactive)
                logger.flush()
            })
        for value in [SIGTERM, SIGINT] {
            signal(value, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
            source.setEventHandler { NSApplication.shared.terminate(nil) }
            source.resume()
            signals.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
        recordShutdown()
    }

    func recordShutdown() {
        logger.log(.info, .shutdown)
        logger.flush()
        defaults.set(false, forKey: Self.activeSessionKey)
    }
}
