import SwiftUI
import PhotosUI

struct AvatarPickerView: View {
    @EnvironmentObject var profileStore: UserProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?

    // 预设头像配置
    private let presets: [(symbol: String, color: Color)] = [
        ("person.fill", .blue),
        ("star.fill", .orange),
        ("heart.fill", .pink),
        ("leaf.fill", .green),
        ("flame.fill", .red),
        ("book.fill", .purple),
        ("music.note", .teal),
        ("gamecontroller.fill", .indigo),
    ]

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 当前头像预览
                currentAvatarPreview
                    .padding(.top, 24)

                // 预设头像网格
                VStack(alignment: .leading, spacing: 12) {
                    Text("选择预设头像")
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(presets, id: \.symbol) { preset in
                            presetButton(preset)
                        }
                    }
                    .padding(.horizontal)
                }

                Divider()
                    .padding(.horizontal)

                // 从相册选择
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("从相册选择")
                    }
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .onChange(of: selectedPhoto) { newItem in
                    handlePhotoSelection(newItem)
                }

                Spacer()
            }
            .navigationTitle("更换头像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - Current Avatar Preview

    @ViewBuilder
    private var currentAvatarPreview: some View {
        switch profileStore.avatarSource {
        case .preset(let symbol):
            let color = presets.first(where: { $0.symbol == symbol })?.color ?? .blue
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundColor(.white)
                .frame(width: 80, height: 80)
                .background(color)
                .clipShape(Circle())
        case .custom:
            if let uiImage = profileStore.loadAvatarImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.white)
                    .frame(width: 80, height: 80)
                    .background(Color.blue)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Preset Button

    private func presetButton(_ preset: (symbol: String, color: Color)) -> some View {
        let isSelected = profileStore.avatarSource == .preset(preset.symbol)
        return Button {
            profileStore.updateAvatar(preset: preset.symbol)
        } label: {
            Image(systemName: preset.symbol)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(preset.color)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                        .padding(-3)
                )
        }
    }

    // MARK: - Photo Selection

    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        item.loadTransferable(type: Data.self) { result in
            switch result {
            case .success(let data):
                if let data, let uiImage = UIImage(data: data) {
                    let cropped = Self.cropToSquare(uiImage)
                    Task { @MainActor in
                        profileStore.updateAvatar(image: cropped)
                    }
                }
            case .failure:
                break
            }
        }
    }

    private nonisolated static func cropToSquare(_ image: UIImage) -> UIImage {
        let size = min(image.size.width, image.size.height)
        let x = (image.size.width - size) / 2
        let y = (image.size.height - size) / 2
        let cropRect = CGRect(x: x, y: y, width: size, height: size)

        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
