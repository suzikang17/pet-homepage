// ios/PetHomepage/Mirror/MirrorCoordinator.swift
import Foundation

/// Builds and pushes a MirrorSnapshot — but ONLY when mirroring is opted in. This is the
/// single choke point that decides whether a copy of the pet's record leaves iCloud.
final class MirrorCoordinator {
    private let builder: SnapshotBuilder
    private let service: MirrorService
    private let settings: MirrorSettings

    init(builder: SnapshotBuilder, service: MirrorService, settings: MirrorSettings) {
        self.builder = builder
        self.service = service
        self.settings = settings
    }

    /// If mirroring is enabled, build one snapshot and push it; returns whether a push happened.
    /// When disabled, returns false WITHOUT building or pushing anything.
    @discardableResult
    func syncIfEnabled() async throws -> Bool {
        guard settings.isMirroringEnabled else { return false }
        let snapshot = try builder.build()
        try await service.push(snapshot)
        return true
    }
}
