// ios/PetHomepage/Features/Schedule/MealFeedingSheet.swift
import SwiftUI

/// Logs one feeding of a meal slot: an amount in the slot's unit, prefilled to the amount
/// still remaining toward the allotment. Also lists today's feedings so one can be removed.
struct MealFeedingSheet: View {
    let slot: RoutineSlot
    let onLog: (Double) -> Void
    let onRemove: (LogEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double

    init(slot: RoutineSlot, onLog: @escaping (Double) -> Void,
         onRemove: @escaping (LogEntry) -> Void) {
        self.slot = slot
        self.onLog = onLog
        self.onRemove = onRemove
        let remaining = max(0, slot.task.mealAllotment - slot.fedTotal)
        _amount = State(initialValue: remaining > 0 ? remaining : slot.step)
    }

    var body: some View {
        BrandFormSheet(
            title: "Add feeding",
            systemImage: "fork.knife",
            confirmDisabled: amount <= 0,
            onCancel: { dismiss() },
            onConfirm: { onLog(amount); dismiss() }
        ) {
            Section {
                HStack {
                    Text(slot.task.name)
                    Spacer()
                    Text(slot.amountLabel).foregroundStyle(Theme.inkSoft)
                }
                Stepper(value: $amount, in: slot.step...max(slot.step, slot.task.mealAllotment * 4),
                        step: slot.step) {
                    Text("\(slot.format(amount)) \(slot.task.mealUnit ?? "")")
                        .font(.body.weight(.semibold))
                }
            } header: {
                Text("Amount")
            }

            if !slot.feedings.isEmpty {
                Section("Today") {
                    ForEach(slot.feedings) { feeding in
                        HStack {
                            Text("\(slot.format(feeding.value)) \(feeding.unit ?? "")")
                            Spacer()
                            Text(feeding.performedAt, format: .dateTime.hour().minute())
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet { onRemove(slot.feedings[i]) }
                    }
                }
            }
        }
    }
}

extension RoutineSlot {
    /// Stepper increment tuned to the unit: quarter cups/scoops, whole oz, 5-gram grams.
    var step: Double {
        switch (task.mealUnit ?? "").lowercased() {
        case "grams", "g": return 5
        case "oz", "ounces": return 1
        default: return 0.25 // cups / scoops
        }
    }

    func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    /// "1.5 / 2 cups" for a meal slot.
    var amountLabel: String {
        "\(format(fedTotal)) / \(format(task.mealAllotment)) \(task.mealUnit ?? "")"
    }
}

/// A small progress ring for a meal slot's check control — fills as feedings are logged,
/// shows a check when the allotment is reached. Sized to match the plain check circle (26pt).
struct MealRing: View {
    let progress: Double
    let complete: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.inkSoft.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(complete ? Theme.ok : Theme.primary,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if complete {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.ok)
            }
        }
        .frame(width: 26, height: 26)
        .animation(.easeOut(duration: 0.25), value: progress)
    }
}
