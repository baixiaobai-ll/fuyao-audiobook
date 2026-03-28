import SwiftUI

// MARK: - Glass Icon Button

struct GlassIconButton: View {
    let title: String
    let icon: String
    var action: () -> Void = {}

    @State private var isPressed = false

    private let blueLight = Color(red: 0.45, green: 0.68, blue: 0.98)
    private let blueDark = Color(red: 0.22, green: 0.42, blue: 0.78)
    private let purpleHint = Color(red: 0.55, green: 0.48, blue: 0.95)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [blueLight, blueDark],
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
                    .foregroundColor(Color(white: 0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)

                    LinearGradient(
                        colors: [
                            blueLight.opacity(0.08),
                            purpleHint.opacity(0.04),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    RoundedRectangle(cornerRadius: 12)
                        .stroke(blueLight.opacity(0.45), lineWidth: 1)
                }
            )
            .shadow(color: blueDark.opacity(0.08), radius: 4, x: 0, y: 2)
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

// MARK: - Section Header

struct FuyaoSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .foregroundColor(AppTheme.Colors.textPrimary)
    }
}
