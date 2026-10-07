import Foundation
import Security

struct LeetCodeSession: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    let sessionCookie: String
    let csrfToken: String

    var description: String { "LeetCodeSession(redacted)" }
    var debugDescription: String { description }

    init(sessionCookie: String, csrfToken: String) throws {
        let session = sessionCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let csrf = csrfToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isCookieValue(session), Self.isCookieValue(csrf) else {
            throw SessionStorageError.invalidCookie
        }
        self.sessionCookie = session
        self.csrfToken = csrf
    }

    private static func isCookieValue(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 16_384
            && value.utf8.allSatisfy {
                (0x21...0x7E).contains($0) && ![0x22, 0x2C, 0x3B, 0x5C].contains($0)
            }
    }
}

enum SessionStorageError: LocalizedError {
    case invalidCookie
    case keychain(OSStatus)
    case invalidStoredSession

    var errorDescription: String? {
        switch self {
        case .invalidCookie:
            "Enter the two cookie values, without cookie names or other request headers."
        case .keychain(let status):
            "Keychain access failed (\(status)). Unlock your login Keychain or approve the macOS access prompt."
        case .invalidStoredSession:
            "The saved session could not be read. Disconnect and connect again."
        }
    }
}

protocol SessionStoring: Sendable {
    func load() throws -> LeetCodeSession?
    func save(_ session: LeetCodeSession) throws
    func delete() throws
}

struct KeychainSessionStore: SessionStoring {
    let service: String

    init(service: String = "dev.leetbar.leetcode-session") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "leetcode.com",
            kSecAttrSynchronizable as String: false,
        ]
    }

    func load() throws -> LeetCodeSession? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SessionStorageError.keychain(status) }
        guard let data = result as? Data,
            let decoded = try? JSONDecoder().decode(LeetCodeSession.self, from: data),
            let session = try? LeetCodeSession(sessionCookie: decoded.sessionCookie, csrfToken: decoded.csrfToken)
        else { throw SessionStorageError.invalidStoredSession }
        return session
    }

    func save(_ session: LeetCodeSession) throws {
        let data = try JSONEncoder().encode(session)
        let changes = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "LeetBar LeetCode Session"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SessionStorageError.keychain(status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionStorageError.keychain(status)
        }
    }
}
