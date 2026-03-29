import SwiftUI
import PhotosUI

struct AvatarPickerView: View {
    @EnvironmentObject var profileStore: UserProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                currentAvatarPreview
                    .padding(.top, 24)

                VStack(alignment: .leading, spacing: 12) {
                    Text("选择预设头像")
                        .font(.headline)
                        .padding(.horizontal)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(AvatarPresetCatalog.imageAssetNames, id: \.self) { assetName in
                            presetImageButton(assetName)
                        }
                    }
                    .padding(.horizontal)
                }

                Divider()
                    .padding(.horizontal)

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

    // MARK: - Preview

    @ViewBuilder
    private var currentAvatarPreview: some View {
        switch profileStore.avatarSource {
        case .preset(let id):
            PresetAvatarCircle(presetId: id, size: 80)
        case .custom:
            if let uiImage = profileStore.loadAvatarImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                PresetAvatarCircle(presetId: AvatarPresetCatalog.defaultId, size: 80)
            }
        }
    }

    private func presetImageButton(_ assetName: String) -> some View {
        let isSelected = profileStore.avatarSource == .preset(assetName)
        return Button {
            profileStore.updateAvatar(preset: assetName)
        } label: {
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                        .padding(-3)
                )
        }
    }

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
