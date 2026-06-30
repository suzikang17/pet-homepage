// ios/PetHomepage/Features/Activities/ActivityTypesView.swift
import SwiftUI

struct ActivityTypesView: View {
    @State private var model: ActivityTypesViewModel

    init(store: ActivityStore) {
        _model = State(initialValue: ActivityTypesViewModel(store: store))
    }

    var body: some View {
        List {
            ForEach(ActivityCategory.allCases) { category in
                let typesInCategory = model.types.filter { $0.category == category }
                if !typesInCategory.isEmpty {
                    Section(category.displayName) {
                        ForEach(typesInCategory) { type in
                            HStack {
                                Label(type.name, systemImage: type.iconName)
                                Spacer()
                                Text(type.defaultIntervalDays > 0 ? "every \(type.defaultIntervalDays)d" : "no repeat")
                                    .font(.caption).foregroundStyle(Theme.inkSoft)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { model.archive(type) } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Activity types")
        .brandSheet()
        .onAppear { model.reload() }
    }
}
