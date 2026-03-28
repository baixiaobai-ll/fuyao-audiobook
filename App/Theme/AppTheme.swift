import SwiftUI

enum AppTheme {

    // MARK: - Colors

    enum Colors {
        static let brandPrimary = Color("BrandPrimary")
        static let brandSecondary = Color("BrandSecondary")
        static let brandAccent = Color("BrandAccent")

        static let backgroundPrimary = Color("BackgroundPrimary")
        static let backgroundSecondary = Color("BackgroundSecondary")
        static let backgroundElevated = Color("BackgroundElevated")

        static let textPrimary = Color("TextPrimary")
        static let textSecondary = Color("TextSecondary")

        static let divider = Color("AppDivider")

        static let brandGradient = LinearGradient(
            colors: [brandPrimary, brandAccent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    enum CornerRadius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let pill: CGFloat = 50
    }

    // MARK: - Shadow

    enum Shadow {
        static func elevated() -> some ViewModifier {
            ElevatedShadow()
        }
    }

    // MARK: - Animation

    enum Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let smooth = SwiftUI.Animation.easeInOut(duration: 0.35)
        static let breathe = SwiftUI.Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
    }
}

// MARK: - View Modifiers

struct ElevatedShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func elevatedShadow() -> some View {
        modifier(ElevatedShadow())
    }
}
