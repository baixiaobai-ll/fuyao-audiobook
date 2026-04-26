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

private actor UpcomingChapterWarmupRegistry {
    static let shared = UpcomingChapterWarmupRegistry()

    private var inFlightKeys: Set<String> = []
    private var completedKeys: Set<String> = []

    func shouldStart(key: String) -> Bool {
        guard !inFlightKeys.contains(key), !completedKeys.contains(key) else {
            return false
        }
        inFlightKeys.insert(key)
        return true
    }

    func finish(key: String, completed: Bool) {
        inFlightKeys.remove(key)
        if completed {
            completedKeys.insert(key)
        }
    }
}

/// 章末**整章**后台预合成（与 18% 时的轻量 `warmup` 并存；键不同，避免互斥误伤）。
private actor NextChapterFullPrefetchRegistry {
    static let shared = NextChapterFullPrefetchRegistry()

    private var inFlightKeys: Set<String> = []
    private var completedKeys: Set<String> = []

    func shouldStart(key: String) -> Bool {
        guard !inFlightKeys.contains(key), !completedKeys.contains(key) else {
            return false
        }
        inFlightKeys.insert(key)
        return true
    }

    func finish(key: String, completed: Bool) {
        inFlightKeys.remove(key)
        if completed {
            completedKeys.insert(key)
        }
    }
}

@MainActor
enum BookChapterPlayback {
    /// 流式生成时，累计多少播放素材（条数/时长）即认为可开播；降低首段等待，具体阈值见 `Config.streamPlaybackStartMinTotalSeconds`。
    private static func isStreamStartupBufferReady(
        items: [PlaybackItem],
        bufferedDuration: TimeInterval,
        minTotalSeconds: TimeInterval
    ) -> Bool {
        if items.count >= 2 { return true }
        let floor = minTotalSeconds > 0 ? minTotalSeconds : 6
        if bufferedDuration >= floor { return true }
        return false
    }

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
        let accessContext = makeAccessContext(shelfBook: shelfBook, chapter: chapter)
        let authorization: CloudPlaybackAuthorization
        do {
            authorization = try await PlaybackAccessController.shared.authorizePlayback(for: accessContext)
        } catch {
            await MainActor.run { player.presentPlaybackError(error) }
            throw error
        }

        var shouldRollbackAuthorization = authorization.didConsumeQuota
        do {
            let content = try await fetchContent(shelfBookId: shelfBook.id, book: shelfBook, chapter: chapter)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BookChapterPlaybackError.emptyContent
            }
            let playbackChunks = splitContentForPlayback(
                content,
                maxChars: Config.chapterTTSDisplayMaxChars
            )

            let generator = AudioBookGenerator(
                aiApiKey: Config.aiApiKey,
                ttsApiKey: Config.ttsApiKey,
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
                bookCoverURL: shelfBook.coverURL,
                chapters: summaries,
                currentChapterIndex: chapter.index
            )

            let metadata = NovelMetadata(
                title: shelfBook.title,
                author: shelfBook.author,
                chapterTitle: chapter.title,
                wordCount: content.count
            )

            let sortedChapters = allChapters.sorted { $0.index < $1.index }
            let upcomingChapter = Self.nextChapter(after: chapter.index, in: sortedChapters)
            player.configureChapterPlaybackHandlers(
                prefetch: upcomingChapter.map { upcoming in
                    {
                        await preloadUpcomingChapter(
                            shelfBook: shelfBook,
                            chapter: upcoming,
                            store: store
                        )
                    }
                },
                advance: upcomingChapter.map { upcoming in
                    { [weak player] in
                        guard let player else { return }
                        try await BookChapterPlayback.play(
                            shelfBook: shelfBook,
                            chapter: upcoming,
                            allChapters: sortedChapters,
                            store: store,
                            player: player,
                            onProgressMessage: { _ in },
                            onFirstPlaybackStarted: {}
                        )
                    }
                }
            )

            final class StartedFlag {
                var value = false
            }
            let startedInline = StartedFlag()

            final class StartupBufferState {
                var items: [PlaybackItem] = []

                var bufferedDuration: TimeInterval {
                    items.reduce(0) { $0 + $1.audioData.duration }
                }
            }
            let startupBuffer = StartupBufferState()

            final class VoiceBindingState {
                var bindings: [String: String]

                init(bindings: [String: String]) {
                    self.bindings = bindings
                }
            }
            let bindingState = VoiceBindingState(bindings: existingBindings)

            let stream = Config.streamPlaybackWhileGenerating
            if stream {
                player.beginStreamingPlayback()
            }
            defer {
                if stream {
                    player.finishStreamingPlayback()
                }
            }

            let remoteCacheKey: PlaybackRemoteCacheKey? = {
                guard shelfBook.source == .biquge, let bid = shelfBook.bookId, !bid.isEmpty else { return nil }
                return PlaybackRemoteCacheKey(bookId: bid, chapterIndex: chapter.index)
            }()

            var combinedItems: [PlaybackItem] = []

            for (chunkIndex, chunkText) in playbackChunks.enumerated() {
                let chunkNumber = chunkIndex + 1
                let chunkCount = playbackChunks.count
                let isFirstChunk = chunkIndex == 0

                let playlist = try await generator.generate(
                    text: chunkText,
                    metadata: metadata,
                    existingVoiceBindings: bindingState.bindings,
                    remoteCacheKey: remoteCacheKey.map {
                        PlaybackRemoteCacheKey(bookId: $0.bookId, chapterIndex: chapter.index * 1000 + chunkIndex)
                    },
                    progressHandler: { progress in
                        let message = chunkCount > 1
                            ? "第 \(chunkNumber)/\(chunkCount) 段：\(progress.message)"
                            : progress.message
                        Task { @MainActor in onProgressMessage(message) }
                    },
                    onItemReady: { item in
                        Task { @MainActor in
                            if !stream { return }
                            if isFirstChunk && !startedInline.value {
                                startupBuffer.items.append(item)
                                startupBuffer.items.sort { $0.order < $1.order }

                                let shouldStart = Self.isStreamStartupBufferReady(
                                    items: startupBuffer.items,
                                    bufferedDuration: startupBuffer.bufferedDuration,
                                    minTotalSeconds: Config.streamPlaybackStartMinTotalSeconds
                                )
                                guard shouldStart else { return }

                                player.load(playlist: Playlist(
                                    title: chapter.title,
                                    items: startupBuffer.items,
                                    currentIndex: 0,
                                    chapterContext: ctx
                                ))
                                player.play()
                                shouldRollbackAuthorization = false
                                startedInline.value = true
                                onFirstPlaybackStarted()
                            } else {
                                player.append(item: item)
                            }
                        }
                    },
                    onVoiceBindingsUpdated: { newBindings in
                        Task { @MainActor in
                            bindingState.bindings.merge(newBindings) { _, new in new }
                            store.updateVoiceBindings(bookId: shelfBook.id, bindings: newBindings)
                        }
                    },
                    streamItemsAsReady: stream
                )

                combinedItems.append(contentsOf: playlist.items)

                if isFirstChunk && stream && !startedInline.value && !startupBuffer.items.isEmpty {
                    let startupItems = startupBuffer.items.sorted { $0.order < $1.order }
                    player.load(playlist: Playlist(
                        title: chapter.title,
                        items: startupItems,
                        currentIndex: 0,
                        chapterContext: ctx
                    ))
                    player.play()
                    shouldRollbackAuthorization = false
                    startedInline.value = true
                    onFirstPlaybackStarted()
                }
            }

            if !startedInline.value {
                let final = Playlist(
                    title: chapter.title,
                    items: combinedItems,
                    currentIndex: 0,
                    chapterContext: ctx
                )
                player.load(playlist: final)
                player.play()
                shouldRollbackAuthorization = false
                onFirstPlaybackStarted()
            }

            store.updateLastRead(bookId: shelfBook.id, chapterIndex: chapter.index)

            if Config.prefetchEntireNextChapterWhenCurrentReady,
               let next = upcomingChapter {
                let copyBook = shelfBook
                let copyNext = next
                let copyStore = store
                Task(priority: .utility) {
                    await prefetchEntireNextChapterTTSInBackground(
                        shelfBook: copyBook,
                        nextChapter: copyNext,
                        store: copyStore
                    )
                }
            }
        } catch {
            if shouldRollbackAuthorization {
                await PlaybackAccessController.shared.rollbackPlayback(
                    authorization,
                    reason: error is CancellationError ? .generationCancelled : .generationFailed
                )
            }
            await MainActor.run { player.presentPlaybackError(error) }
            throw error
        }
    }

    private static func nextChapter(after currentIndex: Int, in chapters: [Chapter]) -> Chapter? {
        let sorted = chapters.sorted { $0.index < $1.index }
        guard let currentPosition = sorted.firstIndex(where: { $0.index == currentIndex }),
              currentPosition + 1 < sorted.count else {
            return nil
        }
        return sorted[currentPosition + 1]
    }

    private static func preloadUpcomingChapter(
        shelfBook: Book,
        chapter: Chapter,
        store: BookshelfStore
    ) async {
        let accessContext = makeAccessContext(shelfBook: shelfBook, chapter: chapter)
        guard await PlaybackAccessController.shared.canWarmupPlayback(for: accessContext) else {
            return
        }
        let warmupKey = "\(shelfBook.id.uuidString):\(chapter.index)"
        guard await UpcomingChapterWarmupRegistry.shared.shouldStart(key: warmupKey) else {
            return
        }
        var didCompleteWarmup = false
        defer {
            Task {
                await UpcomingChapterWarmupRegistry.shared.finish(
                    key: warmupKey,
                    completed: didCompleteWarmup
                )
            }
        }

        do {
            let content = try await fetchContent(shelfBookId: shelfBook.id, book: shelfBook, chapter: chapter)
            let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }

            let playbackChunks = splitContentForPlayback(
                normalized,
                maxChars: Config.chapterTTSDisplayMaxChars
            )
            let warmupText = playbackChunks.first ?? normalized
            let metadata = NovelMetadata(
                title: shelfBook.title,
                author: shelfBook.author,
                chapterTitle: chapter.title,
                wordCount: normalized.count
            )
            let generator = AudioBookGenerator(
                aiApiKey: Config.aiApiKey,
                ttsApiKey: Config.ttsApiKey,
                ttsProvider: Config.ttsProvider
            )
            let existingBindings = store.books.first(where: { $0.id == shelfBook.id })?.voiceBindings ?? [:]
            let remoteCacheKey: PlaybackRemoteCacheKey? = {
                guard shelfBook.source == .biquge,
                      let bid = shelfBook.bookId,
                      !bid.isEmpty else { return nil }
                return PlaybackRemoteCacheKey(bookId: bid, chapterIndex: chapter.index * 1000)
            }()

            try await generator.warmupUpcomingChapterPlayback(
                text: warmupText,
                metadata: metadata,
                existingVoiceBindings: existingBindings,
                remoteCacheKey: remoteCacheKey,
                prefetchSegmentCount: 3,
                onVoiceBindingsUpdated: { newBindings in
                    Task { @MainActor in
                        store.updateVoiceBindings(bookId: shelfBook.id, bindings: newBindings)
                    }
                }
            )
            didCompleteWarmup = true
            print("⚡️ 已预热下一章播放链路: 第 \(chapter.index + 1) 章")
        } catch {
            print("⚠️ 下一章预加载失败: \(error.localizedDescription)")
        }
    }

    /// 当前章**全部 TTS 生成完成后**，在后台把下一章**整章**过一遍 TTS 以写满缓存，减少切章等待（与 18% 的轻量预热并存）。
    private static func prefetchEntireNextChapterTTSInBackground(
        shelfBook: Book,
        nextChapter: Chapter,
        store: BookshelfStore
    ) async {
        guard Config.prefetchEntireNextChapterWhenCurrentReady else { return }
        let key = "fullTTS:\(shelfBook.id.uuidString):\(nextChapter.index)"
        guard await NextChapterFullPrefetchRegistry.shared.shouldStart(key: key) else { return }
        var didComplete = false
        defer {
            Task {
                await NextChapterFullPrefetchRegistry.shared.finish(
                    key: key,
                    completed: didComplete
                )
            }
        }
        let accessContext = makeAccessContext(shelfBook: shelfBook, chapter: nextChapter)
        guard await PlaybackAccessController.shared.canWarmupPlayback(for: accessContext) else {
            return
        }
        final class LocalVoiceBindings {
            var map: [String: String]
            init(_ m: [String: String]) { self.map = m }
        }
        do {
            let content = try await fetchContent(
                shelfBookId: shelfBook.id,
                book: shelfBook,
                chapter: nextChapter
            )
            let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }

            let chunks = splitContentForPlayback(
                normalized,
                maxChars: Config.chapterTTSDisplayMaxChars
            )
            guard !chunks.isEmpty else { return }

            let holder = LocalVoiceBindings(
                store.books.first(where: { $0.id == shelfBook.id })?.voiceBindings ?? [:]
            )

            let metadata = NovelMetadata(
                title: shelfBook.title,
                author: shelfBook.author,
                chapterTitle: nextChapter.title,
                wordCount: normalized.count
            )
            let generator = AudioBookGenerator(
                aiApiKey: Config.aiApiKey,
                ttsApiKey: Config.ttsApiKey,
                ttsProvider: Config.ttsProvider
            )

            for (chunkIndex, chunkText) in chunks.enumerated() {
                let remoteCacheKey: PlaybackRemoteCacheKey? = {
                    guard shelfBook.source == .biquge,
                          let bid = shelfBook.bookId,
                          !bid.isEmpty else { return nil }
                    return PlaybackRemoteCacheKey(
                        bookId: bid,
                        chapterIndex: nextChapter.index * 1000 + chunkIndex
                    )
                }()
                _ = try await generator.generate(
                    text: chunkText,
                    metadata: metadata,
                    existingVoiceBindings: holder.map,
                    remoteCacheKey: remoteCacheKey,
                    progressHandler: { _ in },
                    onItemReady: nil,
                    onVoiceBindingsUpdated: { newBindings in
                        guard !newBindings.isEmpty else { return }
                        holder.map.merge(newBindings) { _, new in new }
                        Task { @MainActor in
                            store.updateVoiceBindings(bookId: shelfBook.id, bindings: newBindings)
                        }
                    },
                    streamItemsAsReady: false
                )
            }
            didComplete = true
            print("⚡️ 已整章预合成下一章: 第 \(nextChapter.index + 1) 章")
        } catch {
            print("⚠️ 下一章整章预合成失败: \(error.localizedDescription)")
        }
    }

    private static func makeAccessContext(
        shelfBook: Book,
        chapter: Chapter
    ) -> CloudPlaybackAccessContext {
        CloudPlaybackAccessContext(
            shelfBookID: shelfBook.id,
            remoteBookID: shelfBook.bookId,
            chapterIndex: chapter.index,
            bookTitle: shelfBook.title,
            chapterTitle: chapter.title,
            bookSource: shelfBook.source
        )
    }

    private static func splitContentForPlayback(_ content: String, maxChars: Int) -> [String] {
        let normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxChars, maxChars > 0 else { return [normalized] }

        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else {
            return strideChunks(of: normalized, maxChars: maxChars)
        }

        var chunks: [String] = []
        var current = ""

        for paragraph in paragraphs {
            let candidate = current.isEmpty ? paragraph : "\(current)\n\n\(paragraph)"
            if candidate.count <= maxChars {
                current = candidate
                continue
            }

            if !current.isEmpty {
                chunks.append(current)
                current = ""
            }

            if paragraph.count <= maxChars {
                current = paragraph
            } else {
                chunks.append(contentsOf: strideChunks(of: paragraph, maxChars: maxChars))
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks.isEmpty ? [normalized] : chunks
    }

    private static func strideChunks(of text: String, maxChars: Int) -> [String] {
        let chars = Array(text)
        guard !chars.isEmpty else { return [] }

        var chunks: [String] = []
        var start = 0

        while start < chars.count {
            let end = min(start + maxChars, chars.count)
            chunks.append(String(chars[start..<end]))
            start = end
        }

        return chunks
    }
}
