// ios/PetHomepage/DesignSystem/Theme.swift
// Bold & distinctive design system: a friendly-yellow brand with rounded, heavy
// type, gradient hero headers, and soft elevated cards. Shared across every screen.
import SwiftUI
import UIKit

enum Theme {
    // Brand palette. Yellow is a *light* hue, so unlike the previous violet it cannot do
    // both brand jobs at once — it is too pale to carry white text, and too pale to read
    // as colored text on a white card. The brand is therefore split into three tokens:
    //
    //   primary     — the yellow itself. Use for FILLS: buttons, gradients, selected chips.
    //   onBrand     — dark warm charcoal. Use for TEXT/ICONS drawn ON a primary fill.
    //   primaryDeep — deep amber. Use for TEXT/ICONS that need to look "brand-colored"
    //                 while sitting on a light surface (card, cream bg).
    //
    // The neutrals (bg/card/ink/inkSoft) stay adaptive so dark mode gets a warm brown-black
    // surface instead of near-black text on system-dark fills.
    static let primary = Color(hex: 0xFFC53D)     // friendly golden yellow (fills)
    static let primary2 = Color(hex: 0xFFDE73)    // lighter sunny yellow (gradient end)
    static let primaryDeep = Color(hex: 0x8F6200) // deep amber — brand color on light surfaces
    static let onBrand = Color(hex: 0x3D2E12)     // warm charcoal — content on a yellow fill
    static let accent = Color(hex: 0xFF7A5C)      // warm coral
    static let bg = Color(light: 0xFDF8EC, dark: 0x1B1710)      // app background
    static let card = Color(light: 0xFFFFFF, dark: 0x2A2419)    // elevated card surface
    static let ink = Color(light: 0x2A2113, dark: 0xF3EDE0)     // primary text
    static let inkSoft = Color(light: 0x7C6F57, dark: 0xB0A48C) // secondary text
    /// Shadow tint: always the warm dark brown. (Shadows must NOT track `ink` — an adaptive
    /// ink would render light-colored "glow" shadows in dark mode.)
    static let shadow = Color(hex: 0x2A2113)

    // Status colors. `warn` is pushed to a vivid orange so it stays distinguishable from
    // the yellow brand fill — the old amber was nearly identical to `primary`.
    static let ok = Color(hex: 0x12B886)
    static let warn = Color(hex: 0xF97316)
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
    /// When set, "+" opens a MENU instead of firing `onAdd` (which is then ignored). `AnyView`
    /// rather than a generic parameter so every existing call site stays source-compatible — a
    /// header button's menu is not worth a type parameter on a view this widely used.
    var addMenu: AnyView? = nil
    var onSettings: (() -> Void)? = nil
    /// SF Symbol for the settings/manage button (defaults to the gear). Override to disambiguate
    /// when a screen's "settings" action isn't app Settings (e.g. Timeline → manage activity types).
    var settingsSymbol: String = "gearshape.fill"

    private var hasPhotoBackground: Bool { backgroundImage != nil }

    /// Photo headers keep white text (they sit on a dark scrim); the yellow brand gradient
    /// needs dark text instead.
    private var onHero: Color { hasPhotoBackground ? .white : Theme.onBrand }

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
                                Text(subtitle ?? "").foregroundStyle(onHero.opacity(0.55))
                            }
                            TextField("", text: editableSubtitle)
                        }
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(onHero)
                        .tint(onHero)
                        .lineLimit(1)
                        .submitLabel(.done)
                    } else if let subtitle {
                        Text(subtitle.uppercased())
                            .font(.system(.caption, design: .rounded).weight(.heavy))
                            .tracking(1.6)
                            .foregroundStyle(onHero.opacity(0.85))
                    }
                    Text(title)
                        .font(Theme.title(34))
                        .foregroundStyle(onHero)
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
                if let addMenu {
                    Menu { addMenu } label: { heroIconLabel("plus") }
                        .accessibilityLabel("Add")
                        .accessibilityIdentifier("heroAddButton")
                } else if let onAdd {
                    heroIconButton("plus", action: onAdd)
                        .accessibilityIdentifier("heroAddButton")
                }
            }
            .padding(.trailing, 20)
            .padding(.top, 62)
        }
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
        .shadow(color: Theme.shadow.opacity(0.18), radius: 16, y: 8)
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
                .foregroundStyle(Theme.onBrand)
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
                .overlay(Circle().stroke(onHero.opacity(0.7), lineWidth: 2))
        } else {
            ZStack {
                Circle().fill(onHero.opacity(0.18)).frame(width: 62, height: 62)
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(onHero)
            }
        }
    }

    private func heroIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { heroIconLabel(systemName) }
    }

    private func heroIconLabel(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.onBrand)
            .frame(width: 42, height: 42)
            .background(.white, in: Circle())
            .shadow(color: Theme.shadow.opacity(0.18), radius: 8, y: 3)
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
    /// Consistent brand treatment for the Form-based add/edit sheets: cream background, amber
    /// accent, prominent section headers, and a drag handle. The nav bar is left to blend with
    /// the cream sheet — a colored bar clashes with iOS 26's capsule toolbar buttons.
    /// Tint is `primaryDeep`, not `primary`: tint colors interactive *labels*, and the yellow
    /// would be unreadable as text on the cream sheet.
    func brandSheet() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.primaryDeep)
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
            .foregroundStyle(Theme.onBrand)
            .padding(.vertical, 17)
            .frame(maxWidth: .infinity)
            .background(Theme.brandGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(color: Theme.shadow.opacity(isEnabled ? 0.22 : 0), radius: 14, y: 8)
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
