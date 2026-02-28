import SwiftUI

// MARK: - Liquid Glass Material (compatible con macOS 15+, usa .liquidGlass en Tahoe cuando esté disponible)
extension ShapeStyle where Self == Material {
    static var liquidGlassApp: Material { .ultraThinMaterial }
    static var liquidGlassAppThin: Material { .thinMaterial }
    static var liquidGlassAppThick: Material { .regularMaterial }
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

struct LiquidGlassSubtaskCard: ViewModifier {
    var cornerRadius: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .background(.liquidGlassAppThick, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

extension View {
    func liquidGlassBackground(cornerRadius: CGFloat = 16, padding: CGFloat = 0) -> some View {
        modifier(LiquidGlassBackground(cornerRadius: cornerRadius, padding: padding))
    }

    func liquidGlassCard(cornerRadius: CGFloat = 12) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius))
    }

    func liquidGlassSubtaskCard(cornerRadius: CGFloat = 6) -> some View {
        modifier(LiquidGlassSubtaskCard(cornerRadius: cornerRadius))
    }
}
