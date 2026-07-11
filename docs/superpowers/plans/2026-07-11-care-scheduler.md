# Care Scheduler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new Schedule tab where each pet gets a day-by-day care checklist driven by a versioned, day-of-week-aware weekly template, with local notifications, check-offs that write `LogEntry` records, and optional photo capture per completion.

**Architecture:** The weekly template (`RoutineTask` rows with effective-date windows) is the source of truth; a day's checklist is *computed*, never materialized. Only deviations are stored: completions (as `LogEntry` kind `routine` with fields copied on), skips (`RoutineSkip`), and one-off tasks (single-day `RoutineTask` windows). Notifications reuse the existing `NotificationScheduling` layer, extended with repeating-weekly triggers.

**Tech Stack:** SwiftUI (iOS 17), Core Data + CloudKit (`NSPersistentCloudKitContainer`), XcodeGen, XCTest + XCUITest.

**Spec:** `docs/superpowers/specs/2026-07-11-care-scheduler-design.md`

## Global Constraints

- iOS deployment target **17.0**, Swift **5.9** (`ios/project.yml`).
- Xcode project is generated: after adding files run `cd ios && xcodegen generate` (sources are path globs — new files under `ios/PetHomepage/` are picked up automatically).
- Core Data model changes must be **additive only** (lightweight migration + CloudKit): new entities/attributes optional or defaulted, `syncable="YES"`, `codeGenerationType="none"`, manual `NSManagedObject` subclasses.
- Copy pattern: history never rewrites — completed entries carry copied-on fields; template edits close rows and spawn successors.
- All stores are pet-scoped through `PetStore.currentPet()` / `ensurePet()`.
- Weekday convention: `Calendar` weekdays, 1 = Sunday … 7 = Saturday; `weekdayMask` bit `(weekday - 1)`.
- **Test command (macOS only):** `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16'`. This workstation is Linux and cannot compile Swift — write tests first anyway (TDD ordering preserved), run the suite on a Mac/CI before merging. Every "run test" step below carries this caveat implicitly.
- Commit after every task with the message given in its final step, ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Core Data model + RoutineTask/RoutineSkip subclasses + LogKind.routine

**Files:**
- Modify: `ios/PetHomepage/Persistence/PetHomepage.xcdatamodeld/PetHomepage.xcdatamodel/contents`
- Modify: `ios/PetHomepage/Models/Pet.swift`
- Modify: `ios/PetHomepage/Models/LogEntry.swift`
- Create: `ios/PetHomepage/Models/RoutineTask.swift`
- Create: `ios/PetHomepage/Models/RoutineSkip.swift`
- Test: `ios/PetHomepageTests/RoutineTaskModelTests.swift`

**Interfaces:**
- Consumes: existing `Pet`, `LogEntry`, `ActivityCategory`, `PersistenceController`.
- Produces: `RoutineTask` (attrs: `id, lineageID, name, categoryRaw, iconName, hour, minute, weekdayMask, effectiveFrom, effectiveUntil, isOneOff, sortOrder, pet` + `category: ActivityCategory` accessor), `RoutineSkip` (`id, date, taskLineageID, pet`), `LogEntry.routineLineageID: UUID?`, `LogKind.routine`, and `enum Weekdays` (`all: Int64`, `bit(for:) -> Int64`, `contains(_:weekday:) -> Bool`, `mask(of:) -> Int64`, `weekdays(in:) -> [Int]`).

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/RoutineTaskModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineTaskModelTests: XCTestCase {
    func testWeekdayMaskHelpers() {
        // Calendar weekdays: 1 = Sunday … 7 = Saturday; bit = weekday - 1.
        XCTAssertEqual(Weekdays.all, 0b111_1111)
        XCTAssertEqual(Weekdays.bit(for: 1), 0b000_0001) // Sunday
        XCTAssertEqual(Weekdays.bit(for: 7), 0b100_0000) // Saturday
        XCTAssertEqual(Weekdays.mask(of: [3, 5]), 0b001_0100) // Tue + Thu
        XCTAssertTrue(Weekdays.contains(0b001_0100, weekday: 3))
        XCTAssertFalse(Weekdays.contains(0b001_0100, weekday: 2))
        XCTAssertEqual(Weekdays.weekdays(in: 0b001_0100), [3, 5])
        XCTAssertEqual(Weekdays.weekdays(in: Weekdays.all), [1, 2, 3, 4, 5, 6, 7])
    }

    func testRoutineEntitiesInsertAndFetch() throws {
        let context = PersistenceController(inMemory: true).container.viewContext

        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = "Morning walk"
        task.category = .play
        task.iconName = "figure.walk"
        task.hour = 8
        task.minute = 0
        task.weekdayMask = Weekdays.all
        task.effectiveFrom = Date()

        let skip = RoutineSkip(context: context)
        skip.id = UUID()
        skip.date = Date()
        skip.taskLineageID = task.lineageID

        try context.save()

        XCTAssertEqual(try context.fetch(RoutineTask.fetchRequest()).count, 1)
        XCTAssertEqual(try context.fetch(RoutineSkip.fetchRequest()).count, 1)
        XCTAssertEqual(try context.fetch(RoutineTask.fetchRequest()).first?.category, .play)
        XCTAssertNil(task.effectiveUntil)
        XCTAssertFalse(task.isOneOff)
    }

    func testLogEntryRoutineKindAndLineage() throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let entry = LogEntry(context: context)
        entry.id = UUID()
        entry.performedAt = Date()
        entry.kind = .routine
        entry.routineLineageID = UUID()
        try context.save()
        XCTAssertEqual(entry.kindRaw, "routine")
        XCTAssertNotNil(entry.routineLineageID)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (macOS): `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PetHomepageTests/RoutineTaskModelTests`
Expected: FAIL — `Weekdays`, `RoutineTask`, `RoutineSkip`, `routineLineageID` not defined.

- [ ] **Step 3: Add the two entities + LogEntry attribute + Pet relationships to the Core Data model**

In `ios/PetHomepage/Persistence/PetHomepage.xcdatamodeld/PetHomepage.xcdatamodel/contents`, add before `</model>`:

```xml
    <entity name="RoutineTask" representedClassName="RoutineTask" syncable="YES" codeGenerationType="none">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="lineageID" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="name" optional="NO" attributeType="String" defaultValueString=""/>
        <attribute name="categoryRaw" optional="NO" attributeType="String" defaultValueString="other"/>
        <attribute name="iconName" optional="NO" attributeType="String" defaultValueString="pawprint"/>
        <attribute name="hour" optional="YES" attributeType="Integer 64" defaultValueString="9" usesScalarValueType="YES"/>
        <attribute name="minute" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="weekdayMask" optional="YES" attributeType="Integer 64" defaultValueString="127" usesScalarValueType="YES"/>
        <attribute name="effectiveFrom" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="effectiveUntil" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="isOneOff" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <attribute name="sortOrder" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
        <relationship name="pet" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Pet" inverseName="routineTasks" inverseEntity="Pet"/>
    </entity>
    <entity name="RoutineSkip" representedClassName="RoutineSkip" syncable="YES" codeGenerationType="none">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="date" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="taskLineageID" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <relationship name="pet" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Pet" inverseName="routineSkips" inverseEntity="Pet"/>
    </entity>
```

Inside the existing `<entity name="Pet" …>` block, add alongside the other relationships:

```xml
        <relationship name="routineTasks" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="RoutineTask" inverseName="pet" inverseEntity="RoutineTask"/>
        <relationship name="routineSkips" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="RoutineSkip" inverseName="pet" inverseEntity="RoutineSkip"/>
```

Inside the existing `<entity name="LogEntry" …>` block, add alongside the other attributes:

```xml
        <attribute name="routineLineageID" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
```

(All additive — lightweight migration handles existing stores; CloudKit dev schema picks the new record types up on next run.)

- [ ] **Step 4: Create the NSManagedObject subclasses**

```swift
// ios/PetHomepage/Models/RoutineTask.swift
import CoreData

/// Weekday-mask helpers shared by the routine template and its scheduler.
/// Calendar weekdays: 1 = Sunday … 7 = Saturday; a weekday's bit is `1 << (weekday - 1)`.
enum Weekdays {
    static let all: Int64 = 0b111_1111

    static func bit(for weekday: Int) -> Int64 { 1 << Int64(weekday - 1) }

    static func contains(_ mask: Int64, weekday: Int) -> Bool {
        mask & bit(for: weekday) != 0
    }

    static func mask(of weekdays: [Int]) -> Int64 {
        weekdays.reduce(0) { $0 | bit(for: $1) }
    }

    static func weekdays(in mask: Int64) -> [Int] {
        (1...7).filter { contains(mask, weekday: $0) }
    }
}

/// One versioned row of the weekly care template. Edits never mutate a row that has been in
/// effect before today — they close it (`effectiveUntil`) and spawn a successor sharing the same
/// `lineageID`, so past days forever compute against the template as it was then. A one-off task
/// for a single day is just a row whose window covers exactly that day (`isOneOff` flags it so
/// the template editor can hide it).
@objc(RoutineTask)
public class RoutineTask: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var lineageID: UUID
    @NSManaged public var name: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var iconName: String
    @NSManaged public var hour: Int64
    @NSManaged public var minute: Int64
    @NSManaged public var weekdayMask: Int64
    @NSManaged public var effectiveFrom: Date
    @NSManaged public var effectiveUntil: Date?
    @NSManaged public var isOneOff: Bool
    @NSManaged public var sortOrder: Int64
    @NSManaged public var pet: Pet?
}

extension RoutineTask {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<RoutineTask> {
        NSFetchRequest<RoutineTask>(entityName: "RoutineTask")
    }

    /// Strongly-typed view of `categoryRaw`; falls back to `.other` for unknown values.
    var category: ActivityCategory {
        get { ActivityCategory(rawValueOrOther: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }
}

extension RoutineTask: Identifiable {}
```

```swift
// ios/PetHomepage/Models/RoutineSkip.swift
import CoreData

/// Deviation record: "this routine task is deliberately skipped on this day." Existence is the
/// whole signal — un-skipping deletes the record. Keyed by the task's lineageID (stable across
/// template versions) and a day-granular date.
@objc(RoutineSkip)
public class RoutineSkip: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var taskLineageID: UUID
    @NSManaged public var pet: Pet?
}

extension RoutineSkip {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<RoutineSkip> {
        NSFetchRequest<RoutineSkip>(entityName: "RoutineSkip")
    }
}

extension RoutineSkip: Identifiable {}
```

- [ ] **Step 5: Extend Pet and LogEntry**

In `ios/PetHomepage/Models/Pet.swift`, add to the class body after `@NSManaged public var photos: NSSet?`:

```swift
    @NSManaged public var routineTasks: NSSet?
    @NSManaged public var routineSkips: NSSet?
```

In `ios/PetHomepage/Models/LogEntry.swift`:
1. Add `case routine` to `LogKind` (after `case symptom`).
2. Add to the `LogEntry` class body after `@NSManaged public var resolvedAt: Date?`:

```swift
    @NSManaged public var routineLineageID: UUID?
```

- [ ] **Step 6: Run test to verify it passes**

Run (macOS): same command as Step 2. Expected: PASS (3 tests). Also confirm the full existing suite still passes — `backfillKindsIfNeeded` and Timeline are untouched by a new enum case with no data.

- [ ] **Step 7: Commit**

```bash
git add ios/PetHomepage/Persistence ios/PetHomepage/Models ios/PetHomepageTests/RoutineTaskModelTests.swift
git commit -m "feat: RoutineTask/RoutineSkip entities + LogKind.routine (care scheduler data model)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: RoutineStore — versioned template CRUD + one-offs

**Files:**
- Create: `ios/PetHomepage/Stores/RoutineStore.swift`
- Test: `ios/PetHomepageTests/RoutineStoreTests.swift`

**Interfaces:**
- Consumes: `RoutineTask`, `Weekdays`, `PetStore` (`currentPet()`, `ensurePet()`), `ActivityCategory`.
- Produces (used by every later task):
  - `RoutineStore(context:petStore:calendar:)`
  - `createTask(name:category:iconName:hour:minute:weekdayMask:from:) throws -> RoutineTask`
  - `currentTasks() throws -> [RoutineTask]` — open-ended template rows (no one-offs), time-sorted
  - `editTask(_:name:category:iconName:hour:minute:weekdayMask:on:) throws -> RoutineTask`
  - `endTask(_:on:) throws`
  - `addOneOff(name:category:iconName:hour:minute:on:) throws -> RoutineTask`

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/RoutineStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!
    private let calendar = Calendar.current

    /// A fixed "today" so tests are deterministic regardless of wall clock.
    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
    }

    func testCreateTaskIsListedAndScopedToPet() throws {
        let task = try store.createTask(name: "Morning walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all)
        XCTAssertEqual(task.lineageID, task.lineageID) // stable, non-nil
        let tasks = try store.currentTasks()
        XCTAssertEqual(tasks.map(\.name), ["Morning walk"])
        XCTAssertEqual(tasks.first?.pet?.name, "Sandy")
        XCTAssertNil(tasks.first?.effectiveUntil)
    }

    func testCurrentTasksSortByTime() throws {
        try store.createTask(name: "Dinner", category: .feeding, iconName: "fork.knife",
                             hour: 18, minute: 0, weekdayMask: Weekdays.all)
        try store.createTask(name: "Breakfast", category: .feeding, iconName: "fork.knife",
                             hour: 7, minute: 0, weekdayMask: Weekdays.all)
        XCTAssertEqual(try store.currentTasks().map(\.name), ["Breakfast", "Dinner"])
    }

    func testEditOfHistoricalTaskClosesRowAndSpawnsSuccessor() throws {
        let original = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                            hour: 8, minute: 0, weekdayMask: Weekdays.all,
                                            from: day(-10))
        let successor = try store.editTask(original, name: "Long walk", category: .play,
                                           iconName: "figure.walk", hour: 9, minute: 30,
                                           weekdayMask: Weekdays.all)
        XCTAssertNotEqual(successor.id, original.id)
        XCTAssertEqual(successor.lineageID, original.lineageID)
        XCTAssertEqual(original.effectiveUntil, today)
        XCTAssertEqual(successor.effectiveFrom, today)
        XCTAssertEqual(successor.name, "Long walk")
        XCTAssertEqual(successor.hour, 9)
        // Only the successor is "current".
        XCTAssertEqual(try store.currentTasks().map(\.name), ["Long walk"])
    }

    func testEditOfTaskCreatedTodayMutatesInPlace() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all)
        let edited = try store.editTask(task, name: "Jog", category: .play, iconName: "figure.run",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all)
        XCTAssertEqual(edited.id, task.id) // no successor: nothing historical to preserve
        XCTAssertEqual(try store.currentTasks().map(\.name), ["Jog"])
    }

    func testEndTaskClosesHistoricalRowButDeletesSameDayRow() throws {
        let historical = try store.createTask(name: "Old", category: .care, iconName: "heart",
                                              hour: 8, minute: 0, weekdayMask: Weekdays.all,
                                              from: day(-5))
        try store.endTask(historical)
        XCTAssertEqual(historical.effectiveUntil, today) // closed, not deleted

        let fresh = try store.createTask(name: "New", category: .care, iconName: "heart",
                                         hour: 9, minute: 0, weekdayMask: Weekdays.all)
        try store.endTask(fresh)
        let all = try context.fetch(RoutineTask.fetchRequest())
        XCTAssertFalse(all.contains { $0.name == "New" }) // genuinely deleted
        XCTAssertEqual(try store.currentTasks().count, 0)
    }

    func testAddOneOffCoversExactlyOneDay() throws {
        let target = day(2)
        let oneOff = try store.addOneOff(name: "Vet pickup", category: .health, iconName: "cross.case",
                                         hour: 15, minute: 0, on: target)
        XCTAssertTrue(oneOff.isOneOff)
        XCTAssertEqual(oneOff.effectiveFrom, target)
        XCTAssertEqual(oneOff.effectiveUntil, day(3))
        let weekday = calendar.component(.weekday, from: target)
        XCTAssertEqual(oneOff.weekdayMask, Weekdays.bit(for: weekday))
        // One-offs never appear in the template editor list.
        XCTAssertFalse(try store.currentTasks().contains { $0.isOneOff })
    }

    func testEmptyWhenNoPetExists() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = RoutineStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try emptyStore.currentTasks().count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (macOS): `xcodebuild test … -only-testing:PetHomepageTests/RoutineStoreTests`
Expected: FAIL — `RoutineStore` not defined.

- [ ] **Step 3: Implement RoutineStore (template CRUD)**

```swift
// ios/PetHomepage/Stores/RoutineStore.swift
import CoreData

/// The versioned weekly care template + per-day deviations, pet-scoped. A day's checklist is
/// COMPUTED from the template rows in effect on that date (see slots(for:) added alongside the
/// day-computation methods) — days are never materialized, so CloudKit sync can't double-create
/// them. Only deviations are stored: completions (LogEntry kind .routine), skips (RoutineSkip),
/// and one-off tasks (single-day RoutineTask windows).
final class RoutineStore {
    let context: NSManagedObjectContext
    let petStore: PetStore
    let calendar: Calendar

    init(context: NSManagedObjectContext, petStore: PetStore, calendar: Calendar = .current) {
        self.context = context
        self.petStore = petStore
        self.calendar = calendar
    }

    // MARK: - Template CRUD (versioned)

    @discardableResult
    func createTask(name: String,
                    category: ActivityCategory,
                    iconName: String,
                    hour: Int,
                    minute: Int,
                    weekdayMask: Int64,
                    from day: Date = Date()) throws -> RoutineTask {
        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = name
        task.category = category
        task.iconName = iconName
        task.hour = Int64(hour)
        task.minute = Int64(minute)
        task.weekdayMask = weekdayMask
        task.effectiveFrom = calendar.startOfDay(for: day)
        task.effectiveUntil = nil
        task.isOneOff = false
        task.sortOrder = Int64(try currentTasks().count)
        task.pet = try petStore.ensurePet()
        try context.save()
        return task
    }

    /// The open-ended template rows (the "current routine" the editor shows). One-offs excluded.
    func currentTasks() throws -> [RoutineTask] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = RoutineTask.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@ AND effectiveUntil == nil AND isOneOff == NO", pet)
        return try context.fetch(request).sorted(by: Self.byTime)
    }

    /// Versioned edit: close the current row as of `day` and spawn a successor sharing its
    /// lineageID, so past days keep computing against the old version. A row that only became
    /// effective today (or a one-off) has no history to preserve — it's edited in place.
    @discardableResult
    func editTask(_ task: RoutineTask,
                  name: String,
                  category: ActivityCategory,
                  iconName: String,
                  hour: Int,
                  minute: Int,
                  weekdayMask: Int64,
                  on day: Date = Date()) throws -> RoutineTask {
        let today = calendar.startOfDay(for: day)
        if task.effectiveFrom >= today || task.isOneOff {
            task.name = name
            task.category = category
            task.iconName = iconName
            task.hour = Int64(hour)
            task.minute = Int64(minute)
            task.weekdayMask = weekdayMask
            try context.save()
            return task
        }
        task.effectiveUntil = today
        let successor = RoutineTask(context: context)
        successor.id = UUID()
        successor.lineageID = task.lineageID
        successor.name = name
        successor.category = category
        successor.iconName = iconName
        successor.hour = Int64(hour)
        successor.minute = Int64(minute)
        successor.weekdayMask = weekdayMask
        successor.effectiveFrom = today
        successor.effectiveUntil = nil
        successor.isOneOff = false
        successor.sortOrder = task.sortOrder
        successor.pet = task.pet
        try context.save()
        return successor
    }

    /// "Delete" = close the window as of `day`; past days keep the task. A row that never
    /// applied to a past day (created today, or a one-off) is genuinely deleted.
    func endTask(_ task: RoutineTask, on day: Date = Date()) throws {
        let today = calendar.startOfDay(for: day)
        if task.effectiveFrom >= today || task.isOneOff {
            context.delete(task)
        } else {
            task.effectiveUntil = today
        }
        try context.save()
    }

    // MARK: - One-offs

    /// A task for a single day only: a template row whose effective window covers exactly `day`.
    @discardableResult
    func addOneOff(name: String,
                   category: ActivityCategory,
                   iconName: String,
                   hour: Int,
                   minute: Int,
                   on day: Date) throws -> RoutineTask {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            throw NSError(domain: "RoutineStore", code: 1)
        }
        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = name
        task.category = category
        task.iconName = iconName
        task.hour = Int64(hour)
        task.minute = Int64(minute)
        task.weekdayMask = Weekdays.bit(for: calendar.component(.weekday, from: start))
        task.effectiveFrom = start
        task.effectiveUntil = end
        task.isOneOff = true
        task.sortOrder = 0
        task.pet = try petStore.ensurePet()
        try context.save()
        return task
    }

    /// Time-of-day sort shared by the template list and day slots.
    static func byTime(_ l: RoutineTask, _ r: RoutineTask) -> Bool {
        if l.hour != r.hour { return l.hour < r.hour }
        if l.minute != r.minute { return l.minute < r.minute }
        if l.sortOrder != r.sortOrder { return l.sortOrder < r.sortOrder }
        return l.name < r.name
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (macOS): same command. Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Stores/RoutineStore.swift ios/PetHomepageTests/RoutineStoreTests.swift
git commit -m "feat: RoutineStore — versioned template CRUD + one-off tasks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: RoutineStore — day computation + skips

**Files:**
- Modify: `ios/PetHomepage/Stores/RoutineStore.swift`
- Test: `ios/PetHomepageTests/RoutineStoreDayTests.swift`

**Interfaces:**
- Consumes: Task 2's `RoutineStore` API.
- Produces:
  - `struct RoutineSlot: Identifiable { let task: RoutineTask; let completion: LogEntry?; let skip: RoutineSkip?; var id: UUID { task.lineageID }; var isCompleted: Bool; var isSkipped: Bool }`
  - `slots(for day: Date) throws -> [RoutineSlot]`
  - `skip(_ task: RoutineTask, on day: Date) throws` / `unskip(_ task: RoutineTask, on day: Date) throws`

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/RoutineStoreDayTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineStoreDayTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!
    private let calendar = Calendar.current

    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
    }

    func testSlotsHonorWeekdayMask() throws {
        let weekdayToday = calendar.component(.weekday, from: today)
        let weekdayTomorrow = calendar.component(.weekday, from: day(1))
        try store.createTask(name: "Today only", category: .care, iconName: "heart",
                             hour: 8, minute: 0, weekdayMask: Weekdays.bit(for: weekdayToday),
                             from: day(-7))
        try store.createTask(name: "Tomorrow only", category: .care, iconName: "heart",
                             hour: 9, minute: 0, weekdayMask: Weekdays.bit(for: weekdayTomorrow),
                             from: day(-7))
        XCTAssertEqual(try store.slots(for: today).map(\.task.name), ["Today only"])
        XCTAssertEqual(try store.slots(for: day(1)).map(\.task.name), ["Tomorrow only"])
    }

    func testSlotsHonorEffectiveWindows() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all,
                                        from: day(-10))
        try store.editTask(task, name: "Long walk", category: .play, iconName: "figure.walk",
                           hour: 8, minute: 0, weekdayMask: Weekdays.all)
        // Yesterday computes against the old version; today against the successor.
        XCTAssertEqual(try store.slots(for: day(-1)).map(\.task.name), ["Walk"])
        XCTAssertEqual(try store.slots(for: today).map(\.task.name), ["Long walk"])
        // Before the task ever existed: nothing.
        XCTAssertEqual(try store.slots(for: day(-11)).count, 0)
    }

    func testOneOffAppearsOnlyOnItsDay() throws {
        try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                             hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        try store.addOneOff(name: "Vet pickup", category: .health, iconName: "cross.case",
                            hour: 15, minute: 0, on: day(2))
        XCTAssertEqual(try store.slots(for: day(2)).map(\.task.name), ["Walk", "Vet pickup"])
        XCTAssertEqual(try store.slots(for: today).map(\.task.name), ["Walk"])
        XCTAssertEqual(try store.slots(for: day(3)).map(\.task.name), ["Walk"])
    }

    func testSkipAndUnskipOverlay() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        try store.skip(task, on: today)
        var slot = try XCTUnwrap(try store.slots(for: today).first)
        XCTAssertTrue(slot.isSkipped)
        // Skips are per-day: yesterday untouched.
        XCTAssertFalse(try XCTUnwrap(try store.slots(for: day(-1)).first).isSkipped)
        // Skipping twice is a no-op (idempotent), unskip removes.
        try store.skip(task, on: today)
        XCTAssertEqual(try context.fetch(RoutineSkip.fetchRequest()).count, 1)
        try store.unskip(task, on: today)
        slot = try XCTUnwrap(try store.slots(for: today).first)
        XCTAssertFalse(slot.isSkipped)
        XCTAssertEqual(try context.fetch(RoutineSkip.fetchRequest()).count, 0)
    }

    func testSlotsSortByTime() throws {
        try store.createTask(name: "Dinner", category: .feeding, iconName: "fork.knife",
                             hour: 18, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        try store.createTask(name: "Breakfast", category: .feeding, iconName: "fork.knife",
                             hour: 7, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        XCTAssertEqual(try store.slots(for: today).map(\.task.name), ["Breakfast", "Dinner"])
    }

    func testSlotsEmptyWithoutPet() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = RoutineStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try emptyStore.slots(for: Date()).count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `RoutineSlot`, `slots(for:)`, `skip`, `unskip` not defined.

- [ ] **Step 3: Implement day computation + skips**

Add to `RoutineStore.swift` (top-level struct above the class):

```swift
/// One row of a day's checklist: the template task in effect that day plus its per-day state.
/// Identity is the lineageID — stable across template versions, unique within a day.
struct RoutineSlot: Identifiable {
    let task: RoutineTask
    let completion: LogEntry?
    let skip: RoutineSkip?

    var id: UUID { task.lineageID }
    var isCompleted: Bool { completion != nil }
    var isSkipped: Bool { skip != nil }
}
```

Add to the `RoutineStore` class:

```swift
    // MARK: - Day computation

    /// The checklist for `day`, computed from template rows in effect on that date (weekday
    /// match + effective window), overlaid with that day's completions and skips. Pure read.
    func slots(for day: Date) throws -> [RoutineSlot] {
        guard let pet = try petStore.currentPet() else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let weekday = calendar.component(.weekday, from: start)

        let taskRequest = RoutineTask.fetchRequest()
        taskRequest.predicate = NSPredicate(
            format: "pet == %@ AND effectiveFrom <= %@ AND (effectiveUntil == nil OR effectiveUntil > %@)",
            pet, start as NSDate, start as NSDate)
        let tasks = try context.fetch(taskRequest)
            .filter { Weekdays.contains($0.weekdayMask, weekday: weekday) }
            .sorted(by: Self.byTime)

        let completionRequest = LogEntry.fetchRequest()
        completionRequest.predicate = NSPredicate(
            format: "pet == %@ AND kindRaw == %@ AND performedAt >= %@ AND performedAt < %@",
            pet, LogKind.routine.rawValue, start as NSDate, end as NSDate)
        var completions: [UUID: LogEntry] = [:]
        for entry in try context.fetch(completionRequest) {
            if let lineage = entry.routineLineageID { completions[lineage] = entry }
        }

        let skipRequest = RoutineSkip.fetchRequest()
        skipRequest.predicate = NSPredicate(format: "pet == %@ AND date == %@", pet, start as NSDate)
        var skips: [UUID: RoutineSkip] = [:]
        for skip in try context.fetch(skipRequest) {
            skips[skip.taskLineageID] = skip
        }

        return tasks.map {
            RoutineSlot(task: $0, completion: completions[$0.lineageID], skip: skips[$0.lineageID])
        }
    }

    // MARK: - Skips

    /// Marks the task's lineage as deliberately skipped on `day`. Idempotent.
    func skip(_ task: RoutineTask, on day: Date) throws {
        guard try skipRecord(lineageID: task.lineageID, on: day) == nil else { return }
        let skip = RoutineSkip(context: context)
        skip.id = UUID()
        skip.date = calendar.startOfDay(for: day)
        skip.taskLineageID = task.lineageID
        skip.pet = try petStore.ensurePet()
        try context.save()
    }

    func unskip(_ task: RoutineTask, on day: Date) throws {
        guard let record = try skipRecord(lineageID: task.lineageID, on: day) else { return }
        context.delete(record)
        try context.save()
    }

    private func skipRecord(lineageID: UUID, on day: Date) throws -> RoutineSkip? {
        let start = calendar.startOfDay(for: day)
        let request = RoutineSkip.fetchRequest()
        request.predicate = NSPredicate(format: "taskLineageID == %@ AND date == %@",
                                        lineageID as CVarArg, start as NSDate)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS (6 tests), plus Task 2's suite still green.

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Stores/RoutineStore.swift ios/PetHomepageTests/RoutineStoreDayTests.swift
git commit -m "feat: RoutineStore day computation — slots(for:) with skip overlay

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: RoutineStore — check-off / uncheck (LogEntry integration)

**Files:**
- Modify: `ios/PetHomepage/Stores/RoutineStore.swift`
- Test: `ios/PetHomepageTests/RoutineStoreCheckOffTests.swift`

**Interfaces:**
- Consumes: Tasks 2–3, `LogEntry`, `LogStore.addPhoto` (photos attach through the existing generic API — no new photo code).
- Produces:
  - `checkOff(_ task: RoutineTask, on day: Date, now: Date = Date()) throws -> LogEntry`
  - `uncheck(_ completion: LogEntry) throws`

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/RoutineStoreCheckOffTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineStoreCheckOffTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!
    private var logStore: LogStore!
    private let calendar = Calendar.current

    private var today: Date { calendar.startOfDay(for: Date()) }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today)!
    }

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
    }

    func testCheckOffWritesRoutineLogEntryWithCopiedFields() throws {
        let task = try store.createTask(name: "Morning walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        let now = Date()
        let entry = try store.checkOff(task, on: today, now: now)
        XCTAssertEqual(entry.kind, .routine)
        XCTAssertEqual(entry.title, "Morning walk") // copied on — template edits never rewrite it
        XCTAssertEqual(entry.routineLineageID, task.lineageID)
        XCTAssertEqual(entry.performedAt, now) // today's check-off stamps the actual moment
        XCTAssertEqual(entry.pet?.name, "Sandy")

        let slot = try XCTUnwrap(try store.slots(for: today).first)
        XCTAssertTrue(slot.isCompleted)
        XCTAssertEqual(slot.completion?.id, entry.id)
    }

    func testPastDayCheckOffStampsScheduledTime() throws {
        let task = try store.createTask(name: "Dinner", category: .feeding, iconName: "fork.knife",
                                        hour: 18, minute: 30, weekdayMask: Weekdays.all, from: day(-7))
        let entry = try store.checkOff(task, on: day(-2))
        let comps = calendar.dateComponents([.hour, .minute], from: entry.performedAt)
        XCTAssertEqual(comps.hour, 18)
        XCTAssertEqual(comps.minute, 30)
        XCTAssertTrue(calendar.isDate(entry.performedAt, inSameDayAs: day(-2)))
        XCTAssertTrue(try XCTUnwrap(try store.slots(for: day(-2)).first).isCompleted)
        XCTAssertFalse(try XCTUnwrap(try store.slots(for: today).first).isCompleted)
    }

    func testCompletionSurvivesTemplateEdit() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        let entry = try store.checkOff(task, on: today)
        let successor = try store.editTask(task, name: "Long walk", category: .play,
                                           iconName: "figure.walk", hour: 9, minute: 0,
                                           weekdayMask: Weekdays.all)
        XCTAssertEqual(entry.title, "Walk") // history frozen
        // The completion still overlays today's slot (lineage is shared).
        let slot = try XCTUnwrap(try store.slots(for: today).first)
        XCTAssertEqual(slot.task.id, successor.id)
        XCTAssertTrue(slot.isCompleted)
    }

    func testUncheckDeletesEntryAndItsPhotos() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        let entry = try store.checkOff(task, on: today)
        try logStore.addPhoto(to: entry, imageData: Data([0xFF]))
        try store.uncheck(entry)
        XCTAssertFalse(try XCTUnwrap(try store.slots(for: today).first).isCompleted)
        XCTAssertEqual(try context.fetch(Photo.fetchRequest()).count, 0) // cascade
        XCTAssertEqual(try logStore.allEntries().count, 0)
    }

    func testPhotoAttachesThroughExistingLogStoreAPI() throws {
        let task = try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                        hour: 8, minute: 0, weekdayMask: Weekdays.all, from: day(-7))
        let entry = try store.checkOff(task, on: today)
        try logStore.addPhoto(to: entry, imageData: Data([0x01, 0x02]))
        XCTAssertEqual(entry.photoArray.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `checkOff`, `uncheck` not defined.

- [ ] **Step 3: Implement check-off**

Add to the `RoutineStore` class:

```swift
    // MARK: - Check-off

    /// Completing a slot writes a routine LogEntry with the task's name copied on, so later
    /// template edits never rewrite what was actually done. Today's check-off stamps `now`
    /// (the real moment); a past day's stamps the task's scheduled time on that day, keeping
    /// the entry inside that day's window.
    @discardableResult
    func checkOff(_ task: RoutineTask, on day: Date, now: Date = Date()) throws -> LogEntry {
        let start = calendar.startOfDay(for: day)
        let performedAt: Date
        if calendar.isDate(now, inSameDayAs: start) {
            performedAt = now
        } else {
            performedAt = calendar.date(bySettingHour: Int(task.hour), minute: Int(task.minute),
                                        second: 0, of: start) ?? start
        }
        let entry = LogEntry(context: context)
        entry.id = UUID()
        entry.performedAt = performedAt
        entry.kind = .routine
        entry.title = task.name
        entry.routineLineageID = task.lineageID
        entry.pet = try petStore.ensurePet()
        try context.save()
        return entry
    }

    /// Un-checking deletes the completion entry (photos cascade with it).
    func uncheck(_ completion: LogEntry) throws {
        context.delete(completion)
        try context.save()
    }
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Stores/RoutineStore.swift ios/PetHomepageTests/RoutineStoreCheckOffTests.swift
git commit -m "feat: routine check-off/uncheck — LogEntry kind routine with copied-on fields

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: RoutineStore — seeded starter routine

**Files:**
- Modify: `ios/PetHomepage/Stores/RoutineStore.swift`
- Test: `ios/PetHomepageTests/RoutineStoreSeedingTests.swift`

**Interfaces:**
- Consumes: Task 2's `createTask`.
- Produces: `RoutineStore.defaultSeeds`, `seedDefaultsIfNeeded() throws` (called from `ContentView`'s existing `.task` in Task 9).

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/RoutineStoreSeedingTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineStoreSeedingTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
    }

    func testSeedsDefaultRoutineOnce() throws {
        try store.seedDefaultsIfNeeded()
        let names = try store.currentTasks().map(\.name)
        XCTAssertEqual(Set(names), ["Breakfast", "Morning walk", "Training", "Dinner", "Wind down"])
        // Training demonstrates day-of-week from minute one: Tue + Thu only.
        let training = try XCTUnwrap(try store.currentTasks().first { $0.name == "Training" })
        XCTAssertEqual(training.weekdayMask, Weekdays.mask(of: [3, 5]))
        // Idempotent.
        try store.seedDefaultsIfNeeded()
        XCTAssertEqual(try store.currentTasks().count, 5)
    }

    func testSeedingRespectsDeletedSeeds() throws {
        try store.seedDefaultsIfNeeded()
        let training = try XCTUnwrap(try store.currentTasks().first { $0.name == "Training" })
        // Make it historical so endTask closes (not deletes) the row, then re-seed.
        training.effectiveFrom = Calendar.current.date(byAdding: .day, value: -5,
                                                       to: Calendar.current.startOfDay(for: Date()))!
        try context.save()
        try store.endTask(training)
        try store.seedDefaultsIfNeeded()
        // The closed row still exists, so the seed must NOT resurrect Training.
        XCTAssertFalse(try store.currentTasks().contains { $0.name == "Training" })
    }

    func testSeedingNoOpWithoutPet() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = RoutineStore(context: ctx, petStore: PetStore(context: ctx))
        try emptyStore.seedDefaultsIfNeeded()
        XCTAssertEqual(try ctx.fetch(RoutineTask.fetchRequest()).count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `seedDefaultsIfNeeded` not defined.

- [ ] **Step 3: Implement seeding**

Add to the `RoutineStore` class:

```swift
    // MARK: - Seeding

    /// The starter routine, pre-seeded so the Schedule tab works with zero setup. Training is
    /// deliberately Tue+Thu so the day-of-week feature is visible from minute one.
    static let defaultSeeds: [(name: String, category: ActivityCategory, iconName: String,
                               hour: Int, minute: Int, weekdayMask: Int64)] = [
        ("Breakfast", .feeding, "fork.knife", 7, 0, Weekdays.all),
        ("Morning walk", .play, "figure.walk", 8, 0, Weekdays.all),
        ("Training", .training, "graduationcap", 17, 0, Weekdays.mask(of: [3, 5])),
        ("Dinner", .feeding, "fork.knife", 18, 0, Weekdays.all),
        ("Wind down", .care, "moon.stars", 21, 0, Weekdays.all),
    ]

    /// Seeds any default tasks that don't already exist. De-dupes by case-insensitive name
    /// against ALL rows for the pet — including closed versions and rows synced in via CloudKit —
    /// so re-running never double-seeds and never resurrects a task the user deleted.
    func seedDefaultsIfNeeded() throws {
        guard let pet = try petStore.currentPet() else { return }
        let request = RoutineTask.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        let existingNames = Set(try context.fetch(request).map { $0.name.lowercased() })
        for seed in Self.defaultSeeds where !existingNames.contains(seed.name.lowercased()) {
            try createTask(name: seed.name, category: seed.category, iconName: seed.iconName,
                           hour: seed.hour, minute: seed.minute, weekdayMask: seed.weekdayMask)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Stores/RoutineStore.swift ios/PetHomepageTests/RoutineStoreSeedingTests.swift
git commit -m "feat: seeded starter routine (Breakfast/Walk/Training Tue+Thu/Dinner/Wind down)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Notification layer — repeating-weekly triggers

**Files:**
- Modify: `ios/PetHomepage/Notifications/NotificationScheduling.swift`
- Modify: `ios/PetHomepage/Notifications/UNNotificationScheduler.swift`
- Modify: `ios/PetHomepageTests/Support/FakeNotificationScheduler.swift`
- Test: `ios/PetHomepageTests/ReminderIdentifierWeekdayTests.swift`

**Interfaces:**
- Consumes: existing `PendingReminder`, `ReminderKind`, `ReminderIdentifier`, `NotificationScheduling`.
- Produces:
  - `ReminderKind.routine`
  - `PendingReminder.repeats: Bool` (default `false`; existing inits unchanged in behavior). Semantics: `dateComponents == nil` → daily repeating (unchanged); `dateComponents != nil, repeats == false` → one-shot on that date (unchanged); `dateComponents != nil, repeats == true` → repeating on those components (weekly when components carry only `.weekday`).
  - `ReminderIdentifier.requestID(for reminder: PendingReminder) -> String` — appends `-w<weekday>` when the reminder is a repeating weekly one, so a task's per-weekday requests coexist.
  - `ReminderIdentifier.requestIDs(kind:entityID:) -> [String]` — base ID + all 7 weekday variants (for cancel).
  - `ReminderIdentifier.parse` handles the `-w<d>` suffix and returns the base `(kind, entityID)`.
  - `FakeNotificationScheduler.schedule` replaces per `(kind, entityID, dateComponents?.weekday)` — existing kinds never set `weekday`, so their replace semantics are untouched.

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/ReminderIdentifierWeekdayTests.swift
import XCTest
@testable import PetHomepage

final class ReminderIdentifierWeekdayTests: XCTestCase {
    private let id = UUID()

    private func weekly(_ weekday: Int) -> PendingReminder {
        PendingReminder(kind: .routine, entityID: id, title: "Walk", body: "Time for a walk",
                        hour: 8, minute: 0, dateComponents: DateComponents(weekday: weekday),
                        repeats: true)
    }

    func testWeeklyRequestIDsCarryWeekdaySuffix() {
        XCTAssertEqual(ReminderIdentifier.requestID(for: weekly(3)),
                       "routine-reminder-\(id.uuidString)-w3")
        // Non-weekly reminders keep the bare ID (back-compat with everything shipped).
        let daily = PendingReminder(kind: .medication, entityID: id, title: "t", body: "b",
                                    hour: 9, minute: 0)
        XCTAssertEqual(ReminderIdentifier.requestID(for: daily),
                       "medication-reminder-\(id.uuidString)")
    }

    func testParseHandlesWeekdaySuffix() throws {
        let (kind, parsed) = try XCTUnwrap(
            ReminderIdentifier.parse("routine-reminder-\(id.uuidString)-w5"))
        XCTAssertEqual(kind, .routine)
        XCTAssertEqual(parsed, id)
        // Bare IDs still parse.
        XCTAssertNotNil(ReminderIdentifier.parse("routine-reminder-\(id.uuidString)"))
        XCTAssertNil(ReminderIdentifier.parse("routine-reminder-not-a-uuid-w5"))
    }

    func testRequestIDsForCancelCoverBaseAndAllWeekdays() {
        let ids = ReminderIdentifier.requestIDs(kind: .routine, entityID: id)
        XCTAssertEqual(ids.count, 8)
        XCTAssertTrue(ids.contains("routine-reminder-\(id.uuidString)"))
        XCTAssertTrue(ids.contains("routine-reminder-\(id.uuidString)-w1"))
        XCTAssertTrue(ids.contains("routine-reminder-\(id.uuidString)-w7"))
    }

    func testFakeSchedulerKeepsPerWeekdayReminders() async {
        let fake = FakeNotificationScheduler()
        await fake.schedule(weekly(2))
        await fake.schedule(weekly(4))
        XCTAssertEqual(fake.scheduled.count, 2) // distinct weekdays coexist
        await fake.schedule(weekly(2))
        XCTAssertEqual(fake.scheduled.count, 2) // same weekday replaces
        await fake.cancel(kind: .routine, entityID: id)
        XCTAssertEqual(fake.scheduled.count, 0) // cancel clears every weekday
    }

    func testPendingReminderDefaultsPreserveBackCompat() {
        let medication = PendingMedicationReminder(medicationID: id, title: "t", body: "b",
                                                   hour: 9, minute: 0)
        XCTAssertFalse(medication.repeats)
        XCTAssertNil(medication.dateComponents)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — no `.routine` kind, no `repeats`, no `requestID(for:)` / `requestIDs(kind:entityID:)`.

- [ ] **Step 3: Extend NotificationScheduling.swift**

1. Add `case routine` to `ReminderKind`, and make it `CaseIterable`:

```swift
enum ReminderKind: String, CaseIterable {
    case medication
    case vaccination
    case vetCadence
    case activity
    case routine
}
```

2. Add `repeats` to `PendingReminder` (keeps every existing call site compiling — new param has a default):

```swift
struct PendingReminder: Equatable {
    let kind: ReminderKind
    let entityID: UUID
    let title: String
    let body: String
    let hour: Int
    let minute: Int
    let dateComponents: DateComponents?
    /// With non-nil dateComponents: false = one-shot on that date (vaccination/vet-cadence),
    /// true = repeating on those components (weekly routine reminders, components = [weekday]).
    /// Ignored when dateComponents is nil (always the daily repeating medication trigger).
    let repeats: Bool

    init(kind: ReminderKind,
         entityID: UUID,
         title: String,
         body: String,
         hour: Int,
         minute: Int,
         dateComponents: DateComponents? = nil,
         repeats: Bool = false) {
        self.kind = kind
        self.entityID = entityID
        self.title = title
        self.body = body
        self.hour = hour
        self.minute = minute
        self.dateComponents = dateComponents
        self.repeats = repeats
    }
}
```

3. In `ReminderIdentifier`: replace the hardcoded kind array in `parse` with `ReminderKind.allCases`, strip an optional `-w<digit>` suffix before UUID parsing, and add the two new helpers:

```swift
enum ReminderIdentifier {
    static func prefix(for kind: ReminderKind) -> String {
        "\(kind.rawValue)-reminder-"
    }

    static func requestID(kind: ReminderKind, entityID: UUID) -> String {
        prefix(for: kind) + entityID.uuidString
    }

    /// The request ID for a specific reminder. Repeating-weekly reminders get a `-w<weekday>`
    /// suffix so one task's per-weekday requests coexist instead of replacing each other.
    static func requestID(for reminder: PendingReminder) -> String {
        let base = requestID(kind: reminder.kind, entityID: reminder.entityID)
        if reminder.repeats, let weekday = reminder.dateComponents?.weekday {
            return base + "-w\(weekday)"
        }
        return base
    }

    /// Every request ID a (kind, entityID) pair could own: the bare ID plus all weekday
    /// variants. Used by cancel — removing IDs that were never scheduled is harmless.
    static func requestIDs(kind: ReminderKind, entityID: UUID) -> [String] {
        let base = requestID(kind: kind, entityID: entityID)
        return [base] + (1...7).map { "\(base)-w\($0)" }
    }

    static func parse(_ requestID: String) -> (ReminderKind, UUID)? {
        // Strip an optional "-w<digit>" weekly suffix before parsing the UUID.
        var body = requestID
        if let range = body.range(of: #"-w[1-7]$"#, options: .regularExpression) {
            body.removeSubrange(range)
        }
        for kind in ReminderKind.allCases {
            let prefix = prefix(for: kind)
            if body.hasPrefix(prefix),
               let id = UUID(uuidString: String(body.dropFirst(prefix.count))) {
                return (kind, id)
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Update UNNotificationScheduler**

In `schedule(_:)`, replace the trigger construction and ID line:

```swift
        let trigger: UNCalendarNotificationTrigger
        if let date = reminder.dateComponents {
            var components = date
            components.hour = reminder.hour
            components.minute = reminder.minute
            // repeats == false: one-shot on a specific calendar date (vaccination/vet-cadence).
            // repeats == true: repeating on the given components (weekly, components = [weekday]).
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: reminder.repeats)
        } else {
            // Daily repeating reminder (medications).
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        }

        let id = ReminderIdentifier.requestID(for: reminder)
```

In `cancel(kind:entityID:)`, clear every variant:

```swift
    func cancel(kind: ReminderKind, entityID: UUID) async {
        center.removePendingNotificationRequests(
            withIdentifiers: ReminderIdentifier.requestIDs(kind: kind, entityID: entityID))
    }
```

In `pendingIDs(kind:)`, de-dupe (a weekly task owns several requests for one entityID):

```swift
    func pendingIDs(kind: ReminderKind) async -> [UUID] {
        let requests = await center.pendingNotificationRequests()
        var seen = Set<UUID>()
        return requests.compactMap { request in
            guard let (parsedKind, id) = ReminderIdentifier.parse(request.identifier),
                  parsedKind == kind, seen.insert(id).inserted else { return nil }
            return id
        }
    }
```

- [ ] **Step 5: Update FakeNotificationScheduler**

Replace `schedule(_:)` so distinct weekdays coexist (matching the real adapter's per-ID replace). Existing kinds never set `weekday`, so their semantics are byte-identical:

```swift
    func schedule(_ reminder: PendingReminder) async {
        scheduled.removeAll {
            $0.kind == reminder.kind && $0.entityID == reminder.entityID
                && $0.dateComponents?.weekday == reminder.dateComponents?.weekday
        }
        scheduled.append(reminder)
    }
```

(`cancel(kind:entityID:)` already removes all matching `(kind, entityID)` — correct for clearing every weekday.)

- [ ] **Step 6: Run test to verify it passes**

Expected: PASS (5 tests) — and the three existing medication notification test files pass UNCHANGED (`NotificationSchedulerContractTests`, `NotificationAuthorizationTests`, `MedicationReminderSchedulerTests`), plus `DueReminderSchedulerTests`.

- [ ] **Step 7: Commit**

```bash
git add ios/PetHomepage/Notifications ios/PetHomepageTests/Support/FakeNotificationScheduler.swift ios/PetHomepageTests/ReminderIdentifierWeekdayTests.swift
git commit -m "feat: repeating-weekly notification triggers + ReminderKind.routine

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: RoutineReminderScheduler

**Files:**
- Create: `ios/PetHomepage/Notifications/RoutineReminderScheduler.swift`
- Test: `ios/PetHomepageTests/RoutineReminderSchedulerTests.swift`

**Interfaces:**
- Consumes: Task 6's `PendingReminder(repeats:)`, `NotificationScheduling`, `RoutineTask`, `Weekdays`.
- Produces:
  - `RoutineReminderScheduler(scheduler:calendar:)`
  - `reminders(for task: RoutineTask, petName: String?) -> [PendingReminder]`
  - `syncTask(_ task: RoutineTask, petName: String?) async` — cancel-then-schedule, idempotent
  - `cancelTask(_ task: RoutineTask) async`
  - `syncAll(tasks: [RoutineTask], petName: String?) async` — `cancelAll(.routine)` then sync each (app-start / pet-switch re-sync; `tasks` = current template rows + not-yet-past one-offs)

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/RoutineReminderSchedulerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class RoutineReminderSchedulerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var fake: FakeNotificationScheduler!
    private var scheduler: RoutineReminderScheduler!
    private let calendar = Calendar.current

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        fake = FakeNotificationScheduler()
        scheduler = RoutineReminderScheduler(scheduler: fake)
    }

    private func makeTask(name: String = "Morning walk", mask: Int64 = Weekdays.all,
                          hour: Int = 8, minute: Int = 0, isOneOff: Bool = false,
                          from: Date = Date()) -> RoutineTask {
        let task = RoutineTask(context: context)
        task.id = UUID()
        task.lineageID = UUID()
        task.name = name
        task.category = .play
        task.iconName = "figure.walk"
        task.hour = Int64(hour)
        task.minute = Int64(minute)
        task.weekdayMask = mask
        task.effectiveFrom = calendar.startOfDay(for: from)
        task.isOneOff = isOneOff
        if isOneOff {
            task.effectiveUntil = calendar.date(byAdding: .day, value: 1, to: task.effectiveFrom)
        }
        return task
    }

    func testAllWeekTaskGetsSingleDailyReminder() {
        let task = makeTask()
        let reminders = scheduler.reminders(for: task, petName: "Bella")
        XCTAssertEqual(reminders.count, 1)
        let reminder = reminders[0]
        XCTAssertEqual(reminder.kind, .routine)
        XCTAssertEqual(reminder.entityID, task.id)
        XCTAssertNil(reminder.dateComponents) // nil = daily repeating trigger
        XCTAssertEqual(reminder.hour, 8)
        XCTAssertEqual(reminder.title, "Morning walk")
        XCTAssertEqual(reminder.body, "Time for Bella's Morning walk")
    }

    func testPartialWeekTaskGetsOneWeeklyReminderPerDay() {
        let task = makeTask(mask: Weekdays.mask(of: [3, 5]), hour: 17)
        let reminders = scheduler.reminders(for: task, petName: nil)
        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map { $0.dateComponents?.weekday }, [3, 5])
        XCTAssertTrue(reminders.allSatisfy { $0.repeats })
        XCTAssertEqual(reminders[0].body, "Time for Morning walk") // pet-agnostic fallback
    }

    func testFutureOneOffGetsOneShotReminder() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date())!
        let task = makeTask(name: "Vet pickup", isOneOff: true, from: tomorrow)
        let reminders = scheduler.reminders(for: task, petName: "Bella")
        XCTAssertEqual(reminders.count, 1)
        XCTAssertFalse(reminders[0].repeats) // one-shot on that date
        let expected = calendar.dateComponents([.year, .month, .day],
                                               from: calendar.startOfDay(for: tomorrow))
        XCTAssertEqual(reminders[0].dateComponents, expected)
    }

    func testPastOneOffAndClosedTaskGetNoReminders() {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let pastOneOff = makeTask(isOneOff: true, from: yesterday)
        XCTAssertEqual(scheduler.reminders(for: pastOneOff, petName: nil).count, 0)

        let closed = makeTask()
        closed.effectiveUntil = calendar.startOfDay(for: Date())
        XCTAssertEqual(scheduler.reminders(for: closed, petName: nil).count, 0)
    }

    func testSyncTaskReplacesAndCancelClears() async {
        let task = makeTask(mask: Weekdays.mask(of: [2, 4, 6]))
        await scheduler.syncTask(task, petName: "Bella")
        XCTAssertEqual(fake.scheduled.count, 3)
        // Re-sync after narrowing the days: stale weekdays must not survive.
        task.weekdayMask = Weekdays.mask(of: [2])
        await scheduler.syncTask(task, petName: "Bella")
        XCTAssertEqual(fake.scheduled.count, 1)
        XCTAssertEqual(fake.scheduled[0].dateComponents?.weekday, 2)
        await scheduler.cancelTask(task)
        XCTAssertEqual(fake.scheduled.count, 0)
    }

    func testSyncAllResetsTheWholeKind() async {
        let stale = makeTask()
        await scheduler.syncTask(stale, petName: nil)
        let current = makeTask(name: "Dinner", hour: 18)
        await scheduler.syncAll(tasks: [current], petName: "Bella")
        XCTAssertEqual(fake.scheduled.map(\.entityID), [current.id])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `RoutineReminderScheduler` not defined.

- [ ] **Step 3: Implement**

```swift
// ios/PetHomepage/Notifications/RoutineReminderScheduler.swift
import Foundation

/// Schedules routine-task reminders through the shared NotificationScheduling. Pure enough to
/// unit-test with the FakeNotificationScheduler — never touches UNUserNotificationCenter.
///
/// Trigger shapes (chosen to respect iOS's 64-pending-notification budget):
/// - every-day task → ONE daily repeating trigger (dateComponents nil)
/// - partial-week task → one repeating weekly trigger per selected weekday
/// - one-off (today or future) → one-shot on its date; past one-offs get nothing
/// Closed template rows (effectiveUntil != nil, except a one-off's own window) get nothing.
///
/// Known v1 limitation: skipping a task for a single day does not suppress that day's
/// already-scheduled repeating notification.
final class RoutineReminderScheduler {
    private let scheduler: NotificationScheduling
    private let calendar: Calendar

    init(scheduler: NotificationScheduling, calendar: Calendar = .current) {
        self.scheduler = scheduler
        self.calendar = calendar
    }

    func reminders(for task: RoutineTask, petName: String?) -> [PendingReminder] {
        let title = task.name
        let body: String
        if let petName, !petName.isEmpty {
            body = "Time for \(petName)'s \(task.name)"
        } else {
            body = "Time for \(task.name)"
        }

        func reminder(dateComponents: DateComponents?, repeats: Bool) -> PendingReminder {
            PendingReminder(kind: .routine, entityID: task.id, title: title, body: body,
                            hour: Int(task.hour), minute: Int(task.minute),
                            dateComponents: dateComponents, repeats: repeats)
        }

        if task.isOneOff {
            // One-shot on the one-off's day; nothing if that day is already over.
            let today = calendar.startOfDay(for: Date())
            guard task.effectiveFrom >= today else { return [] }
            let components = calendar.dateComponents([.year, .month, .day], from: task.effectiveFrom)
            return [reminder(dateComponents: components, repeats: false)]
        }

        guard task.effectiveUntil == nil else { return [] } // closed version: successor owns it

        if task.weekdayMask == Weekdays.all {
            return [reminder(dateComponents: nil, repeats: false)] // nil = daily repeating
        }
        return Weekdays.weekdays(in: task.weekdayMask).map { weekday in
            reminder(dateComponents: DateComponents(weekday: weekday), repeats: true)
        }
    }

    /// Cancel-then-schedule so narrowing a task's weekdays never leaves stale triggers behind.
    func syncTask(_ task: RoutineTask, petName: String?) async {
        await scheduler.cancel(kind: .routine, entityID: task.id)
        for reminder in reminders(for: task, petName: petName) {
            await scheduler.schedule(reminder)
        }
    }

    func cancelTask(_ task: RoutineTask) async {
        await scheduler.cancel(kind: .routine, entityID: task.id)
    }

    /// Full re-sync (app start / pet switch): clears the whole kind, then schedules the given
    /// tasks — pass the current template rows plus any not-yet-past one-offs.
    func syncAll(tasks: [RoutineTask], petName: String?) async {
        await scheduler.cancelAll(kind: .routine)
        for task in tasks {
            for reminder in reminders(for: task, petName: petName) {
                await scheduler.schedule(reminder)
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Notifications/RoutineReminderScheduler.swift ios/PetHomepageTests/RoutineReminderSchedulerTests.swift
git commit -m "feat: RoutineReminderScheduler — daily/weekly/one-shot routine reminders

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: ScheduleViewModel

**Files:**
- Create: `ios/PetHomepage/Features/Schedule/ScheduleViewModel.swift`
- Test: `ios/PetHomepageTests/ScheduleViewModelTests.swift`

**Interfaces:**
- Consumes: `RoutineStore` (Tasks 2–5), `LogStore.addPhoto`.
- Produces (consumed by `ScheduleView` in Task 9):
  - `ScheduleViewModel(store:logStore:calendar:now:)` — `now: () -> Date` injectable clock
  - `day: Date` (start of day), `slots: [RoutineSlot]`, `errorMessage: String?`
  - `toastCompletion: LogEntry?` — the just-checked completion driving the "Add a photo?" toast
  - `isToday: Bool`, `isFuture: Bool`, `dayTitle: String`
  - `load()`, `goToPreviousDay()`, `goToNextDay()`, `goToToday()`
  - `checkOff(_ slot: RoutineSlot)`, `uncheck(_ slot: RoutineSlot)`, `toggleSkip(_ slot: RoutineSlot)`
  - `attachPhoto(_ data: Data, to entry: LogEntry)`, `dismissToast()`
  - `progress: (done: Int, total: Int)` — skipped slots excluded from both

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/ScheduleViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class ScheduleViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: RoutineStore!
    private var logStore: LogStore!
    private var model: ScheduleViewModel!
    private let calendar = Calendar.current

    private var today: Date { calendar.startOfDay(for: Date()) }

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = RoutineStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        try store.createTask(name: "Breakfast", category: .feeding, iconName: "fork.knife",
                             hour: 7, minute: 0, weekdayMask: Weekdays.all, from: weekAgo)
        try store.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                             hour: 8, minute: 0, weekdayMask: Weekdays.all, from: weekAgo)
        model = ScheduleViewModel(store: store, logStore: logStore)
        model.load()
    }

    func testLoadsTodaySlots() {
        XCTAssertTrue(model.isToday)
        XCTAssertFalse(model.isFuture)
        XCTAssertEqual(model.dayTitle, "Today")
        XCTAssertEqual(model.slots.map(\.task.name), ["Breakfast", "Walk"])
        XCTAssertEqual(model.progress.done, 0)
        XCTAssertEqual(model.progress.total, 2)
    }

    func testDayNavigation() {
        model.goToNextDay()
        XCTAssertFalse(model.isToday)
        XCTAssertTrue(model.isFuture)
        model.goToPreviousDay()
        model.goToPreviousDay()
        XCTAssertEqual(model.dayTitle, "Yesterday")
        model.goToToday()
        XCTAssertTrue(model.isToday)
    }

    func testCheckOffCompletesAndArmsToast() throws {
        let slot = try XCTUnwrap(model.slots.first)
        model.checkOff(slot)
        XCTAssertTrue(try XCTUnwrap(model.slots.first).isCompleted)
        XCTAssertEqual(model.toastCompletion?.title, "Breakfast")
        XCTAssertEqual(model.progress.done, 1)
        model.dismissToast()
        XCTAssertNil(model.toastCompletion)
    }

    func testCheckOffRefusedOnFutureDay() throws {
        model.goToNextDay()
        let slot = try XCTUnwrap(model.slots.first)
        model.checkOff(slot)
        XCTAssertFalse(try XCTUnwrap(model.slots.first).isCompleted)
        XCTAssertNil(model.toastCompletion)
    }

    func testUncheckRemovesCompletion() throws {
        model.checkOff(try XCTUnwrap(model.slots.first))
        model.uncheck(try XCTUnwrap(model.slots.first))
        XCTAssertFalse(try XCTUnwrap(model.slots.first).isCompleted)
        XCTAssertNil(model.toastCompletion)
    }

    func testToggleSkipExcludesFromProgress() throws {
        model.toggleSkip(try XCTUnwrap(model.slots.first))
        XCTAssertTrue(try XCTUnwrap(model.slots.first).isSkipped)
        XCTAssertEqual(model.progress.total, 1) // skipped slot out of the denominator
        model.toggleSkip(try XCTUnwrap(model.slots.first))
        XCTAssertFalse(try XCTUnwrap(model.slots.first).isSkipped)
        XCTAssertEqual(model.progress.total, 2)
    }

    func testAttachPhoto() throws {
        model.checkOff(try XCTUnwrap(model.slots.first))
        let entry = try XCTUnwrap(model.toastCompletion)
        model.attachPhoto(Data([0x01]), to: entry)
        XCTAssertEqual(entry.photoArray.count, 1)
        XCTAssertNil(model.toastCompletion) // toast served its purpose
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `ScheduleViewModel` not defined.

- [ ] **Step 3: Implement**

```swift
// ios/PetHomepage/Features/Schedule/ScheduleViewModel.swift
import Foundation
import Observation

/// Day-pager state for the Schedule tab: which day is shown, its computed slots, and the
/// post-check-off "Add a photo?" toast. All writes delegate to RoutineStore; `now` is an
/// injectable clock so tests are deterministic.
@Observable
final class ScheduleViewModel {
    private(set) var day: Date
    private(set) var slots: [RoutineSlot] = []
    var errorMessage: String?
    /// The completion that just happened; non-nil arms the "Add a photo?" toast.
    private(set) var toastCompletion: LogEntry?

    private let store: RoutineStore
    private let logStore: LogStore
    private let calendar: Calendar
    private let now: () -> Date

    init(store: RoutineStore,
         logStore: LogStore,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.store = store
        self.logStore = logStore
        self.calendar = calendar
        self.now = now
        self.day = calendar.startOfDay(for: now())
    }

    var isToday: Bool { calendar.isDate(day, inSameDayAs: now()) }
    var isFuture: Bool { day > calendar.startOfDay(for: now()) }

    var dayTitle: String {
        if isToday { return "Today" }
        if calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: -1,
                                                           to: calendar.startOfDay(for: now()))!) {
            return "Yesterday"
        }
        if calendar.isDate(day, inSameDayAs: calendar.date(byAdding: .day, value: 1,
                                                           to: calendar.startOfDay(for: now()))!) {
            return "Tomorrow"
        }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    /// Done / total for the day, with deliberately-skipped slots out of both counts.
    var progress: (done: Int, total: Int) {
        let counted = slots.filter { !$0.isSkipped }
        return (counted.filter(\.isCompleted).count, counted.count)
    }

    func load() {
        do {
            slots = try store.slots(for: day)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Day navigation

    func goToPreviousDay() { shift(by: -1) }
    func goToNextDay() { shift(by: 1) }

    func goToToday() {
        day = calendar.startOfDay(for: now())
        toastCompletion = nil
        load()
    }

    private func shift(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: day) else { return }
        day = next
        toastCompletion = nil
        load()
    }

    // MARK: - Slot actions

    /// Completes the slot and arms the photo toast. Future days can't be completed.
    func checkOff(_ slot: RoutineSlot) {
        guard !isFuture, !slot.isCompleted else { return }
        do {
            toastCompletion = try store.checkOff(slot.task, on: day, now: now())
            load()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func uncheck(_ slot: RoutineSlot) {
        guard let completion = slot.completion else { return }
        do {
            if toastCompletion?.id == completion.id { toastCompletion = nil }
            try store.uncheck(completion)
            load()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func toggleSkip(_ slot: RoutineSlot) {
        do {
            if slot.isSkipped {
                try store.unskip(slot.task, on: day)
            } else {
                try store.skip(slot.task, on: day)
            }
            load()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    // MARK: - Photo toast

    func attachPhoto(_ data: Data, to entry: LogEntry) {
        do {
            try logStore.addPhoto(to: entry, imageData: data)
            if toastCompletion?.id == entry.id { toastCompletion = nil }
            load()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func dismissToast() { toastCompletion = nil }
}
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Features/Schedule/ScheduleViewModel.swift ios/PetHomepageTests/ScheduleViewModelTests.swift
git commit -m "feat: ScheduleViewModel — day pager state, check-off, skip, photo toast

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: ScheduleView + Schedule tab wiring

**Files:**
- Create: `ios/PetHomepage/Features/Schedule/ScheduleView.swift`
- Modify: `ios/PetHomepage/App/ContentView.swift`
- Modify: `ios/PetHomepageUITests/TabBarTests.swift`

**Interfaces:**
- Consumes: `ScheduleViewModel` (Task 8), `RoutineStore`, `RoutineReminderScheduler` (Task 7), `CameraPicker`, `ImageDownscaler`, `Theme`/`HeroHeader`, `UITestSupport.stubCamera`.
- Produces: `ScheduleView(store:logStore:reminderScheduler:petStore:)`; the 5th tab; sheets it presents are placeholders wired fully in Task 10 (`RoutineTemplateView`, `RoutineTaskEditView` are created there — this task references them, so **Tasks 9 and 10 must land in the same PR/test run**; the suite only compiles after both. Implement 9 then 10 back-to-back, committing after each with tests run after Task 10).

- [ ] **Step 1: Implement ScheduleView**

```swift
// ios/PetHomepage/Features/Schedule/ScheduleView.swift
import PhotosUI
import SwiftUI
import UIKit

/// The Schedule tab: one day's care checklist at a time (chevrons/Today to move between days),
/// check-offs with a transient "Add a photo?" toast, per-day skips, one-off tasks, and the
/// versioned template editor behind the header's manage button.
struct ScheduleView: View {
    @State private var model: ScheduleViewModel
    @State private var showTemplateEditor = false
    @State private var showOneOffEditor = false
    /// The completion a photo capture is targeted at (from the toast or a completed row).
    @State private var photoTarget: LogEntry?
    @State private var showCamera = false
    @State private var showLibraryFallback = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var pendingPhoto: Data?

    private let store: RoutineStore
    private let reminderScheduler: RoutineReminderScheduler
    private let petStore: PetStore

    init(store: RoutineStore, logStore: LogStore,
         reminderScheduler: RoutineReminderScheduler, petStore: PetStore) {
        self.store = store
        self.reminderScheduler = reminderScheduler
        self.petStore = petStore
        _model = State(initialValue: ScheduleViewModel(store: store, logStore: logStore))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 12) {
                    HeroHeader(
                        title: "Schedule",
                        subtitle: progressSubtitle,
                        systemImage: "checklist",
                        onAdd: { showOneOffEditor = true },
                        onSettings: { showTemplateEditor = true },
                        settingsSymbol: "slider.horizontal.3"
                    )
                    dayBar
                    content
                }
                if let completion = model.toastCompletion {
                    photoToast(for: completion)
                }
            }
            .background(Theme.bg)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { model.load() }
            .sheet(isPresented: $showTemplateEditor, onDismiss: { model.load() }) {
                NavigationStack {
                    RoutineTemplateView(store: store, reminderScheduler: reminderScheduler,
                                        petStore: petStore)
                }
            }
            .sheet(isPresented: $showOneOffEditor, onDismiss: { model.load() }) {
                RoutineTaskEditView(store: store, reminderScheduler: reminderScheduler,
                                    petStore: petStore, mode: .oneOff(day: model.day), editing: nil)
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: deliverPendingPhoto) {
                CameraPicker(
                    onCapture: { image in
                        if let jpeg = ImageDownscaler.scaledJPEG(from: image) { pendingPhoto = jpeg }
                    },
                    onFinish: { showCamera = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showLibraryFallback, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let jpeg = ImageDownscaler.scaledJPEG(from: image) {
                        await MainActor.run { pendingPhoto = jpeg; deliverPendingPhoto() }
                    }
                    await MainActor.run { libraryItem = nil }
                }
            }
        }
    }

    private var progressSubtitle: String {
        let p = model.progress
        return p.total == 0 ? model.dayTitle : "\(model.dayTitle) · \(p.done) of \(p.total) done"
    }

    // MARK: - Day navigation bar

    private var dayBar: some View {
        HStack(spacing: 14) {
            dayChevron("chevron.left", id: "schedulePrevDay") { model.goToPreviousDay() }
            VStack(spacing: 1) {
                Text(model.dayTitle)
                    .font(Theme.headline())
                    .foregroundStyle(Theme.ink)
                Text(model.day, format: .dateTime.month().day().year())
                    .font(.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("scheduleDayTitle")
            dayChevron("chevron.right", id: "scheduleNextDay") { model.goToNextDay() }
        }
        .padding(.horizontal, 18)
        .overlay(alignment: .trailing) {
            if !model.isToday {
                Button("Today") { model.goToToday() }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Theme.primary)
                    .padding(.trailing, 60)
                    .accessibilityIdentifier("scheduleTodayButton")
            }
        }
    }

    private func dayChevron(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38)
                .background(Color.white, in: Circle())
                .shadow(color: Theme.ink.opacity(0.06), radius: 6, y: 2)
        }
        .accessibilityIdentifier(id)
    }

    // MARK: - Checklist

    @ViewBuilder
    private var content: some View {
        if model.slots.isEmpty {
            ContentUnavailableView(
                "Nothing scheduled",
                systemImage: "checklist",
                description: Text("Tap the sliders to build this day's routine, or + for a one-off task.")
            )
        } else {
            List {
                ForEach(model.slots) { slot in
                    slotRow(slot)
                        .listRowBackground(Theme.bg)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            if !slot.isCompleted {
                                Button {
                                    model.toggleSkip(slot)
                                } label: {
                                    Label(slot.isSkipped ? "Unskip" : "Skip today",
                                          systemImage: slot.isSkipped ? "arrow.uturn.backward" : "moon.zzz")
                                }
                                .tint(slot.isSkipped ? Theme.primary : .orange)
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func slotRow(_ slot: RoutineSlot) -> some View {
        HStack(spacing: 12) {
            Button {
                if slot.isCompleted {
                    model.uncheck(slot)
                } else {
                    model.checkOff(slot)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } label: {
                Image(systemName: slot.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(slot.isCompleted ? Theme.ok : Theme.inkSoft.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(model.isFuture || slot.isSkipped)
            .accessibilityIdentifier("scheduleCheck.\(slot.task.name)")

            Image(systemName: slot.task.iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(slot.isSkipped ? Theme.inkSoft : Theme.primary)
                .frame(width: 38, height: 38)
                .background((slot.isSkipped ? Theme.inkSoft : Theme.primary).opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.task.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(slot.isSkipped ? Theme.inkSoft : Theme.ink)
                    .strikethrough(slot.isSkipped)
                HStack(spacing: 5) {
                    if slot.isSkipped {
                        Text("Skipped")
                    } else if let completion = slot.completion {
                        Text("Done at \(completion.performedAt, format: .dateTime.hour().minute())")
                    } else {
                        Text(scheduledTime(slot.task), format: .dateTime.hour().minute())
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
            }

            Spacer(minLength: 6)

            if let completion = slot.completion {
                if let photo = completion.photoArray.first, let data = photo.imageData,
                   let ui = UIImage(data: data) {
                    Image(uiImage: ui).resizable().scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Button {
                        photoTarget = completion
                        presentCapture()
                    } label: {
                        Image(systemName: "camera")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 38, height: 38)
                            .background(Theme.primary.opacity(0.1), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("scheduleAddPhoto.\(slot.task.name)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("scheduleRow.\(slot.task.name)")
    }

    private func scheduledTime(_ task: RoutineTask) -> Date {
        Calendar.current.date(bySettingHour: Int(task.hour), minute: Int(task.minute),
                              second: 0, of: model.day) ?? model.day
    }

    // MARK: - Photo toast + capture

    private func photoToast(for completion: LogEntry) -> some View {
        HStack(spacing: 12) {
            Text("Done! 🎉")
                .font(Theme.headline())
                .foregroundStyle(.white)
            Spacer()
            Button {
                photoTarget = completion
                presentCapture()
            } label: {
                Label("Add a photo", systemImage: "camera.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scheduleToastAddPhoto")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Theme.primary.opacity(0.35), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task {
            // Auto-dismiss after 4s; ignoring the toast costs nothing (a camera button stays
            // on the completed row).
            try? await Task.sleep(for: .seconds(4))
            model.dismissToast()
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.toastCompletion?.id)
    }

    private func presentCapture() {
        model.dismissToast()
        // `--uitest-stub-camera`: deliver a generated photo synchronously (deterministic tests).
        if UITestSupport.stubCamera {
            pendingPhoto = UITestSupport.stubPhotoJPEG()
            deliverPendingPhoto()
            return
        }
        if CameraPicker.isAvailable {
            showCamera = true
        } else {
            showLibraryFallback = true
        }
    }

    private func deliverPendingPhoto() {
        guard let data = pendingPhoto, let target = photoTarget else { return }
        pendingPhoto = nil
        photoTarget = nil
        model.attachPhoto(data, to: target)
    }
}
```

- [ ] **Step 2: Wire the tab into ContentView**

In `ios/PetHomepage/App/ContentView.swift`:

1. After the `let activityStore = …` line, add:

```swift
        let routineStore = RoutineStore(context: context, petStore: petStore)
        let routineReminderScheduler = RoutineReminderScheduler(scheduler: UNNotificationScheduler())
```

2. In the `TabView`, insert Schedule between Capture and Care Team, bumping Care Team's tag (the Capture pseudo-tab logic keys on `new == 2` and is untouched):

```swift
            Color.clear
                .tabItem { Label("Capture", systemImage: "camera.fill") }
                .tag(2)
            ScheduleView(store: routineStore, logStore: logStore,
                         reminderScheduler: routineReminderScheduler, petStore: petStore)
                .tabItem { Label("Schedule", systemImage: "checklist") }
                .tag(3)
            CareTeamView(store: veterinarianStore)
                .tabItem { Label("Care Team", systemImage: "stethoscope") }
                .tag(4)
```

3. In the `.task` modifier, add seeding + reminder re-sync after the existing two lines:

```swift
        .task {
            try? activityStore.seedDefaultsIfNeeded()
            try? logStore.backfillKindsIfNeeded()
            try? routineStore.seedDefaultsIfNeeded()
            // Re-sync routine reminders on every launch: template edits made on another device
            // (CloudKit) otherwise leave this device's notifications stale.
            if let tasks = try? routineStore.currentTasks() {
                let petName = try? petStore.currentPet()?.name
                await routineReminderScheduler.syncAll(tasks: tasks, petName: petName ?? nil)
            }
        }
```

- [ ] **Step 3: Update the tab-bar UI test**

In `ios/PetHomepageUITests/TabBarTests.swift`, update the label array and doc comment:

```swift
    /// The five real tabs exist. (Capture is a pseudo-tab — selecting it always snaps back to
    /// the prior tab and opens the camera flow instead — but its tab bar button still exists.)
    func testTabBarLayout() {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        for label in ["Home", "Timeline", "Capture", "Schedule", "Care Team"] {
            XCTAssertTrue(tabBar.buttons[label].waitForExistence(timeout: 5), "\(label) tab missing")
        }
    }
```

- [ ] **Step 4: Commit** (compilation verified after Task 10 — ScheduleView references the two editor views created there)

```bash
git add ios/PetHomepage/Features/Schedule/ScheduleView.swift ios/PetHomepage/App/ContentView.swift ios/PetHomepageUITests/TabBarTests.swift
git commit -m "feat: Schedule tab — day pager, check-off with photo toast, skip swipe

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Template editor + one-off editor

**Files:**
- Create: `ios/PetHomepage/Features/Schedule/RoutineTemplateView.swift`
- Create: `ios/PetHomepage/Features/Schedule/RoutineTaskEditView.swift`

**Interfaces:**
- Consumes: `RoutineStore` (`currentTasks`, `createTask`, `editTask`, `endTask`, `addOneOff`), `RoutineReminderScheduler` (`syncTask`, `cancelTask`), `BrandFormSheet`, `Weekdays`, `ActivityCategory`, `PetStore` (pet name for notification copy).
- Produces: `RoutineTemplateView(store:reminderScheduler:petStore:)`, `RoutineTaskEditView(store:reminderScheduler:petStore:mode:editing:)` with `enum RoutineEditMode { case template; case oneOff(day: Date) }` — exactly the signatures ScheduleView (Task 9) presents.

- [ ] **Step 1: Implement the template list**

```swift
// ios/PetHomepage/Features/Schedule/RoutineTemplateView.swift
import SwiftUI

/// "Edit routine": the current weekly template. Rows show name, time, and a days summary;
/// tapping opens the editor (versioned edit), swiping deletes (closes the version — history
/// keeps it). One-offs never appear here.
struct RoutineTemplateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tasks: [RoutineTask] = []
    @State private var editTarget: RoutineTask?
    @State private var showAdd = false

    let store: RoutineStore
    let reminderScheduler: RoutineReminderScheduler
    let petStore: PetStore

    var body: some View {
        List {
            ForEach(tasks) { task in
                Button { editTarget = task } label: { row(task) }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                await reminderScheduler.cancelTask(task)
                                try? store.endTask(task)
                                reload()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .navigationTitle("Edit routine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityIdentifier("routineTemplateAdd")
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $editTarget, onDismiss: reload) { task in
            RoutineTaskEditView(store: store, reminderScheduler: reminderScheduler,
                                petStore: petStore, mode: .template, editing: task)
        }
        .sheet(isPresented: $showAdd, onDismiss: reload) {
            RoutineTaskEditView(store: store, reminderScheduler: reminderScheduler,
                                petStore: petStore, mode: .template, editing: nil)
        }
    }

    private func reload() {
        tasks = (try? store.currentTasks()) ?? []
    }

    private func row(_ task: RoutineTask) -> some View {
        HStack(spacing: 12) {
            Image(systemName: task.iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38)
                .background(Theme.primary.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("\(timeLabel(task)) · \(daysSummary(task.weekdayMask))")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .contentShape(Rectangle())
        .accessibilityIdentifier("routineTemplateRow.\(task.name)")
    }

    private func timeLabel(_ task: RoutineTask) -> String {
        let date = Calendar.current.date(bySettingHour: Int(task.hour), minute: Int(task.minute),
                                         second: 0, of: Date()) ?? Date()
        return date.formatted(.dateTime.hour().minute())
    }

    private func daysSummary(_ mask: Int64) -> String {
        if mask == Weekdays.all { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols // ["Sun", "Mon", …]
        return Weekdays.weekdays(in: mask).map { symbols[$0 - 1] }.joined(separator: " ")
    }
}
```

- [ ] **Step 2: Implement the task editor**

```swift
// ios/PetHomepage/Features/Schedule/RoutineTaskEditView.swift
import SwiftUI

/// What a save writes: a versioned template row, or a single-day one-off.
enum RoutineEditMode {
    case template
    case oneOff(day: Date)
}

/// Add/edit form for a routine task: name, category (drives the icon), time, and — for template
/// tasks — the weekday picker. Saving syncs the task's notifications.
struct RoutineTaskEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var category: ActivityCategory
    @State private var time: Date
    @State private var weekdayMask: Int64

    private let store: RoutineStore
    private let reminderScheduler: RoutineReminderScheduler
    private let petStore: PetStore
    private let mode: RoutineEditMode
    private let editing: RoutineTask?

    init(store: RoutineStore, reminderScheduler: RoutineReminderScheduler,
         petStore: PetStore, mode: RoutineEditMode, editing: RoutineTask?) {
        self.store = store
        self.reminderScheduler = reminderScheduler
        self.petStore = petStore
        self.mode = mode
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _category = State(initialValue: editing?.category ?? .care)
        let calendar = Calendar.current
        let hour = editing.map { Int($0.hour) } ?? 9
        let minute = editing.map { Int($0.minute) } ?? 0
        _time = State(initialValue: calendar.date(bySettingHour: hour, minute: minute,
                                                  second: 0, of: Date()) ?? Date())
        _weekdayMask = State(initialValue: editing?.weekdayMask ?? Weekdays.all)
    }

    private var isOneOff: Bool {
        if case .oneOff = mode { return true }
        return false
    }

    var body: some View {
        BrandFormSheet(
            title: isOneOff ? "One-off task" : (editing == nil ? "New routine task" : "Edit task"),
            systemImage: "checklist",
            confirmDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { dismiss() },
            onConfirm: { save() }
        ) {
            Section("Task") {
                TextField("Name (e.g. Morning walk)", text: $name)
                    .accessibilityIdentifier("routineTaskName")
                Picker("Category", selection: $category) {
                    ForEach(ActivityCategory.allCases) { cat in
                        Label(cat.displayName, systemImage: cat.systemImage).tag(cat)
                    }
                }
            }
            Section("Time") {
                DatePicker("Reminder time", selection: $time, displayedComponents: .hourAndMinute)
            }
            if !isOneOff {
                Section("Days") {
                    weekdayPicker
                    Button(weekdayMask == Weekdays.all ? "Every day ✓" : "Every day") {
                        weekdayMask = Weekdays.all
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    /// Seven toggle circles, Sun…Sat. At least one day must stay selected.
    private var weekdayPicker: some View {
        HStack(spacing: 8) {
            ForEach(1...7, id: \.self) { weekday in
                let selected = Weekdays.contains(weekdayMask, weekday: weekday)
                Button {
                    let toggled = weekdayMask ^ Weekdays.bit(for: weekday)
                    if toggled != 0 { weekdayMask = toggled }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                        .font(.caption.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(selected ? Theme.primary : Theme.inkSoft.opacity(0.12),
                                    in: Circle())
                        .foregroundStyle(selected ? .white : Theme.inkSoft)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("routineWeekday.\(weekday)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = comps.hour ?? 9
        let minute = comps.minute ?? 0
        // Category drives the icon — one less thing to pick.
        let icon = category.systemImage

        do {
            let saved: RoutineTask
            switch (mode, editing) {
            case (.oneOff(let day), _):
                saved = try store.addOneOff(name: trimmed, category: category, iconName: icon,
                                            hour: hour, minute: minute, on: day)
            case (.template, .some(let task)):
                saved = try store.editTask(task, name: trimmed, category: category, iconName: icon,
                                           hour: hour, minute: minute, weekdayMask: weekdayMask)
            case (.template, .none):
                saved = try store.createTask(name: trimmed, category: category, iconName: icon,
                                             hour: hour, minute: minute, weekdayMask: weekdayMask)
            }
            let petName = try? petStore.currentPet()?.name
            Task {
                // A versioned edit moves reminders from the closed row to its successor.
                if let old = editing, old.id != saved.id {
                    await reminderScheduler.cancelTask(old)
                }
                await reminderScheduler.syncTask(saved, petName: petName ?? nil)
            }
            dismiss()
        } catch {
            // Store errors here are programmer errors (save conflicts) — keep the sheet open.
        }
    }
}
```

- [ ] **Step 3: Regenerate the project and run the full suite**

Run (macOS): `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PetHomepageTests`
Expected: PASS — everything from Tasks 1–8 plus all pre-existing tests. (ScheduleView from Task 9 now compiles: its editor references exist.)

- [ ] **Step 4: Commit**

```bash
git add ios/PetHomepage/Features/Schedule
git commit -m "feat: routine template editor + one-off task form (versioned edits sync reminders)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: Timeline integration — Routine chip + rows

**Files:**
- Modify: `ios/PetHomepage/Features/Timeline/TimelineViewModel.swift`
- Modify: `ios/PetHomepage/Features/Timeline/TimelineView.swift`
- Modify: `ios/PetHomepage/Stores/LogStore.swift`
- Test: `ios/PetHomepageTests/TimelineRoutineTests.swift`

**Interfaces:**
- Consumes: `LogEntry` kind `routine` (Task 4), existing Timeline machinery.
- Produces: `TimelineKind.routine` (label "Routine", icon "checklist" — the chip strip renders it automatically via `CaseIterable`), `TimelineReference.routine(LogEntry)`, `TimelineItem.init(routine:)`, `LogStore.routineEntries()`.

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/TimelineRoutineTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class TimelineRoutineTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var logStore: LogStore!
    private var routineStore: RoutineStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        logStore = LogStore(context: context, petStore: petStore)
        routineStore = RoutineStore(context: context, petStore: petStore)
    }

    func testRoutineEntriesAppearInTimelineWithRoutineKind() throws {
        let task = try routineStore.createTask(name: "Morning walk", category: .play,
                                               iconName: "figure.walk", hour: 8, minute: 0,
                                               weekdayMask: Weekdays.all)
        let entry = try routineStore.checkOff(task, on: Date())
        try logStore.addPhoto(to: entry, imageData: Data([0x01]))

        let model = TimelineViewModel(medicationStore: MedicationStore(context: context, petStore: petStore),
                                      logStore: logStore)
        model.load()
        let item = try XCTUnwrap(model.items.first { $0.kind == .routine })
        XCTAssertEqual(item.title, "Morning walk")
        XCTAssertEqual(item.subtitle, "1 photo")
        // The Routine chip filters to exactly these entries.
        model.filter = .routine
        XCTAssertEqual(model.filtered.count, 1)
    }

    func testRoutineEntriesExcludedFromDiaryQuery() throws {
        let task = try routineStore.createTask(name: "Walk", category: .play, iconName: "figure.walk",
                                               hour: 8, minute: 0, weekdayMask: Weekdays.all)
        try routineStore.checkOff(task, on: Date())
        XCTAssertEqual(try logStore.diaryEntries().count, 0)
        XCTAssertEqual(try logStore.routineEntries().count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Expected: FAIL — `TimelineKind.routine`, `routineEntries()` not defined.

- [ ] **Step 3: Implement**

1. `ios/PetHomepage/Stores/LogStore.swift` — add after `activityLogs()`:

```swift
    /// Routine completions = occurrences explicitly stamped as kind "routine".
    func routineEntries() throws -> [LogEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        return try fetch(NSPredicate(format: "pet == %@ AND kindRaw == %@", pet, LogKind.routine.rawValue))
    }
```

2. `TimelineViewModel.swift`:
- `TimelineKind`: add `case routine` to the case list; add `"Routine"` to `label` and `"checklist"` to `systemImage` switches.
- `TimelineReference`: add `case routine(LogEntry)`.
- `TimelineViewModel.load()`: add `out += try logStore.routineEntries().map(TimelineItem.init(routine:))` after the diary line.
- `delete(_:using:)`: add before the diary case:

```swift
        case .routine(let entry):
            try? services.logStore.delete(entry)
```

- Add the item initializer at the bottom with the others:

```swift
    init(routine entry: LogEntry) {
        let photoCount = entry.photoArray.count
        let note = entry.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            id: "routine:\(entry.id.uuidString)",
            kind: .routine,
            date: entry.performedAt,
            title: entry.title ?? "Routine",
            subtitle: (note?.isEmpty == false) ? note
                : (photoCount > 0 ? "\(photoCount) photo\(photoCount == 1 ? "" : "s")" : nil),
            nextDue: nil,
            reference: .routine(entry)
        )
    }
```

3. `TimelineView.swift`:
- `editor(for:)`: add a case — routine completions reuse the diary editor for note/photo edits (`updateDiary` only touches `performedAt`/`note`, never `kindRaw`, so the entry stays kind routine):

```swift
        case .routine(let entry):
            DiaryEntryEditView(logStore: services.logStore, editing: entry)
```

- `tint(_:)`: add `case .routine: .mint`.

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS (2 tests) + existing `TimelineViewModelTests` still green (new kind, no behavior change for old kinds).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Features/Timeline ios/PetHomepage/Stores/LogStore.swift ios/PetHomepageTests/TimelineRoutineTests.swift
git commit -m "feat: routine completions in Timeline — Routine chip, mint rows, diary-editor reuse

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Schedule UI test + full-suite verification

**Files:**
- Create: `ios/PetHomepageUITests/ScheduleTests.swift`

**Interfaces:**
- Consumes: `--uitest` seams (`UITestSupport.seed` creates Sandy; `ContentView`'s `.task` seeds the routine defaults idempotently on launch), accessibility identifiers from Task 9 (`scheduleRow.<name>`, `scheduleCheck.<name>`, `scheduleToastAddPhoto`, `schedulePrevDay`, `scheduleDayTitle`), `--uitest-stub-camera`.

- [ ] **Step 1: Write the UI test**

```swift
// ios/PetHomepageUITests/ScheduleTests.swift
import XCTest

final class ScheduleTests: UITestCase {
    /// Seeded routine renders on the Schedule tab; checking a task off flips its state and
    /// offers the photo toast; the stubbed camera attaches a photo without real capture UI.
    func testScheduleSeedAndCheckOffWithPhoto() {
        let app = launchApp(extra: ["--uitest-stub-camera"])
        app.tabBars.buttons["Schedule"].tap()

        // Every-day seeds are on today's list regardless of weekday.
        XCTAssertTrue(app.otherElements["scheduleRow.Breakfast"].waitForExistence(timeout: 5)
                      || app.staticTexts["Breakfast"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Morning walk"].exists)

        // Check off Breakfast → toast offers a photo; stub camera attaches one synchronously.
        app.buttons["scheduleCheck.Breakfast"].tap()
        let toast = app.buttons["scheduleToastAddPhoto"]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
        toast.tap()
        // Toast is gone after capture; the row now shows the photo thumbnail (no camera button).
        XCTAssertFalse(app.buttons["scheduleAddPhoto.Breakfast"].waitForExistence(timeout: 2))
    }

    /// Day navigation: yesterday's list exists and the Today button returns.
    func testDayNavigation() {
        let app = launchApp()
        app.tabBars.buttons["Schedule"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
        app.buttons["schedulePrevDay"].tap()
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 3))
        app.buttons["scheduleTodayButton"].tap()
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 3))
    }
}
```

- [ ] **Step 2: Run the FULL suite (unit + UI) on macOS**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: PASS — all pre-existing tests (notably the unchanged medication notification contract tests and updated `TabBarTests`) plus every new suite. If a UI test flakes on element queries, prefer fixing the accessibility identifier over loosening the assertion.

- [ ] **Step 3: Commit**

```bash
git add ios/PetHomepageUITests/ScheduleTests.swift
git commit -m "test: Schedule tab UI tests — seeded routine, check-off with stub photo, day nav

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Post-plan notes

- **Docs follow-up (not part of this plan's gates):** add `docs/features/017-care-scheduler.md` in the repo's lore format after the feature ships.
- **Deferred (per spec "Out of scope"):** suppressing a skipped day's notification, streaks/stats, mirror dashboard sync, household view.
- **CloudKit dev schema:** first device run after Task 1 pushes the new record types to the CloudKit dev environment automatically (`NSPersistentCloudKitContainer` default behavior); nothing to do manually.
