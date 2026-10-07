import Combine
import Foundation

struct QuickLink: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let url: URL

    init(id: UUID = UUID(), title: String, address: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw QuickLinksError.invalidTitle
        }
        guard address.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
            let components = URLComponents(string: address),
            let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            let url = components.url
        else { throw QuickLinksError.invalidURL }
        self.id = id
        self.title = title
        self.url = url
    }
}

enum QuickLinksError: LocalizedError {
    case invalidTitle
    case invalidURL
    case limitReached
    case notFound
    case unreadableStorage

    var errorDescription: String? {
        switch self {
        case .invalidTitle: "Enter a nonempty, single-line title."
        case .invalidURL: "Enter a valid http:// or https:// link without embedded login credentials."
        case .limitReached: "You can save up to four quick links."
        case .notFound: "This quick link no longer exists."
        case .unreadableStorage: "Saved quick links could not be read. Reset Quick Links to replace the damaged data."
        }
    }
}

@MainActor
final class QuickLinksStore: ObservableObject {
    static let maximumCount = 4
    static let storageKey = "quickLinks"

    @Published private(set) var links: [QuickLink] = []
    @Published private(set) var storageError: String?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard defaults.object(forKey: Self.storageKey) != nil else { return }
        do {
            guard let data = defaults.data(forKey: Self.storageKey) else {
                throw QuickLinksError.unreadableStorage
            }
            let decoded = try JSONDecoder().decode([QuickLink].self, from: data)
            guard decoded.count <= Self.maximumCount, Set(decoded.map(\.id)).count == decoded.count else {
                throw QuickLinksError.unreadableStorage
            }
            links = try decoded.map { try QuickLink(id: $0.id, title: $0.title, address: $0.url.absoluteString) }
        } catch {
            storageError = QuickLinksError.unreadableStorage.localizedDescription
        }
    }

    func save(id: UUID? = nil, title: String, address: String) throws {
        guard storageError == nil else { throw QuickLinksError.unreadableStorage }
        let link = try QuickLink(id: id ?? UUID(), title: title, address: address)
        var updated = links
        if let id {
            guard let index = updated.firstIndex(where: { $0.id == id }) else { throw QuickLinksError.notFound }
            updated[index] = link
        } else {
            guard updated.count < Self.maximumCount else { throw QuickLinksError.limitReached }
            updated.append(link)
        }
        try persist(updated)
    }

    func remove(id: UUID) throws {
        guard links.contains(where: { $0.id == id }) else { throw QuickLinksError.notFound }
        try persist(links.filter { $0.id != id })
    }

    func move(id: UUID, by offset: Int) throws {
        guard let index = links.firstIndex(where: { $0.id == id }) else { throw QuickLinksError.notFound }
        let target = index + offset
        guard links.indices.contains(target) else { return }
        var updated = links
        updated.insert(updated.remove(at: index), at: target)
        try persist(updated)
    }

    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
        links = []
        storageError = nil
    }

    private func persist(_ updated: [QuickLink]) throws {
        let data = try JSONEncoder().encode(updated)
        defaults.set(data, forKey: Self.storageKey)
        links = updated
    }
}
