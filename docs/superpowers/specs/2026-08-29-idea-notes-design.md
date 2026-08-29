# Idea Notes — design

**Date:** 2026-08-29
**Status:** approved, ready for implementation planning

## Problem

While dogfooding the iOS app, ideas for improving it surface constantly — but
there is nowhere to put them. They either get lost or land somewhere outside the
app and never make it back to a working session. The goal is to capture an idea
in a couple of seconds, from wherever you are in the app, and read the week's
accumulated ideas back when working on the code.

## Scope

A personal, single-user scratchpad. It is a development aid, not a product
feature — the pet's owner-facing record is untouched.

## Storage

### Model

```swift
struct Idea: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    let screen: String?   // tab the user was on when captured
}
```

### Interface

```swift
protocol IdeaStore {
    func ideas() throws -> [Idea]              // newest first
    func add(text: String, screen: String?) throws -> Idea
    func delete(_ idea: Idea) throws
    func markdownExport() throws -> String
}
```

The protocol is the load-bearing decision. The chosen path is "local file now,
Convex later": a future `ConvexIdeaStore` conforms to these same four methods and
no view code changes. Nothing in the UI may reach past this interface.

### Implementation

`FileIdeaStore` persists a single JSON array to `ideas.json` in the app's
Documents directory, written atomically — the same file-handling shape as the
existing `DocumentStore`.

Explicitly **not** Core Data. A new Core Data entity would require the
CloudKit dev-schema push from an iCloud-signed-in simulator on a Mac, followed by
console promotion. That cost buys nothing here: the notes are single-device and
single-user, and CloudKit would not carry them to the development machine anyway.

Explicitly **not** iCloud Drive. `DocumentStore.iCloudDrive()` exists and would
make the file visible in Files.app, but it returns nil when the user is not
signed into iCloud, and its temp-directory fallback risks silent data loss for
content that is only ever stored in one place. The share export already covers
getting the notes out.

A corrupt or unreadable `ideas.json` returns an empty list rather than throwing
or crashing. Losing a scratchpad is acceptable; a launch-blocking crash in the
app being dogfooded is not.

## Capture

### Shake gesture

Primary entry point, available from every screen. Shaking presents the idea sheet
over the current view, so the user's place in whatever they were testing is
preserved.

SwiftUI has no shake modifier. The implementation is a
`UIViewControllerRepresentable` wrapping a `UIViewController` that returns
`canBecomeFirstResponder == true` and implements
`motionEnded(_:with:)`, checking for `.motionShake`. It attaches as a
`.background()` on `ContentView`.

The commonly-copied alternative — overriding `motionEnded` in a `UIWindow`
extension — must not be used. Overriding a method in an extension is undefined
behavior in Swift; it happens to work today and is not a foundation to build on.

**Known conflict:** shake is also iOS's shake-to-undo gesture. With a keyboard up
and a text field focused, the system undo alert may appear instead of the idea
sheet. This is accepted rather than mitigated — shaking mid-typing is not a real
workflow, and suppressing system undo app-wide costs more than the conflict does.

### Settings entry

Secondary entry point, so the feature is discoverable and reachable when the
gesture does not fire. A `NavigationLink` in `SettingsView`, following the
existing `BrandCard` + `BrandCardTitle` pattern used by the "Walk detection"
card, opening the same idea list view.

## The view — `IdeaListView`

One view serves both entry points: the shake gesture presents it in a sheet, the
Settings `NavigationLink` pushes it onto the settings stack. It therefore must not
assume it is presented modally — no hardcoded dismiss button, no assumption about
owning a `NavigationStack`. The shake path wraps it in a `NavigationStack` and
supplies the close affordance; the Settings path relies on the stack already there.

- Autofocused text field at the top; submit on return adds the idea.
- List below, newest first, swipe to delete.
- `ShareLink` in the toolbar exporting the markdown dump.
- Styled to match `BrandFormSheet` so it reads as part of the app.

Screen context comes from `ContentView`, which already owns `selectedTab`; its
label is passed into the sheet and stamped onto each new idea. Ideas captured
from the Settings entry carry `screen == nil`.

## Markdown export

```markdown
## Ideas — 3 captured

- **Meds tab needs a 'skip today'** — Schedule · Aug 27, 9:14pm
- **Walk timer should keep running** — Home · Aug 26, 7:02am
```

An idea with no `screen` omits that segment and its separator. An empty list
exports a header reading `## Ideas — none captured` rather than a bare heading.

## Testing

`IdeaStoreTests`, in the existing `PetHomepageTests` target, temp-directory based
in the style of `DocumentStoreTests`:

- `add` then `ideas` returns newest first
- `delete` removes the target and leaves the rest intact
- ideas survive a round trip through a new store instance on the same file
- markdown export format, including the no-screen and empty-list cases
- a corrupt `ideas.json` yields an empty list, not a throw

## Out of scope

Editing an existing idea, tags or categories, search, done/archive states, the
Convex push, and CloudKit sync. Each is cheap to add once real usage shows it is
wanted.

## Follow-on

The Convex path, if the paste-into-chat step becomes annoying: a `notes` table in
`convex/schema.ts`, a write endpoint alongside the existing mirror push, and a
`ConvexIdeaStore` conforming to `IdeaStore`. Convex is reachable from the Linux
development machine via `npx convex run`, which is the property that makes it the
eventual destination rather than CloudKit.
