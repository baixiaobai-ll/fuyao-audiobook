import SwiftUI

/// 展示预设头像：优先 `avatar_preset_*` 资源图，否则回退 SF Symbol（兼容旧数据）
struct PresetAvatarCircle: View {
    let presetId: String
    var size: CGFloat

    private static let legacyColors: [String: Color] = [
        "person.fill": .blue,
        "star.fill": .orange,
        "heart.fill": .pink,
        "leaf.fill": .green,
        "flame.fill": .red,
        "book.fill": .purple,
        "music.note": .teal,
        "gamecontroller.fill": .indigo
    ]

    var body: some View {
        if presetId.hasPrefix("avatar_preset_") {
            Image(presetId)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            let color = Self.legacyColors[presetId] ?? .blue
            Image(systemName: presetId)
                .font(.system(size: size * 0.45))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(color)
                .clipShape(Circle())
        }
    }
}
