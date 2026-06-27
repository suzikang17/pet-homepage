// ios/PetHomepage/Models/MedicationFrequency.swift
import Foundation

/// The cadence unit for a medication schedule.
enum FrequencyUnit: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }

    var singular: String { rawValue }
    var plural: String { rawValue + "s" }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

/// "Every N <unit>" — the structured medication frequency. Stored on the Medication as a
/// canonical `label` string (`Medication.frequency`), so there's no Core Data migration: the
/// label round-trips through `init(parsing:)`, and legacy / AI-extracted free text degrades
/// gracefully to a best-effort guess (defaulting to daily).
struct MedFrequency: Equatable {
    var interval: Int
    var unit: FrequencyUnit

    static let `default` = MedFrequency(interval: 1, unit: .day)

    init(interval: Int, unit: FrequencyUnit) {
        self.interval = max(1, interval)
        self.unit = unit
    }

    /// Canonical, human-readable label — what gets stored and shown (mirror, Timeline).
    var label: String {
        if interval <= 1 {
            switch unit {
            case .day: return "Daily"
            case .week: return "Weekly"
            case .month: return "Monthly"
            }
        }
        return "Every \(interval) \(unit.plural)"
    }

    /// Parse the canonical label, plus a best-effort pass over legacy/free-text values.
    init(parsing raw: String) {
        let s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Canonical single-interval labels + common synonyms.
        switch s {
        case "", "daily", "once daily", "once a day", "every day", "qd":
            self = .init(interval: 1, unit: .day); return
        case "weekly", "every week", "once a week":
            self = .init(interval: 1, unit: .week); return
        case "monthly", "every month", "once a month":
            self = .init(interval: 1, unit: .month); return
        default:
            break
        }

        // "every N day(s)/week(s)/month(s)"
        let parts = s.split(separator: " ").map(String.init)
        if parts.count == 3, parts[0] == "every", let n = Int(parts[1]) {
            if let unit = Self.unit(forWord: parts[2]) {
                self = .init(interval: n, unit: unit); return
            }
        }
        // "N days" without "every"
        if parts.count == 2, let n = Int(parts[0]), let unit = Self.unit(forWord: parts[1]) {
            self = .init(interval: n, unit: unit); return
        }

        self = .default
    }

    private static func unit(forWord word: String) -> FrequencyUnit? {
        if word.hasPrefix("day") { return .day }
        if word.hasPrefix("week") { return .week }
        if word.hasPrefix("month") { return .month }
        return nil
    }

    /// The next occurrence strictly after `now`, anchored at `start`'s date with `time`'s
    /// hour/minute, stepping by the interval. Used to schedule the next medication reminder.
    func nextOccurrence(after now: Date, start: Date, time: Date, calendar: Calendar = .current) -> Date {
        let timeComps = calendar.dateComponents([.hour, .minute], from: time)
        var dayComps = calendar.dateComponents([.year, .month, .day], from: start)
        dayComps.hour = timeComps.hour
        dayComps.minute = timeComps.minute
        var candidate = calendar.date(from: dayComps) ?? start

        var guardCount = 0
        while candidate <= now, guardCount < 100_000 {
            candidate = calendar.date(byAdding: unit.calendarComponent, value: interval, to: candidate)
                ?? candidate.addingTimeInterval(86_400)
            guardCount += 1
        }
        return candidate
    }
}
