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
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    HStack(spacing: 14) {
                        currentAvatarPreview

                        VStack(alignment: .leading, spacing: 5) {
                            Text("选择头像")
                                .font(.title3.bold())
                            Text("换个头像，换个心情！")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.headline)
                            Text("从相册选择")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .opacity(0.55)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 48)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.53, green: 0.78, blue: 0.97),
                                    Color(red: 0.70, green: 0.62, blue: 0.98)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(.horizontal, 18)
                    .onChange(of: selectedPhoto) { newItem in
                        handlePhotoSelection(newItem)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("预设头像")
                            .font(.headline)
                            .padding(.horizontal, 2)

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(AvatarPresetCatalog.imageAssetNames, id: \.self) { assetName in
                                presetImageButton(assetName)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("头像")
                        .font(.headline)
                }
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
            PresetAvatarCircle(presetId: id, size: 72)
        case .custom:
            if let uiImage = profileStore.loadAvatarImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(Circle())
            } else {
                PresetAvatarCircle(presetId: AvatarPresetCatalog.defaultId, size: 72)
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
                .frame(width: 58, height: 58)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                        .padding(-3)
                )
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
