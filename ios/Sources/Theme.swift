import SwiftUI

/// The app's own palette, matching the web interface so an instance looks like
/// one product across both. Blue-biased neutrals rather than pure greys.
enum Palette {
    static let base = Color.dyn(0xF4F7F9, 0x090D11)
    static let surface = Color.dyn(0xFFFFFF, 0x121A20)
    static let surface2 = Color.dyn(0xE8EEF2, 0x1A242C)

    static let textPrimary = Color.dyn(0x0C1418, 0xE7EFF3)
    static let textSecondary = Color.dyn(0x41525B, 0xA9BAC4)
    static let textTertiary = Color.dyn(0x6D818C, 0x788C97)

    static let hairline = Color.dynA(0x0C1418, 0.10, 0xFFFFFF, 0.09)
    static let accent = Color.dyn(0x0A6C9E, 0x4CB8E8)
    static let onAccent = Color.dyn(0xFFFFFF, 0x061318)
    static let success = Color.dyn(0x1C6748, 0x6FC79F)
    static let warning = Color.dyn(0x8A5A12, 0xD9AB63)
    static let danger = Color.dyn(0x8A3D33, 0xE08E80)
}

enum Metric {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 18
    static let xl: CGFloat = 26
    static let card: CGFloat = 12
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha)
    }

    /// Resolves per trait collection rather than per launch, so the app follows
    /// the system theme while it is running instead of only at startup.
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
    }

    static func dynA(_ light: UInt32, _ la: Double, _ dark: UInt32, _ da: Double) -> Color {
        Color(UIColor {
            $0.userInterfaceStyle == .dark
                ? UIColor(Color(hex: dark, alpha: da))
                : UIColor(Color(hex: light, alpha: la))
        })
    }
}

extension View {
    func card(radius: CGFloat = Metric.card) -> some View {
        background(Palette.surface, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            }
    }

    func plainRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Palette.accent, in: .rect(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Palette.surface2, in: .rect(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct Tag: View {
    let text: String
    var tint: Color = Palette.accent

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: .rect(cornerRadius: 5))
    }
}
