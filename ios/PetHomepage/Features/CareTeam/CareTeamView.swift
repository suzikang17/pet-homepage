// ios/PetHomepage/Features/CareTeam/CareTeamView.swift
import SwiftUI

/// The Care Team tab: the pet's veterinarians. Add/edit/delete here; attach them to vet visits,
/// vaccines, and medications from those records' edit sheets.
struct CareTeamView: View {
    @State private var model: CareTeamViewModel
    @State private var editTarget: Veterinarian?
    @State private var addVet = false
    private let store: VeterinarianStore

    init(store: VeterinarianStore) {
        self.store = store
        _model = State(initialValue: CareTeamViewModel(store: store))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HeroHeader(
                    title: "Care Team",
                    subtitle: model.vets.isEmpty ? "Your vets" : "\(model.vets.count) vet\(model.vets.count == 1 ? "" : "s")",
                    systemImage: "stethoscope",
                    onAdd: { addVet = true }
                )
                content
            }
            .background(Theme.bg)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { model.load() }
            .sheet(isPresented: $addVet, onDismiss: { model.load() }) {
                VetEditView(store: store, editing: nil)
            }
            .sheet(item: $editTarget, onDismiss: { model.load() }) { vet in
                VetEditView(store: store, editing: vet)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.vets.isEmpty {
            ContentUnavailableView(
                "No vets yet",
                systemImage: "stethoscope",
                description: Text("Tap + to add your vet, then attach them to visits, vaccines, and meds.")
            )
        } else {
            List {
                ForEach(model.vets) { vet in
                    Button { editTarget = vet } label: { row(vet) }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.bg)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { model.delete(vet) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ vet: Veterinarian) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38)
                .background(Theme.primary.opacity(0.13), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(vet.name).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                if let clinic = vet.clinic, !clinic.isEmpty {
                    Text(clinic).font(.caption).foregroundStyle(Theme.inkSoft)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
