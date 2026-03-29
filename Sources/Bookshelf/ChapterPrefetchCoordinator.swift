import Foundation

/// 当前章播放到一定进度时，后台预拉取下一章正文到 `ChapterContentManager`。
final class ChapterPrefetchCoordinator: @unchecked Sendable {
    static let shared = ChapterPrefetchCoordinator()

    private let lock = NSLock()
    private var lastPrefetchKey: String?

    func resetForNewPlayback() {
        lock.lock()
        lastPrefetchKey = nil
        lock.unlock()
    }

    func onPlaybackProgress(currentTime: TimeInterval, duration: TimeInterval, playlist: Playlist?) {
        guard let ctx = playlist?.chapterContext,
              duration > 0,
              currentTime / duration >= 0.35 else { return }

        guard let next = Self.nextChapterSummary(after: ctx.currentChapterIndex, in: ctx.chapters) else { return }
        let key = "\(ctx.shelfBookId.uuidString)|\(ctx.currentChapterIndex)|\(next.index)"

        lock.lock()
        if key == lastPrefetchKey {
            lock.unlock()
            return
        }
        lastPrefetchKey = key
        lock.unlock()

        let shelfId = ctx.shelfBookId
        let apiId = ctx.apiBookId
        let source = ctx.bookSource
        let nextIdx = next.index

        Task(priority: .utility) {
            await Self.prefetchNextChapterText(
                shelfBookId: shelfId,
                nextChapterIndex: nextIdx,
                apiBookId: apiId,
                bookSource: source
            )
        }
    }

    private static func nextChapterSummary(after currentIndex: Int, in chapters: [PlaybackChapterSummary]) -> PlaybackChapterSummary? {
        let sorted = chapters.sorted { $0.index < $1.index }
        guard let pos = sorted.firstIndex(where: { $0.index == currentIndex }), pos + 1 < sorted.count else {
            return nil
        }
        return sorted[pos + 1]
    }

    private static func prefetchNextChapterText(
        shelfBookId: UUID,
        nextChapterIndex: Int,
        apiBookId: String?,
        bookSource: BookSource
    ) async {
        if await ChapterContentManager.shared.hasContent(bookId: shelfBookId, chapterIndex: nextChapterIndex) {
            return
        }
        guard bookSource == .biquge, let remoteId = apiBookId, !remoteId.isEmpty else { return }

        let engine = BookSourceEngine()
        do {
            let content = try await engine.fetchChapterContent(bookId: remoteId, chapterId: nextChapterIndex + 1)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            try? await ChapterContentManager.shared.saveContent(
                bookId: shelfBookId,
                chapterIndex: nextChapterIndex,
                content: content
            )
        } catch {
            print("⚠️ 下一章预加载失败: \(error.localizedDescription)")
        }
    }
}
