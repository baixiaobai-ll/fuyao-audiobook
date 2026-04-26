#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
@MainActor
final class FuyaoLiveActivityManager {
    static let shared = FuyaoLiveActivityManager()

    private var currentActivity: Activity<FuyaoPlaybackAttributes>?
    private var lastState: FuyaoPlaybackLiveState?
    private var lastUpdateTime: TimeInterval = 0

    private init() {}

    func clearAllActivities() {
        lastState = nil
        lastUpdateTime = 0
        currentActivity = nil

        Task {
            for activity in Activity<FuyaoPlaybackAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }

    func sync(with state: FuyaoPlaybackLiveState?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }

        guard let state else {
            end()
            return
        }

        let now = Date().timeIntervalSince1970
        let previousState = lastState
        let minimumUpdateInterval = state.isPlaying ? 1.5 : 8.0
        let shouldThrottle = previousState?.playlistID == state.playlistID
            && previousState?.bookTitle == state.bookTitle
            && previousState?.chapterTitle == state.chapterTitle
            && previousState?.isPlaying == state.isPlaying
            && abs((previousState?.elapsedTime ?? 0) - state.elapsedTime) < 1
            && abs((previousState?.duration ?? 0) - state.duration) < 1
            && (now - lastUpdateTime) < minimumUpdateInterval

        if shouldThrottle {
            return
        }

        lastState = state
        lastUpdateTime = now

        let attributes = FuyaoPlaybackAttributes(playlistID: state.playlistID)
        let contentState = FuyaoPlaybackAttributes.ContentState(
            bookTitle: state.bookTitle,
            chapterTitle: state.chapterTitle,
            bookCoverURL: state.bookCoverURL,
            isPlaying: state.isPlaying,
            progress: state.progress,
            elapsedTime: state.elapsedTime,
            duration: state.duration
        )

        Task { @MainActor in
            if let activity = currentActivity,
               activity.attributes.playlistID == state.playlistID {
                await activity.update(using: contentState)
            } else {
                if let activity = currentActivity {
                    await activity.end(dismissalPolicy: .immediate)
                    currentActivity = nil
                }
                do {
                    currentActivity = try Activity.request(
                        attributes: attributes,
                        contentState: contentState,
                        pushType: nil
                    )
                } catch {
                    // 非前台时系统拒绝创建；主 App/扩展均不能使用 UIApplication.shared 判断，靠错误字符串静默略过
                    let msg = error.localizedDescription
                    if msg.range(of: "foreground", options: .caseInsensitive) != nil
                        || msg.range(of: "非前台", options: .caseInsensitive) != nil
                    { return }
                    print("⚠️ Live Activity 创建失败: \(msg)")
                }
            }
        }
    }

    func end() {
        lastState = nil
        lastUpdateTime = 0
        currentActivity = nil

        Task {
            for activity in Activity<FuyaoPlaybackAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
