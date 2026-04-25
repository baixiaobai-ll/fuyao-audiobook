import Foundation

enum CloudPlaybackAccessError: LocalizedError, Equatable {
    case loginRequired
    case activationRequired

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            return "请先登录后再播放云端章节。"
        case .activationRequired:
            return "当前账号尚未激活，暂时不能播放云端章节。"
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
    }

    private struct StateSnapshot {
        let isLoggedIn: Bool
        let activation: ActivationSnapshot

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

        return CloudPlaybackAuthorization(
            source: .stateContract,
            didConsumeQuota: false,
            reservationID: nil,
            context: context,
            grantedAt: Date()
        )
    }

    func rollbackPlayback(_ authorization: CloudPlaybackAuthorization, reason: CloudPlaybackRollbackReason) async {
        guard authorization.source == .stateContract else { return }
        guard authorization.didConsumeQuota else { return }
    }

    func canWarmupPlayback(for context: CloudPlaybackAccessContext) async -> Bool {
        guard context.requiresCloudEntitlement else { return true }

        let snapshot = loadStateSnapshot()
        return snapshot.isLoggedIn && snapshot.isActivated
    }

    private func loadStateSnapshot() -> StateSnapshot {
        StateSnapshot(
            isLoggedIn: isLoggedIn,
            activation: ActivationSnapshot(
                status: userDefaults.string(forKey: StorageKeys.activationStatus) ?? "",
                planName: userDefaults.string(forKey: StorageKeys.activationPlanName)
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
}
