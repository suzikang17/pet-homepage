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

    // Stored properties so @Observable tracks mutations and SwiftUI Bindings work.
    // Each setter writes through to the injected MirrorSettings (which persists the value).

    /// Bound to the toggle.
    var isMirroringEnabled: Bool {
        didSet { settings.isMirroringEnabled = isMirroringEnabled }
    }

    /// Bound to the endpoint TextField. Blank = use the build-time default.
    var mirrorEndpoint: String {
        didSet { settings.mirrorEndpoint = mirrorEndpoint }
    }

    /// Bound to the token SecureField. Written to the Keychain by the production MirrorSettings.
    var mirrorToken: String {
        didSet { settings.mirrorToken = mirrorToken }
    }

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
        // Seed the tracked stored properties from the persisted settings.
        self.isMirroringEnabled = settings.isMirroringEnabled
        self.mirrorEndpoint = settings.mirrorEndpoint
        self.mirrorToken = settings.mirrorToken
    }

    /// Apply a successful device pairing: store the minted token + push endpoint and turn
    /// mirroring on. Setters write through to MirrorSettings (Keychain for the token).
    func applyPairing(token: String, endpoint: String) {
        mirrorEndpoint = endpoint
        mirrorToken = token
        isMirroringEnabled = true
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
