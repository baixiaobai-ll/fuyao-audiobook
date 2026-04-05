import SwiftUI

// MARK: - Surface Card

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 16
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color(red: 0.94, green: 0.97, blue: 1.0).opacity(0.58),
                                Color(red: 0.86, green: 0.84, blue: 1.0).opacity(0.18),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.52), lineWidth: 1)
                    )
            )
            .shadow(color: Color(red: 0.41, green: 0.53, blue: 0.76).opacity(0.08), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Capsule Tag

struct CapsuleInfoTag: View {
    let title: String
    var icon: String? = nil
    var tint: Color = AppTheme.Colors.brandPrimary

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.semibold))
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.16),
                            Color.white.opacity(0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - Press Style

struct LiftPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

// MARK: - Glass Icon Button

struct GlassIconButton: View {
    let title: String
    let icon: String
    var action: () -> Void = {}

    @State private var isPressed = false

    private let blueLight = Color(red: 0.53, green: 0.78, blue: 0.97)
    private let purpleGlow = Color(red: 0.70, green: 0.62, blue: 0.98)
    private let blueDark = Color(red: 0.35, green: 0.47, blue: 0.83)
    private let purpleDark = Color(red: 0.49, green: 0.42, blue: 0.86)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [blueLight, purpleGlow, blueDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Color(red: 0.28, green: 0.30, blue: 0.46))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)

                    LinearGradient(
                        colors: [
                            blueLight.opacity(0.14),
                            purpleGlow.opacity(0.14),
                            Color.white.opacity(0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.72),
                                    purpleGlow.opacity(0.36),
                                    blueLight.opacity(0.28)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: purpleDark.opacity(0.14), radius: 10, x: 0, y: 4)
        }
        .scaleEffect(isPressed ? 0.96 : 1.0)
        .animation(AppTheme.Animation.quick, value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Gradient Button

struct GradientButton: View {
    let title: String
    let icon: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(AppTheme.Colors.brandGradient)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.CornerRadius.medium))
                .elevatedShadow()
        }
    }
}

// MARK: - Tinted Icon Badge

struct TintedIconBadge: View {
    let icon: String
    var size: CGFloat = 36
    var iconSize: CGFloat = 15
    var primary: Color = AppTheme.Colors.brandPrimary
    var secondary: Color = AppTheme.Colors.brandAccent

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [primary, secondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .padding(1.5)
                )

            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: secondary.opacity(0.18), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Soft Section Header

struct SoftSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(AppTheme.Colors.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }
}

// MARK: - Section Header

struct FuyaoSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundColor(AppTheme.Colors.textPrimary)
    }
}
