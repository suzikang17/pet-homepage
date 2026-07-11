// ios/PetHomepage/DesignSystem/Theme.swift
// Bold & distinctive design system: an electric-violet brand with rounded, heavy
// type, gradient hero headers, and soft elevated cards. Shared across every screen.
import SwiftUI
import UIKit

enum Theme {
    // Brand palette. The violet/coral brand colors read well on both appearances; the
    // neutrals (bg/card/ink/inkSoft) are adaptive so dark mode gets a navy-violet dark
    // surface instead of near-black text on system-dark fills.
    static let primary = Color(hex: 0x6C4CF1)   // electric indigo-violet
    static let primary2 = Color(hex: 0x9B5CF6)  // lighter violet (gradient end)
    static let accent = Color(hex: 0xFF6B5C)    // warm coral
    static let bg = Color(light: 0xF4F3FA, dark: 0x14121F)      // app background
    static let card = Color(light: 0xFFFFFF, dark: 0x211E33)    // elevated card surface
    static let ink = Color(light: 0x16142A, dark: 0xEEECF8)     // primary text
    static let inkSoft = Color(light: 0x6E6A86, dark: 0x9E9AB8) // secondary text
    /// Shadow tint: always the dark navy. (Shadows must NOT track `ink` — an adaptive ink
    /// would render light-colored "glow" shadows in dark mode.)
    static let shadow = Color(hex: 0x16142A)

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

    /// A dynamic color that resolves to `light` or `dark` per the current appearance.
    init(light: UInt, dark: UInt) {
        self.init(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

// MARK: - Reusable components

/// Gradient hero header that fills the top of a screen — replaces the empty
/// space above a default large title and gives each screen a bold identity.
struct HeroHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String = "pawprint.fill"
    var avatar: Image? = nil
    /// When set, the photo fills the whole header (with a legibility scrim) instead of the gradient.
    var backgroundImage: Image? = nil
    var onTapAvatar: (() -> Void)? = nil
    /// When provided, the subtitle becomes an inline editable field (placeholder = `subtitle`).
    var editableSubtitle: Binding<String>? = nil
    var onAdd: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    /// SF Symbol for the settings/manage button (defaults to the gear). Override to disambiguate
    /// when a screen's "settings" action isn't app Settings (e.g. Timeline → manage activity types).
    var settingsSymbol: String = "gearshape.fill"

    private var hasPhotoBackground: Bool { backgroundImage != nil }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let backgroundImage {
                GeometryReader { geo in
                    backgroundImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                LinearGradient(
                    colors: [.black.opacity(0.05), .black.opacity(0.15), .black.opacity(0.65)],
                    startPoint: .top, endPoint: .bottom
                )
            } else {
                Theme.brandGradient
            }
            VStack(alignment: .leading, spacing: 12) {
                if !hasPhotoBackground { avatarView }
                VStack(alignment: .leading, spacing: 2) {
                    if let editableSubtitle {
                        ZStack(alignment: .leading) {
                            if editableSubtitle.wrappedValue.isEmpty {
                                Text(subtitle ?? "").foregroundStyle(.white.opacity(0.55))
                            }
                            TextField("", text: editableSubtitle)
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .tint(.white)
                        .lineLimit(1)
                        .submitLabel(.done)
                    } else if let subtitle {
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
        .frame(height: hasPhotoBackground ? 260 : 200)
        .overlay(alignment: .topLeading) {
            if hasPhotoBackground, let onTapAvatar {
                heroIconButton("camera.fill", action: onTapAvatar)
                    .padding(.leading, 20)
                    .padding(.top, 62)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 12) {
                if let onSettings {
                    heroIconButton(settingsSymbol, action: onSettings)
                }
                if let onAdd {
                    heroIconButton("plus", action: onAdd)
                }
            }
            .padding(.trailing, 20)
            .padding(.top, 62)
        }
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
        .shadow(color: Theme.primary.opacity(0.25), radius: 16, y: 8)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let onTapAvatar {
            Button(action: onTapAvatar) { avatarBadge }.buttonStyle(.plain)
                .accessibilityIdentifier("heroAvatarButton")
        } else {
            avatarCircle
        }
    }

    private var avatarBadge: some View {
        avatarCircle.overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 22, height: 22)
                .background(.white, in: Circle())
                .offset(x: 4, y: 4)
        }
    }

    @ViewBuilder
    private var avatarCircle: some View {
        if let avatar {
            avatar.resizable().scaledToFill()
                .frame(width: 62, height: 62)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
        } else {
            ZStack {
                Circle().fill(.white.opacity(0.22)).frame(width: 62, height: 62)
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func heroIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 42, height: 42)
                .background(.white, in: Circle())
                .shadow(color: Theme.shadow.opacity(0.18), radius: 8, y: 3)
        }
    }
}

/// Soft elevated white card.
struct BrandCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: Theme.shadow.opacity(0.06), radius: 14, y: 6)
    }
}

extension View {
    /// Consistent brand treatment for the Form-based add/edit sheets: cream background, violet
    /// accent, prominent section headers, and a drag handle. The nav bar is left to blend with
    /// the cream sheet — a colored bar clashes with iOS 26's capsule toolbar buttons.
    func brandSheet() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.primary)
            .headerProminence(.increased)
            .presentationDragIndicator(.visible)
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
            // No pinned action bar when there's no action (e.g. the dashboard Home).
            if Action.self != EmptyView.self {
                action
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                    .background(.ultraThinMaterial)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension BrandScreen where Action == EmptyView {
    /// A scrolling brand screen with no pinned bottom action bar.
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.action = EmptyView()
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
            .shadow(color: Theme.shadow.opacity(0.05), radius: 10, y: 4)
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
