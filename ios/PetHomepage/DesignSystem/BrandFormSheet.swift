// ios/PetHomepage/DesignSystem/BrandFormSheet.swift
import SwiftUI

/// Compact gradient header for modal sheets: a title (+ optional icon) with a leading Cancel and
/// an optional trailing confirm action. Sizes to its content — the gradient is a background, not
/// a greedy layer — so it stays a slim strip.
struct SheetHeader: View {
    let title: String
    var systemImage: String? = nil
    var confirmTitle: String = "Save"
    var confirmDisabled: Bool = false
    let onCancel: () -> Void
    var onConfirm: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundStyle(.white.opacity(0.95))
                Spacer()
                if let onConfirm {
                    Button(action: onConfirm) {
                        Text(confirmTitle).fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .disabled(confirmDisabled)
                    .opacity(confirmDisabled ? 0.45 : 1)
                }
            }
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage).font(.title3)
                }
                Text(title).font(Theme.title(26))
                Spacer()
            }
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(Theme.brandGradient)
        .clipShape(.rect(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous))
        .shadow(color: Theme.primary.opacity(0.25), radius: 14, y: 6)
    }
}

/// A modal scaffold for the add/edit sheets: a gradient SheetHeader above a cream Form body.
/// Pass the Form's sections in the trailing `content` builder.
struct BrandFormSheet<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var confirmTitle: String = "Save"
    var confirmDisabled: Bool = false
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SheetHeader(title: title, systemImage: systemImage,
                            confirmTitle: confirmTitle, confirmDisabled: confirmDisabled,
                            onCancel: onCancel, onConfirm: onConfirm)
                Form { content }
                    .scrollContentBackground(.hidden)
                    .headerProminence(.increased)
            }
            .background(Theme.bg)
            .tint(Theme.primary)
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea(edges: .top)
        }
        .presentationDragIndicator(.hidden)
    }
}
