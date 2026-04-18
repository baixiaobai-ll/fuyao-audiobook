import Foundation

enum CloudPlaybackAccessError: LocalizedError, Equatable {
    case loginRequired
    case activationRequired
    case dailyQuotaExceeded(limit: Int, resetText: String?)
    case quotaValidationUnavailable

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            return "请先登录后再播放云端章节。"
        case .activationRequired:
            return "当前账号尚未激活，暂时不能播放云端章节。"
        case .dailyQuotaExceeded(let limit, let resetText):
            if let resetText, !resetText.isEmpty {
                return "今日 \(limit) 章收听额度已用完，\(resetText)。"
            }
            return "今日 \(limit) 章收听额度已用完，请明天再来。"
        case .quotaValidationUnavailable:
            return "当前无法校验今日收听额度，请稍后重试。"
        }
    }
}

struct CloudPlaybackAccessContext: Sendable {
    let shelfBookID: UUID
    let remoteBookID: String?
    let chapterIndex: Int
    let bookTitle: String
    let chapterTitle: String
    let bookSource: BookSource

    var requiresCloudEntitlement: Bool {
        bookSource != .local
    }
}

struct CloudPlaybackAuthorization: Sendable {
    enum Source: String, Sendable {
        case none
        case stateContract
        case backend
    }

    let source: Source
    let didConsumeQuota: Bool
    let reservationID: String?
    let context: CloudPlaybackAccessContext
    let grantedAt: Date

    static func bypass(for context: CloudPlaybackAccessContext) -> CloudPlaybackAuthorization {
        CloudPlaybackAuthorization(
            source: .none,
            didConsumeQuota: false,
            reservationID: nil,
            context: context,
            grantedAt: Date()
        )
    }
}

enum CloudPlaybackRollbackReason: String, Sendable {
    case generationFailed
    case generationCancelled
}

protocol CloudPlaybackQuotaAuthorizing: Sendable {
    func authorizePlayback(for context: CloudPlaybackAccessContext) async throws -> CloudPlaybackAuthorization
    func rollbackPlayback(_ authorization: CloudPlaybackAuthorization, reason: CloudPlaybackRollbackReason) async
    func canWarmupPlayback(for context: CloudPlaybackAccessContext) async -> Bool
}

actor PlaybackAccessController {
    static let shared = PlaybackAccessController()

    private var authorizer: any CloudPlaybackQuotaAuthorizing = StateContractPlaybackQuotaAuthorizer()

    func setAuthorizer(_ authorizer: any CloudPlaybackQuotaAuthorizing) {
        self.authorizer = authorizer
    }

    func authorizePlayback(for context: CloudPlaybackAccessContext) async throws -> CloudPlaybackAuthorization {
        try await authorizer.authorizePlayback(for: context)
    }

    func rollbackPlayback(_ authorization: CloudPlaybackAuthorization, reason: CloudPlaybackRollbackReason) async {
        await authorizer.rollbackPlayback(authorization, reason: reason)
    }

    func canWarmupPlayback(for context: CloudPlaybackAccessContext) async -> Bool {
        await authorizer.canWarmupPlayback(for: context)
    }
}

private actor StateContractPlaybackQuotaAuthorizer: CloudPlaybackQuotaAuthorizing {
    private struct PersistedUserProfileSnapshot: Decodable {
        let isLoggedIn: Bool
    }

    private struct ActivationSnapshot {
        let status: String
        let planName: String?
        let remainingQuota: Int?
        let expiryText: String?
    }

    private struct DailyQuotaSnapshot {
        var total: Int?
        var used: Int?
        let resetText: String?
    }

    private struct StateSnapshot {
        let isLoggedIn: Bool
        let activation: ActivationSnapshot
        let dailyQuota: DailyQuotaSnapshot

        var isActivated: Bool {
            let normalized = activation.status
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if ["1", "true", "yes", "active", "activated", "enabled", "valid", "vip", "member", "success"].contains(normalized) {
                return true
            }
            if ["0", "false", "no", "inactive", "not_activated", "unactivated", "expired", "none", "invalid", ""].contains(normalized) {
                return false
            }

            return !(activation.planName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    private enum StorageKeys {
        static let userProfile = "userprofile_data"
        static let activationStatus = "fuyao_activation_status"
        static let activationPlanName = "fuyao_activation_plan_name"
        static let activationRemainingQuota = "fuyao_activation_remaining_quota"
        static let activationExpiryText = "fuyao_activation_expiry_text"
        static let dailyQuotaTotal = "fuyao_daily_quota_total"
        static let dailyQuotaUsed = "fuyao_daily_quota_used"
        static let dailyQuotaResetText = "fuyao_daily_quota_reset_text"
    }

    private let userDefaults = UserDefaults.standard

    func authorizePlayback(for context: CloudPlaybackAccessContext) async throws -> CloudPlaybackAuthorization {
        guard context.requiresCloudEntitlement else {
            return .bypass(for: context)
        }

        let snapshot = loadStateSnapshot()

        guard snapshot.isLoggedIn else {
            throw CloudPlaybackAccessError.loginRequired
        }
        guard snapshot.isActivated else {
            throw CloudPlaybackAccessError.activationRequired
        }

        guard let total = resolvedDailyQuotaTotal(from: snapshot),
              var used = resolvedDailyQuotaUsed(from: snapshot, total: total) else {
            throw CloudPlaybackAccessError.quotaValidationUnavailable
        }
        if used >= total {
            throw CloudPlaybackAccessError.dailyQuotaExceeded(
                limit: total,
                resetText: snapshot.dailyQuota.resetText
            )
        }

        used += 1
        persistQuotaUsage(used: used, total: total, previousRemainingQuota: snapshot.activation.remainingQuota)

        return CloudPlaybackAuthorization(
            source: .stateContract,
            didConsumeQuota: true,
            reservationID: nil,
            context: context,
            grantedAt: Date()
        )
    }

    func rollbackPlayback(_ authorization: CloudPlaybackAuthorization, reason: CloudPlaybackRollbackReason) async {
        guard authorization.didConsumeQuota else { return }
        guard authorization.source == .stateContract else { return }

        let snapshot = loadStateSnapshot()
        guard let total = resolvedDailyQuotaTotal(from: snapshot),
              let used = resolvedDailyQuotaUsed(from: snapshot, total: total),
              used > 0 else {
            return
        }
        persistQuotaUsage(
            used: used - 1,
            total: total,
            previousRemainingQuota: snapshot.activation.remainingQuota
        )
        print("↩️ 已回滚章节额度占用: chapter=\(authorization.context.chapterIndex + 1), reason=\(reason.rawValue)")
    }

    func canWarmupPlayback(for context: CloudPlaybackAccessContext) async -> Bool {
        guard context.requiresCloudEntitlement else { return true }

        let snapshot = loadStateSnapshot()
        guard snapshot.isLoggedIn, snapshot.isActivated else { return false }
        guard let total = resolvedDailyQuotaTotal(from: snapshot),
              let used = resolvedDailyQuotaUsed(from: snapshot, total: total) else {
            return false
        }
        return used < total
    }

    private func loadStateSnapshot() -> StateSnapshot {
        StateSnapshot(
            isLoggedIn: isLoggedIn,
            activation: ActivationSnapshot(
                status: userDefaults.string(forKey: StorageKeys.activationStatus) ?? "",
                planName: userDefaults.string(forKey: StorageKeys.activationPlanName),
                remainingQuota: integerValue(forKey: StorageKeys.activationRemainingQuota),
                expiryText: userDefaults.string(forKey: StorageKeys.activationExpiryText)
            ),
            dailyQuota: DailyQuotaSnapshot(
                total: integerValue(forKey: StorageKeys.dailyQuotaTotal),
                used: integerValue(forKey: StorageKeys.dailyQuotaUsed),
                resetText: userDefaults.string(forKey: StorageKeys.dailyQuotaResetText)
            )
        )
    }

    private var isLoggedIn: Bool {
        guard let data = userDefaults.data(forKey: StorageKeys.userProfile),
              let snapshot = try? JSONDecoder().decode(PersistedUserProfileSnapshot.self, from: data) else {
            return false
        }
        return snapshot.isLoggedIn
    }

    private func resolvedDailyQuotaTotal(from snapshot: StateSnapshot) -> Int? {
        if let total = snapshot.dailyQuota.total, total > 0 {
            return total
        }
        if let remaining = snapshot.activation.remainingQuota,
           let used = snapshot.dailyQuota.used {
            let derived = used + remaining
            return derived > 0 ? derived : nil
        }
        return nil
    }

    private func resolvedDailyQuotaUsed(from snapshot: StateSnapshot, total: Int) -> Int? {
        if let used = snapshot.dailyQuota.used, used >= 0 {
            return min(used, total)
        }
        if let remaining = snapshot.activation.remainingQuota, remaining >= 0 {
            return max(0, total - remaining)
        }
        return nil
    }

    private func persistQuotaUsage(used: Int, total: Int, previousRemainingQuota: Int?) {
        let safeUsed = max(0, min(used, total))
        userDefaults.set(safeUsed, forKey: StorageKeys.dailyQuotaUsed)
        userDefaults.set(total, forKey: StorageKeys.dailyQuotaTotal)

        if let previousRemainingQuota {
            let safeRemaining = max(0, total - safeUsed)
            if previousRemainingQuota >= 0 {
                userDefaults.set(safeRemaining, forKey: StorageKeys.activationRemainingQuota)
            }
        }
    }

    private func integerValue(forKey key: String) -> Int? {
        if let number = userDefaults.object(forKey: key) as? NSNumber {
            return number.intValue
        }
        if let value = userDefaults.string(forKey: key),
           let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return intValue
        }
        return nil
    }
}
