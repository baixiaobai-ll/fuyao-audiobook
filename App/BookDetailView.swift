import SwiftUI

struct BookDetailView: View {
    let book: Book
    @EnvironmentObject var store: BookshelfStore
    @EnvironmentObject var player: AudioBookPlayer

    @State private var chapters: [Chapter] = []
    @State private var isLoadingChapters = false
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>? = nil
    @State private var generatingChapterIndex: Int? = nil
    @State private var statusMessage = ""
    @State private var navigateToPlayer = false
    @State private var errorMessage: String? = nil
    @State private var currentChapterTitle = ""
    @State private var loadedChapterIndex: Int? = nil

    private let engine = BookSourceEngine()

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.headline)
                        Text(book.author).font(.subheadline).foregroundColor(.secondary)
                        Text(book.source == .local ? "本地导入" : "笔趣阁")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                if !store.containsBook(id: book.id) {
                    Button("加入书架") {
                        store.addBook(book)
                        if !chapters.isEmpty {
                            store.updateChapters(bookId: book.id, chapters: chapters)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .destructive, action: {
                        store.removeBook(id: book.id)
                    }) {
                        Label("从书架移除", systemImage: "trash")
                    }
                }
            }

            if isLoadingChapters {
                Section {
                    HStack { ProgressView(); Text("加载章节列表...").foregroundColor(.secondary) }
                }
            } else if let err = errorMessage {
                Section { Text(err).foregroundColor(.red).font(.footnote) }
            }

            if isGenerating, let idx = generatingChapterIndex {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("正在生成第 \(idx + 1) 章...").font(.footnote)
                                Text(statusMessage).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("取消") {
                                generationTask?.cancel()
                                generationTask = nil
                                isGenerating = false
                                generatingChapterIndex = nil
                            }
                            .foregroundColor(.red)
                            .font(.footnote)
                        }
                        ProgressView()
                    }
                }
            }

            Section(header: Text("章节列表 (\(chapters.count))")) {
                ForEach(chapters) { chapter in
                    Button(action: { playChapter(chapter) }) {
                        HStack {
                            Text(chapter.title).foregroundColor(.primary).lineLimit(1)
                            Spacer()
                            if isGenerating && generatingChapterIndex == chapter.index {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "play.circle").foregroundColor(.accentColor)
                            }
                        }
                    }
                    .disabled(isGenerating)
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToPlayer) {
            PlayerView(player: player, chapterTitle: currentChapterTitle)
        }
        .onAppear { loadChapters() }
    }

    // MARK: - Load Chapters

    private func loadChapters() {
        if let stored = store.books.first(where: { $0.id == book.id }), !stored.chapters.isEmpty {
            chapters = stored.chapters; return
        }
        if !book.chapters.isEmpty { chapters = book.chapters; return }

        guard book.source == .biquge, let bookId = book.bookId else { return }
        isLoadingChapters = true
        Task {
            do {
                let fetched = try await engine.fetchChapters(bookId: bookId)
                chapters = fetched
                store.updateChapters(bookId: book.id, chapters: fetched)
            } catch {
                errorMessage = "加载章节失败: \(error.localizedDescription)"
            }
            isLoadingChapters = false
        }
    }

    // MARK: - Play Chapter

    private func playChapter(_ chapter: Chapter) {
        // Already loaded - just navigate
        if loadedChapterIndex == chapter.index, player.currentPlaylist != nil {
            currentChapterTitle = chapter.title
            navigateToPlayer = true
            return
        }

        isGenerating = true
        generatingChapterIndex = chapter.index
        statusMessage = "获取章节内容..."
        errorMessage = nil
        currentChapterTitle = chapter.title

        let chTitle = chapter.title
        let chIndex = chapter.index
        generationTask = Task {
            do {
                let content = try await fetchContent(for: chapter)
                guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw BookError.emptyContent
                }
                let maxChars = 500
                let processedContent = content.count > maxChars
                    ? String(content.prefix(maxChars))
                    : content
                let generator = AudioBookGenerator(
                    aiApiKey: Config.aiApiKey,
                    ttsApiKey: Config.ttsApiKey,
                    aiProvider: Config.aiProvider,
                    ttsProvider: Config.ttsProvider
                )
                let existingBindings = store.books.first(where: { $0.id == book.id })?.voiceBindings ?? [:]
                try Task.checkCancellation()
                let playlist = try await generator.generate(
                    text: processedContent,
                    existingVoiceBindings: existingBindings,
                    progressHandler: { progress in
                        let msg = progress.message
                        Task { @MainActor in statusMessage = msg }
                    },
                    onItemReady: { item in
                        Task { @MainActor in
                            if item.order == 0 {
                                player.load(playlist: Playlist(title: chTitle, items: [item]))
                                player.play()
                                isGenerating = false
                                generatingChapterIndex = nil
                                loadedChapterIndex = chIndex
                                navigateToPlayer = true
                            } else {
                                player.append(item: item)
                            }
                        }
                    },
                    onVoiceBindingsUpdated: { newBindings in
                        Task { @MainActor in
                            store.updateVoiceBindings(bookId: book.id, bindings: newBindings)
                        }
                    }
                )
                // All segments done - update session and ensure player loaded
                if player.currentPlaylist == nil {
                    player.load(playlist: playlist)
                    player.play()
                    isGenerating = false
                    generatingChapterIndex = nil
                    loadedChapterIndex = chIndex
                    navigateToPlayer = true
                }
                store.updateLastRead(bookId: book.id, chapterIndex: chIndex)
            } catch is CancellationError {
                isGenerating = false
                generatingChapterIndex = nil
            } catch {
                errorMessage = "生成失败: \(error.localizedDescription)"
                isGenerating = false
                generatingChapterIndex = nil
            }
        }
    }

    private func fetchContent(for chapter: Chapter) async throws -> String {
        // Check local cache first
        if let cached = await ChapterContentManager.shared.getContent(
            bookId: book.id, chapterIndex: chapter.index), !cached.isEmpty {
            return cached
        }

        if book.source == .local {
            throw BookError.noURL
        }

        // Fetch via JSON API using bookId + chapterIndex+1 as chapterId
        guard let bookId = book.bookId else { throw BookError.noURL }
        let content = try await engine.fetchChapterContent(bookId: bookId, chapterId: chapter.index + 1)
        try? await ChapterContentManager.shared.saveContent(
            bookId: book.id, chapterIndex: chapter.index, content: content)
        return content
    }
}

private enum BookError: LocalizedError {
    case emptyContent, noURL
    var errorDescription: String? {
        switch self {
        case .emptyContent: return "章节内容为空"
        case .noURL: return "章节无有效地址"
        }
    }
}
