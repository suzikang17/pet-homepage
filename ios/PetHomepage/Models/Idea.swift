// ios/PetHomepage/Models/Idea.swift
import Foundation

/// A development scratchpad note, jotted while dogfooding the app.
///
/// Deliberately *not* a Core Data entity: a new entity would require a CloudKit dev-schema push
/// from an iCloud-signed-in simulator on a Mac plus a console promotion, and CloudKit would not
/// carry these notes to the development machine anyway. See
/// `docs/superpowers/specs/2026-08-29-idea-notes-design.md`.
struct Idea: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    /// Tab the user was on when capturing; nil when captured from Settings.
    let screen: String?
}
