import XCTest

@MainActor
final class QuickLinksTests: XCTestCase {
    private func withDefaults(_ check: (UserDefaults) throws -> Void) throws {
        let suite = "dev.leetbar.quick-links-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try check(defaults)
    }

    func testTrimsTitlesAndPreservesWebURLQueryAndFragment() throws {
        let link = try QuickLink(
            title: "  Revision sheet  ",
            address: " https://docs.google.com/spreadsheets/d/example/edit?usp=sharing#gid=42 ")
        XCTAssertEqual(link.title, "Revision sheet")
        XCTAssertEqual(
            link.url.absoluteString, "https://docs.google.com/spreadsheets/d/example/edit?usp=sharing#gid=42")
        XCTAssertNoThrow(try QuickLink(title: "Local site", address: "http://localhost:8080/practice"))
    }

    func testRejectsEmptyTitlesAndUnsafeURLs() {
        for title in ["", " \n ", "Two\nlines"] {
            XCTAssertThrowsError(try QuickLink(title: title, address: "https://example.com"))
        }
        for address in [
            "", "example.com", "https://", "javascript:alert(1)", "file:///tmp/sheet.xlsx", "data:text/plain,test",
            "https://user:password@example.com", "https://exa mple.com", "https://example.com\n/another",
        ] {
            XCTAssertThrowsError(try QuickLink(title: "Practice", address: address), address)
        }
    }

    func testFourLinkLimitStillAllowsEditingAndSurvivesRelaunch() throws {
        try withDefaults { defaults in
            let store = QuickLinksStore(defaults: defaults)
            for number in 1...4 {
                try store.save(title: "Link \(number)", address: "https://example.com/\(number)")
            }
            XCTAssertThrowsError(try store.save(title: "Fifth", address: "https://example.com/5"))
            let originalID = try XCTUnwrap(store.links.first?.id)
            try store.save(id: originalID, title: "Updated", address: "https://example.org/updated")
            XCTAssertEqual(store.links.count, 4)
            XCTAssertEqual(store.links.first?.id, originalID)
            XCTAssertEqual(store.links.first?.title, "Updated")
            XCTAssertEqual(QuickLinksStore(defaults: defaults).links, store.links)
        }
    }

    func testReorderAndRemovePersistWithoutTouchingOtherPreferences() throws {
        try withDefaults { defaults in
            defaults.set("keep", forKey: "unrelatedPreference")
            let store = QuickLinksStore(defaults: defaults)
            try store.save(title: "First", address: "https://example.com/1")
            try store.save(title: "Second", address: "https://example.com/2")
            let secondID = store.links[1].id
            try store.move(id: secondID, by: -1)
            XCTAssertEqual(store.links.map(\.title), ["Second", "First"])
            try store.move(id: secondID, by: -1)
            XCTAssertEqual(store.links.map(\.title), ["Second", "First"])
            try store.remove(id: secondID)
            XCTAssertEqual(QuickLinksStore(defaults: defaults).links.map(\.title), ["First"])
            XCTAssertEqual(defaults.string(forKey: "unrelatedPreference"), "keep")
        }
    }

    func testInvalidEditLeavesExistingLinkUnchanged() throws {
        try withDefaults { defaults in
            let store = QuickLinksStore(defaults: defaults)
            try store.save(title: "Practice", address: "https://example.com")
            let original = store.links
            XCTAssertThrowsError(try store.save(id: original[0].id, title: "", address: "https://example.com"))
            XCTAssertThrowsError(try store.save(id: UUID(), title: "Missing", address: "https://example.com"))
            XCTAssertEqual(store.links, original)
            XCTAssertEqual(QuickLinksStore(defaults: defaults).links, original)
        }
    }

    func testDamagedStorageIsNotSilentlyOverwritten() throws {
        try withDefaults { defaults in
            let damaged = Data("not JSON".utf8)
            defaults.set(damaged, forKey: QuickLinksStore.storageKey)
            let store = QuickLinksStore(defaults: defaults)
            XCTAssertNotNil(store.storageError)
            XCTAssertTrue(store.links.isEmpty)
            XCTAssertThrowsError(try store.save(title: "Practice", address: "https://example.com"))
            XCTAssertEqual(defaults.data(forKey: QuickLinksStore.storageKey), damaged)
            store.reset()
            XCTAssertNil(store.storageError)
            XCTAssertNoThrow(try store.save(title: "Practice", address: "https://example.com"))
        }
    }

    func testReloadRevalidatesStoredURLs() throws {
        try withDefaults { defaults in
            let data = try JSONSerialization.data(withJSONObject: [
                [
                    "id": UUID().uuidString, "title": "Unsafe", "url": "javascript:alert(1)",
                ]
            ])
            defaults.set(data, forKey: QuickLinksStore.storageKey)
            let store = QuickLinksStore(defaults: defaults)
            XCTAssertTrue(store.links.isEmpty)
            XCTAssertNotNil(store.storageError)
        }
    }

    func testReloadRejectsTooManyLinksAndDuplicateIDs() throws {
        try withDefaults { defaults in
            let links = try (1...5).map { number in
                try QuickLink(title: "Link \(number)", address: "https://example.com/\(number)")
            }
            for invalid in [links, [links[0], links[0]]] {
                defaults.set(try JSONEncoder().encode(invalid), forKey: QuickLinksStore.storageKey)
                let store = QuickLinksStore(defaults: defaults)
                XCTAssertTrue(store.links.isEmpty)
                XCTAssertNotNil(store.storageError)
            }
        }
    }
}
