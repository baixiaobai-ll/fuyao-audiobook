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
    private let detailBlue = Color(red: 0.43, green: 0.66, blue: 0.97)
    private let detailPurple = Color(red: 0.62, green: 0.49, blue: 0.95)
    private let detailIndigo = Color(red: 0.35, green: 0.47, blue: 0.84)

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

    private var continueChapter: Chapter? {
        guard let index = lastReadChapterIndex else { return nil }
        return chapters.first(where: { $0.index == index })
    }

    private var isAlreadyInShelf: Bool {
        store.containsSameBook(as: book)
    }

    private var voiceSummaryText: String {
        configurableRoleNames.isEmpty ? selectedNarrationVoiceName : "\(selectedNarrationVoiceName) + \(configurableRoleNames.count) 个角色"
    }

    private var sourceBadgeTitle: String {
        book.source == .local ? "本地导入" : "公开来源"
    }

    private var chapterSectionHint: String {
        if isGenerating {
            return "当前正在处理章节内容，生成完成后会自动跳转到播放页。"
        }
        return "轻点任一章节即可开始生成并播放，收听进度会自动保存。"
    }

    private var detailActionGradient: LinearGradient {
        LinearGradient(
            colors: [detailBlue, detailPurple, detailIndigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var detailSoftGradient: LinearGradient {
        LinearGradient(
            colors: [
                detailBlue.opacity(0.16),
                detailPurple.opacity(0.18),
                Color.white.opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func voiceTagTint(for bindingKey: String) -> Color {
        _ = bindingKey
        return detailPurple
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                bookHeroCard
                voiceEntryCard

                if isLoadingChapters {
                    loadingCard
                } else if let err = errorMessage {
                    errorCard(message: err)
                }

                if isGenerating, let idx = generatingChapterIndex {
                    generatingCard(chapterIndex: idx)
                }

                chapterSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(detailBackground.ignoresSafeArea())
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(detailIndigo)
        .onAppear { loadChapters() }
        .sheet(isPresented: $showVoiceSettings) {
            voiceSettingsSheet
        }
    }

    private var detailBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.96, blue: 1.0),
                Color(red: 0.91, green: 0.94, blue: 1.0),
                Color(red: 0.97, green: 0.98, blue: 1.0),
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(red: 0.67, green: 0.72, blue: 0.98).opacity(0.18))
                .frame(width: 240, height: 240)
                .blur(radius: 20)
                .offset(x: 80, y: -16)
        }
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(Color(red: 0.56, green: 0.82, blue: 1.0).opacity(0.12))
                .frame(width: 200, height: 200)
                .blur(radius: 24)
                .offset(x: -70, y: -70)
        }
    }

    private var bookHeroCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.53, green: 0.78, blue: 0.97).opacity(0.24),
                                        Color(red: 0.62, green: 0.58, blue: 0.94).opacity(0.16)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 108, height: 146)
                            .offset(x: 8, y: 8)

                        BookCoverView(
                            coverURL: book.coverURL,
                            title: book.title,
                            size: CGSize(width: 104, height: 142)
                        )
                    }
                    .padding(.trailing, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(book.title)
                            .font(.title3.bold())
                            .foregroundStyle(AppTheme.Colors.textPrimary)

                        Text(book.author)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        HStack(spacing: 8) {
                            CapsuleInfoTag(
                                title: sourceBadgeTitle,
                                icon: book.source == .local ? "internaldrive" : "network",
                                tint: detailPurple
                            )
                            CapsuleInfoTag(
                                title: chapters.isEmpty ? "待加载章节" : "\(chapters.count) 章",
                                icon: "text.justify",
                                tint: detailPurple
                            )
                        }

                        if let lastReadChapterTitle {
                            Label(lastReadChapterTitle, systemImage: "headphones")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(detailPurple)
                                .lineLimit(2)
                        } else {
                            Text("先挑一章开始，之后会自动记住你的收听进度。")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 12) {
                    detailMetricCard(
                        title: "章节",
                        value: chapters.isEmpty ? "待载入" : "\(chapters.count)",
                        icon: "list.bullet.rectangle",
                        tint: detailPurple
                    )
                    detailMetricCard(
                        title: "进度",
                        value: lastReadChapterIndex == nil ? "未开始" : "第 \(min((lastReadChapterIndex ?? 0) + 1, max(chapters.count, 1))) 章",
                        icon: "headphones",
                        tint: detailPurple
                    )
                }

                VStack(spacing: 10) {
                    if let continueChapter {
                        Button {
                            playChapter(continueChapter)
                        } label: {
                            Label("继续播放 \(continueChapter.title)", systemImage: "play.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(detailActionGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(LiftPressButtonStyle())
                    } else if !isAlreadyInShelf {
                        Button {
                            addCurrentBookToShelf()
                        } label: {
                            Label("加入书架", systemImage: "books.vertical.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(detailActionGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(LiftPressButtonStyle())
                    } else if !chapters.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(detailPurple)
                            Text("从第一章开始收听，角色音色会在播放过程中逐步识别。")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.trianglehead.clockwise")
                                .foregroundStyle(detailIndigo)
                            Text("已加入书架，章节会在可用时自动补齐；网络恢复后也可以再次进入详情页继续加载。")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private var voiceEntryCard: some View {
        Button {
            prepareVoiceSettings()
            showVoiceSettings = true
        } label: {
            SurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            detailBlue.opacity(0.22),
                                            detailPurple.opacity(0.32)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 46, height: 46)

                            Image(systemName: "waveform.and.mic")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(detailPurple)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("当前配音方案")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text("点击后可调整背景音与角色音色，当前旁白为 \(selectedNarrationVoiceName)。")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(detailPurple)
                    }

                    HStack(spacing: 8) {
                        CapsuleInfoTag(title: selectedNarrationVoiceName, icon: "music.note", tint: detailPurple)
                        CapsuleInfoTag(
                            title: configurableRoleNames.isEmpty ? "待识别角色" : "\(configurableRoleNames.count) 个角色",
                            icon: configurableRoleNames.isEmpty ? "person.crop.circle.badge.questionmark" : "person.2.fill",
                            tint: detailPurple
                        )
                    }
                }
            }
        }
        .buttonStyle(LiftPressButtonStyle(scale: 0.985))
    }

    private var loadingCard: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(detailBlue.opacity(0.12))
                        .frame(width: 34, height: 34)
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(detailIndigo)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("正在整理章节目录…")
                        .font(.subheadline.weight(.semibold))
                    Text("目录载入完成后，就可以直接从任意章节开始。")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    private func errorCard(message: String) -> some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("当前页面出现了一点问题")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func generatingCard(chapterIndex: Int) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("正在生成第 \(chapterIndex + 1) 章")
                            .font(.headline)
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Button("取消") {
                        generationTask?.cancel()
                        generationTask = nil
                        isGenerating = false
                        generatingChapterIndex = nil
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(detailPurple)
                }

                ProgressView()
                    .tint(detailIndigo)
            }
        }
    }

    private var chapterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("章节列表")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(chapterSectionHint)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer()
                CapsuleInfoTag(title: "\(chapters.count) 章", icon: "list.bullet.rectangle", tint: detailPurple)
            }

            if let lastReadChapterTitle {
                SurfaceCard {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(detailPurple)
                        Text("上次听到：\(lastReadChapterTitle)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }

            ForEach(visibleChapters) { chapter in
                chapterButton(chapter)
            }

            if hasMoreChapters {
                Button {
                    visibleChapterCount = min(visibleChapterCount + chapterPageSize, chapters.count)
                } label: {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Text("加载更多章节")
                                .font(.subheadline.weight(.semibold))
                            Text("已显示 \(visibleChapters.count)/\(chapters.count)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(detailSoftGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.88),
                                        detailPurple.opacity(0.22),
                                        detailBlue.opacity(0.18)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(LiftPressButtonStyle(scale: 0.99))
            }
        }
    }

    private func chapterButton(_ chapter: Chapter) -> some View {
        Button(action: { playChapter(chapter) }) {
            HStack(spacing: 14) {
                ZStack {
                    if chapter.index == lastReadChapterIndex {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(detailBlue.opacity(0.16))
                            .frame(width: 42, height: 42)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(detailSoftGradient)
                            .frame(width: 42, height: 42)
                    }

                    if isGenerating && generatingChapterIndex == chapter.index {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(detailIndigo)
                    } else {
                        Image(systemName: chapter.index == lastReadChapterIndex ? "headphones" : "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(chapter.index == lastReadChapterIndex ? detailIndigo : detailPurple)
                    }
                }

                Text("\(chapter.index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 24, alignment: .center)

                VStack(alignment: .leading, spacing: 5) {
                    Text(chapter.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(2)

                    if isGenerating && generatingChapterIndex == chapter.index {
                        Text("正在生成中…")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(detailPurple)
                    } else if chapter.index == loadedChapterIndex, player.currentPlaylist != nil {
                        Text("已就绪，轻点可回到播放页")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(detailPurple)
                    } else if chapter.index == lastReadChapterIndex {
                        Text("上次听到这里")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(detailIndigo)
                    } else {
                        Text("点按即可开始生成并播放")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(detailPurple.opacity(0.8))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(detailSoftGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.86),
                                        detailPurple.opacity(0.20),
                                        detailBlue.opacity(0.16)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(LiftPressButtonStyle(scale: 0.985))
        .disabled(isGenerating)
    }

    private func detailMetricCard(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 34, height: 34)

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.48))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )
        )
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
        let providerName: String
        switch Config.aiProvider {
        case .kimi: providerName = "Kimi"
        case .qwen: providerName = "通义千问"
        case .local: providerName = "本地规则"
        }

        if message.contains("分析超时") || message.contains("\(providerName) 分析超时") {
            return "文本分析超时。请检查网络，或稍后重试。"
        }
        if message.contains("鉴权失败") || message.contains("\(providerName) 鉴权失败") {
            return "文本分析鉴权失败。请检查 Config.plist 里的 AI_API_KEY，并确认 AI_PROVIDER=\(Config.aiProvider.rawValue)。"
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

    private func addCurrentBookToShelf() {
        var bookToAdd = book
        if !chapters.isEmpty {
            bookToAdd.chapters = chapters
        }
        store.addBook(bookToAdd)

        if !chapters.isEmpty,
           let shelfBookId = store.existingBook(matching: bookToAdd)?.id {
            store.updateChapters(bookId: shelfBookId, chapters: chapters)
        }
    }

    private func resetChapterPagination() {
        visibleChapterCount = min(chapterPageSize, chapters.count)
    }

    @ViewBuilder
    private var voiceSettingsSheet: some View {
        NavigationStack {
            ZStack {
                detailBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("配音设置")
                                    .font(.title3.bold())
                                Text("可手动调整旁白和已识别角色的音色搭配，保存后新生成的章节会优先使用这套方案。")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)

                                HStack(spacing: 8) {
                                    CapsuleInfoTag(title: selectedNarrationVoiceName, icon: "music.note", tint: detailPurple)
                                    CapsuleInfoTag(title: "\(configurableRoleNames.count) 个角色", icon: "person.2.fill", tint: detailPurple)
                                }
                            }
                        }
                        

                        voicePickerCard(
                            title: "旁白音色",
                            bindingKey: VoiceManager.narrationBindingKey,
                            helper: "用于旁白、描述、未命名对白等内容"
                        )

                        if configurableRoleNames.isEmpty {
                            SurfaceCard {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "person.crop.circle.badge.questionmark")
                                        .font(.title3)
                                        .foregroundStyle(detailPurple)

                                    Text("当前还没有已识别并保存的角色。先播放一章，角色音色会自动生成，之后就可以逐个调整。")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("角色音色")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)

                                ForEach(configurableRoleNames, id: \.self) { roleName in
                                    voicePickerCard(
                                        title: roleName,
                                        bindingKey: roleName,
                                        helper: "该角色的对白默认使用这个音色"
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("配音设置")
            .navigationBarTitleDisplayMode(.inline)
            .tint(detailIndigo)
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

    private func voicePickerCard(title: String, bindingKey: String, helper: String) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(helper)
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    CapsuleInfoTag(
                        title: voiceName(for: editableVoiceBindings[bindingKey] ?? availableVoices.first?.id),
                        icon: "waveform",
                        tint: voiceTagTint(for: bindingKey)
                    )
                }

                Picker(title, selection: Binding(
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
                .tint(detailIndigo)
            }
        }
    }

    private func voiceName(for voiceId: String?) -> String {
        guard let voiceId,
              let voice = availableVoices.first(where: { $0.id == voiceId }) else {
            return "默认音色"
        }
        return voice.name
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
