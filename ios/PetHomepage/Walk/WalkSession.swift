// ios/PetHomepage/Walk/WalkSession.swift
import Foundation

/// The single in-progress walk. Persisted as JSON in UserDefaults (not Core Data): it must
/// survive app kill and be readable synchronously from notification handlers, and it is
/// device-local by design — a session on your phone shouldn't sync to a partner's phone.
struct WalkSession: Codable, Equatable {
    enum Source: String, Codable { case manual, detected }

    let id: UUID
    let petID: UUID?
    /// Exactly one of activityTypeID / routineTaskID is non-nil.
    let activityTypeID: UUID?
    let routineTaskID: UUID?
    let startedAt: Date
    let source: Source
}
