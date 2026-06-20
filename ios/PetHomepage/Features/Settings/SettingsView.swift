// ios/PetHomepage/Features/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @State private var model: SettingsViewModel
    @State private var syncError: String?

    init(model: SettingsViewModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Desktop mirror") {
                    Toggle("Mirror to dashboard", isOn: $model.isMirroringEnabled)
                    Text(model.privacyNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Sync now") {
                        Task {
                            do { _ = try await model.syncNow() }
                            catch { syncError = error.localizedDescription }
                        }
                    }
                    .disabled(!model.isMirroringEnabled)
                    if let syncError {
                        Text(syncError).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("Documents (iCloud Drive)") {
                    if model.documentRows.isEmpty {
                        Text("No documents yet. Uploaded records appear here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.documentRows) { row in
                            documentRow(row)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear { model.loadDocuments() }
        }
    }

    @ViewBuilder
    private func documentRow(_ row: DocumentRow) -> some View {
        if let url = try? model.shareURL(for: row) {
            ShareLink(item: url) {
                Label(row.reference.fileName, systemImage: "doc")
            }
        } else {
            Label(row.reference.fileName, systemImage: "doc")
                .foregroundStyle(.secondary)
        }
    }
}
