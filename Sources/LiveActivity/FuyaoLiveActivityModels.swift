#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct FuyaoPlaybackAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var bookTitle: String
        var chapterTitle: String
        var bookCoverURL: String?
        var isPlaying: Bool
        var progress: Double
        var elapsedTime: TimeInterval
        var duration: TimeInterval
    }

    var playlistID: String
}

struct FuyaoPlaybackLiveState: Equatable {
    let playlistID: String
    let bookTitle: String
    let chapterTitle: String
    let bookCoverURL: String?
    let isPlaying: Bool
    let elapsedTime: TimeInterval
    let duration: TimeInterval

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsedTime / duration, 0), 1)
    }
}
#endif
