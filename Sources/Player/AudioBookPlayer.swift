//
//  AudioBookPlayer.swift
//  AI有声书
//
//  有声书播放器
//

import Foundation
import AVFoundation
import Combine

/// 有声书播放器
public class AudioBookPlayer: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published public var state: PlaybackState = .idle
    @Published public var progress: PlaybackProgress = PlaybackProgress()
    @Published public var currentPlaylist: Playlist?
    @Published public var config: PlaybackConfig = PlaybackConfig()
    @Published public var sleepTimerRemaining: TimeInterval? = nil

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var sleepTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let cacheManager: AudioCacheManager
    private let sessionManager: PlaybackSessionManager

    // MARK: - Initialization

    public override init() {
        self.cacheManager = AudioCacheManager()
        self.sessionManager = PlaybackSessionManager()
        super.init()

        setupAudioSession()
        setupNotifications()
    }

    deinit {
        cleanup()
    }

    // MARK: - Public Methods

    /// 加载播放列表
    public func load(playlist: Playlist) {
        currentPlaylist = playlist
        state = .idle

        // 尝试恢复上次播放位置
        if let session = sessionManager.loadSession(for: playlist.id) {
            currentPlaylist?.currentIndex = session.currentItemIndex
            print("📖 恢复播放位置: 第 \(session.currentItemIndex + 1) 项")
        }

        print("📚 已加载播放列表: \(playlist.title), 共 \(playlist.items.count) 项")
    }

    /// 追加播放项（流式播放时使用）
    public func append(item: PlaybackItem) {
        currentPlaylist?.items.append(item)
        currentPlaylist?.totalDuration += item.audioData.duration
        print("➕ 追加播放项: 第 \(item.order + 1) 段")
    }

    /// 播放
    public func play() {
        guard let playlist = currentPlaylist,
              let currentItem = playlist.currentItem else {
            print("⚠️ 没有可播放的内容")
            return
        }

        state = .loading

        // 如果已有播放器且是同一项，直接播放
        if player != nil {
            player?.play()
            player?.rate = config.playbackRate
            state = .playing
            return
        }

        // 创建新的播放器
        do {
            let audioURL = try cacheManager.getOrCache(audioData: currentItem.audioData, id: currentItem.id.uuidString)
            let playerItem = AVPlayerItem(url: audioURL)

            player = AVPlayer(playerItem: playerItem)
            player?.volume = config.volume
            player?.rate = config.playbackRate

            setupTimeObserver()
            setupPlayerObservers(for: playerItem)

            player?.play()
            state = .playing

            print("▶️ 开始播放: \(currentItem.segment.text.prefix(20))...")
        } catch {
            state = .error
            print("❌ 播放失败: \(error.localizedDescription)")
        }
    }

    /// 暂停
    public func pause() {
        player?.pause()
        state = .paused
        saveSession()
        print("⏸️ 已暂停")
    }

    /// 停止
    public func stop() {
        cleanupPlayer()
        state = .stopped
        progress = PlaybackProgress()
        saveSession()
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
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio)
            try audioSession.setActive(true)

            if config.enableBackgroundPlayback {
                // 启用后台播放
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            }

            print("🔊 音频会话已配置")
        } catch {
            print("⚠️ 音频会话配置失败: \(error.localizedDescription)")
        }
    }

    /// 设置通知
    private func setupNotifications() {
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
                self.next()
            } else {
                self.pause()
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// 处理播放失败
    @objc private func playerItemFailedToPlay() {
        let work = { [weak self] in
            self?.state = .error
            print("❌ 播放失败")
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
    }

    /// 处理音频路由变化
    @objc private func handleRouteChange(notification: Notification) {
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
    }

    /// 保存播放会话（始终保存当前 AVPlayer 分段内时间，便于恢复）
    private func saveSession() {
        guard let playlist = currentPlaylist else { return }
        let localTime: TimeInterval
        if let p = player, let item = p.currentItem {
            let t = CMTimeGetSeconds(p.currentTime())
            localTime = t.isFinite ? t : 0
        } else {
            localTime = 0
        }
        let session = PlaybackSession(
            playlistId: playlist.id,
            currentItemIndex: playlist.currentIndex,
            currentTime: localTime
        )
        sessionManager.saveSession(session)
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

    /// 清理资源
    private func cleanup() {
        cleanupPlayer()
        sleepTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    /// 获取音频缓存目录 URL
    var audioCacheDirectory: URL {
        cacheManager.cacheDirectory
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

    /// 清除缓存
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

// MARK: - 播放会话管理器

/// 播放会话管理器
class PlaybackSessionManager {

    private let userDefaults = UserDefaults.standard
    private let sessionKey = "PlaybackSessions"

    /// 保存会话
    func saveSession(_ session: PlaybackSession) {
        var sessions = loadAllSessions()
        sessions[session.playlistId.uuidString] = session
        saveSessions(sessions)
    }

    /// 加载会话
    func loadSession(for playlistId: UUID) -> PlaybackSession? {
        let sessions = loadAllSessions()
        return sessions[playlistId.uuidString]
    }

    /// 删除会话
    func deleteSession(for playlistId: UUID) {
        var sessions = loadAllSessions()
        sessions.removeValue(forKey: playlistId.uuidString)
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
