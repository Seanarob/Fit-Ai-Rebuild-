import SwiftUI

enum VoiceLogTokens {
    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
    }
    
    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 22
    }
    
    enum Color {
        static let background = FitTheme.backgroundGradient
        static let card = FitTheme.cardBackground
        static let stroke = FitTheme.cardStroke
        static let textPrimary = FitTheme.textPrimary
        static let textSecondary = FitTheme.textSecondary
        static let accent = FitTheme.accent
        static let accentSoft = FitTheme.accentSoft
        static let success = FitTheme.success
    }
    
    enum Typography {
        static func title(_ size: CGFloat) -> Font { FitFont.heading(size: size) }
        static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { FitFont.body(size: size, weight: weight) }
    }
}

