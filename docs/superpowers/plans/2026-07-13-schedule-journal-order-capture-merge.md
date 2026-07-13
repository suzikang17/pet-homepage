# Schedule Journal Ordering + Capture Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Completed schedule slots sort to the top by done-time with muted styling; Capture moves into the Timeline + menu and the fake Capture tab is deleted.

**Architecture:** Ordering is a presentation concern in `ScheduleViewModel.load()` (never in `RoutineStore.slots(for:)`, which other consumers need in scheduled order). Capture flow stays owned by `ContentView`; `TimelineView` gets an `onCapture` closure.

**Tech Stack:** Swift/SwiftUI, XCTest; branch `schedule-polish`; CI (`iOS Tests`) is the compiler; merge to main triggers TestFlight.

## Global Constraints

- No local Xcode: push per task, verify via the `iOS Tests` workflow; merge only when the full branch is green.
- Keep remaining tab tags (0, 1, 3, 4) unchanged.
- Existing spec: docs/superpowers/specs/2026-07-13-schedule-journal-order-capture-merge-design.md

---

### Task 1: ViewModel ordering + tests

**Files:**
- Modify: `ios/PetHomepage/Features/Schedule/ScheduleViewModel.swift` (`load()`)
- Test: `ios/PetHomepageTests/ScheduleViewModelTests.swift` (append)

**Interfaces:**
- Produces: `slots` ordered done(by completion time asc) → open(scheduled) → skipped.

- [ ] **Step 1: Failing test**

```swift
func testDoneSlotsSortFirstByCompletionTimeThenOpenThenSkipped() throws {
    // Fixture has Breakfast 7:00 and Walk 8:00 (both open).
    let walk = try XCTUnwrap(model.slots.first { $0.task.name == "Walk" })
    model.checkOff(walk)
    XCTAssertEqual(model.slots.map(\.task.name), ["Walk", "Breakfast"])

    let breakfast = try XCTUnwrap(model.slots.first { $0.task.name == "Breakfast" })
    model.toggleSkip(breakfast)
    XCTAssertEqual(model.slots.map(\.task.name), ["Walk", "Breakfast"])
    XCTAssertTrue(try XCTUnwrap(model.slots.last).isSkipped)
}
```

- [ ] **Step 2: Implement in `load()`**

```swift
    func load() {
        do {
            let computed = try store.slots(for: day)
            // Journal ordering: what happened (by completion time) above what's
            // left (scheduled order), deliberately-skipped slots last.
            let done = computed.filter(\.isCompleted).sorted {
                ($0.completion?.performedAt ?? .distantPast)
                    < ($1.completion?.performedAt ?? .distantPast)
            }
            let open = computed.filter { !$0.isCompleted && !$0.isSkipped }
            let skipped = computed.filter { !$0.isCompleted && $0.isSkipped }
            slots = done + open + skipped
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }
```

- [ ] **Step 3: Commit + push, CI green**

### Task 2: Muted completed-row styling

**Files:**
- Modify: `ios/PetHomepage/Features/Schedule/ScheduleView.swift` (check button glyph/size/color; row opacity; title weight)

- [ ] Check control: completed → `checkmark.circle`, 20 pt `.medium`, `Theme.inkSoft.opacity(0.6)`; open → `circle`, 26 pt `.semibold`, `Theme.primary.opacity(0.45)`.
- [ ] Title: `.font(.body.weight(slot.isCompleted ? .regular : .semibold))`.
- [ ] Row container: `.opacity(slot.isCompleted ? 0.55 : 1)`.
- [ ] Commit + push, CI green (UI-only; tests still pass).

### Task 3: Capture into Timeline +, delete Capture tab

**Files:**
- Modify: `ios/PetHomepage/App/ContentView.swift` — extract the `onChange(of: selectedTab)` body into `private func startCapture()`; delete the `Color.clear` tab and the `onChange`; pass `onCapture: { startCapture() }` to `TimelineView`.
- Modify: `ios/PetHomepage/Features/Timeline/TimelineView.swift` — add `let onCapture: (() -> Void)?` (default nil) and a menu entry above "Scan a record":

```swift
Button { onCapture?() } label: { Label("Take photo", systemImage: "camera") }
Divider()
```

- Modify: any UI test navigating via the Capture tab → use the + menu entry (grep `"Capture"` under `ios/PetHomepageUITests`).

- [ ] Implement, commit + push, CI green.

### Task 4: Merge gate

- [ ] Branch diff self-review; `iOS Tests` green on final push.
- [ ] Merge `schedule-polish` → main (`--no-ff`), push, watch TestFlight green.
