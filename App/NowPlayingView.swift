import SwiftUI

struct NowPlayingView: View {
    private enum ContentMode {
        case cover
        case text
    }

    @EnvironmentObject var player: AudioBookPlayer
    @EnvironmentObject var store: BookshelfStore

    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var showSleepTimer = false
    @State private var showPlaylist = false
    @State private var contentMode: ContentMode = .cover
    @State private var chapterTextBody: String?
    @State private var chapterTextHint: String?
    @State private var chapterSwitchError: String?
    @State private var isSwitchingChapter = false
    private let pageBlue = Color(red: 0.52, green: 0.76, blue: 0.98)
    private let pagePurple = Color(red: 0.66, green: 0.54, blue: 0.96)
    private let pageIndigo = Color(red: 0.35, green: 0.45, blue: 0.82)

    var body: some View {
        NavigationStack {
            ZStack {
                playbackBackground

                Group {
                    if player.currentPlaylist != nil {
                        playerContent
                    } else {
                        emptyState
                    }
                }
                .padding(.top, 4)

                if isSwitchingChapter {
                    ZStack {
                        Color.black.opacity(0.18).ignoresSafeArea()

                        SurfaceCard(padding: 20) {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(pageIndigo)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("正在切换章节")
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                    Text("请稍等，新的音频内容马上就绪。")
                                        .font(.footnote)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle(player.currentPlaylist != nil ? topPlaybackDisplayTitle : "播放中")
            .navigationBarTitleDisplayMode(.inline)
            .tint(pageIndigo)
            .alert("切换失败", isPresented: Binding(
                get: { chapterSwitchError != nil },
                set: { if !$0 { chapterSwitchError = nil } }
            )) {
                Button("好", role: .cancel) { chapterSwitchError = nil }
            } message: {
                if let e = chapterSwitchError { Text(e) }
            }
            .onChange(of: contentMode) { mode in
                if mode == .text {
                    loadInlineChapterText()
                }
            }
            .onChange(of: currentChapterContentKey) { _ in
                if contentMode == .text {
                    loadInlineChapterText()
                }
            }
        }
    }

    private var playbackBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.92, green: 0.94, blue: 1.0),
                Color(red: 0.98, green: 0.98, blue: 1.0),
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(pagePurple.opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 24)
                .offset(x: 88, y: -52)
        }
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(pageBlue.opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 22)
                .offset(x: -72, y: -68)
        }
        .ignoresSafeArea()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 44)

                Image("empty_playing")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 214)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)

                Text("播放列表为空")
                    .font(.title3.bold())
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                SurfaceCard {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [pageBlue, pagePurple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("小提示")
                                .font(.subheadline.bold())
                            Text("从书架中选择一本最想听的故事，然后开始畅游奇幻世界")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Player Content

    private var playerContent: some View {
        VStack(spacing: 14) {
            coverFocusSection
            secondaryActionStrip
            transportPanel
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var coverFocusSection: some View {
        VStack(spacing: 12) {
            coverModeBar

            contentStage

            VStack(spacing: 8) {
                Text(playbackSubtitle)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let remaining = player.sleepTimerRemaining {
                    infoPill(title: "剩余 \(formatTime(remaining))", icon: "moon.zzz.fill")
                }
            }
        }
    }

    private var coverModeBar: some View {
        HStack(spacing: 10) {
            modeChip(title: "封面", active: contentMode == .cover) { contentMode = .cover }
            modeChip(title: "正文", active: contentMode == .text) { contentMode = .text }
        }
    }

    private func modeChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(title: title, active: active)
        }
        .buttonStyle(LiftPressButtonStyle(scale: 0.97))
    }

    private func chipLabel(title: String, active: Bool) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? .white : pageIndigo)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                Group {
                    if active {
                        LinearGradient(
                            colors: [pageBlue, pagePurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        LinearGradient(
                            colors: [Color.white.opacity(0.7), pagePurple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .clipShape(Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(active ? 0.12 : 0.72), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var contentStage: some View {
        if contentMode == .text {
            inlineTextPanel
        } else {
            artworkButton
        }
    }

    @ViewBuilder
    private var artworkButton: some View {
        if let ctx = player.currentPlaylist?.chapterContext {
            Button(action: { contentMode = .text }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    pageBlue.opacity(0.22),
                                    pagePurple.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 174, height: 242)
                        .offset(x: 10, y: 10)

                    BookCoverView(
                        coverURL: coverURLForPlayback(ctx: ctx),
                        title: ctx.bookTitle,
                        size: CGSize(width: 166, height: 232)
                    )
                }
            }
            .buttonStyle(LiftPressButtonStyle(scale: 0.985))
            .accessibilityLabel("查看章节正文")
        } else {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [pageBlue.opacity(0.24), pagePurple.opacity(0.26)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 188, height: 188)

                Image(systemName: "headphones")
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(pageIndigo)
            }
        }
    }

    private var inlineTextPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.78),
                            pagePurple.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.76), lineWidth: 1)
                )

            Group {
                if let hint = chapterTextHint {
                    VStack(spacing: 10) {
                        TintedIconBadge(icon: "doc.text", size: 42, iconSize: 16)
                        Text(hint)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                } else if let body = chapterTextBody {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(formattedChapterParagraphs(from: body), id: \.self) { paragraph in
                                Text(paragraph)
                                    .font(.body)
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .lineSpacing(7)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                    }
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(pageIndigo)
                        Text("正在加载正文…")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .frame(height: 252)
    }

    private var transportPanel: some View {
        SurfaceCard(padding: 14) {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    HStack {
                        Text("\(Int((isDragging ? draggedPercentage : player.progress.percentage).rounded()))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(pageIndigo)
                        Spacer()
                        Text(isDragging ? "松手后跳转" : "拖动可快进快退")
                            .font(.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Slider(
                        value: Binding(
                            get: { isDragging ? dragValue : sliderValue },
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
                    .tint(pagePurple)

                    HStack {
                        Text(formatTime(isDragging ? dragValue : player.progress.currentTime))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .monospacedDigit()
                        Spacer()
                        Text(formatTime(player.progress.duration))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .monospacedDigit()
                    }
                }

                HStack(spacing: 18) {
                    playerCircleButton(
                        icon: "backward.fill",
                        size: 52,
                        enabled: !isSwitchingChapter && chapterNavBackwardEnabled(),
                        filled: false
                    ) {
                        goBackward()
                    }

                    Button {
                        if player.state == .playing {
                            player.pause()
                        } else {
                            player.play()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [pageBlue, pagePurple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                )

                            Image(systemName: playButtonIcon)
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 78, height: 78)
                        .shadow(color: pagePurple.opacity(0.22), radius: 12, x: 0, y: 5)
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.95))

                    playerCircleButton(
                        icon: "forward.fill",
                        size: 52,
                        enabled: !isSwitchingChapter && chapterNavForwardEnabled(),
                        filled: false
                    ) {
                        goForward()
                    }
                }
            }
        }
    }

    private var secondaryActionStrip: some View {
        HStack(spacing: 12) {
            actionPanelButton(
                title: repeatLabel,
                subtitle: "循环模式",
                icon: repeatIcon,
                active: player.config.repeatMode != .none
            ) {
                cycleRepeatMode()
            }

            actionPanelButton(
                title: player.currentPlaylist?.chapterContext != nil ? "章节目录" : "播放列表",
                subtitle: "快速跳转",
                icon: "list.bullet",
                active: showPlaylist
            ) {
                showPlaylist = true
            }

            actionPanelButton(
                title: player.sleepTimerRemaining != nil ? formatTime(player.sleepTimerRemaining ?? 0) : "定时",
                subtitle: "睡眠定时",
                icon: "timer",
                active: player.sleepTimerRemaining != nil
            ) {
                showSleepTimer = true
            }
            .confirmationDialog("定时关闭", isPresented: $showSleepTimer) {
                Button("15 分钟") { player.setSleepTimer(minutes: 15) }
                Button("30 分钟") { player.setSleepTimer(minutes: 30) }
                Button("60 分钟") { player.setSleepTimer(minutes: 60) }
                if player.sleepTimerRemaining != nil {
                    Button("取消定时", role: .destructive) { player.setSleepTimer(minutes: nil) }
                }
                Button("取消", role: .cancel) {}
            }
        }
        .padding(.horizontal, 8)
        .sheet(isPresented: $showPlaylist) {
            playlistSheet
        }
    }

    // MARK: - Playback Text Helpers

    private var currentBookTitle: String {
        player.currentPlaylist?.chapterContext?.bookTitle ?? "当前书籍"
    }

    private var currentPrimaryTitle: String {
        if let ctx = player.currentPlaylist?.chapterContext {
            return currentChapterTitle(from: ctx)
        }
        return player.currentPlaylist?.title ?? "暂无标题"
    }

    private var topPlaybackDisplayTitle: String {
        guard player.currentPlaylist != nil else { return "播放中" }
        if currentBookTitle == currentPrimaryTitle || currentBookTitle.isEmpty {
            return currentPrimaryTitle
        }
        return "\(currentBookTitle) · \(currentPrimaryTitle)"
    }

    private var playbackSubtitle: String {
        if let ctx = player.currentPlaylist?.chapterContext {
            return "正在收听《\(ctx.bookTitle)》中的章节内容，切换目录后会自动续播。"
        }
        return "当前正在播放合成好的音频内容。"
    }

    private var remainingTimeForDisplay: TimeInterval {
        max(0, player.progress.duration - (isDragging ? dragValue : player.progress.currentTime))
    }

    private var draggedPercentage: Double {
        guard safeMaxDuration > 0 else { return 0 }
        return min(max((dragValue / safeMaxDuration) * 100, 0), 100)
    }

    private func infoPill(title: String, icon: String) -> some View {
        CapsuleInfoTag(title: title, icon: icon, tint: pagePurple)
    }

    private func playerCircleButton(
        icon: String,
        size: CGFloat,
        enabled: Bool,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        filled
                            ? AnyShapeStyle(LinearGradient(colors: [pageBlue, pagePurple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.white.opacity(enabled ? 0.72 : 0.46))
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                filled ? Color.white.opacity(0.14) : Color.white.opacity(0.78),
                                lineWidth: 1
                            )
                    )

                Image(systemName: icon)
                    .font(.system(size: filled ? 30 : 20, weight: .semibold))
                    .foregroundStyle(filled ? .white : (enabled ? pageIndigo : Color.secondary))
            }
            .frame(width: size, height: size)
            .shadow(color: filled ? pagePurple.opacity(0.22) : .black.opacity(0.06), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(LiftPressButtonStyle(scale: 0.95))
        .disabled(!enabled)
    }

    private func actionPanelButton(
        title: String,
        subtitle: String,
        icon: String,
        active: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                TintedIconBadge(
                    icon: icon,
                    size: 30,
                    iconSize: 12,
                    primary: active ? pagePurple : pageBlue,
                    secondary: pageIndigo
                )

                VStack(spacing: 2) {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.72),
                                (active ? pagePurple : pageBlue).opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: 1)
            )
        }
        .buttonStyle(LiftPressButtonStyle(scale: 0.98))
    }

    // MARK: - Existing Playback Helpers

    private func currentChapterTitle(from ctx: PlaybackChapterContext) -> String {
        if let t = ctx.chapters.first(where: { $0.index == ctx.currentChapterIndex })?.title, !t.isEmpty {
            return t
        }
        return player.currentPlaylist?.title ?? ""
    }

    private func resolvedChapterPosition(in ctx: PlaybackChapterContext) -> Int {
        ctx.chapters.firstIndex(where: { $0.index == ctx.currentChapterIndex }) ?? 0
    }

    private func coverURLForPlayback(ctx: PlaybackChapterContext) -> String? {
        if let u = ctx.bookCoverURL, !u.isEmpty { return u }
        return store.books.first(where: { $0.id == ctx.shelfBookId })?.coverURL
    }

    private var currentChapterContentKey: String {
        guard let ctx = player.currentPlaylist?.chapterContext else { return "none" }
        return "\(ctx.shelfBookId.uuidString)-\(ctx.currentChapterIndex)"
    }

    private func openChapterTextSheet() {
        contentMode = .text
        loadInlineChapterText()
    }

    private func loadInlineChapterText() {
        guard let ctx = player.currentPlaylist?.chapterContext else { return }
        guard let book = resolvedBook(for: ctx) else { return }
        let summary = ctx.chapters.first(where: { $0.index == ctx.currentChapterIndex })
        let chapterTitle = summary?.title ?? (player.currentPlaylist?.title ?? "正文")
        let chapter = Chapter(title: chapterTitle, index: ctx.currentChapterIndex, isDownloaded: true)

        chapterTextBody = nil
        chapterTextHint = nil

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

    private func formattedChapterParagraphs(from body: String) -> [String] {
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")
        let paragraphs = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return paragraphs.isEmpty ? [body] : paragraphs
    }

    // MARK: - Progress

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

    // MARK: - Controls

    private var playButtonIcon: String {
        switch player.state {
        case .playing: return "pause.fill"
        case .loading: return "hourglass"
        default: return "play.fill"
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
        case .one: return "单章循环"
        case .all: return "列表循环"
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
            ZStack {
                playbackBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        if let ctx = player.currentPlaylist?.chapterContext, !ctx.chapters.isEmpty {
                            ForEach(ctx.chapters, id: \.index) { summary in
                                playlistRow(
                                    title: summary.title,
                                    active: summary.index == ctx.currentChapterIndex
                                ) {
                                    Task { await switchToChapter(index: summary.index) }
                                }
                            }
                        } else if let playlist = player.currentPlaylist {
                            ForEach(Array(playlist.items.enumerated()), id: \.element.id) { index, item in
                                playlistRow(
                                    title: String(item.segment.text.prefix(60)) + (item.segment.text.count > 60 ? "…" : ""),
                                    active: index == playlist.currentIndex
                                ) {
                                    player.jumpTo(index: index)
                                    showPlaylist = false
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(player.currentPlaylist?.chapterContext != nil ? "章节目录" : "播放列表")
            .navigationBarTitleDisplayMode(.inline)
            .tint(pageIndigo)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showPlaylist = false }
                }
            }
        }
    }

    private func playlistRow(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SurfaceCard(padding: 14) {
                HStack(spacing: 12) {
                    TintedIconBadge(
                        icon: active ? "speaker.wave.2.fill" : "play.fill",
                        size: 32,
                        iconSize: 12,
                        primary: active ? pagePurple : pageBlue,
                        secondary: pageIndigo
                    )

                    Text(title)
                        .font(.subheadline.weight(active ? .semibold : .medium))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(2)

                    Spacer()
                }
            }
        }
        .buttonStyle(LiftPressButtonStyle(scale: 0.99))
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
        let hours = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
