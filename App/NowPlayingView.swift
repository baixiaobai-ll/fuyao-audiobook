import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var player: AudioBookPlayer
    @EnvironmentObject var store: BookshelfStore

    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var showSleepTimer = false
    @State private var showPlaylist = false
    @State private var showChapterTextSheet = false
    @State private var chapterTextBody: String?
    @State private var chapterTextHint: String?
    @State private var chapterSwitchError: String?
    @State private var isSwitchingChapter = false

    private let rates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            Group {
                if player.currentPlaylist != nil {
                    playerContent
                } else {
                    emptyState
                }
            }
            .navigationTitle("播放中")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isSwitchingChapter {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        ProgressView("切换章节…")
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .alert("切换失败", isPresented: Binding(
                get: { chapterSwitchError != nil },
                set: { if !$0 { chapterSwitchError = nil } }
            )) {
                Button("好", role: .cancel) { chapterSwitchError = nil }
            } message: {
                if let e = chapterSwitchError { Text(e) }
            }
            .sheet(isPresented: $showChapterTextSheet) {
                chapterTextReaderSheet
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("empty_playing")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)

            Text("暂无播放内容")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("去书架选一本书吧")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Player Content

    private var playerContent: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                if let ctx = player.currentPlaylist?.chapterContext {
                    Text(ctx.bookTitle)
                        .font(.headline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Text(currentChapterTitle(from: ctx))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else {
                    Text(player.currentPlaylist?.title ?? "")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            playbackArtwork
                .padding(.vertical, 24)

            progressSection

            rateSelector

            controlButtons

            bottomActions

            Spacer()
        }
        .padding(.horizontal)
    }

    private func currentChapterTitle(from ctx: PlaybackChapterContext) -> String {
        if let t = ctx.chapters.first(where: { $0.index == ctx.currentChapterIndex })?.title, !t.isEmpty {
            return t
        }
        return player.currentPlaylist?.title ?? ""
    }

    @ViewBuilder
    private var playbackArtwork: some View {
        if let ctx = player.currentPlaylist?.chapterContext {
            Button(action: openChapterTextSheet) {
                BookCoverView(
                    coverURL: coverURLForPlayback(ctx: ctx),
                    title: ctx.bookTitle,
                    size: CGSize(width: 200, height: 280)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看章节正文")
        } else {
            Image(systemName: "headphones")
                .font(.system(size: 100))
                .foregroundColor(.accentColor)
        }
    }

    private func coverURLForPlayback(ctx: PlaybackChapterContext) -> String? {
        if let u = ctx.bookCoverURL, !u.isEmpty { return u }
        return store.books.first(where: { $0.id == ctx.shelfBookId })?.coverURL
    }

    private func openChapterTextSheet() {
        guard let ctx = player.currentPlaylist?.chapterContext else { return }
        guard let book = resolvedBook(for: ctx) else { return }
        let summary = ctx.chapters.first(where: { $0.index == ctx.currentChapterIndex })
        let chapterTitle = summary?.title ?? (player.currentPlaylist?.title ?? "正文")
        let chapter = Chapter(title: chapterTitle, index: ctx.currentChapterIndex, isDownloaded: true)

        chapterTextBody = nil
        chapterTextHint = nil
        showChapterTextSheet = true

        Task { @MainActor in
            do {
                let text = try await BookChapterPlayback.fetchContent(
                    shelfBookId: ctx.shelfBookId,
                    book: book,
                    chapter: chapter
                )
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    chapterTextBody = text
                } else {
                    chapterTextHint = "章节内容为空"
                }
            } catch {
                chapterTextHint = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private var chapterTextReaderSheet: some View {
        NavigationStack {
            Group {
                if let hint = chapterTextHint {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(hint)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let body = chapterTextBody {
                    ScrollView {
                        Text(body)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    ProgressView("加载正文…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("章节正文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showChapterTextSheet = false }
                }
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: {
                        isDragging ? dragValue : sliderValue
                    },
                    set: { newValue in
                        isDragging = true
                        dragValue = newValue
                    }
                ),
                in: 0...safeMaxDuration,
                onEditingChanged: { editing in
                    if !editing {
                        player.seekToAggregatedTime(dragValue)
                        isDragging = false
                    }
                }
            )
            .accentColor(.accentColor)

            HStack {
                Text(formatTime(isDragging ? dragValue : player.progress.currentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(player.progress.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
    }

    private var safeMaxDuration: Double {
        let d = player.progress.duration
        return d.isFinite && d > 0 ? d : 1
    }

    private var sliderValue: Double {
        guard player.progress.duration > 0,
              player.progress.currentTime.isFinite,
              player.progress.duration.isFinite else { return 0 }
        return min(player.progress.currentTime, safeMaxDuration)
    }

    // MARK: - Rate Selector

    private var rateSelector: some View {
        HStack(spacing: 12) {
            ForEach(rates, id: \.self) { rate in
                Button {
                    player.setPlaybackRate(rate)
                } label: {
                    Text(rateLabel(rate))
                        .font(.caption)
                        .fontWeight(player.config.playbackRate == rate ? .bold : .regular)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            player.config.playbackRate == rate
                                ? Color.accentColor.opacity(0.2)
                                : Color.gray.opacity(0.1)
                        )
                        .cornerRadius(16)
                }
                .foregroundColor(player.config.playbackRate == rate ? .accentColor : .primary)
            }
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        if rate == Float(Int(rate)) {
            return "\(Int(rate)).0x"
        }
        return "\(rate)x"
    }

    // MARK: - Controls

    private var controlButtons: some View {
        HStack(spacing: 48) {
            Button { goBackward() } label: {
                Image(systemName: "backward.fill")
                    .font(.title)
            }
            .disabled(isSwitchingChapter || !chapterNavBackwardEnabled())

            Button {
                if player.state == .playing {
                    player.pause()
                } else {
                    player.play()
                }
            } label: {
                Image(systemName: playButtonIcon)
                    .font(.system(size: 60))
            }

            Button { goForward() } label: {
                Image(systemName: "forward.fill")
                    .font(.title)
            }
            .disabled(isSwitchingChapter || !chapterNavForwardEnabled())
        }
        .foregroundColor(.primary)
        .padding(.vertical, 8)
    }

    private var playButtonIcon: String {
        switch player.state {
        case .playing: return "pause.circle.fill"
        case .loading: return "hourglass.circle"
        default: return "play.circle.fill"
        }
    }

    private func chapterNavBackwardEnabled() -> Bool {
        if let ctx = player.currentPlaylist?.chapterContext, ctx.chapters.count > 1 {
            guard let pos = ctx.chapters.firstIndex(where: { $0.index == ctx.currentChapterIndex }) else { return false }
            return pos > 0
        }
        return player.currentPlaylist?.hasPrevious ?? false
    }

    private func chapterNavForwardEnabled() -> Bool {
        if let ctx = player.currentPlaylist?.chapterContext, ctx.chapters.count > 1 {
            guard let pos = ctx.chapters.firstIndex(where: { $0.index == ctx.currentChapterIndex }) else { return false }
            return pos + 1 < ctx.chapters.count
        }
        return player.currentPlaylist?.hasNext ?? false
    }

    private func goBackward() {
        if let ctx = player.currentPlaylist?.chapterContext, ctx.chapters.count > 1 {
            guard let pos = ctx.chapters.firstIndex(where: { $0.index == ctx.currentChapterIndex }), pos > 0 else { return }
            let prev = ctx.chapters[pos - 1]
            Task { await switchToChapter(index: prev.index) }
        } else {
            player.previous()
        }
    }

    private func goForward() {
        if let ctx = player.currentPlaylist?.chapterContext, ctx.chapters.count > 1 {
            guard let pos = ctx.chapters.firstIndex(where: { $0.index == ctx.currentChapterIndex }),
                  pos + 1 < ctx.chapters.count else { return }
            let next = ctx.chapters[pos + 1]
            Task { await switchToChapter(index: next.index) }
        } else {
            player.next()
        }
    }

    // MARK: - Bottom Actions

    private var bottomActions: some View {
        HStack(spacing: 40) {
            Button {
                cycleRepeatMode()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: repeatIcon)
                        .font(.title3)
                    Text(repeatLabel)
                        .font(.caption2)
                }
            }
            .foregroundColor(player.config.repeatMode == .none ? .secondary : .accentColor)

            Button { showSleepTimer = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.title3)
                    if let remaining = player.sleepTimerRemaining {
                        Text(formatTime(remaining))
                            .font(.caption2)
                    } else {
                        Text("定时")
                            .font(.caption2)
                    }
                }
            }
            .foregroundColor(player.sleepTimerRemaining != nil ? .accentColor : .secondary)
            .confirmationDialog("定时关闭", isPresented: $showSleepTimer) {
                Button("15 分钟") { player.setSleepTimer(minutes: 15) }
                Button("30 分钟") { player.setSleepTimer(minutes: 30) }
                Button("60 分钟") { player.setSleepTimer(minutes: 60) }
                if player.sleepTimerRemaining != nil {
                    Button("取消定时", role: .destructive) { player.setSleepTimer(minutes: nil) }
                }
                Button("取消", role: .cancel) {}
            }

            Button { showPlaylist = true } label: {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                    Text("目录")
                        .font(.caption2)
                }
            }
            .foregroundColor(.secondary)
            .sheet(isPresented: $showPlaylist) {
                playlistSheet
            }
        }
    }

    private var repeatIcon: String {
        switch player.config.repeatMode {
        case .none: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }

    private var repeatLabel: String {
        switch player.config.repeatMode {
        case .none: return "不循环"
        case .one: return "单章"
        case .all: return "列表"
        }
    }

    private func cycleRepeatMode() {
        switch player.config.repeatMode {
        case .none: player.setRepeatMode(.one)
        case .one: player.setRepeatMode(.all)
        case .all: player.setRepeatMode(.none)
        }
    }

    // MARK: - Sheet（章节目录）

    private var playlistSheet: some View {
        NavigationStack {
            List {
                if let ctx = player.currentPlaylist?.chapterContext, !ctx.chapters.isEmpty {
                    ForEach(ctx.chapters, id: \.index) { summary in
                        Button {
                            Task { await switchToChapter(index: summary.index) }
                        } label: {
                            HStack {
                                Text(summary.title)
                                    .font(.subheadline)
                                    .fontWeight(summary.index == ctx.currentChapterIndex ? .bold : .regular)
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                Spacer()
                                if summary.index == ctx.currentChapterIndex {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                } else if let playlist = player.currentPlaylist {
                    ForEach(Array(playlist.items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            player.jumpTo(index: index)
                            showPlaylist = false
                        } label: {
                            HStack {
                                Text(item.segment.text.prefix(60) + (item.segment.text.count > 60 ? "…" : ""))
                                    .font(.subheadline)
                                    .fontWeight(index == playlist.currentIndex ? .bold : .regular)
                                    .lineLimit(2)
                                Spacer()
                                if index == playlist.currentIndex {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle(player.currentPlaylist?.chapterContext != nil ? "章节目录" : "播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showPlaylist = false }
                }
            }
        }
    }

    // MARK: - Chapter switch

    private func resolvedBook(for ctx: PlaybackChapterContext) -> Book? {
        if let b = store.books.first(where: { $0.id == ctx.shelfBookId }) {
            return b
        }
        return Book(
            id: ctx.shelfBookId,
            title: ctx.bookTitle,
            author: "",
            coverURL: ctx.bookCoverURL,
            bookId: ctx.apiBookId,
            chapters: ctx.chapters.map { Chapter(title: $0.title, index: $0.index, isDownloaded: true) },
            source: ctx.bookSource
        )
    }

    private func switchToChapter(index: Int) async {
        guard let ctx = player.currentPlaylist?.chapterContext else { return }
        guard index != ctx.currentChapterIndex else {
            await MainActor.run { showPlaylist = false }
            return
        }
        guard let summary = ctx.chapters.first(where: { $0.index == index }) else { return }

        await MainActor.run {
            isSwitchingChapter = true
            showPlaylist = false
        }
        defer {
            Task { @MainActor in isSwitchingChapter = false }
        }

        guard let resolved = resolvedBook(for: ctx) else {
            await MainActor.run { chapterSwitchError = "无法解析书籍信息" }
            return
        }

        let chapter = resolved.chapters.first { $0.index == summary.index }
            ?? Chapter(title: summary.title, index: summary.index, isDownloaded: true)
        let allChapters: [Chapter]
        if resolved.chapters.isEmpty {
            allChapters = ctx.chapters.map { Chapter(title: $0.title, index: $0.index, isDownloaded: true) }
        } else {
            allChapters = resolved.chapters
        }
        let sorted = allChapters.sorted { $0.index < $1.index }

        do {
            try await BookChapterPlayback.play(
                shelfBook: resolved,
                chapter: chapter,
                allChapters: sorted,
                store: store,
                player: player,
                onProgressMessage: { _ in },
                onFirstPlaybackStarted: {}
            )
        } catch {
            await MainActor.run { chapterSwitchError = error.localizedDescription }
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
