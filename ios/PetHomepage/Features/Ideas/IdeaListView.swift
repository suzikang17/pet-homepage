// ios/PetHomepage/Features/Ideas/IdeaListView.swift
import SwiftUI

/// The idea scratchpad, shared by both entry points: the shake gesture presents it in a sheet,
/// Settings pushes it onto the settings stack.
///
/// It must not assume it is presented modally — it owns no dismiss affordance and no
/// `NavigationStack`. The presenting side supplies both.
struct IdeaListView: View {
    let store: IdeaStore
    /// Tab the user was on; stamped onto new ideas. nil from the Settings entry.
    var screen: String?

    @State private var draft = ""
    @State private var ideas: [Idea] = []
    @State private var saveError: String?
    @FocusState private var draftFocused: Bool

    private var draftIsBlank: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    // Not `axis: .vertical` — a multiline field swallows Return as a newline
                    // instead of firing onSubmit, and submit-on-return is the whole point.
                    TextField("Jot an idea…", text: $draft)
                        .focused($draftFocused)
                        .onSubmit(save)
                        .submitLabel(.done)
                        .foregroundStyle(Theme.ink)
                        .accessibilityIdentifier("idea.field")
                    Button(action: save) {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(draftIsBlank ? Theme.inkSoft : Theme.primary)
                    .disabled(draftIsBlank)
                    .accessibilityIdentifier("idea.add")
                }
            }

            Section {
                ForEach(ideas) { idea in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(idea.text)
                            .font(Theme.body())
                            .foregroundStyle(Theme.ink)
                        Text(subtitle(for: idea))
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: delete)
            } header: {
                Text(ideas.isEmpty ? "Nothing captured yet" : "\(ideas.count) captured")
            }
        }
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: store.markdownExport()) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(ideas.isEmpty)
                .accessibilityIdentifier("idea.share")
            }
        }
        .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear {
            ideas = store.ideas()
            draftFocused = true
        }
    }

    private func subtitle(for idea: Idea) -> String {
        let stamp = idea.createdAt.formatted(date: .abbreviated, time: .shortened)
        guard let screen = idea.screen else { return stamp }
        return "\(screen) · \(stamp)"
    }

    private func save() {
        guard !draftIsBlank else { return }
        do {
            _ = try store.add(text: draft, screen: screen)
            draft = ""
            ideas = store.ideas()
            draftFocused = true
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        do {
            for index in offsets { try store.delete(ideas[index]) }
            ideas = store.ideas()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
