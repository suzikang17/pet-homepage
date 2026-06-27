// ios/PetHomepage/Features/RecordUpload/RecordUploadView.swift
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Scan a record" — pick a PDF or a photo, send it to /api/extract, review what
/// Claude parsed, and save it into the right records. The load-bearing flow lives in
/// RecordUploadViewModel (fully tested); this view adds the picker + the brand UI.
struct RecordUploadView: View {
    @State private var model: RecordUploadViewModel
    @State private var picked: Picked?
    @State private var photoItem: PhotosPickerItem?
    @State private var showPDFImporter = false
    @State private var loadingFile = false
    @Environment(\.dismiss) private var dismiss

    init(extractionService: ExtractionService, ingestionService: RecordIngestionService) {
        _model = State(initialValue: RecordUploadViewModel(
            extractionService: extractionService,
            ingestionService: ingestionService
        ))
    }

    private struct Picked: Equatable {
        let data: Data
        let fileName: String
        let mimeType: String
    }

    var body: some View {
        NavigationStack {
            Form {
                content
            }
            .navigationTitle("Scan a record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .brandSheet()
            .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { handlePDF($0) }
            .onChange(of: photoItem) { _, item in if let item { loadPhoto(item) } }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            if let picked {
                Section("Selected") {
                    Label(picked.fileName, systemImage: icon(for: picked.mimeType))
                        .foregroundStyle(Theme.ink)
                }
                actionRow("Extract details") {
                    Task { await model.extract(fileData: picked.data, fileName: picked.fileName, mimeType: picked.mimeType) }
                }
                Section { Button("Choose a different file") { self.picked = nil } }
            } else {
                Section {
                    Text("Upload a vet bill, lab result, or vaccination record — the AI pulls out the details and files them for you.")
                        .font(.footnote).foregroundStyle(Theme.inkSoft)
                }
                Section("Choose a record") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Photo of a record", systemImage: "photo")
                    }
                    Button { showPDFImporter = true } label: {
                        Label("PDF document", systemImage: "doc")
                    }
                }
                if loadingFile {
                    Section { HStack { ProgressView(); Text("Loading…").foregroundStyle(Theme.inkSoft) } }
                }
            }

        case .extracting:
            Section { HStack { ProgressView(); Text("Reading the record…").foregroundStyle(Theme.inkSoft) } }

        case .parsed(let results):
            Section("Found \(results.count) record\(results.count == 1 ? "" : "s")") {
                ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.title).font(Theme.headline()).foregroundStyle(Theme.ink)
                        Text(prettyType(r.eventType)).font(.caption.weight(.semibold)).foregroundStyle(Theme.primary)
                        if let notes = r.notes {
                            Text(notes).font(.caption).foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
            actionRow("Save to records") {
                Task { if let p = picked { await model.confirmSave(fileData: p.data, fileName: p.fileName) } }
            }

        case .saved(let outcomes):
            Section {
                Label("Saved \(outcomes.count) record\(outcomes.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.ok)
                Button("Done") { dismiss() }
            }

        case .failed(let message):
            Section {
                Label("Couldn’t extract", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
                Text(message).font(.caption).foregroundStyle(Theme.inkSoft)
                Text("Check the endpoint + secret under Settings if this keeps failing.")
                    .font(.caption).foregroundStyle(Theme.inkSoft)
                Button("Try again") { model.state = .idle; picked = nil }
            }
        }
    }

    private func actionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Section {
            Button(action: action) { Text(title).frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle())
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func handlePDF(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            model.state = .failed("Couldn’t read that PDF."); return
        }
        picked = Picked(data: data, fileName: url.lastPathComponent, mimeType: "application/pdf")
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        loadingFile = true
        Task {
            defer { loadingFile = false }
            // Re-encode to JPEG so the upload is always a server-supported type (iPhone photos are often HEIC).
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.85)
            else {
                model.state = .failed("Couldn’t read that photo."); return
            }
            picked = Picked(data: jpeg, fileName: "record-\(Int(Date().timeIntervalSince1970)).jpg", mimeType: "image/jpeg")
        }
    }

    private func icon(for mime: String) -> String { mime == "application/pdf" ? "doc.fill" : "photo.fill" }

    private func prettyType(_ t: ExtractionEventType) -> String {
        t.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
