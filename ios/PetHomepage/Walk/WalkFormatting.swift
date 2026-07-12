// ios/PetHomepage/Walk/WalkFormatting.swift
import Foundation

enum WalkFormatting {
    /// "5:10–5:42 PM · 32 min" for a closed span (the start drops its meridiem when it
    /// matches the end's), or just "5:10 PM" when the entry has no end time.
    static func spanLabel(start: Date, end: Date?,
                          locale: Locale = .current,
                          timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let startText = formatter.string(from: start)
        guard let end else { return startText }
        let endText = formatter.string(from: end)

        var lead = startText
        for suffix in ["AM", "PM"]
        where startText.hasSuffix(suffix) && endText.hasSuffix(suffix) {
            lead = String(startText.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespaces)
        }
        let minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        return "\(lead)–\(endText) · \(minutes) min"
    }
}
