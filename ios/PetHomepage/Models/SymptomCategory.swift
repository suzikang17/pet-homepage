// ios/PetHomepage/Models/SymptomCategory.swift
import Foundation

/// The kind of symptom an episode tracks.
enum SymptomCategory: String, CaseIterable, Identifiable {
    case digestive
    case skin
    case behavior
    case diet
    case energy
    case other

    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}
