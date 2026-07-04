// ios/PetHomepage/Stores/LogStore+Marker.swift
import CoreData

/// Marker occurrences: kind `.marker`, `subtypeRaw` = `MarkerType.rawValue`, `value`/`unit` hold the
/// reading. Mirrors the old HealthMarkerStore's shape (HealthMarkerStore itself is untouched; this
/// replaces it as the write path consumers use).
extension LogEntry {
    /// Strongly-typed view of `subtypeRaw` for marker entries; falls back to `.other` for unknown values.
    var markerType: MarkerType {
        get { MarkerType(rawValue: subtypeRaw ?? "") ?? .other }
        set { subtypeRaw = newValue.rawValue }
    }
}

extension LogStore {
    @discardableResult
    func logMarker(type: MarkerType, value: Double, unit: String?, recordedAt: Date = Date()) throws -> LogEntry {
        let entry = try makeEntry(performedAt: recordedAt, note: nil)
        entry.kind = .marker
        entry.markerType = type
        entry.value = value
        entry.unit = unit
        try context.save()
        return entry
    }

    /// All marker occurrences for the current pet, most recently recorded first.
    func markers() throws -> [LogEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        return try fetch(NSPredicate(format: "pet == %@ AND kindRaw == %@", pet, LogKind.marker.rawValue))
    }

    /// The most-recently recorded marker of a given type, or nil if none.
    func latestMarker(of markerType: MarkerType) throws -> LogEntry? {
        guard let pet = try petStore.currentPet() else { return nil }
        return try fetch(NSPredicate(format: "pet == %@ AND kindRaw == %@ AND subtypeRaw == %@",
                                     pet, LogKind.marker.rawValue, markerType.rawValue), limit: 1).first
    }

    /// A time-ordered (oldest-first) series of one marker type — drives the weight trend.
    func series(of markerType: MarkerType) throws -> [LogEntry] {
        guard let pet = try petStore.currentPet() else { return [] }
        let request = LogEntry.fetchRequest()
        request.predicate = NSPredicate(format: "pet == %@ AND kindRaw == %@ AND subtypeRaw == %@",
                                        pet, LogKind.marker.rawValue, markerType.rawValue)
        request.sortDescriptors = [NSSortDescriptor(key: "performedAt", ascending: true)]
        return try context.fetch(request)
    }
}
