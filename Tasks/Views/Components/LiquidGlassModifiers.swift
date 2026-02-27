import SwiftUI

// MARK: - Liquid Glass Material (compatible con macOS 15+, usa .liquidGlass en Tahoe)
extension ShapeStyle where Self == Material {
    static var liquidGlassApp: Material {
        if #available(macOS 26.0, *) {
            return .liquidGlass
        }
        return .ultraThinMaterial
    }

    static var liquidGlassAppThin: Material {
        if #available(macOS 26.0, *) {
            return .liquidGlassThin
        }
        return .thinMaterial
    }

    static var liquidGlassAppThick: Material {
        if #available(macOS 26.0, *) {
            return .liquidGlassThick
        }
        return .regularMaterial
    }
}

// MARK: - Modificadores Liquid Glass minimalistas
struct LiquidGlassBackground: ViewModifier {
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.liquidGlassApp, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .background(.liquidGlassAppThin, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func liquidGlassBackground(cornerRadius: CGFloat = 16, padding: CGFloat = 0) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius, padding: padding))
    }

    func liquidGlassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius))
    }
}
