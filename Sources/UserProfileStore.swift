import SwiftUI
import UIKit

// MARK: - AvatarSource

enum AvatarSource: Codable, Equatable {
    case preset(String)   // SF Symbol 名
    case custom(String)   // Documents/UserAvatar/ 下的文件名

    private enum CodingKeys: String, CodingKey {
        case type, value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preset(let name):
            try container.encode("preset", forKey: .type)
            try container.encode(name, forKey: .value)
        case .custom(let path):
            try container.encode("custom", forKey: .type)
            try container.encode(path, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let value = try container.decode(String.self, forKey: .value)
        switch type {
        case "preset":
            self = .preset(value)
        case "custom":
            self = .custom(value)
        default:
            self = .preset("person.fill")
        }
    }
}

// MARK: - UserProfile

private struct UserProfile: Codable {
    var isLoggedIn: Bool = false
    var phone: String = ""
    var nickname: String = ""
    var avatarSource: AvatarSource = .preset("person.fill")
}

// MARK: - UserProfileStore

@MainActor
final class UserProfileStore: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var phone: String = ""
    @Published var nickname: String = ""
    @Published var avatarSource: AvatarSource = .preset("person.fill")

    private static let storageKey = "userprofile_data"

    private static var avatarDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("UserAvatar")
    }

    init() {
        load()
    }

    // MARK: - Login / Logout

    func login(phone: String) {
        self.isLoggedIn = true
        self.phone = phone
        self.nickname = "书友\(String(phone.suffix(4)))"
        self.avatarSource = .preset("person.fill")
        save()
    }

    func logout() {
        isLoggedIn = false
        phone = ""
        nickname = ""
        avatarSource = .preset("person.fill")
        save()
    }

    // MARK: - Update

    func updateNickname(_ name: String) {
        nickname = name
        save()
    }

    func updateAvatar(image: UIImage) {
        let fm = FileManager.default
        let dir = Self.avatarDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileName = "avatar.jpg"
        let fileURL = dir.appendingPathComponent(fileName)

        // 压缩并保存
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
            avatarSource = .custom(fileName)
            save()
        }
    }

    func updateAvatar(preset: String) {
        avatarSource = .preset(preset)
        save()
    }

    func loadAvatarImage() -> UIImage? {
        guard case .custom(let fileName) = avatarSource else { return nil }
        let fileURL = Self.avatarDirectory.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: fileURL.path)
    }

    // MARK: - Masked Phone

    var maskedPhone: String {
        guard phone.count == 11 else { return phone }
        let prefix = phone.prefix(3)
        let suffix = phone.suffix(4)
        return "\(prefix)****\(suffix)"
    }

    // MARK: - Persistence

    private func save() {
        let profile = UserProfile(
            isLoggedIn: isLoggedIn,
            phone: phone,
            nickname: nickname,
            avatarSource: avatarSource
        )
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return
        }
        isLoggedIn = profile.isLoggedIn
        phone = profile.phone
        nickname = profile.nickname
        avatarSource = profile.avatarSource
    }
}
