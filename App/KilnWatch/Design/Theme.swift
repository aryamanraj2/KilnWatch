import SwiftUI

// Colors live in Assets.xcassets and are reached through the generated symbols
// (`.canvas`, `.surface`, `.ink`, `.clay`, `.flagged` …). See docs/DESIGN.md.

/// 4 pt grid. Only these values are used for padding and spacing.
enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48

    /// Screen margin.
    static let margin = l
    /// Card padding.
    static let card = m
}

enum Radius {
    static let card: CGFloat = 20
    static let inner: CGFloat = 12
}

/// Motion tokens. Every token falls back to a 0.2 s opacity-only ease under Reduce Motion;
/// call sites also drop any scale or offset when `reduceMotion` is on.
enum Motion {
    case select, layout, confirm

    func animation(reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        switch self {
        case .select: return .snappy(duration: 0.28)
        case .layout: return .smooth(duration: 0.42)
        case .confirm: return .spring(duration: 0.5, bounce: 0.18)
        }
    }

    /// 0.04 s per item, capped at 6 items.
    static func stagger(_ index: Int) -> Double { Double(min(index, 6)) * 0.04 }
}

extension View {
    /// Section eyebrow: the only uppercase text in the app.
    func eyebrow() -> some View {
        font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.inkSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// Solid content-layer card. Hairline stroke in light mode only; shadow only when floating over the map.
    func card(floating: Bool = false) -> some View {
        modifier(CardModifier(floating: floating))
    }
}

private struct CardModifier: ViewModifier {
    let floating: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(Space.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.surface, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(.hairline, lineWidth: 0.5)
                }
            }
            .containerShape(.rect(cornerRadius: Radius.card, style: .continuous))
            .shadow(color: .black.opacity(floating ? 0.08 : 0), radius: 12, y: 4)
    }
}

/// Inner wells and tiles nested inside a card or sheet: concentric corners, 12 pt minimum.
extension Shape where Self == ConcentricRectangle {
    static var inner: ConcentricRectangle {
        ConcentricRectangle(corners: .concentric(minimum: .fixed(Radius.inner)), isUniform: true)
    }
}

/// Primary action: ink fill, canvas label. Secondary: surface2 fill, ink label.
struct FilledButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Space.m)
            .foregroundStyle(prominent ? Color.canvas : Color.ink)
            .background(prominent ? Color.ink : Color.surface2, in: .capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(.capsule)
    }
}

extension ButtonStyle where Self == FilledButtonStyle {
    static var primary: FilledButtonStyle { FilledButtonStyle() }
    static var secondary: FilledButtonStyle { FilledButtonStyle(prominent: false) }
}

extension Int {
    /// "6,240" — grouping per the current locale.
    var grouped: String { formatted(.number) }
}
