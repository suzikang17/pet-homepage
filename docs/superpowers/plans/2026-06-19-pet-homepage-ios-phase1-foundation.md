# pet-homepage iOS — Phase 1 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the iOS app shell with an offline-first Core Data + CloudKit store, a working single-pet profile, and the iCloud Drive document plumbing later phases build on.

**Architecture:** A SwiftUI iOS app whose data layer is `NSPersistentCloudKitContainer` (offline-first, auto-syncs to the user's private iCloud). Data access goes through thin store classes (`PetStore`, `DocumentStore`) that take an injected `NSManagedObjectContext` / base `URL`, so unit tests run against an in-memory store and a temp directory — no CloudKit or device required to test. SwiftUI views stay thin over `@Observable` view models.

**Tech Stack:** Swift 5.9+, SwiftUI, Core Data (`NSPersistentCloudKitContainer`), XCTest, Xcode 15+, iOS 17+.

## Global Constraints

- Platform: **iOS 17+**, **SwiftUI**, **Swift 5.9+**, **Xcode 15+** (copied as project floor).
- Data layer: **Core Data via `NSPersistentCloudKitContainer`**; CloudKit container identifier `iCloud.pet.homepage`.
- **Single pet** in v1 — stores expose a `currentPet()` singleton accessor, not a list.
- NSManagedObject codegen is **Manual/None** — subclasses are hand-written (so their exact code lives in this plan).
- **Offline-first:** the local store is the source of truth; CloudKit sync is automatic and never blocks the UI.
- CloudKit + device builds require **Apple Developer Program** membership. **Unit tests must not depend on CloudKit** — they use `PersistenceController(inMemory: true)` and temp directories.
- All test/build runs use the simulator: `-destination 'platform=iOS Simulator,name=iPhone 15'`.

---

## File Structure

```
ios/
  PetHomepage.xcodeproj
  PetHomepage/
    App/
      PetHomepageApp.swift          # @main entry, injects PersistenceController
      ContentView.swift             # root; shows PetProfileView
    Persistence/
      PersistenceController.swift   # Core Data / CloudKit stack (+ in-memory variant)
      PetHomepage.xcdatamodeld      # Core Data model (Pet entity in Phase 1)
    Models/
      Pet.swift                     # hand-written NSManagedObject subclass
    Stores/
      PetStore.swift                # create/fetch/update the single pet
      DocumentStore.swift           # iCloud Drive (ubiquity container) file I/O
    Features/
      PetProfile/
        PetProfileViewModel.swift   # @Observable, testable
        PetProfileView.swift        # thin SwiftUI form
  PetHomepageTests/
    PetStoreTests.swift
    DocumentStoreTests.swift
    PetProfileViewModelTests.swift
```

---

### Task 1: Project scaffold + Core Data/CloudKit stack

**Files:**
- Create: `ios/PetHomepage.xcodeproj` (via Xcode, see steps)
- Create: `ios/PetHomepage/App/PetHomepageApp.swift`
- Create: `ios/PetHomepage/App/ContentView.swift`
- Create: `ios/PetHomepage/Persistence/PersistenceController.swift`
- Create: `ios/PetHomepage/Persistence/PetHomepage.xcdatamodeld` (empty model for now)
- Test: `ios/PetHomepageTests/PersistenceControllerTests.swift`

**Interfaces:**
- Produces: `struct PersistenceController { init(inMemory: Bool = false); let container: NSPersistentContainer; static let shared: PersistenceController }`. `container.viewContext` is an `NSManagedObjectContext`.

- [ ] **Step 1: Create the Xcode project**

In Xcode: File → New → Project → iOS → App. Product Name `PetHomepage`, Interface **SwiftUI**, Language **Swift**, Storage **None** (we add Core Data by hand), include a Unit Testing bundle (`PetHomepageTests`). Save into `ios/`. Set the iOS Deployment Target to **17.0**.

- [ ] **Step 2: Add the (empty) Core Data model**

File → New → File → Core Data → Data Model, name it `PetHomepage.xcdatamodeld`, save under `PetHomepage/Persistence/`. Leave it with no entities for now (Task 3 adds `Pet`).

- [ ] **Step 3: Write the failing test for the stack**

```swift
// ios/PetHomepageTests/PersistenceControllerTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class PersistenceControllerTests: XCTestCase {
    func testInMemoryContainerLoadsAViewContext() {
        let controller = PersistenceController(inMemory: true)
        XCTAssertNotNil(controller.container.viewContext)
        XCTAssertTrue(controller.container.viewContext.automaticallyMergesChangesFromParent)
    }
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PetHomepageTests/PersistenceControllerTests`
Expected: FAIL — `cannot find 'PersistenceController' in scope`.

- [ ] **Step 5: Implement the stack**

```swift
// ios/PetHomepage/Persistence/PersistenceController.swift
import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        if inMemory {
            // Plain container with an in-memory store — no CloudKit in tests.
            container = NSPersistentContainer(name: "PetHomepage")
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            container = NSPersistentCloudKitContainer(name: "PetHomepage")
            if let description = container.persistentStoreDescriptions.first {
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                description.setOption(true as NSNumber,
                                      forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error \(error), \(error.userInfo)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
}
```

- [ ] **Step 6: Wire the app entry to inject the context**

```swift
// ios/PetHomepage/App/PetHomepageApp.swift
import SwiftUI

@main
struct PetHomepageApp: App {
    let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistence.container.viewContext)
        }
    }
}
```

```swift
// ios/PetHomepage/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("pet-homepage")
    }
}
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PetHomepageTests/PersistenceControllerTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add ios
git commit -m "feat(ios): scaffold app with Core Data + CloudKit persistence stack"
```

---

### Task 2: Enable iCloud capabilities (CloudKit + iCloud Drive)

**Files:**
- Modify: `ios/PetHomepage.xcodeproj` (Signing & Capabilities)
- Create: `ios/PetHomepage/PetHomepage.entitlements`

**Interfaces:**
- Produces: a CloudKit container `iCloud.pet.homepage` and an iCloud Documents container, available at runtime via `FileManager.url(forUbiquityContainerIdentifier:)`. No new Swift symbols.

> This task is device/account configuration; its deliverable is "release build compiles with iCloud entitlements." Unit tests stay on the in-memory store and are unaffected.

- [ ] **Step 1: Add the iCloud capability**

Project → target `PetHomepage` → Signing & Capabilities → **+ Capability → iCloud**. Check **CloudKit** and **iCloud Documents**. Under Containers, add `iCloud.pet.homepage`. Ensure a development team is selected (requires Apple Developer Program).

- [ ] **Step 2: Add Background Modes for remote notifications**

**+ Capability → Background Modes**, check **Remote notifications** (so CloudKit can push silent sync updates).

- [ ] **Step 3: Declare the iCloud Drive document container**

In `Info.plist`, add `NSUbiquitousContainers` so the Documents folder is user-visible in Files/Finder:

```xml
<key>NSUbiquitousContainers</key>
<dict>
  <key>iCloud.pet.homepage</key>
  <dict>
    <key>NSUbiquitousContainerIsDocumentScopePublic</key><true/>
    <key>NSUbiquitousContainerSupportedFolderLevels</key><string>Any</string>
    <key>NSUbiquitousContainerName</key><string>pet-homepage</string>
  </dict>
</dict>
```

- [ ] **Step 4: Verify the build compiles with entitlements**

Run: `cd ios && xcodebuild build -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: BUILD SUCCEEDED (no entitlement/signing errors).

- [ ] **Step 5: Commit**

```bash
git add ios
git commit -m "feat(ios): enable CloudKit and iCloud Drive capabilities"
```

---

### Task 3: Pet entity + PetStore

**Files:**
- Modify: `ios/PetHomepage/Persistence/PetHomepage.xcdatamodeld` (add `Pet` entity)
- Create: `ios/PetHomepage/Models/Pet.swift`
- Create: `ios/PetHomepage/Stores/PetStore.swift`
- Test: `ios/PetHomepageTests/PetStoreTests.swift`

**Interfaces:**
- Consumes: `PersistenceController(inMemory:).container.viewContext`.
- Produces:
  - `class Pet: NSManagedObject` with `id: UUID, name: String, species: String, breed: String?, dob: Date?, adoptionDate: Date?, photoData: Data?` and `static func fetchRequest() -> NSFetchRequest<Pet>`.
  - `final class PetStore { init(context: NSManagedObjectContext); @discardableResult func createPet(name: String, species: String) throws -> Pet; func currentPet() throws -> Pet?; func update(_ pet: Pet, name: String, species: String) throws }`.

- [ ] **Step 1: Define the `Pet` entity in the model**

In `PetHomepage.xcdatamodeld`, add entity **Pet**. Set **Codegen = Manual/None**. Attributes:
`id` (UUID, non-optional), `name` (String, non-optional), `species` (String, non-optional), `breed` (String, optional), `dob` (Date, optional), `adoptionDate` (Date, optional), `photoData` (Binary Data, optional, **Allows External Storage** on).

- [ ] **Step 2: Write the failing test**

```swift
// ios/PetHomepageTests/PetStoreTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class PetStoreTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
    }

    func testCreatePetIsRetrievableAsCurrentPet() throws {
        let store = PetStore(context: context)
        try store.createPet(name: "Sandy", species: "dog")

        let pet = try store.currentPet()
        XCTAssertEqual(pet?.name, "Sandy")
        XCTAssertEqual(pet?.species, "dog")
        XCTAssertNotNil(pet?.id)
    }

    func testUpdateChangesNameAndSpecies() throws {
        let store = PetStore(context: context)
        let pet = try store.createPet(name: "Sandy", species: "dog")

        try store.update(pet, name: "Sandy B.", species: "dog")

        XCTAssertEqual(try store.currentPet()?.name, "Sandy B.")
    }

    func testCurrentPetIsNilWhenNoneExists() throws {
        let store = PetStore(context: context)
        XCTAssertNil(try store.currentPet())
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PetHomepageTests/PetStoreTests`
Expected: FAIL — `cannot find 'Pet'` / `'PetStore' in scope`.

- [ ] **Step 4: Write the `Pet` subclass**

```swift
// ios/PetHomepage/Models/Pet.swift
import CoreData

@objc(Pet)
public class Pet: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var species: String
    @NSManaged public var breed: String?
    @NSManaged public var dob: Date?
    @NSManaged public var adoptionDate: Date?
    @NSManaged public var photoData: Data?
}

extension Pet {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<Pet> {
        NSFetchRequest<Pet>(entityName: "Pet")
    }
}
```

- [ ] **Step 5: Write the `PetStore`**

```swift
// ios/PetHomepage/Stores/PetStore.swift
import CoreData

final class PetStore {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    @discardableResult
    func createPet(name: String, species: String) throws -> Pet {
        let pet = Pet(context: context)
        pet.id = UUID()
        pet.name = name
        pet.species = species
        try context.save()
        return pet
    }

    /// v1 is single-pet: return the one pet if it exists.
    func currentPet() throws -> Pet? {
        let request = Pet.fetchRequest()
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func update(_ pet: Pet, name: String, species: String) throws {
        pet.name = name
        pet.species = species
        try context.save()
    }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PetHomepageTests/PetStoreTests`
Expected: PASS (all three tests).

- [ ] **Step 7: Commit**

```bash
git add ios
git commit -m "feat(ios): add Pet entity and single-pet PetStore"
```

---

### Task 4: PetProfile view model + screen

**Files:**
- Create: `ios/PetHomepage/Features/PetProfile/PetProfileViewModel.swift`
- Create: `ios/PetHomepage/Features/PetProfile/PetProfileView.swift`
- Modify: `ios/PetHomepage/App/ContentView.swift`
- Test: `ios/PetHomepageTests/PetProfileViewModelTests.swift`

**Interfaces:**
- Consumes: `PetStore`.
- Produces: `@Observable final class PetProfileViewModel { init(store: PetStore); var name: String; var species: String; var isSaved: Bool; func save() throws }`.

- [ ] **Step 1: Write the failing test**

```swift
// ios/PetHomepageTests/PetProfileViewModelTests.swift
import XCTest
import CoreData
@testable import PetHomepage

final class PetProfileViewModelTests: XCTestCase {
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        context = PersistenceController(inMemory: true).container.viewContext
    }

    func testSaveCreatesPetWhenNoneExists() throws {
        let store = PetStore(context: context)
        let vm = PetProfileViewModel(store: store)
        vm.name = "Sandy"
        vm.species = "dog"

        try vm.save()

        XCTAssertEqual(try store.currentPet()?.name, "Sandy")
        XCTAssertTrue(vm.isSaved)
    }

    func testInitLoadsExistingPet() throws {
        let store = PetStore(context: context)
        try store.createPet(name: "Max", species: "dog")

        let vm = PetProfileViewModel(store: store)

        XCTAssertEqual(vm.name, "Max")
    }

    func testSaveUpdatesExistingPet() throws {
        let store = PetStore(context: context)
        try store.createPet(name: "Max", species: "dog")
        let vm = PetProfileViewModel(store: store)
        vm.name = "Maximilian"

        try vm.save()

        XCTAssertEqual(try store.currentPet()?.name, "Maximilian")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PetHomepageTests/PetProfileViewModelTests`
Expected: FAIL — `cannot find 'PetProfileViewModel' in scope`.

- [ ] **Step 3: Implement the view model**

```swift
// ios/PetHomepage/Features/PetProfile/PetProfileViewModel.swift
import Foundation
import Observation

@Observable
final class PetProfileViewModel {
    var name: String = ""
    var species: String = "dog"
    var isSaved: Bool = false

    private let store: PetStore

    init(store: PetStore) {
        self.store = store
        if let pet = try? store.currentPet() {
            name = pet.name
            species = pet.species
            isSaved = true
        }
    }

    func save() throws {
        if let pet = try store.currentPet() {
            try store.update(pet, name: name, species: species)
        } else {
            try store.createPet(name: name, species: species)
        }
        isSaved = true
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PetHomepageTests/PetProfileViewModelTests`
Expected: PASS.

- [ ] **Step 5: Build the SwiftUI screen and mount it**

```swift
// ios/PetHomepage/Features/PetProfile/PetProfileView.swift
import SwiftUI

struct PetProfileView: View {
    @State private var model: PetProfileViewModel

    init(store: PetStore) {
        _model = State(initialValue: PetProfileViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pet") {
                    TextField("Name", text: $model.name)
                    Picker("Species", selection: $model.species) {
                        Text("Dog").tag("dog")
                        Text("Cat").tag("cat")
                        Text("Other").tag("other")
                    }
                }
                Section {
                    Button("Save") { try? model.save() }
                        .disabled(model.name.isEmpty)
                }
            }
            .navigationTitle("Profile")
        }
    }
}
```

```swift
// ios/PetHomepage/App/ContentView.swift
import SwiftUI

struct ContentView: View {
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        PetProfileView(store: PetStore(context: context))
    }
}
```

- [ ] **Step 6: Verify the full test suite and a clean build**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15'`
Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add ios
git commit -m "feat(ios): pet profile screen wired to PetStore"
```

---

### Task 5: DocumentStore (iCloud Drive plumbing)

**Files:**
- Create: `ios/PetHomepage/Stores/DocumentStore.swift`
- Test: `ios/PetHomepageTests/DocumentStoreTests.swift`

**Interfaces:**
- Produces: `final class DocumentStore { init(baseURL: URL, fileManager: FileManager = .default); static func iCloudDrive() -> DocumentStore?; @discardableResult func save(_ data: Data, named: String) throws -> URL; func read(named: String) throws -> Data; func fileURL(named: String) -> URL }`. Used by later phases to store record attachments (PDFs/photos) in the iCloud Drive container.

- [ ] **Step 1: Write the failing test (against a temp dir, not iCloud)**

```swift
// ios/PetHomepageTests/DocumentStoreTests.swift
import XCTest
@testable import PetHomepage

final class DocumentStoreTests: XCTestCase {
    private var baseURL: URL!

    override func setUpWithError() throws {
        baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: baseURL)
    }

    func testSaveThenReadRoundTrips() throws {
        let store = DocumentStore(baseURL: baseURL)
        let payload = Data("bloodwork".utf8)

        let url = try store.save(payload, named: "labs.pdf")

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try store.read(named: "labs.pdf"), payload)
    }

    func testSaveCreatesMissingBaseDirectory() throws {
        let store = DocumentStore(baseURL: baseURL) // baseURL does not exist yet
        XCTAssertNoThrow(try store.save(Data("x".utf8), named: "a.txt"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PetHomepageTests/DocumentStoreTests`
Expected: FAIL — `cannot find 'DocumentStore' in scope`.

- [ ] **Step 3: Implement DocumentStore**

```swift
// ios/PetHomepage/Stores/DocumentStore.swift
import Foundation

final class DocumentStore {
    private let baseURL: URL
    private let fileManager: FileManager

    init(baseURL: URL, fileManager: FileManager = .default) {
        self.baseURL = baseURL
        self.fileManager = fileManager
    }

    /// Production: the app's iCloud Drive Documents folder (visible in Files/Finder).
    /// Returns nil if the user is not signed into iCloud.
    static func iCloudDrive() -> DocumentStore? {
        guard let container = FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents") else { return nil }
        return DocumentStore(baseURL: container)
    }

    func fileURL(named name: String) -> URL {
        baseURL.appendingPathComponent(name)
    }

    @discardableResult
    func save(_ data: Data, named name: String) throws -> URL {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let url = fileURL(named: name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func read(named name: String) throws -> Data {
        try Data(contentsOf: fileURL(named: name))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd ios && xcodebuild test -scheme PetHomepage -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PetHomepageTests/DocumentStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios
git commit -m "feat(ios): add DocumentStore for iCloud Drive file I/O"
```

---

## Self-Review

**Spec coverage (Phase 1 / Foundation scope only):**
- Xcode SwiftUI project → Task 1 ✓
- Core Data + CloudKit offline-first stack → Task 1 (stack) + Task 2 (capabilities) ✓
- Single-pet profile (create/edit) → Tasks 3–4 ✓
- iCloud Drive plumbing → Task 2 (entitlement/Info.plist) + Task 5 (`DocumentStore`) ✓
- Notifications, meds, vaccinations, vet visits, markers, symptoms, AI endpoint, mirror/dashboard → **out of scope for Phase 1**, covered by later-phase plans.

**Placeholder scan:** No TBD/TODO; every code step shows full code; every run step shows an exact command + expected result.

**Type consistency:** `PetStore.update(_:name:species:)` is defined in Task 3 and called with the same signature in Task 4's view model. `currentPet()`/`createPet(name:species:)` names match across Tasks 3–4. `PersistenceController(inMemory:)` is used identically in every test setup. `DocumentStore.save(_:named:)`/`read(named:)`/`fileURL(named:)` are consistent within Task 5.

---

## Notes for later phases (not part of this plan)

- The `shared/` Zod schema → Swift model mirroring discipline kicks in at Phase 3 (when `/api/extract` and richer entities arrive).
- The opt-in Convex mirror and Next.js dashboard are Phase 5; nothing here should assume a server exists.
