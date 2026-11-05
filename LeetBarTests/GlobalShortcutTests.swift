import Carbon
import XCTest

@MainActor
final class GlobalShortcutTests: XCTestCase {
    func testShortcutIsCommandOptionLWithoutShiftOrControl() {
        XCTAssertEqual(CarbonShortcutRegistrar.keyCode, UInt32(kVK_ANSI_L))
        XCTAssertEqual(CarbonShortcutRegistrar.modifiers, UInt32(cmdKey | optionKey))
        XCTAssertEqual(CarbonShortcutRegistrar.modifiers & UInt32(shiftKey | controlKey), 0)
    }

    func testStartIsIdempotentAndDeliversActionUntilStopped() {
        let registrar = ShortcutRegistrarFake()
        let store = GlobalShortcutStore(registrar: registrar)
        var invocations = 0
        store.start { invocations += 1 }
        store.start { invocations += 100 }
        XCTAssertEqual(registrar.registrations, 1)
        registrar.action?()
        XCTAssertEqual(invocations, 1)
        XCTAssertNil(store.errorMessage)
        store.stop()
        store.stop()
        XCTAssertEqual(registrar.unregistrations, 1)
        XCTAssertNil(registrar.action)
        store.start { invocations += 1 }
        XCTAssertEqual(registrar.registrations, 2)
        store.stop()
    }

    func testConflictIsVisibleAndRetryClearsTheError() throws {
        let registrar = ShortcutRegistrarFake()
        registrar.failure = GlobalShortcutError(status: OSStatus(eventHotKeyExistsErr))
        let store = GlobalShortcutStore(registrar: registrar)
        store.start { XCTFail("An unavailable shortcut must not invoke its action.") }
        XCTAssertTrue(try XCTUnwrap(store.errorMessage).contains("already in use"))
        XCTAssertNil(registrar.action)
        registrar.failure = nil
        store.start {}
        XCTAssertEqual(registrar.registrations, 2)
        XCTAssertNil(store.errorMessage)
        store.stop()
    }

    func testSystemFailureReportsCodeAndUnregisteredEventsAreIgnored() {
        let registrar = ShortcutRegistrarFake()
        registrar.failure = GlobalShortcutError(status: -50)
        let store = GlobalShortcutStore(registrar: registrar)
        store.start {}
        XCTAssertTrue(store.errorMessage?.contains("-50") == true)
        let native = CarbonShortcutRegistrar()
        XCTAssertEqual(
            native.handle(identifier: EventHotKeyID(signature: CarbonShortcutRegistrar.signature, id: 1)),
            OSStatus(eventNotHandledErr))
        XCTAssertEqual(
            native.handle(identifier: EventHotKeyID(signature: 0, id: 2)),
            OSStatus(eventNotHandledErr))
    }
}

@MainActor
final class ShortcutRegistrarFake: GlobalShortcutRegistering {
    var registrations = 0
    var unregistrations = 0
    var failure: GlobalShortcutError?
    var action: (@MainActor () -> Void)?

    func register(action: @escaping @MainActor () -> Void) throws {
        registrations += 1
        if let failure { throw failure }
        self.action = action
    }

    func unregister() {
        unregistrations += 1
        action = nil
    }
}
