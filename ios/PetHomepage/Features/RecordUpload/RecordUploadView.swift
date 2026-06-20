// ios/PetHomepage/Features/RecordUpload/RecordUploadView.swift
import SwiftUI

/// Minimal record-upload entry point. In v1 the file picker integration is deferred;
/// this screen drives the extract → confirm → save flow with the injected services.
/// (A real document/photo picker is wired in a later UI pass; the load-bearing logic
/// lives in RecordUploadViewModel, which is fully tested.)
struct RecordUploadView: View {
    @State private var model: RecordUploadViewModel

    /// The file the user selected. Supplied by the caller (picker integration is deferred);
    /// defaults keep the screen functional for manual testing.
    let fileData: Data
    let fileName: String
    let mimeType: String

    init(extractionService: ExtractionService,
         ingestionService: RecordIngestionService,
         fileData: Data,
         fileName: String,
         mimeType: String) {
        _model = State(initialValue: RecordUploadViewModel(extractionService: extractionService,
                                                           ingestionService: ingestionService))
        self.fileData = fileData
        self.fileName = fileName
        self.mimeType = mimeType
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.state {
                case .idle:
                    Section {
                        Button("Extract record") {
                            Task { await model.extract(fileData: fileData, fileName: fileName, mimeType: mimeType) }
                        }
                    }
                case .extracting:
                    Section { ProgressView("Extracting…") }
                case .parsed(let results):
                    Section("Parsed \(results.count) record(s)") {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.title).font(.headline)
                                Text(result.eventType.rawValue).font(.caption).foregroundStyle(.secondary)
                                if let notes = result.notes {
                                    Text(notes).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section {
                        Button("Confirm & save") {
                            Task { await model.confirmSave(fileData: fileData, fileName: fileName) }
                        }
                    }
                case .saved(let outcomes):
                    Section { Text("Saved \(outcomes.count) record(s).") }
                case .failed(let message):
                    Section { Text("Failed: \(message)").foregroundStyle(.red) }
                }
            }
            .navigationTitle("Upload record")
        }
    }
}
