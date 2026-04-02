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
    @State private var showVoiceSettings = false
    @State private var editableVoiceBindings: [String: String] = [:]
    @State private var visibleChapterCount = 60

    private let engine = BookSourceEngine()
    private let chapterPageSize = 60

    /// 书架上的同书记录（笔趣阁多次进入可能 UUID 不同）
    private var shelfBook: Book {
        store.existingBook(matching: book) ?? book
    }

    private var availableVoices: [Voice] {
        VoiceLibrary.getVoices(for: Config.ttsProvider)
    }

    private var configurableRoleNames: [String] {
        shelfBook.voiceBindings.keys
            .filter { $0 != VoiceManager.narrationBindingKey }
            .sorted()
    }

    private var visibleChapters: [Chapter] {
        Array(chapters.prefix(visibleChapterCount))
    }

    private var hasMoreChapters: Bool {
        visibleChapterCount < chapters.count
    }

    private var selectedNarrationVoiceName: String {
        if let voiceId = shelfBook.voiceBindings[VoiceManager.narrationBindingKey],
           let voice = availableVoices.first(where: { $0.id == voiceId }) {
            return voice.name
        }
        return VoiceLibrary.getPreferredNarrationVoice(for: Config.ttsProvider)?.name
            ?? availableVoices.first?.name
            ?? "默认"
    }

    private var lastReadChapterIndex: Int? {
        guard store.containsSameBook(as: book) else { return nil }
        guard chapters.indices.contains(shelfBook.lastReadChapter) else { return nil }
        return shelfBook.lastReadChapter
    }

    private var lastReadChapterTitle: String? {
        guard let index = lastReadChapterIndex else { return nil }
        return chapters.first(where: { $0.index == index })?.title
    }

    var body: some View {
        List {
            Section(header: Text("书籍信息")) {
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

                if !store.containsSameBook(as: book) {
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

            Section(header: Text("个性化")) {
                Button {
                    prepareVoiceSettings()
                    showVoiceSettings = true
                } label: {
                    HStack {
                        Label("配音设置", systemImage: "music.mic")
                        Spacer()
                        Text(configurableRoleNames.isEmpty ? selectedNarrationVoiceName : "\(selectedNarrationVoiceName) + \(configurableRoleNames.count) 个角色")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text("可手动更换旁白及已出场的角色音色")
                    .font(.footnote)
                    .foregroundColor(.secondary)
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
                if let lastReadChapterTitle {
                    HStack(spacing: 8) {
                        Image(systemName: "headphones")
                            .foregroundColor(.accentColor)
                        Text("上次听到：\(lastReadChapterTitle)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(visibleChapters) { chapter in
                    Button(action: { playChapter(chapter) }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chapter.title)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                if chapter.index == lastReadChapterIndex {
                                    Text("上次听到这里")
                                        .font(.caption2)
                                        .foregroundColor(.accentColor)
                                }
                            }
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

                if hasMoreChapters {
                    Button {
                        visibleChapterCount = min(visibleChapterCount + chapterPageSize, chapters.count)
                    } label: {
                        HStack {
                            Spacer()
                            Text("加载更多章节")
                            Text("已显示 \(visibleChapters.count)/\(chapters.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadChapters() }
        .sheet(isPresented: $showVoiceSettings) {
            voiceSettingsSheet
        }
    }

    // MARK: - Load Chapters

    private func loadChapters() {
        if let existing = store.existingBook(matching: book), !existing.chapters.isEmpty {
            chapters = existing.chapters
            resetChapterPagination()
            return
        }
        if let stored = store.books.first(where: { $0.id == book.id }), !stored.chapters.isEmpty {
            chapters = stored.chapters
            resetChapterPagination()
            return
        }
        if !book.chapters.isEmpty {
            chapters = book.chapters
            resetChapterPagination()
            return
        }

        guard book.source == .biquge, let bookId = book.bookId else { return }
        isLoadingChapters = true
        Task {
            do {
                let fetched = try await engine.fetchChapters(bookId: bookId)
                chapters = fetched
                resetChapterPagination()
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
                print("❌ 章节生成失败: \(error)")
                let rawMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                print("❌ 章节生成失败详情: \(rawMessage)")
                errorMessage = friendlyGenerationErrorMessage(error)
                isGenerating = false
                generatingChapterIndex = nil
            }
        }
    }

    private func friendlyGenerationErrorMessage(_ error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        if message.contains("通义千问分析超时") {
            return "文本分析超时。请检查网络，或稍后重试。"
        }
        if message.contains("通义千问鉴权失败") {
            return "文本分析鉴权失败。请检查 Config.plist 里的 AI_API_KEY，并确认 AI_PROVIDER=qwen。"
        }
        if message.contains("请求过于频繁") {
            return "文本分析请求过于频繁，请稍后再试。"
        }
        if message.contains("讯飞发音失败") {
            return "语音合成失败。\(message.replacingOccurrences(of: "TTS API 错误: ", with: ""))"
        }
        if message.contains("TTS API 错误") {
            return "语音合成失败。\(message.replacingOccurrences(of: "TTS API 错误: ", with: ""))"
        }
        if message.localizedCaseInsensitiveContains("timeout") || message.contains("超时") {
            return "语音合成失败。请求超时，请检查当前网络后重试。"
        }
        if message.contains("网络") {
            return "网络请求失败，请检查当前网络后重试。"
        }

        return "生成失败：\(message)"
    }

    private func prepareVoiceSettings() {
        editableVoiceBindings = shelfBook.voiceBindings
        if editableVoiceBindings[VoiceManager.narrationBindingKey] == nil,
           let defaultNarration = VoiceLibrary.getPreferredNarrationVoice(for: Config.ttsProvider) ?? availableVoices.first {
            editableVoiceBindings[VoiceManager.narrationBindingKey] = defaultNarration.id
        }
    }

    private func resetChapterPagination() {
        visibleChapterCount = min(chapterPageSize, chapters.count)
    }

    @ViewBuilder
    private var voiceSettingsSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("旁白")) {
                    voicePickerRow(
                        title: "旁白音色",
                        bindingKey: VoiceManager.narrationBindingKey,
                        helper: "用于旁白、描述、未命名对白等内容"
                    )
                }

                Section(header: Text("角色")) {
                    if configurableRoleNames.isEmpty {
                        Text("当前还没有已识别并保存的角色。先播放一章，角色音色会自动生成，之后你就可以逐个手动调整。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(configurableRoleNames, id: \.self) { roleName in
                            voicePickerRow(
                                title: roleName,
                                bindingKey: roleName,
                                helper: "该角色的对白默认使用这个音色"
                            )
                        }
                    }
                }
            }
            .navigationTitle("配音设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showVoiceSettings = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveVoiceSettings()
                        showVoiceSettings = false
                    }
                }
            }
        }
    }

    private func voicePickerRow(title: String, bindingKey: String, helper: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Picker("", selection: Binding(
                get: {
                    editableVoiceBindings[bindingKey] ?? availableVoices.first?.id ?? ""
                },
                set: { editableVoiceBindings[bindingKey] = $0 }
            )) {
                ForEach(availableVoices, id: \.id) { voice in
                    Text("\(voice.name) · \(voice.description ?? voice.id)").tag(voice.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            Text(helper)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func saveVoiceSettings() {
        let targetBookId = ensureShelfBookId()
        guard let targetBookId else { return }

        let cleaned = editableVoiceBindings.filter { !$0.value.isEmpty }
        store.updateVoiceBindings(bookId: targetBookId, bindings: cleaned)
        if !chapters.isEmpty {
            store.updateChapters(bookId: targetBookId, chapters: chapters)
        }
    }

    private func ensureShelfBookId() -> UUID? {
        if let existing = store.existingBook(matching: book) {
            return existing.id
        }

        var newBook = book
        if !chapters.isEmpty {
            newBook.chapters = chapters
        }
        store.addBook(newBook)
        return store.existingBook(matching: newBook)?.id
    }
}
