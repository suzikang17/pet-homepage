// ios/PetHomepage/Features/Schedule/ScheduleView.swift
import PhotosUI
import SwiftUI
import UIKit

/// What the shared time-picker sheet is editing: a "this day only" schedule move, or the
/// recorded time of a completion.
private enum TimeSheetTarget: Identifiable {
    case moveTime(RoutineSlot)
    case editDone(RoutineSlot)

    var id: UUID {
        switch self {
        case .moveTime(let slot), .editDone(let slot): slot.id
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
            .sheet(item: $timeSheet) { target in
                switch target {
                case .moveTime(let slot):
                    TimeAdjustSheet(title: "Change time", subtitle: "This day only",
                                    systemImage: "clock.arrow.circlepath",
                                    hour: slot.hour, minute: slot.minute) { hour, minute in
                        model.changeTime(slot, hour: hour, minute: minute)
                    }
                case .editDone(let slot):
                    TimeAdjustSheet(title: "Time done", subtitle: "When did it happen?",
                                    systemImage: "clock",
                                    hour: doneHour(of: slot), minute: doneMinute(of: slot)) { hour, minute in
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
                timeSheet = .editDone(slot)
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
