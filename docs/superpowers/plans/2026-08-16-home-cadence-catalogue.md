# Home Cadence Catalogue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Home a tile per recurring thing — preventatives, baths, nail trims — each showing when it was last done and when it is next due, loggable in one tap.

**Architecture:** A `CadenceItem` value type projects both `Medication` and `ActivityType` into one shape, so the view never branches on origin. `CadenceCatalogueViewModel` does the aggregation and ordering with injected stores and an injectable clock, making it fully unit-testable with no view. The grid embeds in `PetProfileView` (which alone hosts the pet switcher and Settings) and replaces its `upcomingCard`. A new `MedicationDoseLogger` collapses four divergent copies of the "log a dose and advance the cadence" rule into one.

**Tech Stack:** Swift 6, SwiftUI, Core Data (+ CloudKit mirroring), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-08-16-home-cadence-catalogue-design.md`

## Global Constraints

- **Tab tags must not change.** `NotificationRouter.Tab` maps `home = 0, timeline = 1, schedule = 3, careTeam = 4`. Reordering changes *display order* only; changing a `.tag(...)` breaks every notification deep link.
- **Never regenerate then commit `project.pbxproj`** — it is gitignored. Run `xcodegen generate` in `ios/` after adding files, but commit only sources.
- **Run tests with:** `cd ios && TEST_RUNNER_CI=true xcodebuild test -project PetHomepage.xcodeproj -scheme PetHomepage -destination "id=087B1257-8565-4D75-B55E-7AC3C71970FB" -only-testing:PetHomepageTests`
  Replace the destination id with any available simulator from `xcrun simctl list devices available`.
- **The suite is flaky on two known axes**, neither caused by this work: a Core Data test-harness crash (~1 in 3 runs, logs `Restarting after unexpected exit`) and an occasional simulator `runner hung before establishing connection`. Both surface as exit 65 with **0 test failures**. Re-run before investigating; CI retries 3×.
- **Day-granularity date math only.** Due-state comparisons use `Calendar.startOfDay` on both sides. A dose due at 09:00 must not read "overdue" at 09:01.
- **`Medication.startedAt` means "next reminder date", not "started at."** It is overloaded by the existing model. Do not rename it; document it where it is read.
- **`MedFrequency(parsing:)` silently falls back to daily** for unrecognized text. Never use "parses to daily" as a signal that a medication lacks a cadence.

---

### Task 1: `CadenceItem` and `DueState` value types

**Files:**
- Create: `ios/PetHomepage/Features/PetProfile/CadenceItem.swift`
- Test: `ios/PetHomepageTests/CadenceItemTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `CadenceItem` (with `id: UUID`, `source: CadenceItem.Source`, `name: String`, `iconName: String`, `subtitle: String?`, `lastDone: Date?`, `nextDue: Date?`), `CadenceItem.Source` (`.medication(NSManagedObjectID)`, `.activityType(NSManagedObjectID)`), `DueState` (`.overdue(days: Int)`, `.dueToday`, `.dueIn(days: Int)`, `.noCadence`), and `CadenceItem.dueState(now:calendar:) -> DueState`.

- [ ] **Step 1: Write the failing test**

Create `ios/PetHomepageTests/CadenceItemTests.swift`:

```swift
// ios/PetHomepageTests/CadenceItemTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class CadenceItemTests: XCTestCase {
    private var calendar: Calendar!
    private var objectID: NSManagedObjectID!

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        let context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        objectID = try XCTUnwrap(petStore.currentPet()).objectID
    }

    private func item(nextDue: Date?) -> CadenceItem {
        CadenceItem(id: UUID(), source: .activityType(objectID), name: "Bath",
                    iconName: "shower", subtitle: nil, lastDone: nil, nextDue: nextDue)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testNilNextDueIsNoCadence() {
        let now = date(2026, 8, 16)
        XCTAssertEqual(item(nextDue: nil).dueState(now: now, calendar: calendar), .noCadence)
    }

    func testDueLaterTodayIsDueToday() {
        let now = date(2026, 8, 16, 9)
        // Due at 17:00 today: still "due today", never "overdue".
        let state = item(nextDue: date(2026, 8, 16, 17)).dueState(now: now, calendar: calendar)
        XCTAssertEqual(state, .dueToday)
    }

    func testDueEarlierTodayIsStillDueToday() {
        let now = date(2026, 8, 16, 23)
        // Due at 09:00, it is now 23:00 the same day — day granularity means NOT overdue.
        let state = item(nextDue: date(2026, 8, 16, 9)).dueState(now: now, calendar: calendar)
        XCTAssertEqual(state, .dueToday)
    }

    func testDueYesterdayIsOverdueByOneDay() {
        let now = date(2026, 8, 16, 9)
        let state = item(nextDue: date(2026, 8, 15, 9)).dueState(now: now, calendar: calendar)
        XCTAssertEqual(state, .overdue(days: 1))
    }

    func testDueTomorrowIsDueInOneDay() {
        let now = date(2026, 8, 16, 23)
        let state = item(nextDue: date(2026, 8, 17, 1)).dueState(now: now, calendar: calendar)
        XCTAssertEqual(state, .dueIn(days: 1))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the test command from Global Constraints with `-only-testing:PetHomepageTests/CadenceItemTests`.
Expected: FAIL to compile — "cannot find 'CadenceItem' in scope".

- [ ] **Step 3: Write minimal implementation**

Create `ios/PetHomepage/Features/PetProfile/CadenceItem.swift`:

```swift
// ios/PetHomepage/Features/PetProfile/CadenceItem.swift
import CoreData
import Foundation

/// How overdue (or not) a cadence item is, at DAY granularity. Day granularity is deliberate:
/// a dose due at 09:00 must not flip to "overdue" at 09:01 — it is due *today* until the day
/// turns over.
enum DueState: Equatable {
    case overdue(days: Int)
    case dueToday
    case dueIn(days: Int)
    /// No next-due date at all — a medication never logged, or an activity type never logged.
    case noCadence
}

/// One recurring thing on Home, projected from either a Medication or an ActivityType so the
/// view never branches on origin.
struct CadenceItem: Identifiable, Equatable {
    /// The originating entity, held as an object ID rather than the object so this value type
    /// stays inert; the view model re-fetches on the main context when acting.
    enum Source: Equatable {
        case medication(NSManagedObjectID)
        case activityType(NSManagedObjectID)
    }

    let id: UUID
    let source: Source
    let name: String
    let iconName: String
    /// Dosage for medications; nil for activities.
    let subtitle: String?
    let lastDone: Date?
    let nextDue: Date?

    func dueState(now: Date, calendar: Calendar = .current) -> DueState {
        guard let nextDue else { return .noCadence }
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: nextDue)
        let days = calendar.dateComponents([.day], from: today, to: due).day ?? 0
        if days == 0 { return .dueToday }
        return days < 0 ? .overdue(days: -days) : .dueIn(days: days)
    }
}
```

- [ ] **Step 4: Regenerate the project and run the test**

```bash
cd ios && xcodegen generate
```

Then run the test command with `-only-testing:PetHomepageTests/CadenceItemTests`.
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Features/PetProfile/CadenceItem.swift ios/PetHomepageTests/CadenceItemTests.swift
git commit -m "feat(ios): CadenceItem value type with day-granularity due state"
```

---

### Task 2: `MedicationDoseLogger` — one copy of the cadence-advance rule

There are currently **four** implementations of "log a dose and move the cadence on," and they disagree:

| Site | Logs dose | Advances `startedAt` | Re-syncs reminder |
|---|---|---|---|
| `LogDoseViewModel.confirm()` | yes | yes | yes |
| `MedicationActionHandler.logDose` | yes | yes | yes |
| `PetProfileView.logDose(_:)` | yes | **no** | **no** |
| (this plan would add a fifth) | | | |

`PetProfileView.logDose` is an outright bug: logging a dose from Home's existing quick action leaves the cadence and the notification untouched. This task collapses all of them into one type before the catalogue adds another caller.

**Files:**
- Create: `ios/PetHomepage/Notifications/MedicationDoseLogger.swift`
- Modify: `ios/PetHomepage/Notifications/MedicationNotificationActions.swift` (the `logDose(for:)` body)
- Modify: `ios/PetHomepage/Features/Medications/LogDoseViewModel.swift` (the `confirm()` body)
- Modify: `ios/PetHomepage/Features/PetProfile/PetProfileView.swift` (the `logDose(_:)` body)
- Test: `ios/PetHomepageTests/MedicationDoseLoggerTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `MedicationDoseLogger(logStore:reminderScheduler:calendar:now:)` with
  `@MainActor @discardableResult func log(_ medication: Medication, at: Date? = nil, note: String? = nil) async -> Date?`
  returning the new next-due date, or `nil` if the dose was deduped.
  Also `func nextDue(for: Medication, after: Date) -> Date` (pure, used by `LogDoseViewModel` for its preview).

- [ ] **Step 1: Write the failing test**

Create `ios/PetHomepageTests/MedicationDoseLoggerTests.swift`:

```swift
// ios/PetHomepageTests/MedicationDoseLoggerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

@MainActor
final class MedicationDoseLoggerTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var medStore: MedicationStore!
    private var logStore: LogStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        medStore = MedicationStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
    }

    private func monthlyMed() throws -> Medication {
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        return try medStore.create(drugName: "Simparica", dosage: "1 chew", frequency: "Monthly",
                                   scheduleTime: start, startedAt: start, refillDueAt: nil)
    }

    private func logger(now: @escaping () -> Date) -> MedicationDoseLogger {
        MedicationDoseLogger(
            logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                           calendar: calendar, now: now),
            calendar: calendar,
            now: now)
    }

    func testLogRecordsDoseAndAdvancesCadenceByOneInterval() async throws {
        let med = try monthlyMed()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!

        let next = await logger(now: { now }).log(med)

        XCTAssertEqual(try logStore.doseCount(for: med), 1)
        let comps = calendar.dateComponents([.year, .month, .day, .hour], from: try XCTUnwrap(next))
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 14)
        XCTAssertEqual(comps.hour, 9, "next due keeps the medication's scheduled time of day")
        XCTAssertEqual(med.startedAt, next, "startedAt IS the next-reminder date in this model")
    }

    func testSecondLogOnSameDayIsDeduped() async throws {
        let med = try monthlyMed()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let sut = logger(now: { now })

        _ = await sut.log(med)
        let second = await sut.log(med)

        XCTAssertNil(second, "a same-day repeat returns nil rather than logging again")
        XCTAssertEqual(try logStore.doseCount(for: med), 1)
    }

    func testExplicitDateBackdatesTheDose() async throws {
        let med = try monthlyMed()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 9))!
        let backdated = calendar.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 8))!

        let next = await logger(now: { now }).log(med, at: backdated)

        let comps = calendar.dateComponents([.month, .day], from: try XCTUnwrap(next))
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 18, "cadence advances from the DOSE date, not from now")
    }

    func testNextDueIsPureAndDoesNotMutate() throws {
        let med = try monthlyMed()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 14, hour: 9))!
        let before = med.startedAt

        _ = logger(now: { now }).nextDue(for: med, after: now)

        XCTAssertEqual(med.startedAt, before, "nextDue must not write to the medication")
        XCTAssertEqual(try logStore.doseCount(for: med), 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:PetHomepageTests/MedicationDoseLoggerTests`.
Expected: FAIL to compile — "cannot find 'MedicationDoseLogger' in scope".

- [ ] **Step 3: Write the implementation**

Create `ios/PetHomepage/Notifications/MedicationDoseLogger.swift`:

```swift
// ios/PetHomepage/Notifications/MedicationDoseLogger.swift
import CoreData
import Foundation

/// The single implementation of "record a dose and move the cadence on."
///
/// This rule lives in exactly one place on purpose. It previously existed in three, and they
/// disagreed: PetProfileView's quick action logged the dose but advanced neither the cadence nor
/// the reminder, so a dose logged from Home left the next reminder pointing at a date that had
/// already passed. Divergent copies of this rule are what produced the original
/// fires-once-then-silent reminder bug.
final class MedicationDoseLogger {
    private let logStore: LogStore
    private let reminderScheduler: MedicationReminderScheduler
    private let calendar: Calendar
    private let now: () -> Date

    init(logStore: LogStore,
         reminderScheduler: MedicationReminderScheduler,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.logStore = logStore
        self.reminderScheduler = reminderScheduler
        self.calendar = calendar
        self.now = now
    }

    /// The next reminder date if a dose is given at `dose`: one cadence interval later, at the
    /// medication's scheduled time of day. Pure — writes nothing.
    func nextDue(for medication: Medication, after dose: Date) -> Date {
        let freq = MedFrequency(parsing: medication.frequency)
        let stepped = calendar.date(byAdding: freq.unit.calendarComponent,
                                    value: freq.interval, to: dose) ?? dose
        let time = calendar.dateComponents([.hour, .minute], from: medication.scheduleTime)
        return calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0,
                             second: 0, of: stepped) ?? stepped
    }

    /// Records the dose, advances the cadence, and re-syncs the reminder.
    ///
    /// Returns the new next-due date, or nil if this was deduped. Dedupe is same-calendar-day:
    /// acting on a notification still sitting on the lock screen after an in-app log must not
    /// record a second dose. No medication in this model is scheduled more than once a day.
    @MainActor
    @discardableResult
    func log(_ medication: Medication, at date: Date? = nil, note: String? = nil) async -> Date? {
        let given = date ?? now()
        if let last = try? logStore.lastDose(for: medication),
           calendar.isDate(last, inSameDayAs: given) {
            return nil
        }
        try? logStore.logDose(for: medication, at: given, note: note)
        // `startedAt` is this model's "next reminder date", not when the course began.
        let next = nextDue(for: medication, after: given)
        medication.startedAt = next
        try? medication.managedObjectContext?.save()
        await reminderScheduler.sync(medication)
        return next
    }
}
```

- [ ] **Step 4: Run the test**

```bash
cd ios && xcodegen generate
```

Run with `-only-testing:PetHomepageTests/MedicationDoseLoggerTests`.
Expected: PASS, 4 tests.

- [ ] **Step 5: Route `MedicationActionHandler` through the logger**

In `ios/PetHomepage/Notifications/MedicationNotificationActions.swift`, replace the whole body of `private func logDose(for medication: Medication) async` with:

```swift
    @MainActor
    private func logDose(for medication: Medication) async {
        let logStore = LogStore(context: context, petStore: PetStore(context: context))
        let logger = MedicationDoseLogger(
            logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: scheduler,
                                                           calendar: calendar, now: now),
            calendar: calendar,
            now: now)
        await logger.log(medication)
    }
```

- [ ] **Step 6: Route `LogDoseViewModel` through the logger**

In `ios/PetHomepage/Features/Medications/LogDoseViewModel.swift`, replace `nextReminder(after:calendar:)` and `confirm()` with:

```swift
    private var doseLogger: MedicationDoseLogger {
        MedicationDoseLogger(logStore: logStore, reminderScheduler: reminderScheduler)
    }

    /// When the next reminder lands if this dose is logged.
    func nextReminder(after dose: Date? = nil, calendar: Calendar = .current) -> Date {
        MedicationDoseLogger(logStore: logStore, reminderScheduler: reminderScheduler,
                             calendar: calendar)
            .nextDue(for: medication, after: dose ?? givenAt)
    }

    @MainActor
    func confirm() async {
        let next = await doseLogger.log(medication, at: givenAt, note: note)
        doseCount = (try? logStore.doseCount(for: medication)) ?? 0
        confirmedNextReminder = next ?? nextReminder()
        isConfirmed = true
    }
```

- [ ] **Step 7: Fix the `PetProfileView` quick-action bug**

In `ios/PetHomepage/Features/PetProfile/PetProfileView.swift`, replace `private func logDose(_ med: Medication)` with:

```swift
    /// Home's quick action previously logged the dose WITHOUT advancing the cadence or
    /// re-syncing the reminder, leaving the next reminder pointing at a date already past.
    private func logDose(_ med: Medication) {
        guard let s = timelineServices else { return }
        Task { @MainActor in
            let logger = MedicationDoseLogger(logStore: s.logStore,
                                              reminderScheduler: s.reminderScheduler)
            await logger.log(med)
            refresh()
        }
    }
```

- [ ] **Step 8: Run the full suite**

Run the full test command (no `-only-testing` filter beyond `PetHomepageTests`).
Expected: 0 failures. `LogDoseViewModelTests` and `MedicationActionHandlerTests` must still pass unchanged — they are the regression net proving the extraction preserved behaviour. If exit is 65 with 0 failures, re-run (see Global Constraints).

- [ ] **Step 9: Commit**

```bash
git add ios/PetHomepage/Notifications/MedicationDoseLogger.swift \
        ios/PetHomepage/Notifications/MedicationNotificationActions.swift \
        ios/PetHomepage/Features/Medications/LogDoseViewModel.swift \
        ios/PetHomepage/Features/PetProfile/PetProfileView.swift \
        ios/PetHomepageTests/MedicationDoseLoggerTests.swift
git commit -m "refactor(ios): one MedicationDoseLogger; fixes Home's dose quick action

Home's Log dose logged the dose but advanced neither the cadence nor the
reminder, leaving the next reminder pointing at a date already past."
```

---

### Task 3: `CadenceCatalogueViewModel` — aggregation and ordering

**Files:**
- Create: `ios/PetHomepage/Features/PetProfile/CadenceCatalogueViewModel.swift`
- Test: `ios/PetHomepageTests/CadenceCatalogueViewModelTests.swift`

**Interfaces:**
- Consumes: `CadenceItem`, `DueState` (Task 1); `MedicationDoseLogger` (Task 2).
- Produces: `CadenceCatalogueViewModel(medicationStore:activityStore:logStore:reminderScheduler:dueScheduler:calendar:now:)` with `private(set) var items: [CadenceItem]`, `func load()`, and `@MainActor func log(_ item: CadenceItem, at: Date? = nil) async`.

- [ ] **Step 1: Write the failing test**

Create `ios/PetHomepageTests/CadenceCatalogueViewModelTests.swift`:

```swift
// ios/PetHomepageTests/CadenceCatalogueViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

@MainActor
final class CadenceCatalogueViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var medStore: MedicationStore!
    private var activityStore: ActivityStore!
    private var logStore: LogStore!
    private var calendar: Calendar!
    private var now: Date!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        medStore = MedicationStore(context: context, petStore: petStore)
        activityStore = ActivityStore(context: context, petStore: petStore)
        logStore = LogStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 9))!
    }

    private func makeSUT() -> CadenceCatalogueViewModel {
        let fixed = now!
        return CadenceCatalogueViewModel(
            medicationStore: medStore,
            activityStore: activityStore,
            logStore: logStore,
            reminderScheduler: MedicationReminderScheduler(scheduler: FakeNotificationScheduler(),
                                                           calendar: calendar, now: { fixed }),
            dueScheduler: DueReminderScheduler(scheduler: FakeNotificationScheduler()),
            calendar: calendar,
            now: { fixed })
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @discardableResult
    private func makeMed(_ name: String, nextDue: Date, ended: Date? = nil) throws -> Medication {
        let med = try medStore.create(drugName: name, dosage: "1 chew", frequency: "Monthly",
                                      scheduleTime: nextDue, startedAt: nextDue, refillDueAt: nil)
        med.endedAt = ended
        try context.save()
        return med
    }

    @discardableResult
    private func makeType(_ name: String, intervalDays: Int, archived: Bool = false) throws -> ActivityType {
        let type = try activityStore.createType(name: name, category: .care,
                                                iconName: "shower",
                                                defaultIntervalDays: intervalDays)
        if archived { try activityStore.archiveType(type) }
        return type
    }

    func testIncludesBothMedicationsAndActivityTypes() throws {
        try makeMed("Simparica", nextDue: date(9, 14))
        try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(Set(sut.items.map(\.name)), ["Simparica", "Bath"])
    }

    func testExcludesEndedMedicationsAndArchivedTypes() throws {
        try makeMed("Ended", nextDue: date(9, 14), ended: date(8, 1))
        try makeType("Archived", intervalDays: 30, archived: true)
        try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(sut.items.map(\.name), ["Bath"])
    }

    func testExcludesActivityTypesWithNoCadence() throws {
        try makeType("One-off", intervalDays: 0)
        try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(sut.items.map(\.name), ["Bath"])
    }

    /// The case the old Upcoming card got wrong: a type that has never been logged has no
    /// LogEntry, so it had no nextDue and never appeared at all.
    func testNeverLoggedActivityTypeStillProducesATile() throws {
        try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()

        sut.load()

        let bath = try XCTUnwrap(sut.items.first { $0.name == "Bath" })
        XCTAssertNil(bath.lastDone)
        XCTAssertNil(bath.nextDue)
        XCTAssertEqual(bath.dueState(now: now, calendar: calendar), .noCadence)
    }

    /// The other case Upcoming got wrong: its `due >= now` filter hid overdue items entirely.
    func testOverdueItemsAppearAndSortFirst() throws {
        try makeMed("Overdue", nextDue: date(8, 10))     // 6 days ago
        try makeMed("Soon", nextDue: date(8, 20))        // in 4 days
        try makeMed("Today", nextDue: date(8, 16, 17))   // later today
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(sut.items.map(\.name), ["Overdue", "Today", "Soon"])
    }

    func testNoCadenceItemsSortLast() throws {
        try makeType("Bath", intervalDays: 30)           // never logged -> no cadence
        try makeMed("Soon", nextDue: date(8, 20))
        let sut = makeSUT()

        sut.load()

        XCTAssertEqual(sut.items.map(\.name), ["Soon", "Bath"])
    }

    func testLoggingAMedicationRecordsADoseAndAdvancesIt() async throws {
        let med = try makeMed("Simparica", nextDue: date(8, 16))
        let sut = makeSUT()
        sut.load()
        let item = try XCTUnwrap(sut.items.first { $0.name == "Simparica" })

        await sut.log(item)

        XCTAssertEqual(try logStore.doseCount(for: med), 1)
        let comps = calendar.dateComponents([.month, .day], from: med.startedAt)
        XCTAssertEqual(comps.month, 9)
        XCTAssertEqual(comps.day, 16)
    }

    func testLoggingAnActivitySetsNextDueFromItsInterval() async throws {
        let type = try makeType("Bath", intervalDays: 30)
        let sut = makeSUT()
        sut.load()
        let item = try XCTUnwrap(sut.items.first { $0.name == "Bath" })

        await sut.log(item)

        let latest = try XCTUnwrap(logStore.latestLog(of: type))
        XCTAssertEqual(latest.performedAt, now)
        let due = try XCTUnwrap(latest.nextDueAt)
        XCTAssertEqual(calendar.dateComponents([.day], from: now, to: due).day, 30)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:PetHomepageTests/CadenceCatalogueViewModelTests`.
Expected: FAIL to compile — "cannot find 'CadenceCatalogueViewModel' in scope".

- [ ] **Step 3: Write the implementation**

Create `ios/PetHomepage/Features/PetProfile/CadenceCatalogueViewModel.swift`:

```swift
// ios/PetHomepage/Features/PetProfile/CadenceCatalogueViewModel.swift
import CoreData
import Foundation
import Observation

/// Aggregates everything on a cadence — medications and recurring activity types — into one
/// ordered list of tiles, and logs them.
///
/// This is a CATALOGUE, not a due list: an item appears whether or not anything is due, and
/// whether or not it has ever been logged. That is deliberate. The card this replaced could only
/// show what the app believed was due, and that belief has been demonstrated to go stale — it
/// also silently dropped never-logged items and excluded overdue ones.
@Observable
final class CadenceCatalogueViewModel {
    private(set) var items: [CadenceItem] = []

    private let medicationStore: MedicationStore
    private let activityStore: ActivityStore
    private let logStore: LogStore
    private let reminderScheduler: MedicationReminderScheduler
    private let dueScheduler: DueReminderScheduler
    private let calendar: Calendar
    private let now: () -> Date

    init(medicationStore: MedicationStore,
         activityStore: ActivityStore,
         logStore: LogStore,
         reminderScheduler: MedicationReminderScheduler,
         dueScheduler: DueReminderScheduler,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.medicationStore = medicationStore
        self.activityStore = activityStore
        self.logStore = logStore
        self.reminderScheduler = reminderScheduler
        self.dueScheduler = dueScheduler
        self.calendar = calendar
        self.now = now
    }

    func load() {
        let medications = ((try? medicationStore.medications()) ?? [])
            .filter { $0.endedAt == nil || ($0.endedAt.map { $0 > now() } ?? true) }
            .map { med in
                CadenceItem(
                    id: med.id,
                    source: .medication(med.objectID),
                    name: med.drugName,
                    // Medication has no category attribute, so the icon is fixed — matching the
                    // "Active meds" stat tile.
                    iconName: "pills.fill",
                    subtitle: med.dosage,
                    lastDone: try? logStore.lastDose(for: med),
                    // `startedAt` is this model's "next reminder date", not when the course began.
                    nextDue: med.startedAt)
            }

        // Only types with a real cadence. defaultIntervalDays == 0 means a one-off log type,
        // which by construction never gets a nextDueAt.
        let activities = ((try? activityStore.types(includeArchived: false)) ?? [])
            .filter { $0.defaultIntervalDays > 0 }
            .map { type in
                let latest = try? logStore.latestLog(of: type)
                return CadenceItem(
                    id: type.id,
                    source: .activityType(type.objectID),
                    name: type.name,
                    iconName: type.iconName,
                    subtitle: nil,
                    lastDone: latest?.performedAt,
                    nextDue: latest?.nextDueAt)
            }

        items = (medications + activities).sorted(by: Self.ordering(now: now(), calendar: calendar))
    }

    /// Overdue first (most overdue at the top), then due today, then soonest, then things with no
    /// cadence at all. Ties broken by name so the grid is stable between loads.
    private static func ordering(now: Date, calendar: Calendar)
        -> (CadenceItem, CadenceItem) -> Bool {
        { lhs, rhs in
            func rank(_ item: CadenceItem) -> Int {
                switch item.dueState(now: now, calendar: calendar) {
                case .overdue: return 0
                case .dueToday: return 1
                case .dueIn: return 2
                case .noCadence: return 3
                }
            }
            let (l, r) = (rank(lhs), rank(rhs))
            if l != r { return l < r }
            switch (lhs.nextDue, rhs.nextDue) {
            case let (ld?, rd?) where ld != rd: return ld < rd
            default: return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    /// Records the item as done now (or at an explicit date), then reloads.
    @MainActor
    func log(_ item: CadenceItem, at date: Date? = nil) async {
        let when = date ?? now()
        switch item.source {
        case .medication(let objectID):
            guard let med = medicationStore.context.object(with: objectID) as? Medication else { return }
            let logger = MedicationDoseLogger(logStore: logStore,
                                              reminderScheduler: reminderScheduler,
                                              calendar: calendar, now: now)
            await logger.log(med, at: when)
        case .activityType(let objectID):
            guard let type = activityStore.context.object(with: objectID) as? ActivityType else { return }
            // Same-day dedupe, matching MedicationDoseLogger.
            if let last = try? logStore.latestLog(of: type)?.performedAt,
               calendar.isDate(last, inSameDayAs: when) {
                return
            }
            guard let entry = try? logStore.logActivity(type: type, performedAt: when, note: nil,
                                                        intervalDays: Int(type.defaultIntervalDays))
            else { return }
            await dueScheduler.syncActivity(entry)
        }
        load()
    }
}
```

- [ ] **Step 4: Expose `context` on the two stores**

`CadenceCatalogueViewModel.log` reads `medicationStore.context` and `activityStore.context` to re-fetch by `NSManagedObjectID`. Both are currently `private` (verified), so this step is required or Step 5 will not compile. `LogStore.context` is already non-private — leave it alone.

In `ios/PetHomepage/Stores/MedicationStore.swift:6`, change:

```swift
    private let context: NSManagedObjectContext
```

to:

```swift
    let context: NSManagedObjectContext
```

Make the identical change in `ios/PetHomepage/Stores/ActivityStore.swift:8`. Change nothing else in either file.

- [ ] **Step 5: Run the test**

```bash
cd ios && xcodegen generate
```

Run with `-only-testing:PetHomepageTests/CadenceCatalogueViewModelTests`.
Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add ios/PetHomepage/Features/PetProfile/CadenceCatalogueViewModel.swift \
        ios/PetHomepageTests/CadenceCatalogueViewModelTests.swift \
        ios/PetHomepage/Stores/MedicationStore.swift ios/PetHomepage/Stores/ActivityStore.swift
git commit -m "feat(ios): CadenceCatalogueViewModel aggregates medications + activity types"
```

---

### Task 4: `CadenceTile` — the tile view

**Files:**
- Create: `ios/PetHomepage/Features/PetProfile/CadenceTile.swift`

**Interfaces:**
- Consumes: `CadenceItem`, `DueState` (Task 1).
- Produces: `CadenceTile(item:now:onTap:onLongPress:)`, and `DueState.badgeText` / `DueState.badgeTint` used only by this view.

This task has no unit test: it is pure layout with no logic beyond the badge strings, which are covered by `DueState` in Task 1. Verify visually in Task 5.

- [ ] **Step 1: Write the view**

Create `ios/PetHomepage/Features/PetProfile/CadenceTile.swift`:

```swift
// ios/PetHomepage/Features/PetProfile/CadenceTile.swift
import SwiftUI

extension DueState {
    var badgeText: String {
        switch self {
        case .overdue(let days): return days == 1 ? "1 day late" : "\(days) days late"
        case .dueToday: return "Due today"
        case .dueIn(let days): return days == 1 ? "Tomorrow" : "In \(days) days"
        case .noCadence: return "Not yet logged"
        }
    }

    var badgeTint: Color {
        switch self {
        case .overdue: return .red
        case .dueToday: return Theme.primary
        case .dueIn: return Theme.inkSoft
        case .noCadence: return Theme.inkSoft
        }
    }
}

/// One recurring thing. Tappable in EVERY state — a catalogue exists so you can record something
/// you just did regardless of what the app thinks is due.
struct CadenceTile: View {
    let item: CadenceItem
    let now: Date
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var lastDoneText: String {
        guard let lastDone = item.lastDone else { return "Never logged" }
        return lastDone.formatted(.relative(presentation: .named))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: item.iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                    Spacer(minLength: 0)
                    Text(item.dueState(now: now).badgeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.dueState(now: now).badgeTint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(lastDoneText)
                    .font(.caption2)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .onLongPressGesture { onLongPress() }
        .accessibilityIdentifier("cadenceTile.\(item.name)")
        .accessibilityLabel("\(item.name), \(item.dueState(now: now).badgeText), last done \(lastDoneText)")
    }
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ios && xcodegen generate
```

Run the full test command. Expected: builds, 0 failures (no new tests).

- [ ] **Step 3: Commit**

```bash
git add ios/PetHomepage/Features/PetProfile/CadenceTile.swift
git commit -m "feat(ios): CadenceTile view with due badge"
```

---

### Task 5: Embed the grid in `PetProfileView`, replacing the Upcoming card

**Files:**
- Modify: `ios/PetHomepage/Features/PetProfile/PetProfileView.swift`

**Interfaces:**
- Consumes: `CadenceItem` (Task 1), `CadenceCatalogueViewModel` (Task 3), `CadenceTile` (Task 4).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the catalogue state**

In `PetProfileView`, next to the other `@State` declarations (around line 19-23), add:

```swift
    @State private var catalogue: CadenceCatalogueViewModel?
    @State private var backdateTarget: CadenceItem?
```

Delete the now-unused `@State private var upcoming: [TimelineItem] = []`.

- [ ] **Step 2: Replace the Upcoming section in `body`**

Replace this block:

```swift
                if !upcoming.isEmpty {
                    upcomingCard.padding(.horizontal, 18)
                }
```

with:

```swift
                if let catalogue, !catalogue.items.isEmpty {
                    cadenceGrid(catalogue).padding(.horizontal, 18)
                }
```

- [ ] **Step 3: Delete `upcomingCard` and add the grid**

Delete the whole `private var upcomingCard: some View { ... }` computed property. In its place add:

```swift
    // MARK: - Cadence catalogue

    /// A tile per recurring thing. Replaces the old Upcoming card, which was built from the
    /// Timeline stream and so could only show things already logged at least once — and whose
    /// `due >= now` filter hid overdue items entirely.
    private func cadenceGrid(_ model: CadenceCatalogueViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Care routine").font(Theme.headline()).foregroundStyle(Theme.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(model.items) { item in
                    CadenceTile(
                        item: item,
                        now: Date(),
                        onTap: { Task { await model.log(item); refresh() } },
                        onLongPress: { backdateTarget = item })
                }
            }
        }
    }
```

- [ ] **Step 4: Add the backdate sheet**

Alongside the other `.sheet` modifiers in `body`, add:

```swift
            .sheet(item: $backdateTarget) { item in
                CadenceBackdateSheet(item: item) { date in
                    guard let catalogue else { return }
                    Task { await catalogue.log(item, at: date); refresh() }
                }
            }
```

Then create the sheet at the bottom of the same file, after the closing brace of `PetProfileView`:

```swift
/// Long-press destination: record a recurring thing as done at a time other than now.
private struct CadenceBackdateSheet: View {
    let item: CadenceItem
    let onConfirm: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var when = Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Done at", selection: $when, in: ...Date())
                    .datePickerStyle(.graphical)
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { onConfirm(when); dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Build the catalogue in `refresh()`**

In `private func refresh()`, delete the line `upcoming = vm.dueSoon(within: 60)`. Then, at the end of the function, add:

```swift
        let model = catalogue ?? CadenceCatalogueViewModel(
            medicationStore: s.medicationStore,
            activityStore: s.activityStore,
            logStore: s.logStore,
            reminderScheduler: s.reminderScheduler,
            dueScheduler: s.dueScheduler)
        model.load()
        catalogue = model
```

- [ ] **Step 6: Build and run the full suite**

```bash
cd ios && xcodegen generate
```

Run the full test command. Expected: 0 failures.

- [ ] **Step 7: Verify visually**

Launch the app in the simulator. On Home you should see a **Care routine** grid with two-column tiles: `Bath`, `Nail trim`, `Teeth brushing`, `Brushing`, `Grooming` (from the seeds) plus any medications. Tapping a tile updates its "last done" text immediately. Long-pressing opens the backdate sheet.

- [ ] **Step 8: Commit**

```bash
git add ios/PetHomepage/Features/PetProfile/PetProfileView.swift
git commit -m "feat(ios): Home shows a cadence catalogue instead of the Upcoming card"
```

---

### Task 6: Tab reorder — Home first, Schedule second

**Files:**
- Modify: `ios/PetHomepage/App/ContentView.swift`
- Modify: `ios/PetHomepageUITests/PetSwitcherTests.swift` (stale comment only)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Change the launch default**

In `ContentView`, change:

```swift
    @State private var selectedTab = 3
```

to:

```swift
    @State private var selectedTab = 0
```

- [ ] **Step 2: Move the Schedule block after the profile block**

In the `TabView`, move the whole `ScheduleView(...)` block (including its `.tabItem` and `.tag(3)`) so it comes *after* the `PetProfileView(...)` block. **Do not change any `.tag(...)` value** — tags are how `NotificationRouter` deep-links, and moving one breaks every notification tap. The resulting order is: `PetProfileView` `.tag(0)`, `ScheduleView` `.tag(3)`, `TimelineView` `.tag(1)`, `CareTeamView` `.tag(4)`.

- [ ] **Step 3: Fix the stale test comment**

In `ios/PetHomepageUITests/PetSwitcherTests.swift`, replace the comment

```swift
        // The app now launches on the Schedule tab; the pet switcher lives on Home.
```

with

```swift
        // The app launches on Home, where the pet switcher lives; the tap is a no-op safeguard.
```

- [ ] **Step 4: Run the full suite**

Run the full test command. Expected: 0 failures. The UI tests select tabs by label (`app.tabBars.buttons["Home"]`), so display order does not affect them.

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/App/ContentView.swift ios/PetHomepageUITests/PetSwitcherTests.swift
git commit -m "feat(ios): Home is the first tab and the launch default"
```

---

### Task 7: Drop the clashing activity seeds

`Flea & tick` and `Deworming` are seeded `ActivityType`s that duplicate what a real `Medication` record represents. New pets should not get them. Existing rows are left alone — deleting user data to tidy a seed list is not a trade worth making.

**Files:**
- Modify: `ios/PetHomepage/Stores/ActivityStore.swift`
- Test: `ios/PetHomepageTests/ActivityStoreSeedingTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Write the failing test**

Add to `ios/PetHomepageTests/ActivityStoreSeedingTests.swift`:

```swift
    /// Preventatives are modelled as Medications (they have a dosage and a prescriber), so
    /// seeding them as activity types too would give every pet a duplicate tile on Home.
    func testDefaultSeedsDoNotIncludePreventatives() {
        let names = Set(ActivityStore.defaultSeeds.map { $0.name.lowercased() })
        XCTAssertFalse(names.contains("flea & tick"))
        XCTAssertFalse(names.contains("deworming"))
    }

    func testDefaultSeedsStillIncludeGroomingCare() {
        let names = Set(ActivityStore.defaultSeeds.map { $0.name })
        XCTAssertEqual(names, ["Bath", "Nail trim", "Teeth brushing", "Brushing", "Grooming"])
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run with `-only-testing:PetHomepageTests/ActivityStoreSeedingTests`.
Expected: FAIL — both new tests, because the two entries are still present.

- [ ] **Step 3: Remove the two seeds**

In `ios/PetHomepage/Stores/ActivityStore.swift`, delete these two lines from `defaultSeeds`:

```swift
        ("Flea & tick", .health, "ladybug", 30),
        ("Deworming", .health, "pills", 90),
```

- [ ] **Step 4: Run the tests**

Run with `-only-testing:PetHomepageTests/ActivityStoreSeedingTests`.
Expected: PASS. Then run the full suite; expected 0 failures.

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Stores/ActivityStore.swift ios/PetHomepageTests/ActivityStoreSeedingTests.swift
git commit -m "feat(ios): stop seeding Flea & tick / Deworming as activity types

Preventatives are Medications; seeding them as activity types too gave every
pet a duplicate tile. Existing rows are untouched."
```

---

## Done when

- Home is the first tab and the launch screen; Schedule is second; every `.tag` is unchanged.
- Home shows a **Care routine** grid with a tile per active medication and per recurring activity type, including ones never logged.
- A tile shows name, icon, last-done, and a badge: `N days late` / `Due today` / `Tomorrow` / `In N days` / `Not yet logged`, ordered most-urgent first.
- Tapping a tile logs it once (same-day repeats are deduped), advances the cadence, and re-syncs the reminder. Long-press backdates.
- Exactly one implementation of the medication cadence-advance rule exists (`MedicationDoseLogger`), used by the in-app flow, the notification action, Home's quick action, and the catalogue.
- New pets are not seeded `Flea & tick` or `Deworming`.
- Full suite passes (allowing for the two documented infrastructure flakes).
