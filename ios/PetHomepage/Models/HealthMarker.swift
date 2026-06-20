// ios/PetHomepage/Models/HealthMarker.swift
import CoreData

/// The kinds of generic health markers the owner can log. `weight` is absorbed here
/// (no separate Weight entity) — the trend view just filters the series to `.weight`.
enum MarkerType: String, CaseIterable, Identifiable {
    case weight
    case appetite
    case energy
    case water
    case temperature
    case other

    var id: String { rawValue }

    /// Title-cased label for pickers and lists.
    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

@objc(HealthMarker)
public class HealthMarker: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var markerTypeRaw: String
    @NSManaged public var value: Double
    @NSManaged public var unit: String?
    @NSManaged public var recordedAt: Date
    @NSManaged public var pet: Pet?
}

extension HealthMarker {
    @nonobjc public static func fetchRequest() -> NSFetchRequest<HealthMarker> {
        NSFetchRequest<HealthMarker>(entityName: "HealthMarker")
    }

    /// Strongly-typed view of `markerTypeRaw`; falls back to `.other` for unknown values.
    var markerType: MarkerType {
        get { MarkerType(rawValue: markerTypeRaw) ?? .other }
        set { markerTypeRaw = newValue.rawValue }
    }
}
