// ios/PetHomepage/Features/Activities/ActivityTypeEditView.swift
import SwiftUI

/// Edit an existing activity type: rename, recategorize, pick an icon, and adjust its default
/// cadence. Self-contained sheet — seeds local state from the type and hands the edited values
/// back through `onSave` (the parent's ViewModel owns the store write).
struct ActivityTypeEditView: View {
    let type: ActivityType
    let onSave: (_ name: String, _ category: ActivityCategory, _ iconName: String, _ intervalDays: Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: ActivityCategory
    @State private var iconName: String
    @State private var hasCadence: Bool
    @State private var intervalDays: Int

    init(type: ActivityType,
         onSave: @escaping (_ name: String, _ category: ActivityCategory, _ iconName: String, _ intervalDays: Int) -> Void) {
        self.type = type
        self.onSave = onSave
        _name = State(initialValue: type.name)
        _category = State(initialValue: type.category)
        _iconName = State(initialValue: type.iconName)
        _hasCadence = State(initialValue: type.defaultIntervalDays > 0)
        _intervalDays = State(initialValue: type.defaultIntervalDays > 0 ? Int(type.defaultIntervalDays) : 30)
    }

    /// A curated set of pet-care SF Symbols to choose from (free-text symbol names are too
    /// error-prone — a typo renders nothing).
    private static let iconChoices = [
        "pawprint", "shower", "scissors", "mouth", "comb", "dog", "ladybug", "pills",
        "cross.case", "heart", "tennisball", "fork.knife", "figure.walk", "drop", "bandage", "sparkles",
    ]

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        BrandFormSheet(
            title: "Edit activity",
            systemImage: iconName,
            confirmDisabled: trimmedName.isEmpty,
            onCancel: { dismiss() },
            onConfirm: {
                onSave(trimmedName, category, iconName, hasCadence ? intervalDays : 0)
                dismiss()
            }
        ) {
            Section {
                TextField("Name", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(ActivityCategory.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Icon") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Self.iconChoices, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 20))
                                .frame(width: 44, height: 44)
                                .background(symbol == iconName ? Theme.primary.opacity(0.15) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(symbol == iconName ? Theme.primary : Theme.ink.opacity(0.1)))
                                .foregroundStyle(symbol == iconName ? Theme.primary : Theme.ink)
                                .onTapGesture { iconName = symbol }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section {
                Toggle("Repeat reminder", isOn: $hasCadence)
                if hasCadence {
                    Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...365)
                }
            }
        }
    }
}
