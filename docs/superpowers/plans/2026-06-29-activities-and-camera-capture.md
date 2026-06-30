# Activities (logged care events) + Camera Capture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let owners log recurring care activities (bath, nail trim, etc.) with per-type cadence, reminders, history, and photos — and let any photo section capture from the camera, not just the library.

**Architecture:** Two new Core Data entities — `ActivityType` (user-defined, pre-seeded, editable definition) and `ActivityLog` (each occurrence, carrying its own `nextDueAt`, mirroring `Vaccination`). A new `ActivityStore` (mirrors `HealthMarkerStore`/`VaccinationStore`). Reminders reuse the existing `DueReminderScheduler`/`NotificationScheduling`. Activities plug into the existing unified **Timeline** (new `TimelineKind.activity`). Type management lives in Settings; logging is a `BrandFormSheet` edit sheet reached from the Timeline "+" menu. Camera capture is added to the shared `PendingPhotoSection`/`PhotoStripSection` via a `UIImagePickerController` wrapper.

**Tech Stack:** Swift, SwiftUI, Core Data (`NSPersistentCloudKitContainer` in prod, in-memory for tests), XCTest, xcodegen (project generated from `ios/project.yml`), UserNotifications, PhotosUI/UIKit.

## Global Constraints

- **iOS app is the system of record.** All work is under `ios/PetHomepage/`. Do NOT touch the Convex `MirrorSnapshot`/dashboard — Activities are explicitly out of the mirror this round.
- **CloudKit compatibility (verbatim model rule):** every Core Data relationship must be `optional="YES"` and have an `inverseName`/`inverseEntity`; the `<model>` is `usedWithCloudKit="YES"`. No required-to-one relationships.
- **Codebase conventions:** enums persisted as `*Raw` String attributes with an `.other` fallback (see `MarkerType`); numerics as `Double` (`usesScalarValueType="YES"`, `defaultValueString="0"`); there are NO existing Int/Bool attributes — `Integer 64`/`Boolean` attributes are introduced here and MUST carry `usesScalarValueType="YES"` + a `defaultValueString`.
- **Reminder sync is ViewModel-driven, never store-driven.** A store saves the context; the edit ViewModel then calls `await dueScheduler.sync…(…)`. Mirror this exactly.
- **Stores are built in `ContentView.body`** and threaded through views / the `TimelineServices` struct. Schedulers wrap a fresh `UNNotificationScheduler()`.
- **Regenerate the project after adding files:** any task that creates a new `.swift` file must run `xcodegen generate` from `ios/` before building/testing (the Xcode project globs source dirs from `project.yml`).
- **Test command template** (adjust simulator name to one installed locally; discover with `xcrun simctl list devices available`):
  `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/<TestClass>`
- **Commit after every task** with a `feat:`/`test:`/`refactor:` message. Work on branch `feat/care-activities` (already created).
- **SF Symbol names are provisional.** Before committing any task that hardcodes a symbol, verify it renders (SF Symbols app or a quick simulator run); substitute the closest existing symbol if missing.

---

## File Structure

**Create:**
- `ios/PetHomepage/Models/ActivityCategory.swift` — the fixed category enum.
- `ios/PetHomepage/Models/ActivityType.swift` — `ActivityType` NSManagedObject subclass + `category` typed accessor.
- `ios/PetHomepage/Models/ActivityLog.swift` — `ActivityLog` NSManagedObject subclass + `photoArray` helper.
- `ios/PetHomepage/Stores/ActivityStore.swift` — type CRUD, logging, queries, seeding.
- `ios/PetHomepage/DesignSystem/CameraPicker.swift` — `UIImagePickerController` SwiftUI wrapper.
- `ios/PetHomepage/DesignSystem/ImageDownscaler.swift` — shared downscale→JPEG helper (extracted from the photo sections).
- `ios/PetHomepage/Features/Activities/ActivityLogEditView.swift` + `ActivityLogEditViewModel.swift` — log/edit sheet.
- `ios/PetHomepage/Features/Activities/ActivityTypesView.swift` + `ActivityTypesViewModel.swift` — type management.
- Tests: `ios/PetHomepageTests/ActivityCategoryTests.swift`, `ActivityModelTests.swift`, `ActivityStoreTests.swift`, `ActivityStoreSeedingTests.swift`, `ActivityLogEditViewModelTests.swift`, `ImageDownscalerTests.swift`; additions to `DueReminderSchedulerTests.swift` and `TimelineViewModelTests.swift`.

**Modify:**
- `ios/PetHomepage/Persistence/PetHomepage.xcdatamodeld/PetHomepage.xcdatamodel/contents` — add two entities + `Photo.activityLog` relationship.
- `ios/PetHomepage/Models/Photo.swift` — add `activityLog` relationship property.
- `ios/PetHomepage/Notifications/NotificationScheduling.swift` — add `ReminderKind.activity` + parse loop.
- `ios/PetHomepage/Notifications/DueReminderScheduler.swift` — `activityReminder`/`syncActivity`/`cancelActivity`.
- `ios/PetHomepage/Features/Timeline/TimelineViewModel.swift` — `.activity` kind/reference/init/delete + store field.
- `ios/PetHomepage/Features/Timeline/TimelineView.swift` — `TimelineServices.activityStore`, editor/addEditor/tint/add-menu branches, `TimelineViewModel` init arg.
- `ios/PetHomepage/App/ContentView.swift` — build `ActivityStore`, pass into `TimelineServices`, seed on appear.
- `ios/PetHomepage/Features/Settings/SettingsView.swift` — a "Manage activity types" navigation entry.
- `ios/PetHomepage/DesignSystem/PendingPhotoSection.swift` + `PhotoStripSection.swift` — "Take photo" button + use `ImageDownscaler`.
- `ios/project.yml` — broaden `INFOPLIST_KEY_NSCameraUsageDescription` wording.

---

## Task 1: ActivityCategory enum

**Files:**
- Create: `ios/PetHomepage/Models/ActivityCategory.swift`
- Test: `ios/PetHomepageTests/ActivityCategoryTests.swift`

**Interfaces:**
- Produces: `enum ActivityCategory: String, CaseIterable, Identifiable` with cases `care, play, feeding, training, health, other`; `var id: String`; `var displayName: String`; `var systemImage: String`; `init(rawValueOrOther:)` falling back to `.other`.

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/ActivityCategoryTests.swift
import XCTest
@testable import PetHomepage

final class ActivityCategoryTests: XCTestCase {
    func testDisplayNamesAreTitleCased() {
        XCTAssertEqual(ActivityCategory.care.displayName, "Care")
        XCTAssertEqual(ActivityCategory.feeding.displayName, "Feeding")
        XCTAssertEqual(ActivityCategory.other.displayName, "Other")
    }

    func testUnknownRawValueFallsBackToOther() {
        XCTAssertEqual(ActivityCategory(rawValueOrOther: "care"), .care)
        XCTAssertEqual(ActivityCategory(rawValueOrOther: "nonsense"), .other)
    }

    func testAllCasesHaveASymbol() {
        for category in ActivityCategory.allCases {
            XCTAssertFalse(category.systemImage.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/ActivityCategoryTests`
Expected: FAIL — `cannot find 'ActivityCategory' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// ios/PetHomepage/Models/ActivityCategory.swift
import Foundation

/// The fixed, app-defined grouping for activity types. Unlike `ActivityType` (user-defined,
/// editable), categories are a small stable set — so this mirrors `MarkerType`: a String-backed
/// enum stored as `categoryRaw` with an `.other` fallback for unknown values.
enum ActivityCategory: String, CaseIterable, Identifiable {
    case care
    case play
    case feeding
    case training
    case health
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .care: "Care"
        case .play: "Play"
        case .feeding: "Feeding"
        case .training: "Training"
        case .health: "Health"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .care: "heart"
        case .play: "tennisball"
        case .feeding: "fork.knife"
        case .training: "figure.walk"
        case .health: "cross.case"
        case .other: "pawprint"
        }
    }

    /// Strongly-typed view of a raw value; falls back to `.other` for unknown strings.
    init(rawValueOrOther raw: String) {
        self = ActivityCategory(rawValue: raw) ?? .other
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Models/ActivityCategory.swift ios/PetHomepageTests/ActivityCategoryTests.swift
git commit -m "feat: add ActivityCategory enum"
```

---

## Task 2: Core Data entities + model classes

**Files:**
- Modify: `ios/PetHomepage/Persistence/PetHomepage.xcdatamodeld/PetHomepage.xcdatamodel/contents`
- Create: `ios/PetHomepage/Models/ActivityType.swift`, `ios/PetHomepage/Models/ActivityLog.swift`
- Modify: `ios/PetHomepage/Models/Photo.swift`
- Test: `ios/PetHomepageTests/ActivityModelTests.swift`

**Interfaces:**
- Consumes: `ActivityCategory` (Task 1).
- Produces:
  - `ActivityType: NSManagedObject` — `@NSManaged var id: UUID`, `name: String`, `categoryRaw: String`, `iconName: String`, `defaultIntervalDays: Int64`, `sortOrder: Int64`, `isArchived: Bool`, `logs: NSSet?`; computed `var category: ActivityCategory { get set }`; static `fetchRequest()`.
  - `ActivityLog: NSManagedObject` — `@NSManaged var id: UUID`, `performedAt: Date`, `note: String?`, `intervalDays: Int64`, `nextDueAt: Date?`, `activityType: ActivityType?`, `pet: Pet?`, `photos: NSSet?`; computed `var photoArray: [Photo]`; static `fetchRequest()`.
  - `Photo.activityLog: ActivityLog?`.

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/ActivityModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class ActivityModelTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
    }

    func testActivityTypeAndLogPersistAndRelate() throws {
        let type = ActivityType(context: context)
        type.id = UUID()
        type.name = "Bath"
        type.category = .care
        type.iconName = "shower"
        type.defaultIntervalDays = 30
        type.sortOrder = 0
        type.isArchived = false

        let log = ActivityLog(context: context)
        log.id = UUID()
        log.performedAt = Date(timeIntervalSince1970: 1_000)
        log.intervalDays = 30
        log.nextDueAt = Date(timeIntervalSince1970: 1_000 + 30 * 86_400)
        log.activityType = type

        try context.save()

        let fetched = try context.fetch(ActivityType.fetchRequest())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.category, .care)
        XCTAssertEqual((fetched.first?.logs as? Set<ActivityLog>)?.count, 1)
    }

    func testCategoryAccessorRoundTripsAndFallsBack() throws {
        let type = ActivityType(context: context)
        type.category = .health
        XCTAssertEqual(type.categoryRaw, "health")
        type.categoryRaw = "bogus"
        XCTAssertEqual(type.category, .other)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/ActivityModelTests`
Expected: FAIL — `cannot find 'ActivityType' in scope`.

- [ ] **Step 3: Add the two entities to the Core Data model**

Open `ios/PetHomepage/Persistence/PetHomepage.xcdatamodeld/PetHomepage.xcdatamodel/contents`. Immediately BEFORE the closing `</model>` tag, insert these two entity blocks:

```xml
    <entity name="ActivityType" representedClassName="ActivityType" syncable="YES" codeGenerationType="none">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="name" optional="NO" attributeType="String" defaultValueString=""/>
        <attribute name="categoryRaw" optional="NO" attributeType="String" defaultValueString="other"/>
        <attribute name="iconName" optional="NO" attributeType="String" defaultValueString="pawprint"/>
        <attribute name="defaultIntervalDays" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="sortOrder" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="isArchived" optional="YES" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>
        <relationship name="pet" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Pet" inverseName="activityTypes" inverseEntity="Pet"/>
        <relationship name="logs" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="ActivityLog" inverseName="activityType" inverseEntity="ActivityLog"/>
    </entity>
    <entity name="ActivityLog" representedClassName="ActivityLog" syncable="YES" codeGenerationType="none">
        <attribute name="id" optional="YES" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="performedAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="note" optional="YES" attributeType="String"/>
        <attribute name="intervalDays" optional="YES" attributeType="Integer 64" defaultValueString="0" usesScalarValueType="YES"/>
        <attribute name="nextDueAt" optional="YES" attributeType="Date" usesScalarValueType="NO"/>
        <relationship name="activityType" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="ActivityType" inverseName="logs" inverseEntity="ActivityType"/>
        <relationship name="pet" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="Pet" inverseName="activityLogs" inverseEntity="Pet"/>
        <relationship name="photos" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="Photo" inverseName="activityLog" inverseEntity="Photo"/>
    </entity>
```

- [ ] **Step 4: Add the inverse relationships on `Pet` and `Photo` in the model**

In the same `contents` file, find the `<entity name="Pet" ...>` block and add these two relationships inside it (alongside its existing `vaccinations`/`medications` relationships):

```xml
        <relationship name="activityTypes" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="ActivityType" inverseName="pet" inverseEntity="ActivityType"/>
        <relationship name="activityLogs" optional="YES" toMany="YES" deletionRule="Cascade" destinationEntity="ActivityLog" inverseName="pet" inverseEntity="ActivityLog"/>
```

Find the `<entity name="Photo" ...>` block and add this relationship inside it (alongside `vetVisit`/`medication`/`vaccination`):

```xml
        <relationship name="activityLog" optional="YES" maxCount="1" deletionRule="Nullify" destinationEntity="ActivityLog" inverseName="photos" inverseEntity="ActivityLog"/>
```

- [ ] **Step 5: Create the `ActivityType` model class**

```swift
// ios/PetHomepage/Models/ActivityType.swift
import CoreData

@objc(ActivityType)
public class ActivityType: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var categoryRaw: String
    @NSManaged public var iconName: String
    @NSManaged public var defaultIntervalDays: Int64
    @NSManaged public var sortOrder: Int64
    @NSManaged public var isArchived: Bool
    @NSManaged public var pet: Pet?
    @NSManaged public var logs: NSSet?
}

extension ActivityType {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<ActivityType> {
        NSFetchRequest<ActivityType>(entityName: "ActivityType")
    }

    /// Strongly-typed view of `categoryRaw`; falls back to `.other` for unknown values.
    var category: ActivityCategory {
        get { ActivityCategory(rawValueOrOther: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }
}

extension ActivityType: Identifiable {}
```

- [ ] **Step 6: Create the `ActivityLog` model class**

```swift
// ios/PetHomepage/Models/ActivityLog.swift
import CoreData

@objc(ActivityLog)
public class ActivityLog: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var performedAt: Date
    @NSManaged public var note: String?
    @NSManaged public var intervalDays: Int64
    @NSManaged public var nextDueAt: Date?
    @NSManaged public var activityType: ActivityType?
    @NSManaged public var pet: Pet?
    @NSManaged public var photos: NSSet?
}

extension ActivityLog {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<ActivityLog> {
        NSFetchRequest<ActivityLog>(entityName: "ActivityLog")
    }

    /// This log's photos, oldest-first.
    var photoArray: [Photo] {
        (photos as? Set<Photo> ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

extension ActivityLog: Identifiable {}
```

- [ ] **Step 7: Add the `activityLog` relationship to `Photo`**

In `ios/PetHomepage/Models/Photo.swift`, add one line to the `@NSManaged` block (after `vaccination`):

```swift
    @NSManaged public var activityLog: ActivityLog?
```

- [ ] **Step 8: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (2 tests). If it fails with "Multiple NSEntityDescriptions claim…" or a keypath crash, recheck that every new relationship has a matching inverse and that `Pet` got both inverse relationships.

- [ ] **Step 9: Commit**

```bash
git add ios/PetHomepage/Persistence/PetHomepage.xcdatamodeld ios/PetHomepage/Models/ActivityType.swift ios/PetHomepage/Models/ActivityLog.swift ios/PetHomepage/Models/Photo.swift ios/PetHomepageTests/ActivityModelTests.swift
git commit -m "feat: add ActivityType and ActivityLog Core Data entities"
```

---

## Task 3: ActivityStore — type CRUD, logging, queries

**Files:**
- Create: `ios/PetHomepage/Stores/ActivityStore.swift`
- Test: `ios/PetHomepageTests/ActivityStoreTests.swift`

**Interfaces:**
- Consumes: `ActivityType`, `ActivityLog`, `ActivityCategory`, `PetStore`.
- Produces (`final class ActivityStore`):
  - `init(context: NSManagedObjectContext, petStore: PetStore)`
  - `@discardableResult func createType(name: String, category: ActivityCategory, iconName: String, defaultIntervalDays: Int) throws -> ActivityType`
  - `func types(includeArchived: Bool = false) throws -> [ActivityType]` (sorted by category displayName, then `sortOrder`, then name)
  - `func updateType(_:name:category:iconName:defaultIntervalDays:) throws`
  - `func archiveType(_ type: ActivityType) throws`
  - `@discardableResult func log(type: ActivityType, performedAt: Date, note: String?, intervalDays: Int) throws -> ActivityLog` (stamps `nextDueAt = performedAt + intervalDays` days when `intervalDays > 0`, else nil; scopes `pet`)
  - `func logs() throws -> [ActivityLog]` (newest first)
  - `func logs(of type: ActivityType) throws -> [ActivityLog]` (newest first)
  - `func latestLog(of type: ActivityType) throws -> ActivityLog?`
  - `func delete(_ log: ActivityLog) throws`

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/ActivityStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class ActivityStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: ActivityStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = ActivityStore(context: context, petStore: petStore)
    }

    func testCreateTypeIsListedAndScopedToPet() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        XCTAssertNotNil(type.id)
        let types = try store.types()
        XCTAssertEqual(types.map(\.name), ["Bath"])
        XCTAssertEqual(types.first?.pet?.name, "Sandy")
    }

    func testArchivedTypesAreHiddenByDefault() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        try store.archiveType(type)
        XCTAssertEqual(try store.types().count, 0)
        XCTAssertEqual(try store.types(includeArchived: true).count, 1)
    }

    func testLogStampsNextDueFromInterval() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let start = Date(timeIntervalSince1970: 0)
        let log = try store.log(type: type, performedAt: start, note: "clean pup", intervalDays: 30)
        XCTAssertEqual(log.pet?.name, "Sandy")
        XCTAssertEqual(log.note, "clean pup")
        XCTAssertEqual(log.nextDueAt, Calendar.current.date(byAdding: .day, value: 30, to: start))
    }

    func testLogWithZeroIntervalHasNoNextDue() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        let log = try store.log(type: type, performedAt: Date(), note: nil, intervalDays: 0)
        XCTAssertNil(log.nextDueAt)
    }

    func testLatestLogReturnsMostRecentOfType() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 1_000), note: nil, intervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 3_000), note: nil, intervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 2_000), note: nil, intervalDays: 0)
        XCTAssertEqual(try store.latestLog(of: type)?.performedAt, Date(timeIntervalSince1970: 3_000))
    }

    func testLogsAreNewestFirst() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 1_000), note: nil, intervalDays: 0)
        try store.log(type: type, performedAt: Date(timeIntervalSince1970: 2_000), note: nil, intervalDays: 0)
        XCTAssertEqual(try store.logs().map(\.performedAt),
                       [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 1_000)])
    }

    func testDeleteRemovesLog() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        let log = try store.log(type: type, performedAt: Date(), note: nil, intervalDays: 0)
        try store.delete(log)
        XCTAssertEqual(try store.logs().count, 0)
    }

    func testEmptyWhenNoPetExists() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = ActivityStore(context: ctx, petStore: PetStore(context: ctx))
        XCTAssertEqual(try emptyStore.types().count, 0)
        XCTAssertEqual(try emptyStore.logs().count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/ActivityStoreTests`
Expected: FAIL — `cannot find 'ActivityStore' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
// ios/PetHomepage/Stores/ActivityStore.swift
import CoreData

/// CRUD for user-defined activity types and their logged occurrences, scoped to the single
/// current pet (v1). Mirrors HealthMarkerStore / VaccinationStore. Reminder scheduling is NOT
/// done here — the edit ViewModel calls DueReminderScheduler after the store saves.
final class ActivityStore {
    private let context: NSManagedObjectContext
    private let petStore: PetStore
    private let calendar: Calendar

    init(context: NSManagedObjectContext, petStore: PetStore, calendar: Calendar = .current) {
        self.context = context
        self.petStore = petStore
        self.calendar = calendar
    }

    // MARK: - Types

    @discardableResult
    func createType(name: String,
                    category: ActivityCategory,
                    iconName: String,
                    defaultIntervalDays: Int) throws -> ActivityType {
        let type = ActivityType(context: context)
        type.id = UUID()
        type.name = name
        type.category = category
        type.iconName = iconName
        type.defaultIntervalDays = Int64(defaultIntervalDays)
        type.sortOrder = Int64(try types(includeArchived: true).count)
        type.isArchived = false
        type.pet = try petStore.ensurePet()
        try context.save()
        return type
    }

    /// Activity types for the current pet, sorted by category then sortOrder then name.
    func types(includeArchived: Bool = false) throws -> [ActivityType] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = ActivityType.fetchRequest()
        request.predicate = includeArchived
            ? NSPredicate(format: "pet == %@", pet)
            : NSPredicate(format: "pet == %@ AND isArchived == NO", pet)
        let all = try context.fetch(request)
        return all.sorted { lhs, rhs in
            if lhs.category.displayName != rhs.category.displayName {
                return lhs.category.displayName < rhs.category.displayName
            }
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.name < rhs.name
        }
    }

    func updateType(_ type: ActivityType,
                    name: String,
                    category: ActivityCategory,
                    iconName: String,
                    defaultIntervalDays: Int) throws {
        type.name = name
        type.category = category
        type.iconName = iconName
        type.defaultIntervalDays = Int64(defaultIntervalDays)
        try context.save()
    }

    func archiveType(_ type: ActivityType) throws {
        type.isArchived = true
        try context.save()
    }

    // MARK: - Logs

    @discardableResult
    func log(type: ActivityType,
             performedAt: Date,
             note: String?,
             intervalDays: Int) throws -> ActivityLog {
        let log = ActivityLog(context: context)
        log.id = UUID()
        log.performedAt = performedAt
        log.note = note
        log.intervalDays = Int64(intervalDays)
        log.nextDueAt = intervalDays > 0
            ? calendar.date(byAdding: .day, value: intervalDays, to: performedAt)
            : nil
        log.activityType = type
        log.pet = try petStore.ensurePet()
        try context.save()
        return log
    }

    /// All logs for the current pet, most recent first.
    func logs() throws -> [ActivityLog] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = ActivityLog.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@", pet)
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: false)]
        return try context.fetch(request)
    }

    func logs(of type: ActivityType) throws -> [ActivityLog] {
        let request = ActivityLog.fetchRequest()
        request.predicate = NSPredicate(format: "activityType == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: false)]
        return try context.fetch(request)
    }

    func latestLog(of type: ActivityType) throws -> ActivityLog? {
        let request = ActivityLog.fetchRequest()
        request.predicate = NSPredicate(format: "activityType == %@", type)
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: false)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func delete(_ log: ActivityLog) throws {
        context.delete(log)
        try context.save()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Stores/ActivityStore.swift ios/PetHomepageTests/ActivityStoreTests.swift
git commit -m "feat: add ActivityStore type CRUD, logging, and queries"
```

---

## Task 4: Seeding default activity types

**Files:**
- Modify: `ios/PetHomepage/Stores/ActivityStore.swift`
- Test: `ios/PetHomepageTests/ActivityStoreSeedingTests.swift`

**Interfaces:**
- Produces: `func seedDefaultsIfNeeded() throws` on `ActivityStore`, and `static let defaultSeeds: [(name: String, category: ActivityCategory, iconName: String, intervalDays: Int)]`.
- Behavior: seeds the 7 default types once. Idempotent: a second call adds nothing. De-dupes by name (case-insensitive) — if a default name already exists (seeded or user-created), it is skipped rather than duplicated. Never seeds when there is no current pet.

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/ActivityStoreSeedingTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class ActivityStoreSeedingTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: ActivityStore!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = ActivityStore(context: context, petStore: petStore)
    }

    func testSeedingCreatesDefaultsOnce() throws {
        try store.seedDefaultsIfNeeded()
        let firstCount = try store.types().count
        XCTAssertEqual(firstCount, ActivityStore.defaultSeeds.count)
        XCTAssertTrue(try store.types().contains { $0.name == "Bath" })

        try store.seedDefaultsIfNeeded()
        XCTAssertEqual(try store.types().count, firstCount, "second seed must add nothing")
    }

    func testSeedingSkipsNamesThatAlreadyExist() throws {
        try store.createType(name: "Bath", category: .play, iconName: "tennisball", defaultIntervalDays: 0)
        try store.seedDefaultsIfNeeded()
        let baths = try store.types(includeArchived: true).filter { $0.name == "Bath" }
        XCTAssertEqual(baths.count, 1, "must not duplicate an existing 'Bath'")
        XCTAssertEqual(baths.first?.category, .play, "must not overwrite the user's existing type")
    }

    func testSeedingDoesNothingWithoutAPet() throws {
        let ctx = PersistenceController(inMemory: true).container.viewContext
        let emptyStore = ActivityStore(context: ctx, petStore: PetStore(context: ctx))
        try emptyStore.seedDefaultsIfNeeded()
        XCTAssertEqual(try emptyStore.types(includeArchived: true).count, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/ActivityStoreSeedingTests`
Expected: FAIL — `value of type 'ActivityStore' has no member 'seedDefaultsIfNeeded'`.

- [ ] **Step 3: Add seeding to `ActivityStore`**

Add this `// MARK: - Seeding` section inside the `ActivityStore` class (after the Logs section):

```swift
    // MARK: - Seeding

    /// The starter set of editable activity types, pre-seeded so logging works with zero setup.
    static let defaultSeeds: [(name: String, category: ActivityCategory, iconName: String, intervalDays: Int)] = [
        ("Bath", .care, "shower", 30),
        ("Nail trim", .care, "scissors", 21),
        ("Teeth brushing", .care, "mouth", 1),
        ("Brushing", .care, "comb", 7),
        ("Grooming", .care, "dog", 42),
        ("Flea & tick", .health, "ladybug", 30),
        ("Deworming", .health, "pills", 90),
    ]

    /// Seeds any default types that don't already exist (by case-insensitive name). Idempotent,
    /// and a no-op when there is no current pet. Safe to call every time the Activities UI appears:
    /// because it de-dupes by name against ALL existing types (including ones synced in from another
    /// device via CloudKit), it won't double-seed once the cloud import has settled.
    func seedDefaultsIfNeeded() throws {
        guard (try petStore.currentPet()) != nil else { return }
        let existingNames = Set(try types(includeArchived: true).map { $0.name.lowercased() })
        for seed in Self.defaultSeeds where !existingNames.contains(seed.name.lowercased()) {
            try createType(name: seed.name,
                           category: seed.category,
                           iconName: seed.iconName,
                           defaultIntervalDays: seed.intervalDays)
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Stores/ActivityStore.swift ios/PetHomepageTests/ActivityStoreSeedingTests.swift
git commit -m "feat: seed default activity types (idempotent, dedupe by name)"
```

> **CloudKit note (no extra code in v1):** de-duping by name against all existing types is the backstop. A tighter guard (a synced "did-seed" marker) is intentionally deferred; the dedupe makes repeated seeds safe even if two devices both run it before the cloud import settles — at worst a brief window could create a duplicate that the next dedupe pass leaves alone. Acceptable for v1; revisit if duplicates are observed.

---

## Task 5: Notification layer — activity reminders

**Files:**
- Modify: `ios/PetHomepage/Notifications/NotificationScheduling.swift`
- Modify: `ios/PetHomepage/Notifications/DueReminderScheduler.swift`
- Test: `ios/PetHomepageTests/DueReminderSchedulerTests.swift` (add cases)

**Interfaces:**
- Consumes: `ActivityLog`, `PendingReminder`, `NotificationScheduling`.
- Produces:
  - `ReminderKind.activity`
  - `DueReminderScheduler.activityReminder(for: ActivityLog) -> PendingReminder?`
  - `DueReminderScheduler.syncActivity(_ log: ActivityLog) async`
  - `DueReminderScheduler.cancelActivity(_ log: ActivityLog) async`

- [ ] **Step 1: Write the failing tests** (append to `DueReminderSchedulerTests`)

Add an `activityStore` to the existing `setUpWithError` and these test methods. Replace the `setUpWithError` body with:

```swift
    private var context: NSManagedObjectContext!
    private var vaxStore: VaccinationStore!
    private var activityStore: ActivityStore!
    private var calendar: Calendar!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        vaxStore = VaccinationStore(context: context, petStore: petStore)
        activityStore = ActivityStore(context: context, petStore: petStore)
        calendar = Calendar(identifier: .gregorian)
    }
```

Then add:

```swift
    func testActivityReminderUsesNextDueAt() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let performed = calendar.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let log = try activityStore.log(type: type, performedAt: performed, note: nil, intervalDays: 30)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)

        let reminder = sched.activityReminder(for: log)

        XCTAssertNotNil(reminder)
        XCTAssertEqual(reminder?.kind, .activity)
        XCTAssertEqual(reminder?.entityID, log.id)
        XCTAssertEqual(reminder?.dateComponents?.month, 7)
        XCTAssertEqual(reminder?.dateComponents?.day, 1)
        XCTAssertTrue(reminder?.body.contains("Bath") ?? false)
    }

    func testActivityWithoutNextDueHasNoReminder() throws {
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 0)
        let log = try activityStore.log(type: type, performedAt: Date(), note: nil, intervalDays: 0)
        let sched = DueReminderScheduler(scheduler: FakeNotificationScheduler(), calendar: calendar, hour: 9, minute: 0)
        XCTAssertNil(sched.activityReminder(for: log))
    }

    func testSyncActivitySchedulesThenCancelOnRemoval() async throws {
        let fake = FakeNotificationScheduler()
        let sched = DueReminderScheduler(scheduler: fake, calendar: calendar, hour: 9, minute: 0)
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let log = try activityStore.log(type: type, performedAt: Date(timeIntervalSince1970: 0), note: nil, intervalDays: 30)

        await sched.syncActivity(log)
        var pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending, [log.id])

        await sched.cancelActivity(log)
        pending = await fake.pendingIDs(kind: .activity)
        XCTAssertTrue(pending.isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/DueReminderSchedulerTests`
Expected: FAIL — `type 'ReminderKind' has no member 'activity'`.

- [ ] **Step 3: Add the `.activity` reminder kind**

In `ios/PetHomepage/Notifications/NotificationScheduling.swift`, add `case activity` to the `ReminderKind` enum:

```swift
enum ReminderKind: String {
    case medication
    case vaccination
    case vetCadence
    case activity
}
```

And add `.activity` to the `ReminderIdentifier.parse` kind loop:

```swift
        for kind in [ReminderKind.medication, .vaccination, .vetCadence, .activity] {
```

- [ ] **Step 4: Add the scheduler methods**

In `ios/PetHomepage/Notifications/DueReminderScheduler.swift`, add a `// MARK: - Activities` section before the final closing brace:

```swift
    // MARK: - Activities

    /// A one-shot reminder on the log's nextDueAt date, or nil if it has no due date.
    func activityReminder(for log: ActivityLog) -> PendingReminder? {
        guard let due = log.nextDueAt else { return nil }
        let name = log.activityType?.name ?? "Activity"
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: due)
        return PendingReminder(
            kind: .activity,
            entityID: log.id,
            title: "\(name) due",
            body: "Time for \(name.lowercased())",
            hour: hour,
            minute: minute,
            dateComponents: dateComponents
        )
    }

    /// Schedules the activity reminder if it has a due date, otherwise cancels it.
    func syncActivity(_ log: ActivityLog) async {
        if let reminder = activityReminder(for: log) {
            await scheduler.schedule(reminder)
        } else {
            await scheduler.cancel(kind: .activity, entityID: log.id)
        }
    }

    func cancelActivity(_ log: ActivityLog) async {
        await scheduler.cancel(kind: .activity, entityID: log.id)
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: same as Step 2.
Expected: PASS (existing vaccination/vet tests + 3 new activity tests).

- [ ] **Step 6: Commit**

```bash
git add ios/PetHomepage/Notifications/NotificationScheduling.swift ios/PetHomepage/Notifications/DueReminderScheduler.swift ios/PetHomepageTests/DueReminderSchedulerTests.swift
git commit -m "feat: add activity due reminders to DueReminderScheduler"
```

---

## Task 6: Camera capture in shared photo sections

**Files:**
- Create: `ios/PetHomepage/DesignSystem/ImageDownscaler.swift`, `ios/PetHomepage/DesignSystem/CameraPicker.swift`
- Modify: `ios/PetHomepage/DesignSystem/PendingPhotoSection.swift`, `ios/PetHomepage/DesignSystem/PhotoStripSection.swift`
- Modify: `ios/project.yml`
- Test: `ios/PetHomepageTests/ImageDownscalerTests.swift`

**Interfaces:**
- Produces:
  - `enum ImageDownscaler { static func scaledJPEG(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? }`
  - `struct CameraPicker: UIViewControllerRepresentable` with `var onCapture: (UIImage) -> Void`.
- This task is mostly UI/UIKit (build-verified). Only `ImageDownscaler` is unit-tested.

- [ ] **Step 1: Write the failing test** (the one unit-testable piece)

```swift
// ios/PetHomepageTests/ImageDownscalerTests.swift
import XCTest
import UIKit
@testable import PetHomepage

final class ImageDownscalerTests: XCTestCase {
    private func solidImage(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testProducesNonEmptyJPEGData() {
        let data = ImageDownscaler.scaledJPEG(from: solidImage(size: CGSize(width: 200, height: 200)))
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
        XCTAssertNotNil(UIImage(data: data!))
    }

    func testScalesDownLargeImage() {
        let data = ImageDownscaler.scaledJPEG(from: solidImage(size: CGSize(width: 4000, height: 4000)), maxDimension: 100)
        let result = UIImage(data: data!)!
        XCTAssertLessThanOrEqual(max(result.size.width, result.size.height), 200) // allow scale slack
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/ImageDownscalerTests`
Expected: FAIL — `cannot find 'ImageDownscaler' in scope`.

- [ ] **Step 3: Create `ImageDownscaler`** (the existing inline logic, extracted)

```swift
// ios/PetHomepage/DesignSystem/ImageDownscaler.swift
import UIKit

/// Shared downscale → JPEG step used by every photo picker path (library + camera), so the
/// behaviour is identical regardless of source.
enum ImageDownscaler {
    static func scaledJPEG(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        let scaled = image.preparingThumbnail(of: CGSize(width: maxDimension, height: maxDimension)) ?? image
        return scaled.jpegData(compressionQuality: quality)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (2 tests).

- [ ] **Step 5: Create `CameraPicker`**

```swift
// ios/PetHomepage/DesignSystem/CameraPicker.swift
import SwiftUI
import UIKit

/// SwiftUI wrapper over UIImagePickerController's camera source — SwiftUI's PhotosPicker is
/// library-only, so camera capture needs this. Present it as a `.fullScreenCover`/`.sheet`.
struct CameraPicker: UIViewControllerRepresentable {
    /// Whether the device actually has a camera (false on Simulator). Callers gate the button on this.
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
```

- [ ] **Step 6: Add the "Take photo" button + use `ImageDownscaler` in `PendingPhotoSection`**

In `ios/PetHomepage/DesignSystem/PendingPhotoSection.swift`: add a camera sheet state and button, and replace the inline downscale with `ImageDownscaler`. Add to the struct's state:

```swift
    @State private var showingCamera = false
```

Replace the `PhotosPicker { ... }` line's enclosing area so the `Section("Photos")` starts with both buttons:

```swift
        Section("Photos") {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                Label("Add photos", systemImage: "photo.on.rectangle")
            }
            if CameraPicker.isAvailable {
                Button { showingCamera = true } label: {
                    Label("Take photo", systemImage: "camera")
                }
            }
```

Add the camera sheet modifier next to `.onChange(of: pickerItems)`:

```swift
        .onChange(of: pickerItems) { _, items in load(items) }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in
                if let jpeg = ImageDownscaler.scaledJPEG(from: image) { onPick(jpeg) }
            }
            .ignoresSafeArea()
        }
```

And replace the body of `load(_:)`'s inner downscale lines:

```swift
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else { continue }
                if let jpeg = ImageDownscaler.scaledJPEG(from: ui) {
                    await MainActor.run { onPick(jpeg) }
                }
```

- [ ] **Step 7: Mirror the same changes in `PhotoStripSection`**

In `ios/PetHomepage/DesignSystem/PhotoStripSection.swift`: add `@State private var showingCamera = false`, add the identical "Take photo" button inside `Section("Photos")` after the `PhotosPicker`, add the camera `.sheet` (calling `onAdd(jpeg)` instead of `onPick`), and replace the inline downscale in `load(_:)` with `ImageDownscaler.scaledJPEG(from: ui)` calling `onAdd(jpeg)`. The camera sheet:

```swift
        .sheet(isPresented: $showingCamera) {
            CameraPicker { image in
                if let jpeg = ImageDownscaler.scaledJPEG(from: image) {
                    onAdd(jpeg)
                    onReload()
                }
            }
            .ignoresSafeArea()
        }
```

- [ ] **Step 8: Broaden the camera usage string**

In `ios/project.yml`, change the existing line:

```yaml
        INFOPLIST_KEY_NSCameraUsageDescription: "Scan the pairing QR code shown on your dashboard."
```

to:

```yaml
        INFOPLIST_KEY_NSCameraUsageDescription: "Take photos to attach to your pet's records and scan the pairing QR code shown on your dashboard."
```

- [ ] **Step 9: Build to verify the app compiles, then run the downscaler test**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.
Then: `xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/ImageDownscalerTests`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add ios/PetHomepage/DesignSystem/ImageDownscaler.swift ios/PetHomepage/DesignSystem/CameraPicker.swift ios/PetHomepage/DesignSystem/PendingPhotoSection.swift ios/PetHomepage/DesignSystem/PhotoStripSection.swift ios/project.yml ios/PetHomepageTests/ImageDownscalerTests.swift
git commit -m "feat: camera capture in shared photo sections"
```

---

## Task 7: Timeline integration

**Files:**
- Modify: `ios/PetHomepage/Features/Timeline/TimelineViewModel.swift`
- Modify: `ios/PetHomepage/Features/Timeline/TimelineView.swift` (TimelineServices field + VM init arg only; editor/addEditor wiring lands in Task 9)
- Test: `ios/PetHomepageTests/TimelineViewModelTests.swift` (add cases)

**Interfaces:**
- Consumes: `ActivityStore`, `ActivityLog`.
- Produces: `TimelineKind.activity`; `TimelineReference.activity(ActivityLog)`; `TimelineItem.init(activity:)`; `TimelineViewModel` gains an `activityStore` init parameter and includes activity logs in `load()`; `delete` handles `.activity`.

- [ ] **Step 1: Write the failing tests** (append to `TimelineViewModelTests`)

First inspect the existing `TimelineViewModelTests.swift` setUp to match how it builds stores. Add a test that constructs the VM WITH the new `activityStore:` argument and asserts activity logs appear and flow into `dueSoon`:

```swift
    func testActivityLogsAppearInStreamAndDueSoon() throws {
        // Uses the same in-memory context + petStore the other tests build.
        let context = PersistenceController(inMemory: true).container.viewContext
        let petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        let activityStore = ActivityStore(context: context, petStore: petStore)
        let type = try activityStore.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 7)
        _ = try activityStore.log(type: type, performedAt: Date(), note: nil, intervalDays: 7)

        let vm = TimelineViewModel(
            vaccinationStore: VaccinationStore(context: context, petStore: petStore),
            vetVisitStore: VetVisitStore(context: context, petStore: petStore),
            medicationStore: MedicationStore(context: context, petStore: petStore),
            healthMarkerStore: HealthMarkerStore(context: context, petStore: petStore),
            symptomEpisodeStore: SymptomEpisodeStore(context: context, petStore: petStore),
            activityStore: activityStore
        )
        vm.load()

        XCTAssertTrue(vm.items.contains { $0.kind == .activity && $0.title == "Bath" })
        XCTAssertTrue(vm.dueSoon(within: 30).contains { $0.kind == .activity })
    }
```

(If the existing test file already has a shared `setUp` building the VM, add the `activityStore:` argument there too so the file compiles — see Step 4.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/TimelineViewModelTests`
Expected: FAIL — `extra argument 'activityStore' in call` / `type 'TimelineKind' has no member 'activity'`.

- [ ] **Step 3: Extend `TimelineViewModel`**

In `ios/PetHomepage/Features/Timeline/TimelineViewModel.swift`:

Add `case activity` to `TimelineKind`:

```swift
    case vaccine, vet, medication, marker, symptom, activity
```

Add its `label` and `systemImage` arms:

```swift
        case .activity: "Activities"
```
```swift
        case .activity: "shower"
```

Add to `TimelineReference`:

```swift
    case activity(ActivityLog)
```

Add the store property + init parameter:

```swift
    private let symptomEpisodeStore: SymptomEpisodeStore
    private let activityStore: ActivityStore
```
```swift
    init(vaccinationStore: VaccinationStore,
         vetVisitStore: VetVisitStore,
         medicationStore: MedicationStore,
         healthMarkerStore: HealthMarkerStore,
         symptomEpisodeStore: SymptomEpisodeStore,
         activityStore: ActivityStore) {
        self.vaccinationStore = vaccinationStore
        self.vetVisitStore = vetVisitStore
        self.medicationStore = medicationStore
        self.healthMarkerStore = healthMarkerStore
        self.symptomEpisodeStore = symptomEpisodeStore
        self.activityStore = activityStore
    }
```

Add to `load()` (after the symptom line):

```swift
            out += try activityStore.logs().map(TimelineItem.init(activity:))
```

Add the `.activity` arm to `delete(_:using:)`:

```swift
        case .activity(let log):
            await services.dueScheduler.cancelActivity(log)
            try? services.activityStore.delete(log)
```

Add the `TimelineItem` initializer at the bottom (in the `extension TimelineItem`):

```swift
    init(activity log: ActivityLog) {
        self.init(
            id: "activity:\(log.id.uuidString)",
            kind: .activity,
            date: log.performedAt,
            title: log.activityType?.name ?? "Activity",
            subtitle: (log.note?.isEmpty == false) ? log.note : log.activityType?.category.displayName,
            nextDue: log.nextDueAt,
            reference: .activity(log)
        )
    }
```

- [ ] **Step 4: Add the `activityStore` argument to the two existing `TimelineViewModel(...)` call sites so the project compiles**

In `ios/PetHomepage/Features/Timeline/TimelineView.swift` `init(services:)`, add `activityStore: services.activityStore` to the `TimelineViewModel(...)` call. In `ios/PetHomepage/Features/PetProfile/PetProfileView.swift` `refresh()`, add `activityStore: s.activityStore`. (Both require the `TimelineServices.activityStore` field — add it now: in `TimelineView.swift`'s `TimelineServices` struct add `let activityStore: ActivityStore`. The `ContentView` construction of `TimelineServices` is updated in Task 9; until then the project won't build, so do Step 4's compile check together with Task 9, OR temporarily add `activityStore` to `TimelineServices` and `ContentView` now.)

> To keep this task independently testable, ALSO make the minimal `ContentView` change here: build `let activityStore = ActivityStore(context: context, petStore: petStore)` and pass `activityStore: activityStore` into `TimelineServices(...)`. (Full seeding/menu wiring is Task 9.)

- [ ] **Step 5: Run tests to verify they pass**

Run: same as Step 2, then also build:
`xcodebuild build -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: tests PASS and BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add ios/PetHomepage/Features/Timeline/ ios/PetHomepage/Features/PetProfile/PetProfileView.swift ios/PetHomepage/App/ContentView.swift ios/PetHomepageTests/TimelineViewModelTests.swift
git commit -m "feat: surface activity logs in the unified Timeline"
```

---

## Task 8: ActivityLogEditViewModel (logic + reminder sync)

**Files:**
- Create: `ios/PetHomepage/Features/Activities/ActivityLogEditViewModel.swift`
- Test: `ios/PetHomepageTests/ActivityLogEditViewModelTests.swift`

**Interfaces:**
- Consumes: `ActivityStore`, `DueReminderScheduler`, `ActivityType`, `ActivityLog`, `ActivityCategory`, `DiaryStore` (for photo attach — see note).
- Produces (`@Observable final class ActivityLogEditViewModel`):
  - fields: `availableTypes: [ActivityType]`, `selectedType: ActivityType?`, `performedAt: Date`, `note: String`, `hasCadence: Bool`, `intervalDays: Int`, `pendingPhotos: [Data]`, `existingPhotos: [Photo]`, and new-type fields `newTypeName: String`, `newTypeCategory: ActivityCategory`.
  - `init(store: ActivityStore, dueScheduler: DueReminderScheduler, diaryStore: DiaryStore, editing: ActivityLog?)`
  - `var isValid: Bool`
  - `func selectType(_:)` (sets `intervalDays`/`hasCadence` from the type's default)
  - `func createAndSelectNewType() throws` (creates a type from `newTypeName`/`newTypeCategory`, selects it)
  - `func addPickedPhoto(_:)`, `removePending(at:)`, `deleteExisting(_:)`
  - `func save() async throws` — create/update log, attach photos, then cancel the prior latest-of-type reminder (create path) and `syncActivity(newLog)`.

> **Photo attach note:** photos attach to records through `DiaryStore` helpers in this codebase (e.g. `diaryStore.addPhoto(toVaccination:imageData:)`). Add a sibling `addPhoto(toActivityLog:imageData:)` to `DiaryStore` as Step 0 of this task (grep `func addPhoto(to` in `ios/PetHomepage/Stores/DiaryStore.swift` to copy the exact pattern, setting `photo.activityLog = log`). If `DiaryStore` is not the right home, attach inline by creating a `Photo` in the context and setting `.activityLog`.

- [ ] **Step 0: Add the photo-attach helper to `DiaryStore`**

Grep `ios/PetHomepage/Stores/DiaryStore.swift` for `func addPhoto(toVaccination`. Copy that method to a new `addPhoto(toActivityLog log: ActivityLog, imageData: Data)` that sets `photo.activityLog = log` (and `photo.pet`/`createdAt`/`id` the same way the sibling does). Keep `deletePhoto(_:)` reused as-is.

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/ActivityLogEditViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

@MainActor
final class ActivityLogEditViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!
    private var petStore: PetStore!
    private var store: ActivityStore!
    private var diaryStore: DiaryStore!
    private var fake: FakeNotificationScheduler!
    private var sched: DueReminderScheduler!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
        petStore = PetStore(context: context)
        try petStore.createPet(name: "Sandy", species: "dog")
        store = ActivityStore(context: context, petStore: petStore)
        diaryStore = DiaryStore(context: context, petStore: petStore)
        fake = FakeNotificationScheduler()
        sched = DueReminderScheduler(scheduler: fake, calendar: Calendar(identifier: .gregorian), hour: 9, minute: 0)
    }

    func testSelectingTypeAdoptsItsDefaultCadence() throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let vm = ActivityLogEditViewModel(store: store, dueScheduler: sched, diaryStore: diaryStore, editing: nil)
        vm.selectType(type)
        XCTAssertTrue(vm.hasCadence)
        XCTAssertEqual(vm.intervalDays, 30)
        XCTAssertTrue(vm.isValid)
    }

    func testCreateNewTypeFromInlineFields() throws {
        let vm = ActivityLogEditViewModel(store: store, dueScheduler: sched, diaryStore: diaryStore, editing: nil)
        vm.newTypeName = "Ear cleaning"
        vm.newTypeCategory = .care
        try vm.createAndSelectNewType()
        XCTAssertEqual(vm.selectedType?.name, "Ear cleaning")
        XCTAssertTrue(try store.types().contains { $0.name == "Ear cleaning" })
    }

    func testSaveLogsAndSchedulesReminder() async throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        let vm = ActivityLogEditViewModel(store: store, dueScheduler: sched, diaryStore: diaryStore, editing: nil)
        vm.selectType(type)
        vm.performedAt = Date(timeIntervalSince1970: 0)
        try await vm.save()

        XCTAssertEqual(try store.logs().count, 1)
        let pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending.count, 1)
    }

    func testSaveCancelsPriorLatestReminderOfSameType() async throws {
        let type = try store.createType(name: "Bath", category: .care, iconName: "shower", defaultIntervalDays: 30)
        // First log + its reminder.
        let vm1 = ActivityLogEditViewModel(store: store, dueScheduler: sched, diaryStore: diaryStore, editing: nil)
        vm1.selectType(type)
        vm1.performedAt = Date(timeIntervalSince1970: 0)
        try await vm1.save()
        let firstID = try store.latestLog(of: type)!.id

        // Second log should cancel the first's reminder and schedule its own.
        let vm2 = ActivityLogEditViewModel(store: store, dueScheduler: sched, diaryStore: diaryStore, editing: nil)
        vm2.selectType(type)
        vm2.performedAt = Date(timeIntervalSince1970: 10_000)
        try await vm2.save()

        let pending = await fake.pendingIDs(kind: .activity)
        XCTAssertEqual(pending.count, 1, "only the latest log should have a pending reminder")
        XCTAssertFalse(pending.contains(firstID))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ios && xcodegen generate && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:PetHomepageTests/ActivityLogEditViewModelTests`
Expected: FAIL — `cannot find 'ActivityLogEditViewModel' in scope`.

- [ ] **Step 3: Write the ViewModel**

```swift
// ios/PetHomepage/Features/Activities/ActivityLogEditViewModel.swift
import Foundation
import Observation

@Observable
final class ActivityLogEditViewModel {
    var availableTypes: [ActivityType] = []
    var selectedType: ActivityType?
    var performedAt: Date = Date()
    var note: String = ""
    var hasCadence: Bool = false
    var intervalDays: Int = 0
    var pendingPhotos: [Data] = []
    var existingPhotos: [Photo] = []

    // Inline "+ New activity" fields.
    var newTypeName: String = ""
    var newTypeCategory: ActivityCategory = .other

    private let store: ActivityStore
    private let dueScheduler: DueReminderScheduler
    private let diaryStore: DiaryStore
    private let editing: ActivityLog?

    init(store: ActivityStore, dueScheduler: DueReminderScheduler, diaryStore: DiaryStore, editing: ActivityLog?) {
        self.store = store
        self.dueScheduler = dueScheduler
        self.diaryStore = diaryStore
        self.editing = editing
        availableTypes = (try? store.types()) ?? []
        if let log = editing {
            selectedType = log.activityType
            performedAt = log.performedAt
            note = log.note ?? ""
            intervalDays = Int(log.intervalDays)
            hasCadence = log.intervalDays > 0
            existingPhotos = log.photoArray
        } else if let first = availableTypes.first {
            selectType(first)
        }
    }

    var isValid: Bool { selectedType != nil }

    /// Adopt a type and pre-fill cadence from its default.
    func selectType(_ type: ActivityType) {
        selectedType = type
        intervalDays = Int(type.defaultIntervalDays)
        hasCadence = type.defaultIntervalDays > 0
    }

    /// Create a type from the inline fields and select it.
    func createAndSelectNewType() throws {
        let name = newTypeName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let type = try store.createType(name: name, category: newTypeCategory, iconName: newTypeCategory.systemImage, defaultIntervalDays: 0)
        availableTypes = (try? store.types()) ?? []
        newTypeName = ""
        newTypeCategory = .other
        selectType(type)
    }

    func addPickedPhoto(_ data: Data) { pendingPhotos.append(data) }
    func removePending(at index: Int) {
        if pendingPhotos.indices.contains(index) { pendingPhotos.remove(at: index) }
    }
    func deleteExisting(_ photo: Photo) {
        try? diaryStore.deletePhoto(photo)
        existingPhotos.removeAll { $0 == photo }
    }

    func save() async throws {
        guard let type = selectedType else { return }
        let interval = hasCadence ? intervalDays : 0
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let noteOrNil = trimmedNote.isEmpty ? nil : trimmedNote

        // Capture the prior latest-of-type BEFORE logging, so we can cancel its reminder
        // (only the newest log of a type should hold a pending reminder).
        let priorLatest = editing == nil ? (try? store.latestLog(of: type)) : nil

        let log: ActivityLog
        if let existing = editing {
            existing.performedAt = performedAt
            existing.note = noteOrNil
            existing.intervalDays = Int64(interval)
            existing.nextDueAt = interval > 0 ? Calendar.current.date(byAdding: .day, value: interval, to: performedAt) : nil
            existing.activityType = type
            try? existing.managedObjectContext?.save()
            log = existing
        } else {
            log = try store.log(type: type, performedAt: performedAt, note: noteOrNil, intervalDays: interval)
        }

        for data in pendingPhotos {
            try? diaryStore.addPhoto(toActivityLog: log, imageData: data)
        }

        if let prior = priorLatest, prior.id != log.id {
            await dueScheduler.cancelActivity(prior)
        }
        await dueScheduler.syncActivity(log)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: same as Step 2.
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add ios/PetHomepage/Features/Activities/ActivityLogEditViewModel.swift ios/PetHomepage/Stores/DiaryStore.swift ios/PetHomepageTests/ActivityLogEditViewModelTests.swift
git commit -m "feat: ActivityLogEditViewModel with cadence + reminder sync"
```

---

## Task 9: UI — log sheet, type management, and wiring

**Files:**
- Create: `ios/PetHomepage/Features/Activities/ActivityLogEditView.swift`, `ActivityTypesView.swift`, `ActivityTypesViewModel.swift`
- Modify: `ios/PetHomepage/Features/Timeline/TimelineView.swift`, `ios/PetHomepage/App/ContentView.swift`, `ios/PetHomepage/Features/Settings/SettingsView.swift`

**Interfaces:**
- Consumes everything from Tasks 1–8.
- This task is SwiftUI views + composition wiring — verified by BUILD SUCCEEDED + a manual smoke run (no new unit tests; the logic is already covered by Task 8).

- [ ] **Step 1: Create `ActivityLogEditView`**

```swift
// ios/PetHomepage/Features/Activities/ActivityLogEditView.swift
import SwiftUI

struct ActivityLogEditView: View {
    @State private var model: ActivityLogEditViewModel
    @State private var addingNewType = false
    @Environment(\.dismiss) private var dismiss

    init(store: ActivityStore, dueScheduler: DueReminderScheduler, diaryStore: DiaryStore, editing: ActivityLog?) {
        _model = State(initialValue: ActivityLogEditViewModel(store: store, dueScheduler: dueScheduler,
                                                              diaryStore: diaryStore, editing: editing))
    }

    var body: some View {
        BrandFormSheet(
            title: "Activity",
            systemImage: "shower",
            confirmDisabled: !model.isValid,
            onCancel: { dismiss() },
            onConfirm: { Task { try? await model.save(); dismiss() } }
        ) {
            Section("Activity") {
                Picker("Type", selection: Binding(
                    get: { model.selectedType },
                    set: { if let t = $0 { model.selectType(t) } }
                )) {
                    ForEach(ActivityCategory.allCases) { category in
                        let typesInCategory = model.availableTypes.filter { $0.category == category }
                        if !typesInCategory.isEmpty {
                            Section(category.displayName) {
                                ForEach(typesInCategory) { type in
                                    Label(type.name, systemImage: type.iconName)
                                        .tag(ActivityType?.some(type))
                                }
                            }
                        }
                    }
                }
                Button { addingNewType = true } label: {
                    Label("New activity", systemImage: "plus.circle")
                }
            }
            Section("When") {
                DatePicker("Performed", selection: $model.performedAt, displayedComponents: .date)
                TextField("Note", text: $model.note)
            }
            Section("Repeat") {
                Toggle("Remind me again", isOn: $model.hasCadence)
                if model.hasCadence {
                    Stepper("Every \(model.intervalDays) days", value: $model.intervalDays, in: 1...365)
                }
            }
            PendingPhotoSection(
                existing: model.existingPhotos,
                pending: model.pendingPhotos,
                onPick: { model.addPickedPhoto($0) },
                onDeleteExisting: { model.deleteExisting($0) },
                onRemovePending: { model.removePending(at: $0) }
            )
        }
        .sheet(isPresented: $addingNewType) {
            newTypeSheet
        }
    }

    private var newTypeSheet: some View {
        BrandFormSheet(
            title: "New activity",
            systemImage: "plus.circle",
            confirmDisabled: model.newTypeName.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: { addingNewType = false },
            onConfirm: { try? model.createAndSelectNewType(); addingNewType = false }
        ) {
            Section("Details") {
                TextField("Name", text: $model.newTypeName)
                Picker("Category", selection: $model.newTypeCategory) {
                    ForEach(ActivityCategory.allCases) { Text($0.displayName).tag($0) }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Create `ActivityTypesViewModel`**

```swift
// ios/PetHomepage/Features/Activities/ActivityTypesViewModel.swift
import Foundation
import Observation

@Observable
final class ActivityTypesViewModel {
    var types: [ActivityType] = []
    private let store: ActivityStore

    init(store: ActivityStore) {
        self.store = store
        reload()
    }

    func reload() { types = (try? store.types(includeArchived: false)) ?? [] }

    func archive(_ type: ActivityType) {
        try? store.archiveType(type)
        reload()
    }

    func updateInterval(_ type: ActivityType, days: Int) {
        try? store.updateType(type, name: type.name, category: type.category, iconName: type.iconName, defaultIntervalDays: days)
        reload()
    }
}
```

- [ ] **Step 3: Create `ActivityTypesView`**

```swift
// ios/PetHomepage/Features/Activities/ActivityTypesView.swift
import SwiftUI

struct ActivityTypesView: View {
    @State private var model: ActivityTypesViewModel

    init(store: ActivityStore) {
        _model = State(initialValue: ActivityTypesViewModel(store: store))
    }

    var body: some View {
        List {
            ForEach(ActivityCategory.allCases) { category in
                let typesInCategory = model.types.filter { $0.category == category }
                if !typesInCategory.isEmpty {
                    Section(category.displayName) {
                        ForEach(typesInCategory) { type in
                            HStack {
                                Label(type.name, systemImage: type.iconName)
                                Spacer()
                                Text(type.defaultIntervalDays > 0 ? "every \(type.defaultIntervalDays)d" : "no repeat")
                                    .font(.caption).foregroundStyle(Theme.inkSoft)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { model.archive(type) } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Activity types")
        .brandSheet()
        .onAppear { model.reload() }
    }
}
```

- [ ] **Step 4: Wire the log sheet into `TimelineView`**

In `ios/PetHomepage/Features/Timeline/TimelineView.swift`:
- Add to the add-menu (`addButton`'s `Menu`):
  ```swift
  Button { addKind = .activity } label: { Label("Activity", systemImage: "shower") }
  ```
- Add the `.activity` arm to `addEditor(for:)`:
  ```swift
  case .activity:
      ActivityLogEditView(store: services.activityStore, dueScheduler: services.dueScheduler,
                          diaryStore: services.diaryStore, editing: nil)
  ```
- Add the `.activity` arm to `editor(for:)`:
  ```swift
  case .activity(let log):
      ActivityLogEditView(store: services.activityStore, dueScheduler: services.dueScheduler,
                          diaryStore: services.diaryStore, editing: log)
  ```
- Add the `.activity` arm to `tint(_:)`:
  ```swift
  case .activity: .cyan
  ```

- [ ] **Step 5: Seed defaults + confirm `ActivityStore` wiring in `ContentView`**

In `ios/PetHomepage/App/ContentView.swift`, confirm `let activityStore = ActivityStore(context: context, petStore: petStore)` exists (added in Task 7) and is passed into `TimelineServices`. Add a one-time seed on the root view. Attach to the `TabView`:

```swift
        .task { try? activityStore.seedDefaultsIfNeeded() }
```

(`.task` runs once when the view appears; `seedDefaultsIfNeeded` is idempotent + dedupes, so this is safe.)

- [ ] **Step 6: Add the "Manage activity types" entry to Settings**

In `ios/PetHomepage/Features/Settings/SettingsView.swift`, the view needs access to the `ActivityStore`. Grep how `SettingsView` is built in `ContentView` (it's driven by `SettingsViewModel`). Add an `activityStore: ActivityStore` parameter to `SettingsView`'s init (pass it from wherever `SettingsView` is presented — `PetProfileView`/`SettingsViewModel` path), and add a navigation row:

```swift
            Section("Activities") {
                NavigationLink {
                    ActivityTypesView(store: activityStore)
                } label: {
                    Label("Manage activity types", systemImage: "checklist")
                }
            }
```

If threading `activityStore` into `SettingsView` is invasive, the acceptable alternative is to add the "Manage activity types" `NavigationLink` to the Timeline screen's toolbar instead (it already holds `services.activityStore`). Pick whichever requires the smaller diff; document the choice in the commit message.

- [ ] **Step 7: Build and smoke-test**

Run: `cd ios && xcodegen generate && xcodebuild build -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: BUILD SUCCEEDED.
Then launch in the simulator and verify: Timeline "+" → Activity → the type picker shows seeded types grouped by category → log a Bath with a photo (library; camera is simulator-unavailable) → it appears in the Timeline and (with cadence on) under Home "Due soon" → Settings shows "Manage activity types" and archive works.

- [ ] **Step 8: Run the full test suite**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all tests PASS (existing + new).

- [ ] **Step 9: Commit**

```bash
git add ios/PetHomepage/Features/Activities/ ios/PetHomepage/Features/Timeline/TimelineView.swift ios/PetHomepage/App/ContentView.swift ios/PetHomepage/Features/Settings/SettingsView.swift
git commit -m "feat: activity log sheet, type management, and Timeline/Settings wiring"
```

---

## Self-Review

**Spec coverage:**
- Two entities + `Photo.activityLog` → Task 2. ✓
- `ActivityCategory` fixed enum → Task 1. ✓
- `ActivityStore` (type CRUD, log, queries, latest-of-type) → Task 3. ✓
- Seeding (zero-setup, idempotent, dedupe-by-name, no-pet no-op, CloudKit note) → Task 4. ✓
- Reminders (`ReminderKind.activity`, parse loop, `activityReminder`/`syncActivity`/`cancelActivity`) → Task 5. ✓
- Camera capture (CameraPicker, shared downscaler, both sections, availability gate, usage string) → Task 6. ✓
- Timeline (`.activity` kind/reference/init/`load`/`delete`/`dueSoon`) → Task 7. ✓
- Log/Edit sheet with category-grouped picker, inline new-type, cadence, photos, reminder sync → Tasks 8 + 9. ✓
- Type management (rename via cadence/archive; sectioned by category) → Task 9 (`ActivityTypesView`). Note: rename UI is minimal (archive + interval shown); full rename/icon edit can be a fast follow — flagged below.
- "Due soon = latest occurrence per type" → enforced by cadence-on-occurrence + cancel-prior-latest in Task 8. ✓
- Non-goal (no mirror changes) → respected; `SnapshotBuilder` untouched. ✓

**Known minor gap (intentional):** `ActivityTypesView` in Task 9 supports archive + shows cadence but does not yet expose inline rename / icon change / cadence edit controls (only `updateInterval` exists on the VM). The spec asked for rename/change-cadence/change-icon. To fully satisfy it, Task 9 Step 2-3 should grow an edit sheet for a type. RECOMMENDATION: keep v1 as archive + a follow-up task for the type-edit sheet, OR expand Task 9 with an `ActivityTypeEditView`. Decide with the user before executing Task 9.

**Placeholder scan:** No TBD/TODO; every code step has complete code. The only deferred specifics are SF Symbol verification (global constraint) and the Settings-vs-Timeline placement choice in Task 9 Step 6 (explicit, with a default).

**Type consistency:** `ActivityStore.log(type:performedAt:note:intervalDays:)`, `latestLog(of:)`, `types(includeArchived:)`, `createType(name:category:iconName:defaultIntervalDays:)` are used identically across Tasks 3–9. `DueReminderScheduler.syncActivity/cancelActivity/activityReminder` and `ReminderKind.activity` consistent across Tasks 5, 7, 8. `TimelineViewModel(... activityStore:)` matches the call sites updated in Task 7. `ImageDownscaler.scaledJPEG(from:)` consistent across Task 6.
