// ios/PetHomepageTests/IdeaStoreTests.swift
import XCTest
@testable import PetHomepage

final class IdeaStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A store with a fixed clock, so ordering assertions are deterministic.
    private func makeStore(now: @escaping () -> Date = { Date() }) -> FileIdeaStore {
        FileIdeaStore(directory: directory,
                      timeZone: TimeZone(identifier: "America/Los_Angeles")!,
                      now: now)
    }

    func testIdeasIsEmptyBeforeAnythingIsAdded() {
        XCTAssertEqual(makeStore().ideas(), [])
    }

    func testAddedIdeasComeBackNewestFirst() throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(now: { clock })

        _ = try store.add(text: "oldest", screen: "Home")
        clock = Date(timeIntervalSince1970: 2_000)
        _ = try store.add(text: "newest", screen: "Schedule")

        XCTAssertEqual(store.ideas().map(\.text), ["newest", "oldest"])
    }

    func testAddStampsTextScreenAndTime() throws {
        let store = makeStore(now: { Date(timeIntervalSince1970: 1_500) })

        let idea = try store.add(text: "swipe to skip", screen: "Schedule")

        XCTAssertEqual(idea?.text, "swipe to skip")
        XCTAssertEqual(idea?.screen, "Schedule")
        XCTAssertEqual(idea?.createdAt, Date(timeIntervalSince1970: 1_500))
    }

    func testAddTrimsSurroundingWhitespace() throws {
        let store = makeStore()

        let idea = try store.add(text: "  padded  \n", screen: nil)

        XCTAssertEqual(idea?.text, "padded")
    }

    func testAddIgnoresBlankText() throws {
        let store = makeStore()

        XCTAssertNil(try store.add(text: "   \n ", screen: nil))
        XCTAssertEqual(store.ideas(), [])
    }

    func testDeleteRemovesOnlyTheTargetIdea() throws {
        var clock = Date(timeIntervalSince1970: 1_000)
        let store = makeStore(now: { clock })
        let doomed = try XCTUnwrap(try store.add(text: "doomed", screen: nil))
        clock = Date(timeIntervalSince1970: 2_000)
        _ = try store.add(text: "keeper", screen: nil)

        try store.delete(doomed)

        XCTAssertEqual(store.ideas().map(\.text), ["keeper"])
    }

    func testIdeasSurviveANewStoreOnTheSameDirectory() throws {
        _ = try makeStore().add(text: "persisted", screen: "Home")

        XCTAssertEqual(makeStore().ideas().map(\.text), ["persisted"])
    }

    /// A mangled file must degrade to an empty scratchpad. Crashing on launch in the app being
    /// dogfooded is a far worse outcome than losing notes.
    func testCorruptFileYieldsAnEmptyList() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json at all".utf8)
            .write(to: directory.appendingPathComponent("ideas.json"))

        XCTAssertEqual(makeStore().ideas(), [])
    }

    func testAddRecoversFromACorruptFileRatherThanThrowing() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: directory.appendingPathComponent("ideas.json"))
        let store = makeStore()

        _ = try store.add(text: "after corruption", screen: nil)

        XCTAssertEqual(store.ideas().map(\.text), ["after corruption"])
    }

    // MARK: Markdown export

    func testMarkdownExportOfAnEmptyListSaysNoneCaptured() {
        XCTAssertEqual(makeStore().markdownExport(), "## Ideas — none captured")
    }

    func testMarkdownExportListsIdeasNewestFirstWithScreenAndTime() throws {
        // 2026-08-26 07:02 and 2026-08-27 21:14, America/Los_Angeles.
        var clock = Date(timeIntervalSince1970: 1_787_752_920)
        let store = makeStore(now: { clock })
        _ = try store.add(text: "Walk timer should keep running", screen: "Home")
        clock = Date(timeIntervalSince1970: 1_787_890_440)
        _ = try store.add(text: "Meds tab needs a 'skip today'", screen: "Schedule")

        XCTAssertEqual(store.markdownExport(), """
        ## Ideas — 2 captured

        - **Meds tab needs a 'skip today'** — Schedule · Aug 27, 9:14pm
        - **Walk timer should keep running** — Home · Aug 26, 7:02am
        """)
    }

    /// An idea captured from Settings has no screen; the separator must go with it.
    func testMarkdownExportOmitsTheScreenSegmentWhenAbsent() throws {
        let store = makeStore(now: { Date(timeIntervalSince1970: 1_787_890_440) })
        _ = try store.add(text: "no context", screen: nil)

        XCTAssertEqual(store.markdownExport(), """
        ## Ideas — 1 captured

        - **no context** — Aug 27, 9:14pm
        """)
    }
}
