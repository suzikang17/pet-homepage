// ios/PetHomepage/Features/Settings/SettingsViewModel.swift
import Foundation
import Observation

/// One browsable document in the Settings list.
struct DocumentRow: Identifiable, Equatable {
    let id: String                 // fileName (unique within the container)
    let reference: AttachmentReference
}

/// Drives the Settings screen: the opt-in toggle (written through to MirrorSettings), the
/// privacy note, an on-demand "sync now" (gated by the coordinator), and the browsable
/// list of iCloud Drive documents. Thin and fully testable — no UIKit/SwiftUI here.
@Observable
final class SettingsViewModel {
    var documentRows: [DocumentRow] = []

    /// The opt-in privacy posture, shown verbatim next to the toggle.
    let privacyNote = "When mirroring is on, a copy of your pet's records leaves iCloud and is sent to the dashboard backend. It stays off by default."

    private let settings: MirrorSettings
    private let coordinator: MirrorCoordinator
    private let documentSharing: DocumentSharing
    private let documentNames: [String]

    init(settings: MirrorSettings,
         coordinator: MirrorCoordinator,
         documentSharing: DocumentSharing,
         documentNames: [String]) {
        self.settings = settings
        self.coordinator = coordinator
        self.documentSharing = documentSharing
        self.documentNames = documentNames
    }

    /// Bound to the toggle — reads and writes the injected MirrorSettings directly.
    var isMirroringEnabled: Bool {
        get { settings.isMirroringEnabled }
        set { settings.isMirroringEnabled = newValue }
    }

    /// Populate `documentRows` with only the candidate documents that actually exist on disk.
    func loadDocuments() {
        documentRows = documentSharing
            .availableReferences(named: documentNames)
            .map { DocumentRow(id: $0.fileName, reference: $0) }
    }

    /// The iCloud Drive file URL for a row, for the View layer's ShareLink/share sheet.
    func shareURL(for row: DocumentRow) throws -> URL {
        try documentSharing.shareURL(for: row.reference)
    }

    /// Manually push a snapshot if opted in; returns whether a push happened.
    @discardableResult
    func syncNow() async throws -> Bool {
        try await coordinator.syncIfEnabled()
    }
}
