import SwiftUI

struct BookDetailView: View {
    let book: Book
    @EnvironmentObject var store: BookshelfStore
    @EnvironmentObject var player: AudioBookPlayer
    @EnvironmentObject var tabRouter: MainTabRouter

    @State private var chapters: [Chapter] = []
    @State private var isLoadingChapters = false
    @State private var isGenerating = false
    @State private var generationTask: Task<Void, Never>? = nil
    @State private var generatingChapterIndex: Int? = nil
    @State private var statusMessage = ""
    @State private var errorMessage: String? = nil
    @State private var loadedChapterIndex: Int? = nil

    private let engine = BookSourceEngine()

    /// 书架上的同书记录（笔趣阁多次进入可能 UUID 不同）
    private var shelfBook: Book {
        store.existingBook(matching: book) ?? book
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(
                        coverURL: book.coverURL,
                        title: book.title,
                        size: CGSize(width: 72, height: 100)
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.headline)
                        Text(book.author).font(.subheadline).foregroundColor(.secondary)
                        Text(book.source == .local ? "本地导入" : "笔趣阁")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                if store.containsSameBook(as: book) {
                    HStack {
                        Text("已添加")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(role: .destructive, action: {
                            if let existing = store.existingBook(matching: book) {
                                store.removeBook(id: existing.id)
                            }
                        }) {
                            Label("从书架移除", systemImage: "trash")
                        }
                    }
                } else {
                    Button("加入书架") {
                        store.addBook(book)
                        if !chapters.isEmpty {
                            let sid = store.existingBook(matching: book)?.id ?? book.id
                            store.updateChapters(bookId: sid, chapters: chapters)
                        }
                    }
                    .buttonStyle(.borderedProminent)
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
        .onAppear { loadChapters() }
    }

    // MARK: - Load Chapters

    private func loadChapters() {
        if let existing = store.existingBook(matching: book), !existing.chapters.isEmpty {
            chapters = existing.chapters
            return
        }
        if let stored = store.books.first(where: { $0.id == book.id }), !stored.chapters.isEmpty {
            chapters = stored.chapters
            return
        }
        if !book.chapters.isEmpty { chapters = book.chapters; return }

        guard book.source == .biquge, let bookId = book.bookId else { return }
        isLoadingChapters = true
        Task {
            do {
                let fetched = try await engine.fetchChapters(bookId: bookId)
                chapters = fetched
                let sid = store.existingBook(matching: book)?.id ?? book.id
                store.updateChapters(bookId: sid, chapters: fetched)
            } catch {
                errorMessage = "加载章节失败: \(error.localizedDescription)"
            }
            isLoadingChapters = false
        }
    }

    // MARK: - Play Chapter

    private func playChapter(_ chapter: Chapter) {
        if loadedChapterIndex == chapter.index, player.currentPlaylist != nil {
            tabRouter.openPlayTab()
            return
        }

        isGenerating = true
        generatingChapterIndex = chapter.index
        statusMessage = "获取章节内容..."
        errorMessage = nil

        let chIndex = chapter.index
        let shelf = shelfBook
        let chList = chapters

        generationTask = Task {
            do {
                try Task.checkCancellation()
                try await BookChapterPlayback.play(
                    shelfBook: shelf,
                    chapter: chapter,
                    allChapters: chList,
                    store: store,
                    player: player,
                    onProgressMessage: { msg in statusMessage = msg },
                    onFirstPlaybackStarted: {
                        isGenerating = false
                        generatingChapterIndex = nil
                        loadedChapterIndex = chIndex
                        tabRouter.openPlayTab()
                    }
                )
                isGenerating = false
                generatingChapterIndex = nil
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
}
