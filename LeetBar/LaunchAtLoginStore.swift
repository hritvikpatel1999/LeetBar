import Combine
import ServiceManagement

@MainActor
protocol LoginItemServing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() async throws
    func openSystemSettings()
}

@MainActor
struct MainAppLoginItemService: LoginItemServing {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() async throws {
        try await SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
final class LaunchAtLoginStore: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?

    private let service: any LoginItemServing

    init(service: any LoginItemServing = MainAppLoginItemService()) {
        self.service = service
        status = service.status
    }

    var isOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    var canToggle: Bool {
        switch status {
        case .notRegistered, .enabled, .requiresApproval: !isWorking
        case .notFound: false
        @unknown default: false
        }
    }

    var statusMessage: String {
        switch status {
        case .notRegistered: "Off. LeetBar will not launch automatically."
        case .enabled: "On. LeetBar will open in the menu bar when you sign in."
        case .requiresApproval: "Approval required. Allow LeetBar in System Settings > Login Items."
        case .notFound: "macOS could not find the login item. Run LeetBar from Applications and check Login Items."
        @unknown default: "macOS returned an unknown login-item status. Check Login Items in System Settings."
        }
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isWorking else { return }
        refresh()
        errorMessage = nil
        guard enabled != isOn else { return }
        isWorking = true
        defer {
            refresh()
            isWorking = false
        }
        do {
            if enabled {
                try service.register()
            } else {
                try await service.unregister()
            }
        } catch {
            let action = enabled ? "enable" : "disable"
            errorMessage = "Could not \(action) launch at login: \(error.localizedDescription)"
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
