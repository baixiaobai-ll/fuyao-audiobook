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

    func sync(with state: FuyaoPlaybackLiveState?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let state else {
            end()
            return
        }

        let now = Date().timeIntervalSince1970
        let shouldThrottle = lastState?.bookTitle == state.bookTitle
            && lastState?.chapterTitle == state.chapterTitle
            && lastState?.isPlaying == state.isPlaying
            && (now - lastUpdateTime) < 5

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

        Task {
            if let activity = currentActivity,
               activity.attributes.playlistID == state.playlistID {
                await activity.update(using: contentState)
            } else {
                if let activity = currentActivity {
                    await activity.end(dismissalPolicy: .immediate)
                }
                do {
                    currentActivity = try Activity.request(
                        attributes: attributes,
                        contentState: contentState,
                        pushType: nil
                    )
                } catch {
                    print("⚠️ Live Activity 创建失败: \(error.localizedDescription)")
                }
            }
        }
    }

    func end() {
        lastState = nil
        lastUpdateTime = 0

        guard let activity = currentActivity else { return }
        currentActivity = nil

        Task {
            await activity.end(dismissalPolicy: .immediate)
        }
    }
}
#endif
