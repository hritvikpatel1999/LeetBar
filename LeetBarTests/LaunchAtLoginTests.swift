import ServiceManagement
import XCTest

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    func testInitializationReadsStatusWithoutRegistering() {
        let service = TestLoginItemService()
        let store = LaunchAtLoginStore(service: service)
        XCTAssertEqual(store.status, .notRegistered)
        XCTAssertFalse(store.isOn)
        XCTAssertTrue(store.canToggle)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testExistingRegistrationIsReflectedWithoutChangingIt() {
        let service = TestLoginItemService(status: .enabled)
        let store = LaunchAtLoginStore(service: service)
        XCTAssertTrue(store.isOn)
        XCTAssertEqual(service.registerCalls, 0)
    }

    func testEnableRegistersAndReadsActualStatus() async {
        let service = TestLoginItemService()
        let store = LaunchAtLoginStore(service: service)
        await store.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 0)
        XCTAssertEqual(store.status, .enabled)
        XCTAssertTrue(store.isOn)
        XCTAssertFalse(store.isWorking)
        XCTAssertNil(store.errorMessage)
    }

    func testApprovalRequiredIsNotReportedAsEnabled() async {
        let service = TestLoginItemService()
        service.registrationStatus = .requiresApproval
        let store = LaunchAtLoginStore(service: service)
        await store.setEnabled(true)
        XCTAssertEqual(store.status, .requiresApproval)
        XCTAssertTrue(store.isOn)
        XCTAssertTrue(store.statusMessage.contains("Approval required"))
        XCTAssertNil(store.errorMessage)
        await store.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 1)
    }

    func testDisableUnregistersEnabledAndPendingRegistrations() async {
        for status: SMAppService.Status in [.enabled, .requiresApproval] {
            let service = TestLoginItemService(status: status)
            let store = LaunchAtLoginStore(service: service)
            await store.setEnabled(false)
            XCTAssertEqual(service.unregisterCalls, 1)
            XCTAssertEqual(store.status, .notRegistered)
            XCTAssertFalse(store.isOn)
            XCTAssertFalse(store.isWorking)
            XCTAssertNil(store.errorMessage)
        }
    }

    func testRegisterFailureShowsErrorAndDoesNotAssumeSuccess() async {
        let service = TestLoginItemService()
        service.registrationError = TestLoginItemError()
        let store = LaunchAtLoginStore(service: service)
        await store.setEnabled(true)
        XCTAssertFalse(store.isOn)
        XCTAssertEqual(store.status, .notRegistered)
        XCTAssertTrue(store.errorMessage?.contains("Could not enable") == true)
        XCTAssertTrue(store.errorMessage?.contains("Test registration failure") == true)
        XCTAssertFalse(store.isWorking)
        service.registrationError = nil
        await store.setEnabled(true)
        XCTAssertTrue(store.isOn)
        XCTAssertNil(store.errorMessage)
    }

    func testUnregisterFailurePreservesActualEnabledStatus() async {
        let service = TestLoginItemService(status: .enabled)
        service.unregistrationError = TestLoginItemError()
        let store = LaunchAtLoginStore(service: service)
        await store.setEnabled(false)
        XCTAssertTrue(store.isOn)
        XCTAssertEqual(store.status, .enabled)
        XCTAssertTrue(store.errorMessage?.contains("Could not disable") == true)
        XCTAssertFalse(store.isWorking)
    }

    func testRefreshReflectsExternalSystemSettingsChanges() {
        let service = TestLoginItemService()
        let store = LaunchAtLoginStore(service: service)
        for status: SMAppService.Status in [.enabled, .requiresApproval, .notRegistered, .notFound] {
            service.status = status
            store.refresh()
            XCTAssertEqual(store.status, status)
        }
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testSetEnabledRereadsStatusBeforePerformingOperation() async {
        let service = TestLoginItemService()
        let store = LaunchAtLoginStore(service: service)
        service.status = .enabled
        await store.setEnabled(false)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertFalse(store.isOn)
    }

    func testMatchingRequestsDoNotRegisterOrUnregisterAgain() async {
        let service = TestLoginItemService()
        let store = LaunchAtLoginStore(service: service)
        await store.setEnabled(false)
        service.status = .enabled
        await store.setEnabled(true)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testMissingServiceHasVisibleExplanationAndDisabledToggle() {
        let service = TestLoginItemService(status: .notFound)
        let store = LaunchAtLoginStore(service: service)
        XCTAssertFalse(store.canToggle)
        XCTAssertFalse(store.isOn)
        XCTAssertTrue(store.statusMessage.contains("could not find"))
    }

    func testOpenSystemSettingsDoesNotChangeRegistration() {
        let service = TestLoginItemService()
        let store = LaunchAtLoginStore(service: service)
        store.openSystemSettings()
        XCTAssertEqual(service.openSettingsCalls, 1)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testRepeatedToggleIsIgnoredWhileUnregistering() async {
        let service = TestLoginItemService(status: .enabled)
        service.pauseUnregistration = true
        let store = LaunchAtLoginStore(service: service)
        let work = Task { await store.setEnabled(false) }
        await service.waitUntilPaused()
        XCTAssertTrue(store.isWorking)
        XCTAssertFalse(store.canToggle)
        await store.setEnabled(false)
        await store.setEnabled(true)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(service.registerCalls, 0)
        service.resume()
        await work.value
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(store.isOn)
        XCTAssertTrue(store.canToggle)
    }
}

@MainActor
private final class TestLoginItemService: LoginItemServing {
    var status: SMAppService.Status
    var registrationStatus: SMAppService.Status = .enabled
    var registrationError: Error?
    var unregistrationError: Error?
    var pauseUnregistration = false
    private(set) var registerCalls = 0
    private(set) var unregisterCalls = 0
    private(set) var openSettingsCalls = 0
    private var paused: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    init(status: SMAppService.Status = .notRegistered) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registrationError { throw registrationError }
        status = registrationStatus
    }

    func unregister() async throws {
        unregisterCalls += 1
        if pauseUnregistration {
            await withCheckedContinuation {
                paused = $0
                waiter?.resume()
                waiter = nil
            }
        }
        if let unregistrationError { throw unregistrationError }
        status = .notRegistered
    }

    func openSystemSettings() {
        openSettingsCalls += 1
    }

    func waitUntilPaused() async {
        if paused != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        paused?.resume()
        paused = nil
    }
}

private struct TestLoginItemError: LocalizedError {
    var errorDescription: String? { "Test registration failure" }
}
