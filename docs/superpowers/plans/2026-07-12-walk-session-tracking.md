# Walk Session Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Optional start/end times on activity + routine logs, a single active walk-session model with Live Activity, and geofence/motion auto-detection that prompts to start and silently auto-ends at home.

**Architecture:** One `WalkSessionStore` (UserDefaults-persisted `WalkSession`) is the sole writer of durations; manual UI, notification actions, and `WalkDetector` are all just callers. Detection is a pure state machine over injected location/motion/clock protocols; CoreLocation/CoreMotion adapters are thin. LogEntry gains one optional `endedAt` column.

**Tech Stack:** Swift 5.9 / iOS 17, Core Data (+CloudKit), CoreLocation, CoreMotion, ActivityKit, XcodeGen, XCTest.

## Global Constraints

- **No local Xcode**: CI is the only compiler. All work happens on branch `walk-sessions`; every task ends with a push and a green `iOS Tests` workflow run (Task 1 creates it). `main` is merged only in Task 13 (triggers TestFlight).
- Deployment target iOS 17.0, Swift 5.9 (`ios/project.yml`).
- Follow existing patterns: pure string-keyed notification handlers (`RoutineActionHandler`), injected `now: () -> Date`, fakes in `PetHomepageTests/Support/`.
- New Swift files under `ios/PetHomepage/**` are picked up automatically by XcodeGen (`sources: path: PetHomepage`); only Task 11 (widget extension) edits `project.yml`.
- Spec deltas (agreed simplifications): duration is supported on **all** activity types and routine slots (no category gating); the detector's default walk activity type is an explicit user pick in Settings; Live Activity v1 is display-only with tap-to-open (End lives in-app + auto-end) so the widget extension needs no App Group.
- Timestamps: `performedAt` = start; `endedAt` optional; duration always derived; `endedAt >= performedAt` enforced at store level.

---

### Task 1: CI test workflow (the validation loop)

**Files:**
- Create: `.github/workflows/ios-tests.yml`

**Interfaces:**
- Produces: a required check every later task pushes against. Workflow name `iOS Tests`, job `unit-tests`.

- [ ] **Step 1: Create branch**

```bash
git checkout -b walk-sessions
```

- [ ] **Step 2: Write the workflow**

```yaml
# .github/workflows/ios-tests.yml
name: iOS Tests

# Runs the unit-test bundle on every branch push and PR. main pushes are covered
# by the TestFlight archive; this workflow is the compile+test loop for branches
# (this repo is developed without local Xcode).
on:
  push:
    branches-ignore: [main]
    paths:
      - "ios/**"
      - ".github/workflows/ios-tests.yml"
  pull_request:
    paths:
      - "ios/**"

concurrency:
  group: ios-tests-${{ github.ref }}
  cancel-in-progress: true

jobs:
  unit-tests:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - name: Select latest Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest-stable

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        working-directory: ios
        run: xcodegen generate

      - name: Run unit tests (simulator)
        working-directory: ios
        run: |
          xcodebuild test \
            -scheme PetHomepage \
            -destination 'platform=iOS Simulator,name=iPhone 16' \
            -only-testing:PetHomepageTests \
            CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 3: Commit, push, verify the loop works**

```bash
git add .github/workflows/ios-tests.yml
git commit -m "ci: run iOS unit tests on branch pushes and PRs"
git push -u origin walk-sessions
gh run watch $(gh run list --workflow "iOS Tests" --branch walk-sessions --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```

Expected: run completes green (existing tests pass). If the simulator name is wrong on the runner, `xcrun simctl list devices` in a debug step and pick an available iPhone.

---

### Task 2: `LogEntry.endedAt` + LogStore support

**Files:**
- Modify: `ios/PetHomepage/Persistence/PetHomepage.xcdatamodeld/PetHomepage.xcdatamodel/contents` (LogEntry entity, after the `resolvedAt` line)
- Modify: `ios/PetHomepage/Models/LogEntry.swift`
- Modify: `ios/PetHomepage/Stores/LogStore.swift:31-77` (`logActivity`, `updateActivity`)
- Test: `ios/PetHomepageTests/LogStoreDurationTests.swift`

**Interfaces:**
- Produces: `LogEntry.endedAt: Date?`; `LogEntry.durationMinutes: Int?`;
  `LogStore.logActivity(type:performedAt:endedAt:note:intervalDays:) throws -> LogEntry`;
  `LogStore.updateActivity(_:type:performedAt:endedAt:note:intervalDays:) throws`.
  Passing `endedAt` earlier than `performedAt` throws `LogStoreError.endBeforeStart`.

- [ ] **Step 1: Write failing tests**

```swift
// ios/PetHomepageTests/LogStoreDurationTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class LogStoreDurationTests: XCTestCase {
    private var controller: PersistenceController!
    private var logStore: LogStore!
    private var activityStore: ActivityStore!

    override func setUpWithError() throws {
        controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        logStore = LogStore(context: context, petStore: PetStore(context: context))
        activityStore = ActivityStore(context: context, petStore: PetStore(context: context))
    }

    func testLogActivityStoresEndedAt() throws {
        let type = try activityStore.createType(name: "Walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(32 * 60)
        let entry = try logStore.logActivity(type: type, performedAt: start, endedAt: end,
                                             note: nil, intervalDays: 0)
        XCTAssertEqual(entry.endedAt, end)
        XCTAssertEqual(entry.durationMinutes, 32)
    }

    func testLogActivityWithoutEndHasNilDuration() throws {
        let type = try activityStore.createType(name: "Walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
        let entry = try logStore.logActivity(type: type, performedAt: Date(), endedAt: nil,
                                             note: nil, intervalDays: 0)
        XCTAssertNil(entry.endedAt)
        XCTAssertNil(entry.durationMinutes)
    }

    func testEndBeforeStartThrows() throws {
        let type = try activityStore.createType(name: "Walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
        let start = Date()
        XCTAssertThrowsError(try logStore.logActivity(type: type, performedAt: start,
                                                      endedAt: start.addingTimeInterval(-60),
                                                      note: nil, intervalDays: 0))
    }

    func testUpdateActivityCanSetAndClearEnd() throws {
        let type = try activityStore.createType(name: "Walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = try logStore.logActivity(type: type, performedAt: start, endedAt: nil,
                                             note: nil, intervalDays: 0)
        try logStore.updateActivity(entry, type: type, performedAt: start,
                                    endedAt: start.addingTimeInterval(600), note: nil, intervalDays: 0)
        XCTAssertEqual(entry.durationMinutes, 10)
        try logStore.updateActivity(entry, type: type, performedAt: start,
                                    endedAt: nil, note: nil, intervalDays: 0)
        XCTAssertNil(entry.endedAt)
    }
}
```

Note: check `LogStore.init` / `ActivityStore.init` signatures before writing — match exactly what exists (they may take `context` + `petStore`); adjust the test setup to the real initializers.

- [ ] **Step 2: Push and verify FAIL** (compile error: no `endedAt` parameter)

```bash
git add ios/PetHomepageTests/LogStoreDurationTests.swift
git commit -m "test: duration storage on activity logs (red)"
git push
```

Expected: `iOS Tests` fails compiling tests.

- [ ] **Step 3: Add the model attribute**

In `contents`, inside `<entity name="LogEntry" ...>`, after the `resolvedAt` attribute line, add:

```xml
        <attribute name="endedAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
```

In `LogEntry.swift`, after `@NSManaged public var resolvedAt: Date?` add:

```swift
    @NSManaged public var endedAt: Date?
```

and in the `extension LogEntry` add:

```swift
    /// Whole minutes between start and end, when this entry is a span.
    var durationMinutes: Int? {
        guard let endedAt else { return nil }
        return Int(endedAt.timeIntervalSince(performedAt) / 60)
    }
```

(Adding an optional attribute is a lightweight migration; the store options already default to automatic migration. CloudKit: the field reaches the dev schema on first Debug run; **production promotion in the CloudKit dashboard is a manual step — flagged in Task 13.**)

- [ ] **Step 4: Extend LogStore**

Add to `LogStore` (top of file):

```swift
enum LogStoreError: Error { case endBeforeStart }
```

Change `logActivity` and `updateActivity` signatures and bodies:

```swift
    func logActivity(type: ActivityType, performedAt: Date, endedAt: Date? = nil,
                     note: String?, intervalDays: Int) throws -> LogEntry {
        if let endedAt, endedAt < performedAt { throw LogStoreError.endBeforeStart }
        // ...existing body...; before `try context.save()` add:
        entry.endedAt = endedAt
```

```swift
    func updateActivity(_ entry: LogEntry, type: ActivityType, performedAt: Date,
                        endedAt: Date? = nil, note: String?, intervalDays: Int) throws {
        if let endedAt, endedAt < performedAt { throw LogStoreError.endBeforeStart }
        // ...existing body...; alongside the other assignments add:
        entry.endedAt = endedAt
```

Existing callers compile unchanged (`endedAt` defaults to `nil`).

- [ ] **Step 5: Push, verify PASS, commit message**

```bash
git add -A ios
git commit -m "feat(ios): optional endedAt span on LogEntry + LogStore duration support"
git push
gh run watch $(gh run list --workflow "iOS Tests" --branch walk-sessions --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```

---

### Task 3: RoutineStore check-off with real start/end

**Files:**
- Modify: `ios/PetHomepage/Stores/RoutineStore.swift:293-320` (`checkOff`)
- Test: `ios/PetHomepageTests/RoutineStoreDurationTests.swift`

**Interfaces:**
- Produces: `checkOff(_ task:on:now:startedAt:endedAt:)` — when `startedAt` is non-nil it overrides the computed `performedAt`; `endedAt` stored as-is (validated `>= start`). Existing call sites unchanged (both new params default nil).

- [ ] **Step 1: Failing test**

```swift
// ios/PetHomepageTests/RoutineStoreDurationTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class RoutineStoreDurationTests: XCTestCase {
    func testCheckOffWithSessionTimesStoresSpan() throws {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext
        let store = RoutineStore(context: context, petStore: PetStore(context: context),
                                 calendar: .current)
        // Create a minimal task row directly (mirror how existing RoutineStore tests do it —
        // read PetHomepageTests for the established helper and reuse it).
        let task = RoutineTask(context: context)
        task.id = UUID(); task.lineageID = UUID(); task.name = "Evening walk"
        task.categoryRaw = ActivityCategory.training.rawValue; task.iconName = "figure.walk"
        task.hour = 17; task.minute = 30; task.weekdayMask = Weekdays.all
        task.effectiveFrom = Date(timeIntervalSince1970: 0); task.isOneOff = false
        try context.save()

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(45 * 60)
        let entry = try store.checkOff(task, on: end, now: end, startedAt: start, endedAt: end)
        XCTAssertEqual(entry.performedAt, start)
        XCTAssertEqual(entry.endedAt, end)
        XCTAssertEqual(entry.durationMinutes, 45)
    }
}
```

- [ ] **Step 2: Push, verify FAIL** (no such parameters)

- [ ] **Step 3: Implement**

```swift
    @discardableResult
    func checkOff(_ task: RoutineTask, on day: Date, now: Date = Date(),
                  startedAt: Date? = nil, endedAt: Date? = nil) throws -> LogEntry {
        // ...existing performedAt computation unchanged...
        let entry = LogEntry(context: context)
        entry.id = UUID()
        entry.performedAt = startedAt ?? performedAt
        if let endedAt, endedAt >= entry.performedAt { entry.endedAt = endedAt }
        // ...rest unchanged...
```

- [ ] **Step 4: Push, verify PASS, commit**

```bash
git add -A ios && git commit -m "feat(ios): routine check-off records real start/end when a session provides them" && git push
```

---

### Task 4: WalkSession model + WalkSessionStore

**Files:**
- Create: `ios/PetHomepage/Walk/WalkSession.swift`
- Create: `ios/PetHomepage/Walk/WalkSessionStore.swift`
- Test: `ios/PetHomepageTests/WalkSessionStoreTests.swift`

**Interfaces:**
- Produces:

```swift
struct WalkSession: Codable, Equatable {
    enum Source: String, Codable { case manual, detected }
    let id: UUID
    let petID: UUID?
    let activityTypeID: UUID?      // exactly one of activityTypeID /
    let routineTaskID: UUID?       // routineTaskID is non-nil
    let startedAt: Date
    let source: Source
}

final class WalkSessionStore {
    static let maxSessionAge: TimeInterval = 4 * 60 * 60
    init(context: NSManagedObjectContext, defaults: UserDefaults = .standard,
         calendar: Calendar = .current, now: @escaping () -> Date = Date.init)
    var active: WalkSession? { get }
    func startActivity(typeID: UUID, startedAt: Date?, source: WalkSession.Source) throws -> WalkSession
    func startRoutine(taskID: UUID, startedAt: Date?, source: WalkSession.Source) throws -> WalkSession
    @discardableResult func end(at endDate: Date?) throws -> LogEntry?   // nil if no active session
    func cancel()
    @discardableResult func expireIfStale() throws -> LogEntry?         // > maxSessionAge → entry without endedAt
}
enum WalkSessionError: Error { case sessionAlreadyActive, unknownReference }
```

Session persisted under UserDefaults key `"walk.activeSession"` as JSON.

- [ ] **Step 1: Failing tests**

```swift
// ios/PetHomepageTests/WalkSessionStoreTests.swift
import CoreData
import XCTest
@testable import PetHomepage

final class WalkSessionStoreTests: XCTestCase {
    private var controller: PersistenceController!
    private var context: NSManagedObjectContext!
    private var defaults: UserDefaults!
    private var walkType: ActivityType!

    override func setUpWithError() throws {
        controller = PersistenceController(inMemory: true)
        context = controller.container.viewContext
        defaults = UserDefaults(suiteName: "walk-tests-\(UUID().uuidString)")
        let activityStore = ActivityStore(context: context, petStore: PetStore(context: context))
        walkType = try activityStore.createType(name: "Walk", category: .training,
                                                iconName: "figure.walk", defaultIntervalDays: 0)
    }

    private func makeStore(now: Date) -> WalkSessionStore {
        WalkSessionStore(context: context, defaults: defaults, now: { now })
    }

    func testStartEndWritesActivitySpan() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(now: t0)
        _ = try store.startActivity(typeID: walkType.id, startedAt: nil, source: .manual)
        XCTAssertNotNil(store.active)

        let t1 = t0.addingTimeInterval(30 * 60)
        let endStore = makeStore(now: t1)          // fresh instance: persistence must carry it
        let entry = try endStore.end(at: nil)
        XCTAssertEqual(entry?.performedAt, t0)
        XCTAssertEqual(entry?.endedAt, t1)
        XCTAssertNil(endStore.active)
    }

    func testSecondStartThrows() throws {
        let store = makeStore(now: Date())
        _ = try store.startActivity(typeID: walkType.id, startedAt: nil, source: .manual)
        XCTAssertThrowsError(try store.startActivity(typeID: walkType.id, startedAt: nil,
                                                     source: .manual)) { error in
            XCTAssertEqual(error as? WalkSessionError, .sessionAlreadyActive)
        }
    }

    func testBackdatedStart() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(now: t0)
        let session = try store.startActivity(typeID: walkType.id,
                                              startedAt: t0.addingTimeInterval(-300),
                                              source: .detected)
        XCTAssertEqual(session.startedAt, t0.addingTimeInterval(-300))
    }

    func testExpireIfStaleLogsOpenEndedEntry() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try makeStore(now: t0).startActivity(typeID: walkType.id, startedAt: nil, source: .manual)
        let later = makeStore(now: t0.addingTimeInterval(5 * 60 * 60))
        let entry = try later.expireIfStale()
        XCTAssertNotNil(entry)
        XCTAssertNil(entry?.endedAt)
        XCTAssertNil(later.active)
    }

    func testExpireIfStaleKeepsFreshSession() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try makeStore(now: t0).startActivity(typeID: walkType.id, startedAt: nil, source: .manual)
        let later = makeStore(now: t0.addingTimeInterval(60 * 60))
        XCTAssertNil(try later.expireIfStale())
        XCTAssertNotNil(later.active)
    }

    func testCancelDiscardsWithoutLogging() throws {
        let store = makeStore(now: Date())
        _ = try store.startActivity(typeID: walkType.id, startedAt: nil, source: .manual)
        store.cancel()
        XCTAssertNil(store.active)
        XCTAssertNil(try store.end(at: nil))
    }
}
```

- [ ] **Step 2: Push, verify FAIL**

- [ ] **Step 3: Implement**

```swift
// ios/PetHomepage/Walk/WalkSession.swift
import Foundation

/// The single in-progress walk. Persisted as JSON in UserDefaults (not Core Data): it must
/// survive app kill and be readable synchronously from notification handlers, and it is
/// device-local by design — a session on your phone shouldn't sync to a partner's.
struct WalkSession: Codable, Equatable {
    enum Source: String, Codable { case manual, detected }
    let id: UUID
    let petID: UUID?
    let activityTypeID: UUID?
    let routineTaskID: UUID?
    let startedAt: Date
    let source: Source
}
```

```swift
// ios/PetHomepage/Walk/WalkSessionStore.swift
import CoreData
import Foundation

enum WalkSessionError: Error, Equatable { case sessionAlreadyActive, unknownReference }

/// Owns the one active walk session and is the only path from "session" to "LogEntry".
/// Manual UI, notification actions, and WalkDetector all call through here.
final class WalkSessionStore {
    static let maxSessionAge: TimeInterval = 4 * 60 * 60
    private static let key = "walk.activeSession"

    private let context: NSManagedObjectContext
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: () -> Date

    init(context: NSManagedObjectContext, defaults: UserDefaults = .standard,
         calendar: Calendar = .current, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
    }

    var active: WalkSession? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WalkSession.self, from: data)
    }

    @discardableResult
    func startActivity(typeID: UUID, startedAt: Date?, source: WalkSession.Source) throws -> WalkSession {
        try start(WalkSession(id: UUID(), petID: nil, activityTypeID: typeID, routineTaskID: nil,
                              startedAt: startedAt ?? now(), source: source))
    }

    @discardableResult
    func startRoutine(taskID: UUID, startedAt: Date?, source: WalkSession.Source) throws -> WalkSession {
        try start(WalkSession(id: UUID(), petID: nil, activityTypeID: nil, routineTaskID: taskID,
                              startedAt: startedAt ?? now(), source: source))
    }

    /// Ends the active session, writing the LogEntry through the normal stores. Returns nil
    /// when there is no active session (stale notification action, double tap).
    @discardableResult
    func end(at endDate: Date?) throws -> LogEntry? {
        guard let session = active else { return nil }
        let end = max(endDate ?? now(), session.startedAt)
        let entry = try writeEntry(for: session, endedAt: end)
        clear()
        return entry
    }

    func cancel() { clear() }

    /// A forgotten session (older than maxSessionAge) is saved open-ended so the walk isn't
    /// lost, and cleared so a new one can start. Caller decides whether to notify.
    @discardableResult
    func expireIfStale() throws -> LogEntry? {
        guard let session = active,
              now().timeIntervalSince(session.startedAt) > Self.maxSessionAge else { return nil }
        let entry = try writeEntry(for: session, endedAt: nil)
        clear()
        return entry
    }

    // MARK: - Private

    private func start(_ session: WalkSession) throws -> WalkSession {
        guard active == nil else { throw WalkSessionError.sessionAlreadyActive }
        let data = try JSONEncoder().encode(session)
        defaults.set(data, forKey: Self.key)
        return session
    }

    private func writeEntry(for session: WalkSession, endedAt: Date?) throws -> LogEntry {
        let petStore = PetStore(context: context)
        if let typeID = session.activityTypeID {
            let request = ActivityType.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", typeID as CVarArg)
            request.fetchLimit = 1
            guard let type = try context.fetch(request).first else {
                throw WalkSessionError.unknownReference
            }
            let logStore = LogStore(context: context, petStore: petStore)
            return try logStore.logActivity(type: type, performedAt: session.startedAt,
                                            endedAt: endedAt, note: nil,
                                            intervalDays: Int(type.defaultIntervalDays))
        }
        if let taskID = session.routineTaskID {
            let request = RoutineTask.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", taskID as CVarArg)
            request.fetchLimit = 1
            guard let task = try context.fetch(request).first else {
                throw WalkSessionError.unknownReference
            }
            let store = RoutineStore(context: context, petStore: petStore, calendar: calendar)
            let reference = endedAt ?? now()
            // Dedupe: if the slot was already checked off in-app, don't double-log —
            // fall back to an ad-hoc span on the completion instead of a second entry.
            if let existing = try store.completion(of: task, on: reference) {
                existing.performedAt = session.startedAt
                if let endedAt { existing.endedAt = endedAt }
                try context.save()
                return existing
            }
            return try store.checkOff(task, on: reference, now: reference,
                                      startedAt: session.startedAt, endedAt: endedAt)
        }
        throw WalkSessionError.unknownReference
    }

    private func clear() { defaults.removeObject(forKey: Self.key) }
}
```

Adjust `LogStore`/`ActivityStore`/`RoutineStore` initializer calls to the real signatures found in Task 2/3.

- [ ] **Step 4: Push, verify PASS, commit**

```bash
git add -A ios && git commit -m "feat(ios): WalkSessionStore — single active walk session with persistence, expiry, dedupe" && git push
```

---

### Task 5: Walk notification categories + action handler

**Files:**
- Create: `ios/PetHomepage/Notifications/WalkNotificationActions.swift`
- Modify: `ios/PetHomepage/Notifications/NotificationBootstrap.swift` (register the new categories where `RoutineNotificationAction.registerCategories` is called — read the file first and mirror it)
- Test: `ios/PetHomepageTests/WalkActionHandlerTests.swift`

**Interfaces:**
- Consumes: `WalkSessionStore` (Task 4).
- Produces:

```swift
enum WalkNotificationAction {
    static let detectedCategoryID = "walkDetected"   // "Looks like a walk — log it?"
    static let start = "walkStart"                   // backdated start
    static let dismiss = "walkNotNow"
    static let endedCategoryID = "walkEnded"         // "Walk logged — 34 min"
    static let undo = "walkUndoEnd"
    static func registerCategories(center: UNUserNotificationCenter = .current())
}

final class WalkActionHandler {
    init(sessions: WalkSessionStore, context: NSManagedObjectContext,
         now: @escaping () -> Date = Date.init)
    /// requestID formats: "walk-detected-<typeOrTaskUUID>-<exitEpochSeconds>" and
    /// "walk-ended-<logEntryUUID>-<startEpochSeconds>"
    func handle(actionID: String, requestID: String) throws
}
```

Behavior: `walkStart` → parse type/task id + exit timestamp, `startActivity/startRoutine(startedAt: exitDate, source: .detected)`; no-op if a session is already active. `walkUndoEnd` → parse entry UUID + original start epoch, delete that LogEntry and re-open the session with the same start (source preserved as `.detected`).

- [ ] **Step 1: Failing tests** — cover: start action creates a backdated session; start is a no-op when a session exists; undo deletes the entry and restores an active session with the original `startedAt`; malformed requestIDs are ignored without throwing. Follow the structure of `RoutineActionHandler` tests (find them in `PetHomepageTests` and mirror setup).

```swift
// ios/PetHomepageTests/WalkActionHandlerTests.swift — core assertions
func testStartActionCreatesBackdatedSession() throws {
    let exit = Date(timeIntervalSince1970: 1_700_000_000)
    let requestID = "walk-detected-\(walkType.id.uuidString)-\(Int(exit.timeIntervalSince1970))"
    try handler.handle(actionID: WalkNotificationAction.start, requestID: requestID)
    XCTAssertEqual(sessions.active?.startedAt, exit)
    XCTAssertEqual(sessions.active?.source, .detected)
}

func testUndoRestoresSessionAndDeletesEntry() throws {
    _ = try sessions.startActivity(typeID: walkType.id, startedAt: start, source: .detected)
    let entry = try sessions.end(at: start.addingTimeInterval(1800))!
    let requestID = "walk-ended-\(entry.id.uuidString)-\(Int(start.timeIntervalSince1970))"
    try handler.handle(actionID: WalkNotificationAction.undo, requestID: requestID)
    XCTAssertEqual(sessions.active?.startedAt, start)
    XCTAssertEqual(try logStore.activityLogs().count, 0)
}
```

- [ ] **Step 2: Push, verify FAIL**
- [ ] **Step 3: Implement** `WalkNotificationActions.swift` (mirror `RoutineNotificationActions.swift` structure: category registration + pure handler; the undo path needs the walk type id from the deleted entry to rebuild the session — read `entry.activityType?.id` / `entry.routineLineageID` before deleting).
- [ ] **Step 4: Register categories at launch** — in `NotificationBootstrap` (or wherever `RoutineNotificationAction.registerCategories()` is invoked), add `WalkNotificationAction.registerCategories()`. Route the new action IDs in the `UNUserNotificationCenterDelegate` shim next to the routine ones (find the responder in `PetHomepageApp.swift:22-25` and follow its wiring).
- [ ] **Step 5: Push, verify PASS, commit**

```bash
git add -A ios && git commit -m "feat(ios): walk notification categories + pure action handler (start backdated, undo end)" && git push
```

---

### Task 6: WalkDetector state machine (pure logic)

**Files:**
- Create: `ios/PetHomepage/Walk/WalkDetectionTuning.swift`
- Create: `ios/PetHomepage/Walk/WalkDetectorState.swift`
- Test: `ios/PetHomepageTests/WalkDetectorStateTests.swift`

**Interfaces:**
- Produces a pure, event-driven reducer — **no** CoreLocation/CoreMotion imports here:

```swift
struct WalkDetectionTuning {
    var sustainedWalkSeconds: TimeInterval = 4 * 60
    var homeRadiusMeters: Double = 100
    var slotAttachWindowMinutes: Int = 90
    var scheduledPromptWindowMinutes: Int = 60
    static let `default` = WalkDetectionTuning()
}

enum WalkPromptRule: String, Codable, CaseIterable { case anyWalk, scheduledOnly, off }

enum WalkDetectorEvent: Equatable {
    case exitedHome(at: Date)
    case enteredHome(at: Date)
    case walkingSample(at: Date, isWalking: Bool)
    case promptDismissed
}

enum WalkDetectorEffect: Equatable {
    case promptStart(exitedAt: Date)      // fire the "log this walk?" notification
    case endSession(at: Date)             // silent auto-end
    case none
}

struct WalkDetectorState: Equatable {
    // internal: awaySince, walkingSince, promptedThisExcursion
    static let initial = WalkDetectorState()
    /// hasActiveSession + rule are read fresh on each event by the caller.
    mutating func apply(_ event: WalkDetectorEvent, rule: WalkPromptRule,
                        hasActiveSession: Bool, isNearScheduledSlot: Bool,
                        tuning: WalkDetectionTuning) -> WalkDetectorEffect
}
```

- [ ] **Step 1: Failing tests** — the heart of the feature; cover at minimum:

```swift
// ios/PetHomepageTests/WalkDetectorStateTests.swift — behaviors to assert
// 1. exit → walking samples spanning >= sustainedWalkSeconds → .promptStart(exitedAt: exitTime)
// 2. exit → walking 2 min → not-walking gap → walking again: rolling window tolerates the
//    gap only if cumulative "walking" since exit dominates (implement as: walkingSince
//    resets only after 2 consecutive non-walking samples > 60s apart) → still prompts
// 3. exit → driving samples (isWalking false) → never prompts
// 4. prompt fired once per excursion: further walking samples → .none until next exitedHome
// 5. promptDismissed → no further prompt this excursion
// 6. rule == .off → never .promptStart
// 7. rule == .scheduledOnly && !isNearScheduledSlot → no prompt; && isNearScheduledSlot → prompt
// 8. hasActiveSession == true → walking samples produce .none (no prompt over a running walk)
// 9. enteredHome with hasActiveSession → .endSession(at: entryTime)
// 10. enteredHome without session → .none; state resets for next excursion
```

Write each as a real XCTest with explicit dates (`t0 = Date(timeIntervalSince1970: 1_700_000_000)`, samples at 30 s intervals).

- [ ] **Step 2: Push, verify FAIL**
- [ ] **Step 3: Implement the reducer** — keep it a small value type; the rolling-window rule from test 2 is the only subtlety, and the test defines it exactly.
- [ ] **Step 4: Push, verify PASS, commit**

```bash
git add -A ios && git commit -m "feat(ios): WalkDetector pure state machine — prompt rules, sustained-walk window, auto-end" && git push
```

---

### Task 7: Detection wiring — adapters, home store, app bootstrap

**Files:**
- Create: `ios/PetHomepage/Walk/HomeLocationStore.swift` (UserDefaults: `walk.homeLat/homeLon`, `walk.promptRule`, `walk.defaultActivityTypeID`; typed accessors, `var isConfigured: Bool`)
- Create: `ios/PetHomepage/Walk/WalkDetector.swift` — the impure shell: owns `CLLocationManager` (region monitoring for `CLCircularRegion(center: home, radius: tuning.homeRadiusMeters, identifier: "walk.home")`), `CMMotionActivityManager` (started on region exit, stopped on prompt/entry), feeds `WalkDetectorState`, executes effects: `.promptStart` → local notification via `UNUserNotificationCenter` with category `walkDetected` and requestID `walk-detected-<defaultTypeOrSlotTaskID>-<exitEpoch>`; `.endSession` → `try sessions.end(at: date)` + "Walk logged — N min · Edit / Undo" notification (category `walkEnded`, requestID `walk-ended-<entryID>-<startEpoch>`)
- Create: `ios/PetHomepage/Walk/WalkSlotFinder.swift` — `func openWalkSlot(near date: Date, within minutes: Int, context: NSManagedObjectContext, calendar: Calendar) throws -> RoutineTask?` (uses `RoutineStore.slots(for:)` + `completion(of:on:)`; a slot qualifies if `abs(slotTime − date) <= minutes` and uncompleted; prefer the nearest)
- Modify: `ios/PetHomepage/App/PetHomepageApp.swift` — construct + retain `WalkDetector` alongside the existing notification wiring; call `sessions.expireIfStale()` on foreground (post the "never ended" notification when it returns an entry)
- Modify: `ios/project.yml` — add to the app target's `settings.base`:

```yaml
        INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "Detect when a walk starts so the app can offer to log it."
        INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription: "End the walk automatically the moment you arrive back home, even when the app is closed."
        INFOPLIST_KEY_NSMotionUsageDescription: "Recognize walking so short trips to the car don't trigger walk prompts."
```

- Test: `ios/PetHomepageTests/WalkSlotFinderTests.swift` (slot inside window attaches; completed slot skipped; nothing within window → nil) and `ios/PetHomepageTests/HomeLocationStoreTests.swift` (round-trip, `isConfigured` false until both coords set)

**Interfaces:**
- Consumes: Tasks 4, 5, 6. `WalkDetector.init(sessions:home:tuning:notificationCenter:context:)` — CL/CM types stay inside this one file so everything else remains testable.

- [ ] **Step 1: Failing tests for `WalkSlotFinder` + `HomeLocationStore`; push (FAIL)**
- [ ] **Step 2: Implement both stores + detector shell + app wiring + Info.plist keys**
- [ ] **Step 3: Push, verify PASS (detector shell compiles; logic was tested in Task 6), commit**

```bash
git add -A ios && git commit -m "feat(ios): walk detection wiring — geofence+motion adapters, home store, slot attach, app bootstrap" && git push
```

---

### Task 8: Editor + row UI for durations

**Files:**
- Modify: `ios/PetHomepage/Features/Activities/ActivityLogEditView.swift:28-31`
- Modify: `ios/PetHomepage/Features/Activities/ActivityLogEditViewModel.swift` (add `hasEndTime: Bool`, `endedAt: Date`; init from `editing?.endedAt`; `save()` passes `endedAt: hasEndTime ? endedAt : nil`; clamp `endedAt = max(endedAt, performedAt)` in a `didSet`)
- Modify: `ios/PetHomepage/Features/Timeline/TimelineView.swift` and `ios/PetHomepage/Features/Schedule/ScheduleView.swift` — wherever a row formats `performedAt` as a time, append the span when `endedAt` exists
- Create: `ios/PetHomepage/Walk/WalkFormatting.swift`
- Test: `ios/PetHomepageTests/WalkFormattingTests.swift`

**Interfaces:**
- Produces:

```swift
enum WalkFormatting {
    /// "5:10–5:42 PM · 32 min" (same-meridiem start drops its suffix), or "5:10 PM" when open.
    static func spanLabel(start: Date, end: Date?, calendar: Calendar = .current,
                          locale: Locale = .current) -> String
}
```

- [ ] **Step 1: Failing formatter tests** (fixed dates + `en_US` locale: closed span, open span, cross-meridiem span "11:50 AM–12:20 PM · 30 min")
- [ ] **Step 2: Implement formatter; push green; commit**
- [ ] **Step 3: Editor changes** — in `ActivityLogEditView` replace the `Performed` section:

```swift
            Section {
                DatePicker("Started", selection: $model.performedAt,
                           displayedComponents: [.date, .hourAndMinute])
                Toggle("Add end time", isOn: $model.hasEndTime)
                if model.hasEndTime {
                    DatePicker("Ended", selection: $model.endedAt,
                               in: model.performedAt...,
                               displayedComponents: [.date, .hourAndMinute])
                    if let minutes = model.durationMinutes {
                        LabeledContent("Duration", value: "\(minutes) min")
                    }
                }
                TextField("Note", text: $model.note)
            }
```

- [ ] **Step 4: Row rendering** — use `WalkFormatting.spanLabel` in the Timeline/Schedule row time labels (locate the existing time formatting in each view first; change only the label text expression).
- [ ] **Step 5: Push, verify PASS, commit**

```bash
git add -A ios && git commit -m "feat(ios): start/end pickers in activity editor + span labels on timeline/schedule rows" && git push
```

---

### Task 9: Start actions + in-progress banner (manual End)

**Files:**
- Create: `ios/PetHomepage/Walk/WalkInProgressBanner.swift` — observable banner shown while `sessions.active != nil`: pet-accent card (use `Theme.swift` tokens + `BrandFormSheet` styling conventions) with elapsed time (`TimelineView(.periodic(from:by: 60))`) and **End** button → `try? sessions.end(at: nil)`; long-press → Cancel (discard) with confirmation dialog
- Modify: `ios/PetHomepage/Features/Schedule/ScheduleView.swift:277` — add to `contextActions(for: slot)`: `Button("Start now", systemImage: "play.circle") { startSession(for: slot) }` (guarded to slots without a completion; disabled when a session is active); render `WalkInProgressBanner` above the day list
- Modify: `ios/PetHomepage/Features/Activities/ActivityTypesView.swift` — swipe/context action "Start now" on each type row → `sessions.startActivity(typeID:startedAt:nil, source: .manual)`
- Modify: `ios/PetHomepage/Notifications/RoutineReminderScheduler.swift` + `RoutineNotificationActions.swift` — add a fourth action `routineStartWalk` ("Start walk") to the routine category; handler calls `sessions.startRoutine(taskID:...)` (no-op if active session or already completed — same dedupe shape as the `done` action)
- Test: extend `ios/PetHomepageTests/WalkActionHandlerTests.swift` with the routine-start action (creates session bound to the task, second fire is a no-op)

**Interfaces:**
- Consumes: `WalkSessionStore` from environment — inject the same way stores already reach these views (read how `ScheduleView` receives `RoutineStore` and mirror it).

- [ ] **Step 1: Failing test for `routineStartWalk` action; push (FAIL)**
- [ ] **Step 2: Implement handler action + banner + menu/swipe entries**
- [ ] **Step 3: Push, verify PASS, commit**

```bash
git add -A ios && git commit -m "feat(ios): Start now actions, walk-in-progress banner with End, Start walk notification action" && git push
```

---

### Task 10: Settings — detection section, home picker, staged permissions

**Files:**
- Create: `ios/PetHomepage/Features/Settings/WalkDetectionSettingsView.swift`
- Create: `ios/PetHomepage/Features/Settings/HomeLocationPickerView.swift` — `MapReader { proxy in Map(...) }` (iOS 17 MapKit SwiftUI); tap converts to coordinate via `proxy.convert(_:from:)`, drops a pin, "Use current location" button (one-shot `CLLocationManager.requestLocation` behind When-In-Use)
- Modify: `ios/PetHomepage/Features/Settings/SettingsView.swift` — add a "Walk detection" row/section linking to `WalkDetectionSettingsView` (read the file and match its structure)

**Section contents:**
- Home location row (set → shows "Set ✓ · Change"; unset → "Required for detection")
- Default walk activity Picker over `ActivityStore.types()` (persists `walk.defaultActivityTypeID`)
- Prompt rule Picker: Any sustained walk / Only near scheduled walks / Off (`WalkPromptRule`)
- Permission staging: a "Enable auto-detection" button that (1) requests When-In-Use; (2) on grant, shows an explainer (`"One more step — Always access lets the walk end itself the moment you're home, even with the app closed."`) with a button that calls `requestAlwaysAuthorization()`; (3) reflects the real `authorizationStatus` afterward with a "Open Settings" link (`UIApplication.openSettingsURLString`) when denied. Manual logging is never gated on any of this.

- [ ] **Step 1: Implement views + wiring (UI task — no new unit tests; state logic already covered)**
- [ ] **Step 2: Push, verify build+tests still green, commit**

```bash
git add -A ios && git commit -m "feat(ios): walk detection settings — home picker, default type, prompt rule, staged permissions" && git push
```

---

### Task 11: Live Activity (display-only widget extension)

**Files:**
- Create: `ios/PetHomepageWidgets/WalkActivityAttributes.swift`

```swift
import ActivityKit
import Foundation

struct WalkActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var startedAt: Date }
    var petName: String
}
```

- Create: `ios/PetHomepageWidgets/WalkLiveActivityWidget.swift` — `WidgetBundle` `@main` with one `ActivityConfiguration(for: WalkActivityAttributes.self)`: lock-screen view = pet name + `Text(context.state.startedAt, style: .timer)` + "walk in progress"; Dynamic Island compact = timer; `.widgetURL(URL(string: "pethomepage://walk"))`
- Create: `ios/PetHomepage/Walk/WalkLiveActivityController.swift` — app-side: `start(session:petName:)` → `Activity.request`, `endAll()` → `Activity<WalkActivityAttributes>.activities.forEach { await $0.end(...) }`; called from `WalkSessionStore` call sites (banner start/end, detector, action handler) — keep it invoked from the app layer, not inside the store, so the store stays UIKit-free. Duplicate `WalkActivityAttributes.swift` reference: add the file to **both** targets via project.yml `sources` (shared file, no App Group needed since the extension only renders what the app pushes)
- Modify: `ios/project.yml`:

```yaml
  PetHomepageWidgets:
    type: app-extension
    platform: iOS
    sources:
      - path: PetHomepageWidgets
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: pet.homepage.PetHomepage.Widgets
        DEVELOPMENT_TEAM: X5C7XC8SAV
        CODE_SIGN_STYLE: Automatic
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_CFBundleDisplayName: "Pet Homepage"
        INFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier: com.apple.widgetkit-extension
    info:
      path: PetHomepageWidgets/Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

  plus on the **app** target: `INFOPLIST_KEY_NSSupportsLiveActivities: "YES"`, a `dependencies:` entry `- target: PetHomepageWidgets, embed: true`, and add `- path: PetHomepage/../PetHomepageWidgets/WalkActivityAttributes.swift` style shared-source reference (XcodeGen: list the file under the app target's `sources` as an additional path). Also handle `pethomepage://walk` in the app (`onOpenURL` → present the in-progress banner screen).

- [ ] **Step 1: Add extension + controller + wiring**
- [ ] **Step 2: Push, watch CI closely** — this is the highest-blind-risk task (target config). If `xcodegen`/`xcodebuild` fails, iterate on `project.yml` (common fixes: `NSExtension` only via `info.properties`, not INFOPLIST_KEY; scheme may need the widget target added to build; `-only-testing` keeps tests unaffected).
- [ ] **Step 3: Commit**

```bash
git add -A ios && git commit -m "feat(ios): walk Live Activity — lock-screen timer via display-only widget extension" && git push
```

---

### Task 12: Mirror contract bump (iOS + web)

**Files:**
- Modify: `ios/PetHomepage/Mirror/MirrorSnapshot.swift` — `ActivityLogSnapshot`: add `var endedAt: String?` with `case endedAt = "ended_at"`; bump `currentSchemaVersion` by 1 and extend the version-history doc comment ("vN adds activity_logs[].ended_at")
- Modify: `ios/PetHomepage/Mirror/SnapshotBuilder.swift:136-150` — populate `endedAt` with the same ISO-8601 formatter used for `performed_at`
- Modify: `lib/types/mirror.ts` — `activity_logs` entries gain `ended_at?: string`
- Modify: `components/mirror/SnapshotView.tsx` — Routine care rows: when `ended_at` present, render the span via the existing `fmt` helpers: `` `${fmtShort(a.performed_at)} … ` `` → show `"32 min"` suffix (compute minutes from the two ISO dates)
- Modify: `lib/fixtures/mirrorSnapshot.ts` — give one activity log an `ended_at` 32 min after `performed_at` so the preview exercises it
- Test: extend the iOS snapshot-builder test if one exists (grep `PetHomepageTests` for `SnapshotBuilder`); web: `npx tsc --noEmit` + `/dev/preview` screenshot

- [ ] **Step 1: iOS changes; push; CI green**
- [ ] **Step 2: Web changes; `npx tsc --noEmit` passes; dev-preview renders the "· 32 min" row**
- [ ] **Step 3: Commit**

```bash
git add -A ios lib components && git commit -m "feat: mirror schema +ended_at on activity logs; web shows durations" && git push
```

---

### Task 13: Merge gate + release

- [ ] **Step 1: Full self-review of the branch diff** (`git diff main...walk-sessions` — check for leftover debug code, spec coverage, consistent naming)
- [ ] **Step 2: Confirm `iOS Tests` green on the final branch push**
- [ ] **Step 3: Merge to main** (no PR needed unless requested: `git checkout main && git merge --no-ff walk-sessions && git push`) — this triggers the TestFlight archive; watch it green (`gh run watch`)
- [ ] **Step 4: Manual follow-ups for Suzi (cannot be done from CI):**
  - Run a Debug build once from Xcode (or first TestFlight install) and then **promote the CloudKit schema to Production** in the CloudKit dashboard — the new `endedAt` field won't sync for TestFlight users until promoted.
  - On-device sanity pass: pair, log a walk manually, set home location, take an actual walk (the tuning constants in `WalkDetectionTuning` are the knobs if prompts feel late/early).
