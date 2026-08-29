# Idea Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture improvement ideas from anywhere in the iOS app with a shake, read the week's collection back as markdown when working on the code.

**Architecture:** An `IdeaStore` protocol is the only thing the views touch; `FileIdeaStore` implements it against a single atomically-written `ideas.json` in the app's Documents directory. No Core Data entity, so no CloudKit dev-schema push. One `IdeaListView` serves both entry points — presented in a sheet by a shake gesture, pushed onto the stack from Settings. Shake is observed by a first-responder `UIViewController` wrapped in a `UIViewControllerRepresentable`.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, XcodeGen. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-29-idea-notes-design.md`

## Global Constraints

- **This plan cannot be executed on the Linux development box.** `xcodebuild` is macOS-only. Every task's test steps require a Mac with Xcode and an iOS simulator. Do not mark a task complete on the strength of "the code looks right" — the test steps are the gate.
- **Never regenerate then commit `project.pbxproj`** — it is gitignored. After adding any new file, run `xcodegen generate` in `ios/`, but commit only sources.
- **Run tests with:** `cd ios && TEST_RUNNER_CI=true xcodebuild test -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=<SIM_ID>" -only-testing:PetHomepageTests`
  Get a `<SIM_ID>` from `xcrun simctl list devices available`.
- **The suite is flaky on two known axes**, neither caused by this work: a Core Data test-harness crash (~1 in 3 runs, logs `Restarting after unexpected exit`) and an occasional simulator `runner hung before establishing connection`. Both surface as **exit 65 with 0 test failures**. Re-run before investigating.
- **Tab tags must not change.** `NotificationRouter.Tab` maps `home = 0, timeline = 1, schedule = 3, careTeam = 4`. Task 4 reads these tags to label an idea; it must not renumber them.
- **Never override a method in a Swift extension.** Specifically: do not implement shake by overriding `motionEnded` in a `UIWindow` extension, which is the most-copied recipe online. It is undefined behavior. Task 4 specifies the sound approach.
- **This is a development aid, not a product feature.** It must never write to Core Data, never touch the pet's record, and never appear in the tab bar.

### Deliberate deviation from the spec

The spec sketched `ideas() throws` and `add(...) throws -> Idea`. This plan narrows that:

- `ideas()` and `markdownExport()` **do not throw**. The spec requires a corrupt `ideas.json` to yield an empty list rather than crash, and a throwing signature invites a call site that propagates instead.
- `add(text:screen:)` returns `Idea?`, nil for blank input. Blank text is a no-op, not an error — throwing for it would force every call site into a `do/catch` that has nothing to report.
- `add` and `delete` still throw, because a genuine disk write failure must be visible rather than silently dropping a note.

---

### Task 1: `Idea` model and `FileIdeaStore` persistence

**Files:**
- Create: `ios/PetHomepage/Models/Idea.swift`
- Create: `ios/PetHomepage/Stores/IdeaStore.swift`
- Test: `ios/PetHomepageTests/IdeaStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Idea` (`id: UUID`, `text: String`, `createdAt: Date`, `screen: String?`); protocol `IdeaStore` with `ideas() -> [Idea]`, `add(text: String, screen: String?) throws -> Idea?`, `delete(_ idea: Idea) throws`, `markdownExport() -> String`; `FileIdeaStore(directory:fileManager:timeZone:now:)` and `FileIdeaStore.documents()`.

- [ ] **Step 1: Write the failing test**

Create `ios/PetHomepageTests/IdeaStoreTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ios && TEST_RUNNER_CI=true xcodebuild test -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=<SIM_ID>" -only-testing:PetHomepageTests/IdeaStoreTests`

Expected: FAIL to compile — "cannot find 'FileIdeaStore' in scope".

- [ ] **Step 3: Write the model**

Create `ios/PetHomepage/Models/Idea.swift`:

```swift
// ios/PetHomepage/Models/Idea.swift
import Foundation

/// A development scratchpad note, jotted while dogfooding the app.
///
/// Deliberately *not* a Core Data entity: a new entity would require a CloudKit dev-schema push
/// from an iCloud-signed-in simulator on a Mac plus a console promotion, and CloudKit would not
/// carry these notes to the development machine anyway. See
/// `docs/superpowers/specs/2026-08-29-idea-notes-design.md`.
struct Idea: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    /// Tab the user was on when capturing; nil when captured from Settings.
    let screen: String?
}
```

- [ ] **Step 4: Write the store**

Create `ios/PetHomepage/Stores/IdeaStore.swift`:

```swift
// ios/PetHomepage/Stores/IdeaStore.swift
import Foundation

/// The seam that keeps a future Convex-backed store a drop-in replacement: views talk only to
/// this protocol, never to the file. Adding a `ConvexIdeaStore` must not require touching
/// `IdeaListView`.
///
/// `ideas()` and `markdownExport()` do not throw by design — a corrupt file degrades to an
/// empty scratchpad rather than surfacing an error the user cannot act on.
protocol IdeaStore {
    /// Newest first.
    func ideas() -> [Idea]
    /// Returns nil (without writing) when `text` is blank; throws only on a real write failure.
    @discardableResult
    func add(text: String, screen: String?) throws -> Idea?
    func delete(_ idea: Idea) throws
    func markdownExport() -> String
}

/// Persists the scratchpad as one JSON array, written atomically.
final class FileIdeaStore: IdeaStore {
    private let fileURL: URL
    private let fileManager: FileManager
    private let timeZone: TimeZone
    private let now: () -> Date

    init(directory: URL,
         fileManager: FileManager = .default,
         timeZone: TimeZone = .current,
         now: @escaping () -> Date = Date) {
        self.fileURL = directory.appendingPathComponent("ideas.json")
        self.fileManager = fileManager
        self.timeZone = timeZone
        self.now = now
    }

    /// Production: the app's private Documents directory.
    static func documents() -> FileIdeaStore {
        let directory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        return FileIdeaStore(directory: directory)
    }

    func ideas() -> [Idea] {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([Idea].self, from: data) else {
            return [] // missing or corrupt: an empty scratchpad beats a crash
        }
        return decoded.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func add(text: String, screen: String?) throws -> Idea? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let idea = Idea(id: UUID(), text: trimmed, createdAt: now(), screen: screen)
        try write(ideas() + [idea])
        return idea
    }

    func delete(_ idea: Idea) throws {
        try write(ideas().filter { $0.id != idea.id })
    }

    func markdownExport() -> String {
        "" // Task 2
    }

    private func write(_ ideas: [Idea]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try Self.encoder.encode(ideas).write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

- [ ] **Step 5: Regenerate the Xcode project**

Run: `cd ios && xcodegen generate`

Expected: succeeds. Two new source files are picked up by the `PetHomepage` target's directory glob. Do not `git add` `project.pbxproj`.

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd ios && TEST_RUNNER_CI=true xcodebuild test -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=<SIM_ID>" -only-testing:PetHomepageTests/IdeaStoreTests`

Expected: PASS, 9 tests.

- [ ] **Step 7: Commit**

```bash
git add ios/PetHomepage/Models/Idea.swift ios/PetHomepage/Stores/IdeaStore.swift ios/PetHomepageTests/IdeaStoreTests.swift
git commit -m "feat(ios): Idea model and file-backed IdeaStore"
```

---

### Task 2: Markdown export

**Files:**
- Modify: `ios/PetHomepage/Stores/IdeaStore.swift` (replace the `markdownExport()` stub)
- Test: `ios/PetHomepageTests/IdeaStoreTests.swift` (append)

**Interfaces:**
- Consumes: `FileIdeaStore` and `Idea` from Task 1.
- Produces: a working `markdownExport() -> String`, consumed by the `ShareLink` in Task 3.

- [ ] **Step 1: Write the failing test**

Append these methods inside `final class IdeaStoreTests` in `ios/PetHomepageTests/IdeaStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ios && TEST_RUNNER_CI=true xcodebuild test -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=<SIM_ID>" -only-testing:PetHomepageTests/IdeaStoreTests`

Expected: FAIL — 3 failures, each `XCTAssertEqual` against the empty string the stub returns.

- [ ] **Step 3: Implement the export**

In `ios/PetHomepage/Stores/IdeaStore.swift`, replace the stub:

```swift
    func markdownExport() -> String {
        "" // Task 2
    }
```

with:

```swift
    func markdownExport() -> String {
        let all = ideas()
        guard !all.isEmpty else { return "## Ideas — none captured" }
        let formatter = Self.stampFormatter(in: timeZone)
        let lines = all.map { idea in
            let context = [idea.screen, formatter.string(from: idea.createdAt)]
                .compactMap { $0 }
                .joined(separator: " · ")
            return "- **\(idea.text)** — \(context)"
        }
        return (["## Ideas — \(all.count) captured", ""] + lines).joined(separator: "\n")
    }

    /// Fixed POSIX locale and lowercase am/pm so the output is stable wherever the phone is set.
    private static func stampFormatter(in timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, h:mma"
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        return formatter
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ios && TEST_RUNNER_CI=true xcodebuild test -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=<SIM_ID>" -only-testing:PetHomepageTests/IdeaStoreTests`

Expected: PASS, 12 tests.

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Stores/IdeaStore.swift ios/PetHomepageTests/IdeaStoreTests.swift
git commit -m "feat(ios): markdown export for the idea scratchpad"
```

---

### Task 3: `IdeaListView`

**Files:**
- Create: `ios/PetHomepage/Features/Ideas/IdeaListView.swift`

**Interfaces:**
- Consumes: `IdeaStore`, `Idea` from Task 1; `markdownExport()` from Task 2; `Theme` from `ios/PetHomepage/DesignSystem/Theme.swift`.
- Produces: `IdeaListView(store: IdeaStore, screen: String?)`, presented in a sheet by Task 4 and pushed by Task 5.

This task has no unit test: it is a view with no logic of its own — blank-input rejection and ordering both live in the store and are covered by Tasks 1 and 2. Its gate is a clean build plus the manual check in Step 3.

- [ ] **Step 1: Write the view**

Create `ios/PetHomepage/Features/Ideas/IdeaListView.swift`:

```swift
// ios/PetHomepage/Features/Ideas/IdeaListView.swift
import SwiftUI

/// The idea scratchpad, shared by both entry points: the shake gesture presents it in a sheet,
/// Settings pushes it onto the settings stack.
///
/// It must not assume it is presented modally — it owns no dismiss affordance and no
/// `NavigationStack`. The presenting side supplies both.
struct IdeaListView: View {
    let store: IdeaStore
    /// Tab the user was on; stamped onto new ideas. nil from the Settings entry.
    var screen: String?

    @State private var draft = ""
    @State private var ideas: [Idea] = []
    @State private var saveError: String?
    @FocusState private var draftFocused: Bool

    private var draftIsBlank: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    // Not `axis: .vertical` — a multiline field swallows Return as a newline
                    // instead of firing onSubmit, and submit-on-return is the whole point.
                    TextField("Jot an idea…", text: $draft)
                        .focused($draftFocused)
                        .onSubmit(save)
                        .submitLabel(.done)
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("idea.field")
                    Button(action: save) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(draftIsBlank ? Theme.inkSoft : Theme.primary)
                    .disabled(draftIsBlank)
                    .accessibilityIdentifier("idea.add")
                }
            }

            Section {
                ForEach(ideas) { idea in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(idea.text)
                            .font(Theme.body())
                            .foregroundStyle(Theme.ink)
                        Text(subtitle(for: idea))
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: delete)
            } header: {
                Text(ideas.isEmpty ? "Nothing captured yet" : "\(ideas.count) captured")
            }
        }
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: store.markdownExport()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(ideas.isEmpty)
                .accessibilityIdentifier("idea.share")
            }
        }
        .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear {
            ideas = store.ideas()
            draftFocused = true
        }
    }

    private func subtitle(for idea: Idea) -> String {
        let stamp = idea.createdAt.formatted(date: .abbreviated, time: .shortened)
        guard let screen = idea.screen else { return stamp }
        return "\(screen) · \(stamp)"
    }

    private func save() {
        guard !draftIsBlank else { return }
        do {
            _ = try store.add(text: draft, screen: screen)
            draft = ""
            ideas = store.ideas()
            draftFocused = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        do {
            for index in offsets { try store.delete(ideas[index]) }
            ideas = store.ideas()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `cd ios && xcodegen generate && xcodebuild build -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=<SIM_ID>"`

Expected: BUILD SUCCEEDED. Do not `git add` `project.pbxproj`.

- [ ] **Step 3: Run the existing suite to verify nothing regressed**

Run: `cd ios && TEST_RUNNER_CI=true xcodebuild test -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=<SIM_ID>" -only-testing:PetHomepageTests`

Expected: 0 failures. (Exit 65 with 0 failures is the known flake — re-run.)

- [ ] **Step 4: Commit**

```bash
git add ios/PetHomepage/Features/Ideas/IdeaListView.swift
git commit -m "feat(ios): IdeaListView, shared by both scratchpad entry points"
```

---

### Task 4: Shake to capture

**Files:**
- Create: `ios/PetHomepage/DesignSystem/ShakeDetector.swift`
- Modify: `ios/PetHomepage/App/ContentView.swift`

**Interfaces:**
- Consumes: `IdeaListView` from Task 3; `FileIdeaStore.documents()` from Task 1.
- Produces: `ShakeDetector(onShake:)`, reusable from any SwiftUI view.

- [ ] **Step 1: Write the shake detector**

Create `ios/PetHomepage/DesignSystem/ShakeDetector.swift`:

```swift
// ios/PetHomepage/DesignSystem/ShakeDetector.swift
import SwiftUI
import UIKit

/// Shake-to-capture for the idea scratchpad, attachable as a `.background()` on any view.
///
/// A first-responder view controller is the only sound way to observe `motionEnded` from
/// SwiftUI. The widely-copied alternative — overriding `motionEnded` in a `UIWindow` extension —
/// is undefined behaviour in Swift (a method override in an extension); it happens to work
/// today and must not be built on.
///
/// Known and accepted: shake is also iOS's shake-to-undo gesture. While a text field holds
/// first-responder status the system undo alert wins and this never fires. Shaking mid-typing
/// is not a real workflow, and suppressing system undo app-wide costs more than the conflict.
struct ShakeDetector: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeViewController {
        let controller = ShakeViewController()
        controller.onShake = onShake
        return controller
    }

    func updateUIViewController(_ controller: ShakeViewController, context: Context) {
        controller.onShake = onShake
    }

    final class ShakeViewController: UIViewController {
        var onShake: (() -> Void)?

        override var canBecomeFirstResponder: Bool { true }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }

        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            guard motion == .motionShake else {
                super.motionEnded(motion, with: event)
                return
            }
            onShake?()
        }
    }
}
```

- [ ] **Step 2: Add the state and tab-label mapping to `ContentView`**

In `ios/PetHomepage/App/ContentView.swift`, add alongside the other `@State` declarations (just after `@State private var pendingLibraryFromCamera = false`):

```swift
    /// Development scratchpad, opened by shaking the phone from any tab.
    @State private var showIdeas = false
```

Then add this method just above `var body: some View`:

```swift
    /// Tab tags are load-bearing (`NotificationRouter` deep links) — this only reads them, to
    /// label an idea with where it was captured.
    private static func screenLabel(for tag: Int) -> String? {
        switch tag {
        case 0: return "Home"
        case 1: return "Timeline"
        case 3: return "Schedule"
        case 4: return "Care Team"
        default: return nil
        }
    }
```

- [ ] **Step 3: Wire the gesture and sheet into the `TabView`**

In the same file, find:

```swift
        .tint(Theme.primary)
```

and insert immediately after it:

```swift
        .background(ShakeDetector { showIdeas = true })
        .sheet(isPresented: $showIdeas) {
            NavigationStack {
                IdeaListView(store: FileIdeaStore.documents(),
                             screen: Self.screenLabel(for: selectedTab))
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { showIdeas = false }
                        }
                    }
            }
        }
```

- [ ] **Step 4: Build and run the suite**

Run: `cd ios && xcodegen generate && TEST_RUNNER_CI=true xcodebuild test -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=<SIM_ID>" -only-testing:PetHomepageTests`

Expected: builds, 0 failures (no new tests). Exit 65 with 0 failures is the known flake — re-run.

- [ ] **Step 5: Verify the gesture by hand**

In the simulator, trigger **Device → Shake** (⌃⌘Z) from each tab in turn. Expected each time: the Ideas sheet appears over the current tab without changing the selected tab; typing a line and pressing Return adds it; the subtitle names the tab you shook from. Dismiss with Done and shake again — the idea is still listed.

- [ ] **Step 6: Commit**

```bash
git add ios/PetHomepage/DesignSystem/ShakeDetector.swift ios/PetHomepage/App/ContentView.swift
git commit -m "feat(ios): shake from any tab to capture an idea"
```

---

### Task 5: Settings entry point

**Files:**
- Modify: `ios/PetHomepage/Features/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `IdeaListView` from Task 3, `FileIdeaStore.documents()` from Task 1.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the card**

In `ios/PetHomepage/Features/Settings/SettingsView.swift`, find the "Walk detection" card and insert a matching card immediately after its closing `.padding(.horizontal, 18)`:

```swift
                    BrandCard {
                        VStack(alignment: .leading, spacing: 14) {
                            BrandCardTitle("Ideas")
                            NavigationLink {
                                IdeaListView(store: FileIdeaStore.documents(), screen: nil)
                            } label: {
                                HStack {
                                    Label("Idea scratchpad", systemImage: "lightbulb")
                                        .font(Theme.body().weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Theme.inkSoft)
                                }
                            }
                            .accessibilityIdentifier("settings.ideas")
                            Text("Jot down improvements as you use the app — or just shake the phone from any screen.")
                                .font(.footnote).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .padding(.horizontal, 18)
```

- [ ] **Step 2: Build and run the suite**

Run: `cd ios && TEST_RUNNER_CI=true xcodebuild test -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=<SIM_ID>" -only-testing:PetHomepageTests`

Expected: builds, 0 failures. No `xcodegen generate` needed — no files were added.

- [ ] **Step 3: Verify by hand**

In the simulator, open Settings and tap **Idea scratchpad**. Expected: the list pushes onto the settings stack with a working back button (not a modal), shows every idea captured by shaking, and adding one here leaves its subtitle with only a timestamp and no screen name.

- [ ] **Step 4: Verify the export end to end**

With at least two ideas captured from different tabs, tap the share button. Expected: the share sheet offers the markdown, formatted as

```markdown
## Ideas — 2 captured

- **Meds tab needs a 'skip today'** — Schedule · Aug 27, 9:14pm
- **Walk timer should keep running** — Home · Aug 26, 7:02am
```

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Features/Settings/SettingsView.swift
git commit -m "feat(ios): Settings entry for the idea scratchpad"
```
