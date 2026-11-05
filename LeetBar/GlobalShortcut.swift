import Carbon
import Combine
import Foundation

@MainActor
protocol GlobalShortcutRegistering: AnyObject {
    func register(action: @escaping @MainActor () -> Void) throws
    func unregister()
}

struct GlobalShortcutError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        if status == eventHotKeyExistsErr {
            return "Command-Option-L is already in use. Free this shortcut in the other app, then restart LeetBar."
        }
        return "Command-Option-L could not be registered (macOS error \(status)). Restart LeetBar to retry."
    }
}

@MainActor
final class GlobalShortcutStore: ObservableObject {
    @Published private(set) var errorMessage: String?
    private let registrar: any GlobalShortcutRegistering
    private let logger: DiagnosticLogger
    private var isRegistered = false

    init(registrar: any GlobalShortcutRegistering = CarbonShortcutRegistrar(), logger: DiagnosticLogger = .disabled) {
        self.registrar = registrar
        self.logger = logger
    }

    func start(action: @escaping @MainActor () -> Void) {
        guard !isRegistered else { return }
        do {
            try registrar.register(action: action)
            isRegistered = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            logger.log(
                .warning, .shortcutRegistrationFailed, reason: .system,
                systemCode: (error as? GlobalShortcutError).map { Int($0.status) })
        }
    }

    func stop() {
        guard isRegistered else { return }
        registrar.unregister()
        isRegistered = false
    }
}

@MainActor
final class CarbonShortcutRegistrar: GlobalShortcutRegistering {
    static let keyCode = UInt32(kVK_ANSI_L)
    static let modifiers = UInt32(cmdKey | optionKey)
    static let signature: OSType = 0x4C42_724B
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    func register(action: @escaping @MainActor () -> Void) throws {
        unregister()
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    let registrar = Unmanaged<CarbonShortcutRegistrar>.fromOpaque(userData).takeUnretainedValue()
                    var identifier = EventHotKeyID()
                    let status = GetEventParameter(
                        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                    guard status == noErr else { return status }
                    return registrar.handle(identifier: identifier)
                }
            },
            1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard handlerStatus == noErr else { throw GlobalShortcutError(status: handlerStatus) }
        let status = RegisterEventHotKey(
            Self.keyCode, Self.modifiers, EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        guard status == noErr else {
            unregister()
            throw GlobalShortcutError(status: status)
        }
        self.action = action
    }

    func handle(identifier: EventHotKeyID) -> OSStatus {
        guard identifier.signature == Self.signature, identifier.id == 1, let action else {
            return OSStatus(eventNotHandledErr)
        }
        action()
        return noErr
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
