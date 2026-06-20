// ios/PetHomepage/Features/RecordUpload/RecordUploadViewModel.swift
import Foundation
import Observation

enum RecordUploadState: Equatable {
    case idle
    case extracting
    case parsed([ExtractionResult])
    case saved([IngestionOutcome])
    case failed(String)
}

/// Drives the "upload a record → AI extract → confirm → save" flow. The extraction
/// is injected (a fake in tests — NO network, NO real Claude); on confirm, each parsed
/// result is written via RecordIngestionService and the original file is retained.
@Observable
final class RecordUploadViewModel {
    var state: RecordUploadState = .idle

    private let extractionService: ExtractionService
    private let ingestionService: RecordIngestionService

    init(extractionService: ExtractionService, ingestionService: RecordIngestionService) {
        self.extractionService = extractionService
        self.ingestionService = ingestionService
    }

    /// Runs extraction and parks the parsed results for user confirmation.
    /// `fileName` flows through to the server so /api/extract receives the actual document name
    /// (ExtractRequestSchema requires fileName). Uses the full 5-arg protocol method so the
    /// caller-supplied name is not silently substituted with the "upload" convenience default.
    func extract(fileData: Data, fileName: String, mimeType: String) async {
        state = .extracting
        do {
            let results = try await extractionService.extract(
                fileData: fileData,
                mimeType: mimeType,
                fileName: fileName,
                note: nil,
                date: nil
            )
            state = .parsed(results)
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// Writes each parsed result and saves the original file (attached to the first result only,
    /// so the document is stored once). Requires the current state to be `.parsed`.
    func confirmSave(fileData: Data, fileName: String) async {
        guard case let .parsed(results) = state else { return }
        do {
            var outcomes: [IngestionOutcome] = []
            for (index, result) in results.enumerated() {
                let file: (data: Data, fileName: String)? = index == 0 ? (fileData, fileName) : nil
                outcomes.append(try ingestionService.ingest(result, originalFile: file))
            }
            state = .saved(outcomes)
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
