// ios/PetHomepage/DesignSystem/Theme.swift
// Bold & distinctive design system: an electric-violet brand with rounded, heavy
// type, gradient hero headers, and soft elevated cards. Shared across every screen.
import SwiftUI

enum Theme {
    // Brand palette
    static let primary = Color(hex: 0x6C4CF1)   // electric indigo-violet
    static let primary2 = Color(hex: 0x9B5CF6)  // lighter violet (gradient end)
    static let accent = Color(hex: 0xFF6B5C)    // warm coral
    static let bg = Color(hex: 0xF4F3FA)         // app background
    static let card = Color.white
    static let ink = Color(hex: 0x16142A)        // near-black navy
    static let inkSoft = Color(hex: 0x6E6A86)    // secondary text

    // Status colors
    static let ok = Color(hex: 0x12B886)
    static let warn = Color(hex: 0xF59E0B)
    static let danger = Color(hex: 0xEF4444)

    static let brandGradient = LinearGradient(
        colors: [primary, primary2], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Fonts
    static func title(_ size: CGFloat = 32) -> Font { .system(size: size, weight: .heavy, design: .rounded) }
    static func headline() -> Font { .system(.headline, design: .rounded).weight(.bold) }
    static func body() -> Font { .system(.body, design: .rounded) }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Reusable components

/// Gradient hero header that fills the top of a screen — replaces the empty
/// space above a default large title and gives each screen a bold identity.
struct HeroHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String = "pawprint.fill"
    var onAdd: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.brandGradient
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.22)).frame(width: 62, height: 62)
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let subtitle {
                        Text(subtitle.uppercased())
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .tracking(1.6)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Text(title)
                        .font(Theme.title(34))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .padding(22)
            .padding(.top, 56) // clear the status bar (header bleeds to the top edge)
        }
        .frame(height: 200)
        .overlay(alignment: .topTrailing) {
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 42, height: 42)
                        .background(.white, in: Circle())
                        .shadow(color: Theme.ink.opacity(0.18), radius: 8, y: 3)
                }
                .padding(.trailing, 20)
                .padding(.top, 62)
            }
        }
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
        .shadow(color: Theme.primary.opacity(0.25), radius: 16, y: 8)
    }
}

/// Soft elevated white card.
struct BrandCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.06), radius: 14, y: 6)
    }
}

/// A label + trailing control row, used inside cards.
struct FieldRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(label).font(Theme.body().weight(.semibold)).foregroundStyle(Theme.ink)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.vertical, 12)
    }
}

/// Bold full-width primary button.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.headline())
            .foregroundStyle(.white)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity)
            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: Theme.primary.opacity(isEnabled ? 0.35 : 0), radius: 14, y: 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A screen wrapper: brand background + a bottom-pinned action bar that floats
/// above the (iOS 26 floating) tab bar via safeAreaInset.
struct BrandScreen<Content: View, Action: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var action: Action
    var body: some View {
        ScrollView {
            VStack(spacing: 18) { content }
                .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) {
            action
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(.ultraThinMaterial)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A List styled as the brand: a gradient hero header (with an optional add
/// button), brand background, and rows you style with `.brandRow()`. Stays a
/// List, so swipe actions and NavigationLinks keep working.
struct BrandList<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String = "pawprint.fill"
    var onAdd: (() -> Void)? = nil
    @ViewBuilder var content: Content

    var body: some View {
        List {
            HeroHeader(title: title, subtitle: subtitle, systemImage: systemImage, onAdd: onAdd)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .padding(.bottom, 6)
            content
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension View {
    /// Styles a List row as a floating white brand card.
    func brandRow() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.05), radius: 10, y: 4)
            .listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// An uppercased section label for use between brand cards.
struct BrandSectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption, design: .rounded).weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 8, leading: 22, bottom: 2, trailing: 18))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
