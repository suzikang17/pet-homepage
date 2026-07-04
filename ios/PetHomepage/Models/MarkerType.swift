// ios/PetHomepage/Models/MarkerType.swift
import Foundation

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
