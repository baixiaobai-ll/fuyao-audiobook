//
//  AudioBookPlayer.swift
//  AI有声书
//
//  有声书播放器
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
#if canImport(UIKit)
import UIKit
#endif

/// 有声书播放器
public class AudioBookPlayer: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published public var state: PlaybackState = .idle
    @Published public var progress: PlaybackProgress = PlaybackProgress()
    @Published public var currentPlaylist: Playlist?
    @Published public var config: PlaybackConfig = PlaybackConfig()
    @Published public var sleepTimerRemaining: TimeInterval? = nil
    @Published public private(set) var lastErrorMessage: String?
    /// App 内播放页专用的章节占位状态。自动切到下一章生成音频时，
    /// 播放页先展示下一章标题与 0 进度；锁屏/实时活动仍走既有系统媒体链路。
    @Published public private(set) var displayChapterContextOverride: PlaybackChapterContext?

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var sleepTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let cacheManager: AudioCacheManager
    private let sessionManager: PlaybackSessionManager
    private var lastNowPlayingInfoUpdate: TimeInterval = 0
    #if canImport(UIKit)
    /// 当前书在 NowPlayingInfo 上挂的 artwork key（shelfBookId 或 playlist:UUID）。
    /// 用来识别"换书"，不识别"换章"——同一本书内部不重复加载封面。
    private var currentArtworkBookKey: String?
    /// 当前已经成功加载到的封面 UIImage（远程或品牌 fallback）。
    private var currentArtworkImage: UIImage?
    /// 当前正在异步下载的封面 URL，避免重复发起请求。
    private var currentArtworkLoadingURL: URL?
    #endif
    private var isStreamingPlaybackPending = false
    private var pendingRestoredLocalTime: TimeInterval = 0
    private var pendingRestoredItemIndex: Int?
    private var lastSessionSaveTime: TimeInterval = 0
    private var chapterPrefetchHandler: (() async -> Void)?
    private var chapterAdvanceHandler: (() async throws -> Void)?
    private var hasTriggeredChapterPrefetch = false
    private var isAdvancingToNextChapter = false
    private var remoteCommandCenterConfigured = false

    // MARK: - Initialization

    public override init() {
        self.cacheManager = AudioCacheManager()
        self.sessionManager = PlaybackSessionManager()
        super.init()

        setupAudioSession()
        setupNotifications()
        setupRemoteCommandCenter()
        restorePersistedPlaybackState()
        applyListLoopAsDefaultIfNeeded()
    }

    deinit {
        cleanup()
    }

    // MARK: - Public Methods

    /// 加载播放列表
    public func load(playlist: Playlist) {
        let shouldStartFromBeginning = isAdvancingToNextChapter || displayChapterContextOverride != nil
        displayChapterContextOverride = nil
        currentPlaylist = playlist
        state = .idle
        lastErrorMessage = nil
        hasTriggeredChapterPrefetch = false
        isAdvancingToNextChapter = false
        var restoredTime: TimeInterval = 0
        var restoredItemIndex = playlist.currentIndex

        // 尝试恢复上次播放位置
        if !shouldStartFromBeginning, let session = sessionManager.loadSession(for: playlist) {
            let clampedIndex = min(max(session.currentItemIndex, 0), max(playlist.items.count - 1, 0))
            currentPlaylist?.currentIndex = clampedIndex
            restoredTime = max(0, session.currentTime)
            restoredItemIndex = clampedIndex
            print("📖 恢复播放位置: 第 \(clampedIndex + 1) 项")
        }

        pendingRestoredLocalTime = restoredTime
        pendingRestoredItemIndex = restoredTime > 0 ? restoredItemIndex : nil

        if let currentPlaylist {
            progress = PlaybackProgress(
                currentTime: aggregatedTime(
                    in: currentPlaylist,
                    currentItemIndex: restoredItemIndex,
                    localTime: restoredTime
                ),
                duration: max(0, currentPlaylist.totalDuration),
                currentItemIndex: currentPlaylist.currentIndex,
                totalItems: currentPlaylist.items.count
            )
        }

        print("📚 已加载播放列表: \(playlist.title), 共 \(playlist.items.count) 项")
        ChapterPrefetchCoordinator.shared.resetForNewPlayback()
        persistPlaybackState()
        publishNowPlayingInfoCenter()
    }

    /// 追加播放项（流式播放时使用）
    public func append(item: PlaybackItem) {
        currentPlaylist?.items.append(item)
        currentPlaylist?.totalDuration += safeDuration(item.audioData.duration)
        if let playlist = currentPlaylist {
            progress = PlaybackProgress(
                currentTime: progress.currentTime,
                duration: max(progress.currentTime, safeDuration(playlist.totalDuration)),
                currentItemIndex: playlist.currentIndex,
                totalItems: playlist.items.count
            )
        }
        print("➕ 追加播放项: 第 \(item.order + 1) 段")

        if isStreamingPlaybackPending,
           state == .loading,
           player == nil,
           let playlist = currentPlaylist,
           playlist.hasNext {
            next()
            return
        }

        persistPlaybackState()
        updateRemoteCommandAvailability()
    }

    public func beginStreamingPlayback() {
        isStreamingPlaybackPending = true
    }

    public func finishStreamingPlayback() {
        isStreamingPlaybackPending = false

        if state == .loading, player == nil {
            if let playlist = currentPlaylist, playlist.hasNext {
                next()
            } else {
                handlePlaylistEnded()
            }
        }
    }

    func configureChapterPlaybackHandlers(
        prefetch: (() async -> Void)?,
        advance: (() async throws -> Void)?
    ) {
        chapterPrefetchHandler = prefetch
        chapterAdvanceHandler = advance
        hasTriggeredChapterPrefetch = false
        isAdvancingToNextChapter = false
    }

    func presentPlaybackError(_ error: Error) {
        displayChapterContextOverride = nil
        lastErrorMessage = userFacingMessage(for: error)
        state = .error
        publishNowPlayingInfoCenter()
        print("❌ 播放失败: \(lastErrorMessage ?? error.localizedDescription)")
    }

    /// 播放
    public func play() {
        guard let playlist = currentPlaylist,
              let currentItem = playlist.currentItem else {
            print("⚠️ 没有可播放的内容")
            return
        }

        ensureAudioSessionActive()
        state = .loading
        lastErrorMessage = nil

        // 如果已有播放器且是同一项，直接播放
        if player != nil {
            player?.play()
            player?.rate = config.playbackRate
            state = .playing
            publishNowPlayingInfoCenter()
            return
        }

        // 创建新的播放器
        do {
            let audioURL = try cacheManager.getOrCache(audioData: currentItem.audioData, id: currentItem.id.uuidString)
            let playerItem = AVPlayerItem(url: audioURL)

            player = AVPlayer(playerItem: playerItem)
            player?.automaticallyWaitsToMinimizeStalling = true
            player?.volume = config.volume
            player?.rate = config.playbackRate

            setupTimeObserver()
            setupPlayerObservers(for: playerItem)
            let initialSeekTime = restoredLocalTimeIfNeeded(for: playlist.currentIndex)
            startPlayback(for: currentItem, initialSeekTime: initialSeekTime)
        } catch {
            presentPlaybackError(error)
        }
    }

    /// 暂停
    public func pause() {
        player?.pause()
        state = .paused
        saveSession()
        publishNowPlayingInfoCenter()
        print("⏸️ 已暂停")
    }

    /// 停止
    public func stop() {
        displayChapterContextOverride = nil
        cleanupPlayer()
        state = .stopped
        progress = PlaybackProgress()
        lastErrorMessage = nil
        saveSession()
        clearNowPlayingInfoCenter()
        print("⏹️ 已停止")
    }

    /// 下一项（无缝切换，不经过 stopped 状态）
    public func next() {
        guard var playlist = currentPlaylist else { return }

        if playlist.moveToNext() {
            currentPlaylist = playlist
            cleanupPlayer()
            play()
        } else {
            print("⚠️ 已是最后一项")
            handlePlaylistEnded()
        }
    }

    /// 上一项
    public func previous() {
        guard var playlist = currentPlaylist else { return }

        if playlist.moveToPrevious() {
            currentPlaylist = playlist
            cleanupPlayer()
            play()
        } else {
            print("⚠️ 已是第一项")
        }
    }

    /// 跳转到指定位置（当前分段内）
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] completed in
            if completed {
                self?.updateProgress()
            }
        }
    }

    /// 按「整章」聚合时间跳转（跨当前列表中的多个 TTS 分段）
    func seekToAggregatedTime(_ target: TimeInterval) {
        guard var playlist = currentPlaylist, !playlist.items.isEmpty else { return }
        if playlist.items.count == 1 {
            seek(to: max(0, target))
            updateProgress()
            return
        }
        let total = playlist.items.reduce(0) { $0 + safeDuration($1.audioData.duration) }
        guard total > 0 else {
            seek(to: 0)
            updateProgress()
            return
        }
        let clamped = max(0, min(target, total))
        var accum: TimeInterval = 0
        var targetIndex = 0
        var localTime: TimeInterval = 0
        for (i, item) in playlist.items.enumerated() {
            let d = safeDuration(item.audioData.duration)
            let segmentEnd = accum + d
            if clamped < segmentEnd || i == playlist.items.count - 1 {
                targetIndex = i
                localTime = clamped - accum
                if d > 0 {
                    localTime = min(max(0, localTime), d)
                } else {
                    localTime = 0
                }
                break
            }
            accum = segmentEnd
        }
        if targetIndex == playlist.currentIndex {
            seek(to: localTime)
            return
        }
        if playlist.jumpTo(index: targetIndex) {
            currentPlaylist = playlist
            cleanupPlayer()
            play()
            let seekLocal = localTime
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.seek(to: seekLocal)
            }
        }
    }

    private func safeDuration(_ d: TimeInterval) -> TimeInterval {
        (d.isFinite && d > 0) ? d : 0
    }

    /// 跳转到指定项
    func jumpTo(index: Int) {
        guard var playlist = currentPlaylist else { return }

        if playlist.jumpTo(index: index) {
            currentPlaylist = playlist
            stop()
            play()
        }
    }

    /// 设置播放速度
    func setPlaybackRate(_ rate: Float) {
        config.playbackRate = rate
        player?.rate = rate
        print("⚡ 播放速度: \(rate)x")
    }

    /// 设置定时关闭（nil 或 0 表示取消）
    func setSleepTimer(minutes: Int?) {
        sleepTimer?.invalidate()
        guard let minutes = minutes, minutes > 0 else {
            sleepTimerRemaining = nil
            return
        }
        sleepTimerRemaining = TimeInterval(minutes * 60)
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let remaining = self.sleepTimerRemaining, remaining > 1 {
                    self.sleepTimerRemaining = remaining - 1
                } else {
                    self.sleepTimerRemaining = nil
                    self.sleepTimer?.invalidate()
                    self.pause()
                }
            }
        }
    }

    /// 设置音量
    func setVolume(_ volume: Float) {
        config.volume = volume
        player?.volume = volume
    }

    /// 设置重复模式
    func setRepeatMode(_ mode: PlaybackConfig.RepeatMode) {
        config.repeatMode = mode
        print("🔁 重复模式: \(mode.rawValue)")
    }

    // MARK: - Private Methods

    /// 设置音频会话
    private func setupAudioSession() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if Thread.isMainThread {
            performAudioSessionConfiguration()
        } else {
            DispatchQueue.main.sync { [self] in
                self.performAudioSessionConfiguration()
            }
        }
        #else
        print("🔊 当前平台跳过 AVAudioSession 配置")
        #endif
    }

    /// 必须在主线程调用；`setCategory`/`setActive` 在非主线程会触发 `paramErr`（OSStatus -50）与 SessionCore 报错。
    private func performAudioSessionConfiguration() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            let options = makeAudioSessionOptions()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: options)
            try audioSession.setActive(true, options: [])
            #if canImport(UIKit)
            UIApplication.shared.beginReceivingRemoteControlEvents()
            #endif

            print("🔊 音频会话已配置")
        } catch {
            print("⚠️ 音频会话配置失败: \(error.localizedDescription)")
        }
        #endif
    }

    /// 设置通知
    private func setupNotifications() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        #endif
    }

    private func ensureAudioSessionActive() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if Thread.isMainThread {
            performEnsureAudioSessionActive()
        } else {
            DispatchQueue.main.sync { [self] in
                self.performEnsureAudioSessionActive()
            }
        }
        #endif
    }

    private func performEnsureAudioSessionActive() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            let options = makeAudioSessionOptions()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: options)
            try audioSession.setActive(true, options: [])
        } catch {
            print("⚠️ 激活音频会话失败: \(error.localizedDescription)")
        }
        #endif
    }

    #if os(iOS) || os(tvOS) || os(watchOS)
    private func makeAudioSessionOptions() -> AVAudioSession.CategoryOptions {
        var options: AVAudioSession.CategoryOptions = [.allowAirPlay]
        #if os(iOS) || os(tvOS)
        options.insert(.allowBluetoothA2DP)
        #endif
        return options
    }
    #endif

    private func setupRemoteCommandCenter() {
        #if os(iOS) || os(tvOS)
        guard !remoteCommandCenterConfigured else { return }
        remoteCommandCenterConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)

        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            guard self.currentPlaylist?.currentItem != nil else { return .noActionableNowPlayingItem }
            if self.state != .playing {
                self.play()
            }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            guard self.currentPlaylist?.currentItem != nil else { return .noActionableNowPlayingItem }
            if self.state == .playing {
                self.pause()
            }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            guard self.currentPlaylist?.currentItem != nil else { return .noActionableNowPlayingItem }
            if self.state == .playing {
                self.pause()
            } else {
                self.play()
            }
            return .success
        }

        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            return self.handleRemoteNextCommand()
        }

        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            guard let playlist = self.currentPlaylist else { return .noActionableNowPlayingItem }
            guard playlist.hasPrevious else { return .commandFailed }
            self.previous()
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self else { return .commandFailed }
            guard let _ = self.currentPlaylist,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .noActionableNowPlayingItem
            }
            self.seekToAggregatedTime(positionEvent.positionTime)
            self.publishNowPlayingInfoCenter()
            return .success
        }

        updateRemoteCommandAvailability()
        #endif
    }

    private func handleRemoteNextCommand() -> MPRemoteCommandHandlerStatus {
        guard let playlist = currentPlaylist else {
            return .noActionableNowPlayingItem
        }

        if playlist.hasNext {
            next()
            return .success
        }

        if playlist.chapterContext != nil, chapterAdvanceHandler != nil {
            advanceToNextChapterIfPossible()
            return .success
        }

        return .commandFailed
    }

    private func updateRemoteCommandAvailability() {
        #if os(iOS) || os(tvOS)
        let commandCenter = MPRemoteCommandCenter.shared()
        let hasPlayableItem = currentPlaylist?.currentItem != nil
        let canSkipForward = (currentPlaylist?.hasNext ?? false)
            || (currentPlaylist?.chapterContext != nil && chapterAdvanceHandler != nil)

        commandCenter.playCommand.isEnabled = hasPlayableItem && state != .playing
        commandCenter.pauseCommand.isEnabled = hasPlayableItem && state == .playing
        commandCenter.togglePlayPauseCommand.isEnabled = hasPlayableItem
        commandCenter.nextTrackCommand.isEnabled = hasPlayableItem && canSkipForward
        commandCenter.previousTrackCommand.isEnabled = currentPlaylist?.hasPrevious ?? false
        commandCenter.changePlaybackPositionCommand.isEnabled = hasPlayableItem && progress.duration > 0
        #endif
    }

    /// 设置时间观察器
    private func setupTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateProgress()
        }
    }

    /// 设置播放器观察器
    private func setupPlayerObservers(for item: AVPlayerItem) {
        // 监听播放完成
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        // 监听播放失败
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlay),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )
    }

    /// 更新进度（多分段时按整章聚合当前时间与总时长）
    private func updateProgress() {
        guard let player = player,
              let avItem = player.currentItem,
              let playlist = currentPlaylist else {
            return
        }

        let localTime = CMTimeGetSeconds(player.currentTime())
        let localDuration = CMTimeGetSeconds(avItem.duration)
        let safeLocalTime = localTime.isFinite ? localTime : 0
        let safeLocalDuration = localDuration.isFinite && localDuration > 0 ? localDuration : 0

        let totalItems = playlist.items.count
        if totalItems <= 1 {
            progress = PlaybackProgress(
                currentTime: safeLocalTime,
                duration: safeLocalDuration,
                currentItemIndex: playlist.currentIndex,
                totalItems: totalItems
            )
            notifyPrefetchAndNowPlaying()
            return
        }

        var before: TimeInterval = 0
        for i in 0..<min(playlist.currentIndex, playlist.items.count) {
            before += safeDuration(playlist.items[i].audioData.duration)
        }
        var totalChapter: TimeInterval = 0
        for item in playlist.items {
            totalChapter += safeDuration(item.audioData.duration)
        }
        if totalChapter <= 0 {
            totalChapter = safeLocalDuration
        }

        let aggregatedCurrent = before + min(safeLocalTime, safeLocalDuration > 0 ? safeLocalDuration : safeLocalTime)

        progress = PlaybackProgress(
            currentTime: aggregatedCurrent,
            duration: totalChapter,
            currentItemIndex: playlist.currentIndex,
            totalItems: totalItems
        )
        notifyPrefetchAndNowPlaying()
        updateRemoteCommandAvailability()
    }

    /// 处理播放完成
    @objc private func playerDidFinishPlaying() {
        let work = { [weak self] in
            guard let self else { return }
            print("✅ 当前项播放完成")

            if self.config.repeatMode == .one {
                self.seek(to: 0)
                self.play()
            } else if self.config.enableAutoNext {
                if let playlist = self.currentPlaylist, playlist.hasNext {
                    self.next()
                } else if self.isStreamingPlaybackPending {
                    self.cleanupPlayer()
                    self.state = .loading
                    self.publishNowPlayingInfoCenter()
                    print("⏳ 已播到当前缓冲末尾，等待后续音频生成...")
                } else if self.currentPlaylist?.chapterContext != nil {
                    self.advanceToNextChapterIfPossible()
                } else {
                    self.handlePlaylistEnded()
                }
            } else {
                self.pause()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// 处理播放失败
    @objc private func playerItemFailedToPlay() {
        let work: () -> Void = { [weak self] in
            guard let self else { return }
            self.presentPlaybackError(TTSError.audioProcessingError)
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// 处理播放列表结束
    private func handlePlaylistEnded() {
        if config.repeatMode == .all {
            // 列表循环
            jumpTo(index: 0)
        } else {
            stop()
            print("🏁 播放列表已结束")
        }
    }

    /// 处理音频中断
    @objc private func handleInterruption(notification: Notification) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        let work = { [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                self.pause()
            case .ended:
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        self.play()
                    }
                }
            @unknown default:
                break
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
        #endif
    }

    /// 处理音频路由变化
    @objc private func handleRouteChange(notification: Notification) {
        #if os(iOS) || os(tvOS) || os(watchOS)
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        let work = { [weak self] in
            if reason == .oldDeviceUnavailable {
                self?.pause()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
        #endif
    }

    @objc private func handleMediaServicesReset() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        let work = { [weak self] in
            guard let self else { return }
            self.setupAudioSession()
            if self.state == .playing {
                self.ensureAudioSessionActive()
                self.player?.play()
                self.player?.rate = self.config.playbackRate
            }
            self.publishNowPlayingInfoCenter()
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
        #endif
    }

    @objc private func handleAppDidEnterBackground() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if state == .playing {
            ensureAudioSessionActive()
            publishNowPlayingInfoCenter()
        }
        maybeSaveSessionIfNeeded(force: true)
        #endif
    }

    @objc private func handleAppWillEnterForeground() {
        #if os(iOS) || os(tvOS) || os(watchOS)
        if state == .playing || state == .paused {
            ensureAudioSessionActive()
        }
        #endif
    }

    @objc private func handleAppWillTerminate() {
        maybeSaveSessionIfNeeded(force: true)
    }

    /// 保存播放会话（始终保存当前 AVPlayer 分段内时间，便于恢复）
    private func saveSession() {
        guard let playlist = currentPlaylist else { return }
        let localTime: TimeInterval
        if let p = player, p.currentItem != nil {
            let t = CMTimeGetSeconds(p.currentTime())
            localTime = t.isFinite ? t : 0
        } else {
            localTime = 0
        }
        let session = PlaybackSession(
            playlistId: playlist.id,
            resumeIdentifier: playlist.resumeIdentifier,
            currentItemIndex: playlist.currentIndex,
            currentTime: localTime
        )
        sessionManager.saveSession(session, for: playlist)
        persistPlaybackState()
    }

    /// 清理播放器资源（不改变 state，供 next/previous 使用）
    private func cleanupPlayer() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        // 移除当前 playerItem 的通知
        if let item = player?.currentItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: item)
        }
        player?.pause()
        player = nil
    }


    private func notifyPrefetchAndNowPlaying() {
        if state == .playing {
            maybeSaveSessionIfNeeded()
            maybeTriggerUpcomingChapterPrefetch()
            ChapterPrefetchCoordinator.shared.onPlaybackProgress(
                currentTime: progress.currentTime,
                duration: progress.duration,
                playlist: currentPlaylist
            )
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastNowPlayingInfoUpdate >= 1.5 {
                lastNowPlayingInfoUpdate = now
                publishNowPlayingInfoCenter()
            }
        }
        updateRemoteCommandAvailability()
    }

    private func publishNowPlayingInfoCenter() {
        guard currentPlaylist != nil else { return }
        var info = [String: Any]()
        var bookTitleForArtwork = ""
        var bookKeyForArtwork = ""
        var coverURLString: String? = nil
        if let pl = currentPlaylist, let ctx = pl.chapterContext {
            info[MPMediaItemPropertyTitle] = ctx.bookTitle
            if let t = ctx.chapters.first(where: { $0.index == ctx.currentChapterIndex })?.title {
                info[MPMediaItemPropertyArtist] = t
            }
            bookTitleForArtwork = ctx.bookTitle
            bookKeyForArtwork = ctx.shelfBookId.uuidString
            coverURLString = ctx.bookCoverURL
        } else if let pl = currentPlaylist {
            info[MPMediaItemPropertyTitle] = pl.title
            bookTitleForArtwork = pl.title
            bookKeyForArtwork = "playlist:\(pl.id.uuidString)"
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress.currentTime
        info[MPMediaItemPropertyPlaybackDuration] = max(progress.duration, 0)
        info[MPNowPlayingInfoPropertyPlaybackRate] = (state == .playing) ? Double(config.playbackRate) : 0.0
        info[MPNowPlayingInfoPropertyPlaybackQueueCount] = progress.totalItems
        info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = progress.currentItemIndex
        #if canImport(UIKit)
        if let artwork = makeNowPlayingArtwork(
            bookKey: bookKeyForArtwork,
            bookTitle: bookTitleForArtwork,
            coverURLString: coverURLString
        ) {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        #endif
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        updateRemoteCommandAvailability()
    }

    private func clearNowPlayingInfoCenter() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #if canImport(UIKit)
        currentArtworkBookKey = nil
        currentArtworkImage = nil
        currentArtworkLoadingURL = nil
        #endif
        updateRemoteCommandAvailability()
    }

    #if canImport(UIKit)
    /// 构建 MPMediaItemArtwork。优先使用远程书籍封面，失败/未加载时使用品牌色 fallback；
    /// 若远程封面尚未下载完成，会在后台异步拉取，下载完成后再次 publish。
    private func makeNowPlayingArtwork(
        bookKey: String,
        bookTitle: String,
        coverURLString: String?
    ) -> MPMediaItemArtwork? {
        guard !bookKey.isEmpty else { return nil }

        // 切书时清掉上一本书的 artwork 状态，避免封面错配。
        if currentArtworkBookKey != bookKey {
            currentArtworkBookKey = bookKey
            currentArtworkImage = nil
            currentArtworkLoadingURL = nil
        }

        let resolvedURL = NowPlayingArtworkProvider.resolveURL(from: coverURLString)

        // 优先用已成功加载的图（来自上一次下载或缓存）。
        var imageToUse: UIImage? = currentArtworkImage

        // 命中全局缓存。
        if imageToUse == nil,
           let url = resolvedURL,
           let cached = NowPlayingArtworkProvider.cachedRemoteImage(for: url.absoluteString) {
            currentArtworkImage = cached
            imageToUse = cached
        }

        // 还没有真实封面 → 用品牌色 fallback（蓝紫色调，至少让灵动岛 / 锁屏不再空白、波形也不再灰）。
        let displayedImage = imageToUse ?? NowPlayingArtworkProvider.brandFallbackImage(for: bookTitle)

        // 仍未拿到真实封面，且 URL 有效 → 起一次后台下载。
        if imageToUse == nil,
           let url = resolvedURL,
           currentArtworkLoadingURL != url {
            currentArtworkLoadingURL = url
            let bookKeyAtRequest = bookKey
            URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
                guard error == nil,
                      let data,
                      let image = UIImage(data: data) else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if self.currentArtworkLoadingURL == url {
                            self.currentArtworkLoadingURL = nil
                        }
                    }
                    return
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // 期间用户切书 → 丢弃这次结果。
                    guard self.currentArtworkBookKey == bookKeyAtRequest else { return }
                    NowPlayingArtworkProvider.setCachedRemoteImage(image, for: url.absoluteString)
                    self.currentArtworkImage = image
                    self.currentArtworkLoadingURL = nil
                    // 真实封面到位，立刻刷一次 NowPlayingInfo，让锁屏 / 灵动岛换图。
                    self.publishNowPlayingInfoCenter()
                }
            }.resume()
        }

        // MPMediaItemArtwork 在 iOS 上只接受 UIImage。closure 由系统在需要尺寸时回调。
        let baseSize = displayedImage.size
        return MPMediaItemArtwork(boundsSize: baseSize) { requestedSize in
            return NowPlayingArtworkProvider.resizedImage(displayedImage, to: requestedSize)
        }
    }
    #endif

    /// 清理资源
    private func cleanup() {
        maybeSaveSessionIfNeeded(force: true)
        cleanupPlayer()
        sleepTimer?.invalidate()
        #if canImport(UIKit)
        UIApplication.shared.endReceivingRemoteControlEvents()
        #endif
        #if os(iOS) || os(tvOS)
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        remoteCommandCenterConfigured = false
        #endif
        NotificationCenter.default.removeObserver(self)
    }

    /// 获取音频缓存目录 URL
    var audioCacheDirectory: URL {
        cacheManager.cacheDirectory
    }

    private func startPlayback(for item: PlaybackItem, initialSeekTime: TimeInterval) {
        let beginPlayback = { [weak self] in
            guard let self else { return }
            self.player?.play()
            self.player?.rate = self.config.playbackRate
            self.state = .playing
            self.publishNowPlayingInfoCenter()
            print("▶️ 开始播放: \(item.segment.text.prefix(20))...")
        }

        guard initialSeekTime > 0 else {
            beginPlayback()
            return
        }

        let cmTime = CMTime(seconds: initialSeekTime, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
            guard let self else { return }
            if !completed {
                self.pendingRestoredLocalTime = 0
                self.pendingRestoredItemIndex = nil
                beginPlayback()
                return
            }
            self.pendingRestoredLocalTime = 0
            self.pendingRestoredItemIndex = nil
            self.updateProgress()
            beginPlayback()
        }
    }

    private func restoredLocalTimeIfNeeded(for itemIndex: Int) -> TimeInterval {
        guard pendingRestoredItemIndex == itemIndex else { return 0 }
        return max(0, pendingRestoredLocalTime)
    }

    private func maybeSaveSessionIfNeeded(force: Bool = false) {
        guard currentPlaylist != nil, state == .playing || state == .paused else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastSessionSaveTime >= 12 else { return }
        lastSessionSaveTime = now
        saveSession()
    }

    private func maybeTriggerUpcomingChapterPrefetch() {
        guard !hasTriggeredChapterPrefetch,
              let playlist = currentPlaylist,
              playlist.chapterContext != nil,
              progress.duration > 0,
              chapterPrefetchHandler != nil else {
            return
        }

        let segEst = max(playlist.items.count, 4)
        let threshold = PlaybackGenerationPacing.suggestedChapterPrefetchProgressThreshold(
            estimatedSegmentCount: segEst,
            concurrent: Config.maxConcurrentTasks,
            baseThreshold: Config.chapterPrefetchProgressThreshold
        )
        guard progress.currentTime / progress.duration >= threshold else { return }

        hasTriggeredChapterPrefetch = true
        Task { @MainActor [weak self] in
            guard let handler = self?.chapterPrefetchHandler else { return }
            await handler()
        }
    }

    private func advanceToNextChapterIfPossible() {
        guard !isAdvancingToNextChapter,
              let handler = chapterAdvanceHandler else {
            handlePlaylistEnded()
            return
        }

        isAdvancingToNextChapter = true
        displayChapterContextOverride = nextChapterDisplayContext()
        progress = PlaybackProgress()
        cleanupPlayer()
        state = .loading
        publishNowPlayingInfoCenter()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await handler()
            } catch {
                self.isAdvancingToNextChapter = false
                self.displayChapterContextOverride = nil
                self.presentPlaybackError(error)
                print("❌ 自动切换下一章失败: \(error.localizedDescription)")
            }
        }
    }

    private func nextChapterDisplayContext() -> PlaybackChapterContext? {
        guard var context = currentPlaylist?.chapterContext,
              let currentPosition = context.chapters.firstIndex(where: { $0.index == context.currentChapterIndex }),
              currentPosition + 1 < context.chapters.count else {
            return nil
        }

        context.currentChapterIndex = context.chapters[currentPosition + 1].index
        return context
    }

    private func userFacingMessage(for error: Error) -> String {
        if let accessError = error as? CloudPlaybackAccessError {
            return accessError.errorDescription ?? error.localizedDescription
        }
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
    }

    private func aggregatedTime(
        in playlist: Playlist,
        currentItemIndex: Int,
        localTime: TimeInterval
    ) -> TimeInterval {
        guard !playlist.items.isEmpty else { return max(0, localTime) }
        var totalBefore: TimeInterval = 0
        for index in 0..<min(currentItemIndex, playlist.items.count) {
            totalBefore += safeDuration(playlist.items[index].audioData.duration)
        }
        return totalBefore + max(0, localTime)
    }

    private func persistPlaybackState() {
        guard let playlist = currentPlaylist else { return }
        do {
            let items = try playlist.items.map { item -> PersistedPlaybackItem in
                let url = try cacheManager.getOrCache(audioData: item.audioData, id: item.id.uuidString)
                return PersistedPlaybackItem(
                    id: item.id,
                    segment: item.segment,
                    order: item.order,
                    format: item.audioData.format,
                    duration: item.audioData.duration,
                    sampleRate: item.audioData.sampleRate,
                    cachedFileName: url.lastPathComponent
                )
            }

            let snapshot = PersistedPlaybackSnapshot(
                playlistID: playlist.id,
                title: playlist.title,
                currentIndex: playlist.currentIndex,
                chapterContext: playlist.chapterContext,
                items: items,
                state: state == .playing ? .paused : state,
                config: config
            )

            let encoder = JSONEncoder()
            let data = try encoder.encode(snapshot)
            try data.write(to: persistedPlaybackSnapshotURL(), options: .atomic)
        } catch {
            print("⚠️ 保存播放快照失败: \(error.localizedDescription)")
        }
    }

    /// 升级后首次启动：若快照中循环仍为旧默认「不循环」，自动改为「列表循环」并写回（仅一次）；曾手动选「不循环」的用户可在播放页再切回。
    private func applyListLoopAsDefaultIfNeeded() {
        let k = "playbackRepeatModeDefaultMigratedListLoopV1"
        guard !UserDefaults.standard.bool(forKey: k) else { return }
        UserDefaults.standard.set(true, forKey: k)
        if config.repeatMode == .none {
            config.repeatMode = .all
            if currentPlaylist != nil { persistPlaybackState() }
        }
    }

    private func restorePersistedPlaybackState() {
        let url = persistedPlaybackSnapshotURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let snapshot = try decoder.decode(PersistedPlaybackSnapshot.self, from: data)
            let items = try snapshot.items.map { persisted in
                let audioURL = cacheManager.cachedAudioURL(fileName: persisted.cachedFileName)
                let audioData = try Data(contentsOf: audioURL)
                return PlaybackItem(
                    id: persisted.id,
                    segment: persisted.segment,
                    audioData: AudioData(
                        data: audioData,
                        format: persisted.format,
                        duration: persisted.duration,
                        sampleRate: persisted.sampleRate
                    ),
                    order: persisted.order
                )
            }

            guard !items.isEmpty else { return }
            let restoredPlaylist = Playlist(
                id: snapshot.playlistID,
                title: snapshot.title,
                items: items,
                currentIndex: min(max(snapshot.currentIndex, 0), items.count - 1),
                chapterContext: snapshot.chapterContext
            )

            currentPlaylist = restoredPlaylist
            config = snapshot.config
            state = snapshot.state == .playing ? .paused : snapshot.state

            if let session = sessionManager.loadSession(for: restoredPlaylist) {
                let clampedIndex = min(max(session.currentItemIndex, 0), items.count - 1)
                currentPlaylist?.currentIndex = clampedIndex
                let restoredTime = max(0, session.currentTime)
                pendingRestoredLocalTime = restoredTime
                pendingRestoredItemIndex = restoredTime > 0 ? clampedIndex : nil
                progress = PlaybackProgress(
                    currentTime: aggregatedTime(
                        in: restoredPlaylist,
                        currentItemIndex: clampedIndex,
                        localTime: restoredTime
                    ),
                    duration: max(0, restoredPlaylist.totalDuration),
                    currentItemIndex: clampedIndex,
                    totalItems: restoredPlaylist.items.count
                )
            } else {
                progress = PlaybackProgress(
                    currentTime: 0,
                    duration: max(0, restoredPlaylist.totalDuration),
                    currentItemIndex: restoredPlaylist.currentIndex,
                    totalItems: restoredPlaylist.items.count
                )
            }

            print("📚 已恢复上次播放快照: \(restoredPlaylist.title)")
            publishNowPlayingInfoCenter()
            updateRemoteCommandAvailability()
        } catch {
            try? FileManager.default.removeItem(at: url)
            print("⚠️ 恢复播放快照失败，已清理损坏快照: \(error.localizedDescription)")
        }
    }

    private func persistedPlaybackSnapshotURL() -> URL {
        cacheManager.cacheDirectory.appendingPathComponent("last-playback-snapshot.json")
    }
}

// MARK: - 音频缓存管理器

/// 音频缓存管理器
class AudioCacheManager {

    private let fileManager = FileManager.default
    let cacheDirectory: URL

    init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesURL.appendingPathComponent("AudioCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    /// 获取或缓存音频
    func getOrCache(audioData: AudioData, id: String) throws -> URL {
        let fileURL = cacheDirectory.appendingPathComponent("\(id).\(audioData.format.rawValue)")

        // 如果已缓存，直接返回
        if fileManager.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        // 缓存音频
        try audioData.data.write(to: fileURL)
        return fileURL
    }

    func cachedAudioURL(fileName: String) -> URL {
        cacheDirectory.appendingPathComponent(fileName)
    }

    /// 清除缓存
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

private struct PersistedPlaybackSnapshot: Codable {
    let playlistID: UUID
    let title: String
    let currentIndex: Int
    let chapterContext: PlaybackChapterContext?
    let items: [PersistedPlaybackItem]
    let state: PlaybackState
    let config: PlaybackConfig
}

private struct PersistedPlaybackItem: Codable {
    let id: UUID
    let segment: TextSegment
    let order: Int
    let format: AudioData.AudioFormat
    let duration: TimeInterval
    let sampleRate: Int
    let cachedFileName: String
}

// MARK: - 播放会话管理器

/// 播放会话管理器
class PlaybackSessionManager {

    private let userDefaults = UserDefaults.standard
    private let sessionKey = "PlaybackSessions"

    /// 保存会话
    func saveSession(_ session: PlaybackSession, for playlist: Playlist) {
        var sessions = loadAllSessions()
        sessions[playlist.resumeIdentifier] = session
        saveSessions(sessions)
    }

    /// 加载会话
    func loadSession(for playlist: Playlist) -> PlaybackSession? {
        let sessions = loadAllSessions()
        if let session = sessions[playlist.resumeIdentifier] {
            return session
        }
        return sessions["playlist:\(playlist.id.uuidString)"]
    }

    /// 删除会话
    func deleteSession(for playlist: Playlist) {
        var sessions = loadAllSessions()
        sessions.removeValue(forKey: playlist.resumeIdentifier)
        sessions.removeValue(forKey: "playlist:\(playlist.id.uuidString)")
        saveSessions(sessions)
    }

    /// 清除所有会话
    func clearAllSessions() {
        userDefaults.removeObject(forKey: sessionKey)
    }

    private func loadAllSessions() -> [String: PlaybackSession] {
        guard let data = userDefaults.data(forKey: sessionKey) else {
            return [:]
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode([String: PlaybackSession].self, from: data)
        } catch {
            print("⚠️ 加载会话失败: \(error.localizedDescription)")
            return [:]
        }
    }

    private func saveSessions(_ sessions: [String: PlaybackSession]) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(sessions)
            userDefaults.set(data, forKey: sessionKey)
        } catch {
            print("⚠️ 保存会话失败: \(error.localizedDescription)")
        }
    }
}

#if canImport(UIKit)
/// 锁屏 / 灵动岛 NowPlayingInfo 用的封面图工具：
/// - 远程封面下载 + 内存缓存
/// - URL 标准化（兼容 //、/ 开头的相对路径）
/// - 无封面/失败时绘制一张品牌蓝紫渐变 fallback（用书名首字符做 hero）
/// - MPMediaItemArtwork 系统按需 resize 时复用同一张高清图
enum NowPlayingArtworkProvider {
    private static let remoteCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()
    private static let brandCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()

    static func cachedRemoteImage(for key: String) -> UIImage? {
        return remoteCache.object(forKey: key as NSString)
    }

    static func setCachedRemoteImage(_ image: UIImage, for key: String) {
        remoteCache.setObject(image, forKey: key as NSString)
    }

    static func resolveURL(from raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        if let direct = URL(string: raw), direct.scheme != nil {
            return direct
        }
        if raw.hasPrefix("//") {
            return URL(string: "https:\(raw)")
        }
        if raw.hasPrefix("/") {
            return URL(string: "https://www.bqg291.cc\(raw)")
        }
        return URL(string: "https://www.bqg291.cc/\(raw)")
    }

    static func resizedImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let bounded = CGSize(
            width: max(targetSize.width, 1),
            height: max(targetSize.height, 1)
        )
        if abs(image.size.width - bounded.width) < 1,
           abs(image.size.height - bounded.height) < 1 {
            return image
        }
        let renderer = UIGraphicsImageRenderer(size: bounded)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: bounded))
        }
    }

    /// 品牌蓝紫渐变 + 书名首字 fallback。一旦绘制完成会缓存，避免每次 publish 重画。
    static func brandFallbackImage(for title: String, side: CGFloat = 600) -> UIImage {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = "\(trimmed)|\(Int(side))" as NSString
        if let cached = brandCache.object(forKey: key) {
            return cached
        }
        let size = CGSize(width: side, height: side)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext

            let colors: [CGColor] = [
                UIColor(red: 0.42, green: 0.48, blue: 0.88, alpha: 1).cgColor,
                UIColor(red: 0.55, green: 0.50, blue: 0.92, alpha: 1).cgColor,
                UIColor(red: 0.66, green: 0.54, blue: 0.96, alpha: 1).cgColor
            ]
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(
                colorsSpace: space,
                colors: colors as CFArray,
                locations: [0.0, 0.5, 1.0]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            } else {
                UIColor(red: 0.55, green: 0.50, blue: 0.92, alpha: 1).setFill()
                cg.fill(CGRect(origin: .zero, size: size))
            }

            let highlightRect = CGRect(
                x: -size.width * 0.18,
                y: -size.height * 0.10,
                width: size.width * 0.85,
                height: size.height * 0.85
            )
            cg.saveGState()
            cg.setBlendMode(.plusLighter)
            UIColor.white.withAlphaComponent(0.10).setFill()
            cg.fillEllipse(in: highlightRect)
            cg.restoreGState()

            let initial = String(trimmed.prefix(1))
            if !initial.isEmpty {
                let font = UIFont.systemFont(ofSize: side * 0.42, weight: .heavy)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.white.withAlphaComponent(0.94)
                ]
                let str = NSAttributedString(string: initial, attributes: attrs)
                let strSize = str.size()
                let rect = CGRect(
                    x: (size.width - strSize.width) / 2,
                    y: (size.height - strSize.height) / 2 - size.height * 0.04,
                    width: strSize.width,
                    height: strSize.height
                )
                str.draw(in: rect)

                let subtitle = String(trimmed.prefix(8))
                if !subtitle.isEmpty {
                    let subFont = UIFont.systemFont(ofSize: side * 0.07, weight: .semibold)
                    let subAttrs: [NSAttributedString.Key: Any] = [
                        .font: subFont,
                        .foregroundColor: UIColor.white.withAlphaComponent(0.86)
                    ]
                    let sub = NSAttributedString(string: subtitle, attributes: subAttrs)
                    let subSize = sub.size()
                    let subRect = CGRect(
                        x: (size.width - subSize.width) / 2,
                        y: rect.maxY + size.height * 0.04,
                        width: subSize.width,
                        height: subSize.height
                    )
                    sub.draw(in: subRect)
                }
            }
        }
        brandCache.setObject(image, forKey: key)
        return image
    }
}
#endif
