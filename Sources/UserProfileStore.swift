import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformAvatarImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformAvatarImage = NSImage
#endif

// MARK: - 预设卡通头像（与 Assets 中 avatar_preset_0 … 对应）

enum AvatarPresetCatalog {
    static let defaultId = "avatar_preset_0"
    /// 与 `App/Assets.xcassets/avatar_preset_*.imageset` 一致（0–15 原有，16–31 为新增四神兽表情套图）
    static let imageAssetNames: [String] = (0..<32).map { "avatar_preset_\($0)" }
    /// 旧版 SF Symbol 预设 → 迁移到上面对应下标
    private static let legacySymbolOrder: [String] = [
        "person.fill", "star.fill", "heart.fill", "leaf.fill",
        "flame.fill", "book.fill", "music.note", "gamecontroller.fill"
    ]

    static func normalizedPresetId(_ raw: String) -> String {
        if raw.hasPrefix("avatar_preset_") { return raw }
        if let i = legacySymbolOrder.firstIndex(of: raw), i < imageAssetNames.count {
            return imageAssetNames[i]
        }
        return defaultId
    }
}

// MARK: - AvatarSource

enum AvatarSource: Codable, Equatable {
    case preset(String)   // 资源图名 avatar_preset_n，或旧版 SF Symbol（会迁移）
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
            self = .preset(AvatarPresetCatalog.defaultId)
        }
    }
}

// MARK: - UserProfile

private struct UserProfile: Codable {
    var isLoggedIn: Bool = false
    var phone: String = ""
    var nickname: String = ""
    var userId: String = ""
    var sessionToken: String = ""
    var avatarSource: AvatarSource = .preset(AvatarPresetCatalog.defaultId)
}

// MARK: - UserProfileStore

@MainActor
final class UserProfileStore: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var phone: String = ""
    @Published var nickname: String = ""
    @Published var userId: String = ""
    @Published var sessionToken: String = ""
    @Published var avatarSource: AvatarSource = .preset(AvatarPresetCatalog.defaultId)

    private enum AccessKeys {
        static let activationStatus = "fuyao_activation_status"
        static let activationPlanName = "fuyao_activation_plan_name"
        static let activationRemainingQuota = "fuyao_activation_remaining_quota"
        static let activationExpiryText = "fuyao_activation_expiry_text"
        static let dailyQuotaTotal = "fuyao_daily_quota_total"
        static let dailyQuotaUsed = "fuyao_daily_quota_used"
        static let dailyQuotaResetText = "fuyao_daily_quota_reset_text"
    }

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
        self.userId = ""
        self.sessionToken = ""
        self.avatarSource = .preset(AvatarPresetCatalog.defaultId)
        resetAccessState()
        save()
    }

    func applyLoginSuccess(
        phone: String,
        nickname: String?,
        userId: String?,
        sessionToken: String?,
        activationStatusRaw: String,
        activationPlanName: String?,
        dailyQuotaTotal: Int?,
        dailyQuotaUsed: Int?,
        dailyQuotaRemaining: Int?,
        dailyQuotaResetText: String?,
        activationExpiryText: String?
    ) {
        let trimmedNickname = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        isLoggedIn = true
        self.phone = phone
        self.nickname = !trimmedNickname.isEmpty
            ? trimmedNickname
            : "书友\(String(phone.suffix(4)))"
        self.userId = userId ?? ""
        self.sessionToken = sessionToken ?? ""
        if case .preset = avatarSource {
            avatarSource = .preset(AvatarPresetCatalog.defaultId)
        }

        let normalizedStatus: String
        normalizedStatus = Self.normalizeActivationStatus(activationStatusRaw)

        storeAccessState(
            activationStatus: normalizedStatus,
            activationPlanName: activationPlanName,
            dailyQuotaTotal: dailyQuotaTotal,
            dailyQuotaUsed: dailyQuotaUsed,
            dailyQuotaRemaining: dailyQuotaRemaining,
            dailyQuotaResetText: dailyQuotaResetText,
            activationExpiryText: activationExpiryText
        )

        save()
    }

    func applyActivationSuccess(
        activationStatusRaw: String,
        activationPlanName: String?,
        dailyQuotaTotal: Int?,
        dailyQuotaUsed: Int?,
        dailyQuotaRemaining: Int?,
        dailyQuotaResetText: String?,
        activationExpiryText: String?
    ) {
        let normalizedStatus = Self.normalizeActivationStatus(activationStatusRaw)
        storeAccessState(
            activationStatus: normalizedStatus,
            activationPlanName: activationPlanName,
            dailyQuotaTotal: dailyQuotaTotal,
            dailyQuotaUsed: dailyQuotaUsed,
            dailyQuotaRemaining: dailyQuotaRemaining,
            dailyQuotaResetText: dailyQuotaResetText,
            activationExpiryText: activationExpiryText
        )
        save()
    }

    func logout() {
        isLoggedIn = false
        phone = ""
        nickname = ""
        userId = ""
        sessionToken = ""
        avatarSource = .preset(AvatarPresetCatalog.defaultId)
        resetAccessState()
        save()
    }

    // MARK: - Update

    func updateNickname(_ name: String) {
        nickname = name
        save()
    }

    func updateAvatar(image: PlatformAvatarImage) {
        let fm = FileManager.default
        let dir = Self.avatarDirectory
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileName = "avatar.jpg"
        let fileURL = dir.appendingPathComponent(fileName)

        // 压缩并保存
        if let data = avatarJPEGData(from: image) {
            try? data.write(to: fileURL)
            avatarSource = .custom(fileName)
            save()
        }
    }

    func updateAvatar(preset: String) {
        avatarSource = .preset(preset)
        save()
    }

    func loadAvatarImage() -> PlatformAvatarImage? {
        guard case .custom(let fileName) = avatarSource else { return nil }
        let fileURL = Self.avatarDirectory.appendingPathComponent(fileName)
        #if canImport(UIKit)
        return UIImage(contentsOfFile: fileURL.path)
        #elseif canImport(AppKit)
        return NSImage(contentsOf: fileURL)
        #else
        return nil
        #endif
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
            userId: userId,
            sessionToken: sessionToken,
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
        userId = profile.userId
        sessionToken = profile.sessionToken
        switch profile.avatarSource {
        case .preset(let id):
            let normalized = AvatarPresetCatalog.normalizedPresetId(id)
            avatarSource = .preset(normalized)
            if normalized != id { save() }
        case .custom:
            avatarSource = profile.avatarSource
        }
    }

    private func avatarJPEGData(from image: PlatformAvatarImage) -> Data? {
        #if canImport(UIKit)
        return image.jpegData(compressionQuality: 0.8)
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        #else
        return nil
        #endif
    }

    private func resetAccessState() {
        let defaults = UserDefaults.standard
        defaults.set("inactive", forKey: AccessKeys.activationStatus)
        defaults.set("扶摇云端畅听", forKey: AccessKeys.activationPlanName)
        defaults.set(0, forKey: AccessKeys.activationRemainingQuota)
        defaults.set("", forKey: AccessKeys.activationExpiryText)
        defaults.set(0, forKey: AccessKeys.dailyQuotaTotal)
        defaults.set(0, forKey: AccessKeys.dailyQuotaUsed)
        defaults.set("每日 00:00 重置", forKey: AccessKeys.dailyQuotaResetText)
    }

    private func storeAccessState(
        activationStatus: String,
        activationPlanName: String?,
        dailyQuotaTotal: Int?,
        dailyQuotaUsed: Int?,
        dailyQuotaRemaining: Int?,
        dailyQuotaResetText: String?,
        activationExpiryText: String?
    ) {
        let total = dailyQuotaTotal ?? {
            if let remaining = dailyQuotaRemaining, let used = dailyQuotaUsed {
                return remaining + used
            }
            return activationStatus == "active" ? 120 : 0
        }()
        let used = dailyQuotaUsed ?? max(total - (dailyQuotaRemaining ?? total), 0)
        let remaining = dailyQuotaRemaining ?? max(total - used, 0)

        let defaults = UserDefaults.standard
        defaults.set(activationStatus, forKey: AccessKeys.activationStatus)
        defaults.set(activationPlanName ?? "扶摇云端畅听", forKey: AccessKeys.activationPlanName)
        defaults.set(remaining, forKey: AccessKeys.activationRemainingQuota)
        defaults.set(activationExpiryText ?? "", forKey: AccessKeys.activationExpiryText)
        defaults.set(total, forKey: AccessKeys.dailyQuotaTotal)
        defaults.set(used, forKey: AccessKeys.dailyQuotaUsed)
        defaults.set(
            dailyQuotaResetText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? dailyQuotaResetText
                : "每日 00:00 重置",
            forKey: AccessKeys.dailyQuotaResetText
        )
    }

    private static func normalizeActivationStatus(_ raw: String) -> String {
        switch raw.lowercased() {
        case "active", "activated", "valid", "enabled":
            return "active"
        case "expired", "expire":
            return "expired"
        default:
            return "inactive"
        }
    }
}
