import Foundation

private enum BookChapterPlaybackError: LocalizedError {
    case emptyContent
    case noURL

    var errorDescription: String? {
        switch self {
        case .emptyContent: return "章节内容为空"
        case .noURL: return "章节无有效地址"
        }
    }
}

@MainActor
enum BookChapterPlayback {
    static func fetchContent(shelfBookId: UUID, book: Book, chapter: Chapter) async throws -> String {
        if let cached = await ChapterContentManager.shared.getContent(
            bookId: shelfBookId, chapterIndex: chapter.index), !cached.isEmpty {
            return cached
        }
        if book.source == .local { throw BookChapterPlaybackError.noURL }
        guard let remoteId = book.bookId else { throw BookChapterPlaybackError.noURL }
        let engine = BookSourceEngine()
        let content = try await engine.fetchChapterContent(bookId: remoteId, chapterId: chapter.index + 1)
        try? await ChapterContentManager.shared.saveContent(
            bookId: shelfBookId, chapterIndex: chapter.index, content: content)
        return content
    }

    /// 拉取正文并生成语音，写入 `player`；首段就绪时调用 `onFirstPlaybackStarted`。
    static func play(
        shelfBook: Book,
        chapter: Chapter,
        allChapters: [Chapter],
        store: BookshelfStore,
        player: AudioBookPlayer,
        onProgressMessage: @escaping (String) -> Void,
        onFirstPlaybackStarted: @escaping () -> Void
    ) async throws {
        let content = try await fetchContent(shelfBookId: shelfBook.id, book: shelfBook, chapter: chapter)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BookChapterPlaybackError.emptyContent
        }
        let maxChars = 500
        let processed = content.count > maxChars ? String(content.prefix(maxChars)) : content

        let generator = AudioBookGenerator(
            aiApiKey: Config.aiApiKey,
            ttsApiKey: Config.ttsApiKey,
            aiProvider: Config.aiProvider,
            ttsProvider: Config.ttsProvider
        )
        let existingBindings = store.books.first(where: { $0.id == shelfBook.id })?.voiceBindings ?? [:]

        let summaries = allChapters
            .map { PlaybackChapterSummary(index: $0.index, title: $0.title) }
            .sorted { $0.index < $1.index }
        let ctx = PlaybackChapterContext(
            shelfBookId: shelfBook.id,
            apiBookId: shelfBook.bookId,
            bookSource: shelfBook.source,
            bookTitle: shelfBook.title,
            chapters: summaries,
            currentChapterIndex: chapter.index
        )

        let metadata = NovelMetadata(
            title: shelfBook.title,
            author: shelfBook.author,
            chapterTitle: chapter.title,
            wordCount: processed.count
        )

        final class StartedFlag {
            var value = false
        }
        let startedInline = StartedFlag()

        let playlist = try await generator.generate(
            text: processed,
            metadata: metadata,
            existingVoiceBindings: existingBindings,
            progressHandler: { progress in
                Task { @MainActor in onProgressMessage(progress.message) }
            },
            onItemReady: { item in
                Task { @MainActor in
                    if item.order == 0 {
                        player.load(playlist: Playlist(
                            title: chapter.title,
                            items: [item],
                            currentIndex: 0,
                            chapterContext: ctx
                        ))
                        player.play()
                        startedInline.value = true
                        onFirstPlaybackStarted()
                    } else {
                        player.append(item: item)
                    }
                }
            },
            onVoiceBindingsUpdated: { newBindings in
                Task { @MainActor in
                    store.updateVoiceBindings(bookId: shelfBook.id, bindings: newBindings)
                }
            }
        )

        if !startedInline.value {
            var final = playlist
            final.chapterContext = ctx
            final.title = chapter.title
            player.load(playlist: final)
            player.play()
            onFirstPlaybackStarted()
        }
        store.updateLastRead(bookId: shelfBook.id, chapterIndex: chapter.index)
    }
}
