// ios/PetHomepage/Features/Schedule/ScheduleView.swift
import PhotosUI
import SwiftUI
import UIKit

/// The wheel time-picker sheet's target: a "this day only" schedule move. (Done-times are set
/// on the analog clock instead — see ClockTarget.)
private enum TimeSheetTarget: Identifiable {
    case moveTime(RoutineSlot)

    var id: UUID {
        switch self {
        case .moveTime(let slot): slot.id
        }
    }
}

/// What the analog-clock sheet is setting: the done-time of a slot being checked off after the
/// fact (`setDone`), or a correction to an already-recorded completion (`editDone`).
private enum ClockTarget: Identifiable {
    case setDone(RoutineSlot)
    case editDone(RoutineSlot)

    var id: UUID {
        switch self {
        case .setDone(let slot), .editDone(let slot): slot.id
        }
    }
}

/// The Schedule tab: one day's care checklist at a time (chevrons/Today to move between days),
/// check-offs with a transient "Add a photo?" toast, per-day skips and time changes
/// (long-press a row), one-off tasks, and the versioned template editor behind the header's
/// manage button.
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
    @State private var timeSheet: TimeSheetTarget?
    @State private var clockTarget: ClockTarget?
    @State private var feedingTarget: RoutineSlot?
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("walk.setupCardDismissed") private var walkSetupDismissed = false
    /// Mirrors HomeLocationStore's key so the card disappears the moment home is set —
    /// reading the store inside `body` wouldn't re-render on the write.
    @AppStorage("walk.homeLat") private var walkHomeLat: Double = .nan
    @State private var showWalkSetup = false

    private let store: RoutineStore
    private let reminderScheduler: RoutineReminderScheduler
    private let petStore: PetStore
    @State private var walkModel: WalkSessionModel

    /// Which subtab is showing. "Today" is the day-pager routine; "Upcoming" is every dated
    /// reminder, including the vaccinations, vet visits and refills that have no routine slot.
    private enum Tab: String, CaseIterable { case today = "Today", upcoming = "Upcoming" }
    @State private var tab: Tab = .today
    @State private var catalogue: CadenceCatalogueViewModel?
    private let timelineServices: TimelineServices?

    init(store: RoutineStore, logStore: LogStore,
         reminderScheduler: RoutineReminderScheduler, petStore: PetStore,
         walkSessions: WalkSessionStore, timelineServices: TimelineServices? = nil) {
        self.timelineServices = timelineServices
        self.store = store
        self.reminderScheduler = reminderScheduler
        self.petStore = petStore
        _model = State(initialValue: ScheduleViewModel(store: store, logStore: logStore))
        _walkModel = State(initialValue: WalkSessionModel(sessions: walkSessions, petName: {
            (try? petStore.currentPet())?.name ?? "Your pet"
        }))
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
                    Picker("", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    if tab == .today {
                        dayBar
                        // Auto-detect setup nudge: only while a walk slot exists but detection
                        // was never configured, and never after "Not now".
                        if !walkSetupDismissed, walkHomeLat.isNaN,
                           model.slots.contains(where: { $0.task.isWalk }) {
                            WalkSetupCard(onSetUp: { showWalkSetup = true },
                                          onDismiss: { walkSetupDismissed = true })
                                .padding(.horizontal, 16)
                        }
                        WalkInProgressBanner(model: walkModel)
                            .padding(.horizontal, 16)
                        content
                    } else {
                        upcomingList
                    }
                }
                if let completion = model.toastCompletion {
                    photoToast(for: completion)
                }
            }
            .background(Theme.bg)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                refreshUpcoming()
                // Sessions can start/end outside this view (notification actions, auto-end).
                walkModel.refresh()
                // Always land on Today: a left-open past/future day or a midnight rollover must
                // never be what greets the user. goToToday() reloads; plain load() otherwise.
                if model.isToday { model.load() } else { model.goToToday() }
                // Any check-off/skip/time-change must silence or move its pending reminder.
                model.onDayStateChanged = {
                    Task {
                        await RoutineReminderPlanner.resync(context: store.context,
                                                            using: reminderScheduler)
                    }
                }
                // Ending a walk completes a slot: reload the visible day immediately (the
                // fix for "I ended a walk and the schedule still showed it open").
                walkModel.onChange = {
                    model.load()
                    model.onDayStateChanged?()
                }
            }
            .sheet(isPresented: $showWalkSetup) {
                NavigationStack { WalkDetectionSettingsView() }
            }
            .onChange(of: scenePhase) { _, phase in
                // The geofence can auto-end a walk while we're backgrounded; refresh what's
                // on screen when the user comes back. Re-anchor to Today too, so an overnight
                // background (or a day left paged forward/back) reopens on the current day.
                guard phase == .active else { return }
                walkModel.refresh()
                if model.isToday { model.load() } else { model.goToToday() }
            }
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
            .sheet(item: $feedingTarget) { slot in
                MealFeedingSheet(
                    slot: slot,
                    onLog: { amount in model.logFeeding(slot, amount: amount) },
                    onRemove: { entry in model.removeFeeding(entry) }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $timeSheet) { target in
                switch target {
                case .moveTime(let slot):
                    TimeAdjustSheet(title: "Change time", subtitle: "This day only",
                                    systemImage: "clock.arrow.circlepath",
                                    hour: slot.hour, minute: slot.minute) { hour, minute in
                        model.changeTime(slot, hour: hour, minute: minute)
                    }
                }
            }
            .sheet(item: $clockTarget) { target in
                switch target {
                case .setDone(let slot):
                    let start = nowHM()
                    ClockTimeSheet(
                        title: "Done at",
                        systemImage: "clock.badge.checkmark",
                        subtitle: "When did “\(slot.task.name)” happen?",
                        day: model.day,
                        initialHour: start.hour, initialMinute: start.minute,
                        clampTo: model.isToday ? Date() : nil
                    ) { hour, minute in
                        if let date = Calendar.current.date(bySettingHour: hour, minute: minute,
                                                            second: 0, of: model.day) {
                            model.checkOff(slot, at: date)
                        }
                    }
                case .editDone(let slot):
                    ClockTimeSheet(
                        title: "Time done",
                        subtitle: "When did “\(slot.task.name)” happen?",
                        day: model.day,
                        initialHour: doneHour(of: slot), initialMinute: doneMinute(of: slot),
                        clampTo: model.isToday ? Date() : nil
                    ) { hour, minute in
                        model.updateCompletionTime(slot, hour: hour, minute: minute)
                    }
                }
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
                .background(Theme.card, in: Circle())
                .shadow(color: Theme.shadow.opacity(0.06), radius: 6, y: 2)
        }
        .accessibilityIdentifier(id)
    }

    // MARK: - Checklist

    @ViewBuilder
    /// Rebuilds the upcoming list, reusing the view model across appearances so it is not
    /// reconstructed on every tab switch.
    private func refreshUpcoming() {
        guard let s = timelineServices else { return }
        let vm = catalogue ?? CadenceCatalogueViewModel(
            medicationStore: s.medicationStore,
            activityStore: s.activityStore,
            logStore: s.logStore,
            reminderScheduler: s.reminderScheduler,
            dueScheduler: s.dueScheduler)
        vm.load()
        catalogue = vm
    }

    /// Every dated reminder, most urgent first. The day-pager answers "what is left today";
    /// this answers "what is coming", including the vaccinations, vet visits and refills that
    /// have no routine slot and therefore never appeared on this tab at all.
    @ViewBuilder
    private var upcomingList: some View {
        if let reminders = catalogue?.upcoming, !reminders.isEmpty {
            List(reminders) { UpcomingReminderRow(reminder: $0) }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                "Nothing coming up",
                systemImage: "bell.slash",
                description: Text("Vaccinations, vet visits, refills and anything on a cadence will show up here.")
            )
        }
    }

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
                        .swipeActions(edge: .leading) { doneAtSwipe(slot) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    /// Leading-swipe shortcut for after-the-fact logging: an open row jumps straight to the
    /// clock to pick a done-time; a completed row re-opens the clock to correct it. Meals log
    /// amounts (their own sheet), so they're left out; future days can't be completed.
    @ViewBuilder
    private func doneAtSwipe(_ slot: RoutineSlot) -> some View {
        if !slot.isMeal {
            if slot.isCompleted {
                Button {
                    clockTarget = .editDone(slot)
                } label: {
                    Label("Edit time", systemImage: "clock")
                }
                .tint(Theme.primary)
            } else if !slot.isSkipped, !model.isFuture {
                Button {
                    clockTarget = .setDone(slot)
                } label: {
                    Label("Done at…", systemImage: "clock.badge.checkmark")
                }
                .tint(Theme.ok)
            }
        }
    }

    private func slotRow(_ slot: RoutineSlot) -> some View {
        HStack(spacing: 12) {
            Button {
                if slot.isMeal {
                    feedingTarget = slot
                } else if slot.isCompleted {
                    model.uncheck(slot)
                } else {
                    model.checkOff(slot)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } label: {
                if slot.isMeal {
                    MealRing(progress: slot.mealProgress, complete: slot.isCompleted)
                } else {
                    // Completed reads as a quiet receipt; the open circle is the loud, inviting tap.
                    Image(systemName: slot.isCompleted ? "checkmark.circle" : "circle")
                        .font(.system(size: slot.isCompleted ? 20 : 26,
                                      weight: slot.isCompleted ? .medium : .semibold))
                        .foregroundStyle(slot.isCompleted
                                         ? Theme.inkSoft.opacity(0.6)
                                         : Theme.primary.opacity(0.45))
                        .frame(width: 26)
                }
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
                    .font(.body.weight(slot.isCompleted ? .regular : .semibold))
                    .foregroundStyle(slot.isSkipped ? Theme.inkSoft : Theme.ink)
                    .strikethrough(slot.isSkipped)
                HStack(spacing: 5) {
                    if slot.isSkipped {
                        Text("Skipped")
                    } else if slot.isMeal {
                        Text(scheduledTime(slot), format: .dateTime.hour().minute())
                        Text("· \(slot.amountLabel)")
                            .foregroundStyle(slot.isCompleted ? Theme.ok : Theme.inkSoft)
                    } else if let completion = slot.completion {
                        if completion.endedAt != nil {
                            Text("Done \(WalkFormatting.spanLabel(start: completion.performedAt, end: completion.endedAt))")
                        } else {
                            Text("Done at \(completion.performedAt, format: .dateTime.hour().minute())")
                        }
                    } else {
                        Text(scheduledTime(slot), format: .dateTime.hour().minute())
                        if slot.timeOverride != nil {
                            // Marks a "this day only" time change (long-press → reset).
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.primary)
                        }
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
        // Done rows recede so the remaining work is visually loudest.
        .opacity(slot.isCompleted ? 0.55 : 1)
        .padding(.vertical, 4)
        .accessibilityIdentifier("scheduleRow.\(slot.task.name)")
        .contextMenu { contextActions(for: slot) }
    }

    /// Long-press menu: per-day deviations (time change, skip) on open rows; time/photo/uncheck
    /// on completed ones. Nothing here ever touches the weekly template.
    @ViewBuilder
    private func contextActions(for slot: RoutineSlot) -> some View {
        if slot.isCompleted {
            Button {
                clockTarget = .editDone(slot)
            } label: {
                Label("Edit time done", systemImage: "clock")
            }
            if slot.completion?.photoArray.isEmpty ?? true {
                Button {
                    photoTarget = slot.completion
                    presentCapture()
                } label: {
                    Label("Add a photo", systemImage: "camera")
                }
            }
            Button(role: .destructive) {
                model.uncheck(slot)
            } label: {
                Label("Mark as not done", systemImage: "circle")
            }
        } else {
            if !slot.isSkipped {
                // Live session start: records real start/end instead of a single done-time.
                if model.isToday, walkModel.active == nil {
                    Button {
                        walkModel.startRoutine(taskID: slot.task.id)
                    } label: {
                        Label("Start now", systemImage: "play.circle")
                    }
                }
                Button {
                    timeSheet = .moveTime(slot)
                } label: {
                    Label("Change time (this day only)", systemImage: "clock.arrow.circlepath")
                }
                if slot.timeOverride != nil {
                    Button {
                        model.clearTimeChange(slot)
                    } label: {
                        Label("Reset to usual time", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            Button {
                model.toggleSkip(slot)
            } label: {
                Label(slot.isSkipped ? "Unskip today" : "Skip today",
                      systemImage: slot.isSkipped ? "arrow.uturn.backward" : "moon.zzz")
            }
        }
    }

    private func scheduledTime(_ slot: RoutineSlot) -> Date {
        Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute,
                              second: 0, of: model.day) ?? model.day
    }

    /// Current wall-clock hour/minute, read once so the two components can't straddle a minute
    /// boundary — the default "done at" start for a fresh check-off.
    private func nowHM() -> (hour: Int, minute: Int) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 9, c.minute ?? 0)
    }

    private func doneHour(of slot: RoutineSlot) -> Int {
        slot.completion.map { Calendar.current.component(.hour, from: $0.performedAt) } ?? 9
    }

    private func doneMinute(of slot: RoutineSlot) -> Int {
        slot.completion.map { Calendar.current.component(.minute, from: $0.performedAt) } ?? 0
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

/// Compact hour/minute picker shared by "change time (this day only)" and "edit time done".
private struct TimeAdjustSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String
    let systemImage: String
    @State private var time: Date
    let onSave: (Int, Int) -> Void

    init(title: String, subtitle: String, systemImage: String,
         hour: Int, minute: Int, onSave: @escaping (Int, Int) -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.onSave = onSave
        _time = State(initialValue: Calendar.current.date(bySettingHour: hour, minute: minute,
                                                          second: 0, of: Date()) ?? Date())
    }

    var body: some View {
        BrandFormSheet(
            title: title,
            systemImage: systemImage,
            onCancel: { dismiss() },
            onConfirm: {
                let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
                onSave(comps.hour ?? 9, comps.minute ?? 0)
                dismiss()
            }
        ) {
            Section(subtitle) {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("timeAdjustPicker")
            }
        }
        .presentationDetents([.medium])
    }
}
