//
//  PlayerModels.swift
//  AI有声书
//
//  播放器相关的数据模型
//

import Foundation

// MARK: - 播放状态

/// 播放状态
public enum PlaybackState: String, Codable {
    case idle       // 空闲
    case loading    // 加载中
    case playing    // 播放中
    case paused     // 暂停
    case stopped    // 停止
    case error      // 错误
}

// MARK: - 播放项

/// 播放项
public struct PlaybackItem: Codable, Identifiable, Sendable {
    public let id: UUID
    public let segment: TextSegment
    public let audioData: AudioData
    public let order: Int

    public init(id: UUID = UUID(), segment: TextSegment, audioData: AudioData, order: Int) {
        self.id = id
        self.segment = segment
        self.audioData = audioData
        self.order = order
    }
}

// MARK: - 章节播放上下文（整章多段 TTS 时用于目录与进度）

/// 章节目录项（仅索引与标题，用于播放页切换章节）
public struct PlaybackChapterSummary: Codable, Hashable, Sendable {
    public var index: Int
    public var title: String

    public init(index: Int, title: String) {
        self.index = index
        self.title = title
    }
}

/// 当前播放所属书的章节信息
public struct PlaybackChapterContext: Codable, Hashable, Sendable {
    /// 书架上的书籍 id（缓存正文与音色绑定）
    public var shelfBookId: UUID
    public var apiBookId: String?
    public var bookSource: BookSource
    public var bookTitle: String
    /// 封面图 URL（发现/书架展示用；可选）
    public var bookCoverURL: String?
    public var chapters: [PlaybackChapterSummary]
    public var currentChapterIndex: Int

    public init(
        shelfBookId: UUID,
        apiBookId: String?,
        bookSource: BookSource,
        bookTitle: String,
        bookCoverURL: String? = nil,
        chapters: [PlaybackChapterSummary],
        currentChapterIndex: Int
    ) {
        self.shelfBookId = shelfBookId
        self.apiBookId = apiBookId
        self.bookSource = bookSource
        self.bookTitle = bookTitle
        self.bookCoverURL = bookCoverURL
        self.chapters = chapters
        self.currentChapterIndex = currentChapterIndex
    }
}

// MARK: - 播放列表

/// 播放列表
public struct Playlist: Codable, Identifiable {
    public let id: UUID
    public var title: String
    public var items: [PlaybackItem]
    public var currentIndex: Int
    public var totalDuration: TimeInterval
    /// 若存在，表示当前列表为某一整章的连续分段，进度条按章聚合
    public var chapterContext: PlaybackChapterContext?

    public init(
        id: UUID = UUID(),
        title: String,
        items: [PlaybackItem] = [],
        currentIndex: Int = 0,
        chapterContext: PlaybackChapterContext? = nil
    ) {
        self.id = id
        self.title = title
        self.items = items
        self.currentIndex = currentIndex
        self.chapterContext = chapterContext
        self.totalDuration = items.reduce(0) { $0 + $1.audioData.duration }
    }

    /// 当前播放项
    public var currentItem: PlaybackItem? {
        guard currentIndex >= 0 && currentIndex < items.count else {
            return nil
        }
        return items[currentIndex]
    }

    /// 是否有下一项
    public var hasNext: Bool {
        return currentIndex < items.count - 1
    }

    /// 是否有上一项
    public var hasPrevious: Bool {
        return currentIndex > 0
    }

    /// 移动到下一项
    public mutating func moveToNext() -> Bool {
        if hasNext {
            currentIndex += 1
            return true
        }
        return false
    }

    /// 移动到上一项
    public mutating func moveToPrevious() -> Bool {
        if hasPrevious {
            currentIndex -= 1
            return true
        }
        return false
    }

    /// 跳转到指定索引
    public mutating func jumpTo(index: Int) -> Bool {
        guard index >= 0 && index < items.count else {
            return false
        }
        currentIndex = index
        return true
    }
}

// MARK: - 播放进度

/// 播放进度
public struct PlaybackProgress: Codable {
    public var currentTime: TimeInterval
    public var duration: TimeInterval
    public var currentItemIndex: Int
    public var totalItems: Int

    public init(
        currentTime: TimeInterval = 0,
        duration: TimeInterval = 0,
        currentItemIndex: Int = 0,
        totalItems: Int = 0
    ) {
        self.currentTime = currentTime
        self.duration = duration
        self.currentItemIndex = currentItemIndex
        self.totalItems = totalItems
    }

    /// 进度百分比
    var percentage: Double {
        guard duration > 0 else { return 0 }
        return (currentTime / duration) * 100
    }

    /// 剩余时间
    var remainingTime: TimeInterval {
        return max(0, duration - currentTime)
    }

    /// 格式化当前时间
    var formattedCurrentTime: String {
        return formatTime(currentTime)
    }

    /// 格式化总时长
    var formattedDuration: String {
        return formatTime(duration)
    }

    /// 格式化剩余时间
    var formattedRemainingTime: String {
        return formatTime(remainingTime)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - 播放配置

/// 播放配置
public struct PlaybackConfig: Codable {
    public var playbackRate: Float
    public var volume: Float
    public var enableBackgroundPlayback: Bool
    public var enableAutoNext: Bool
    public var repeatMode: RepeatMode

    public init(
        playbackRate: Float = 1.0,
        volume: Float = 1.0,
        enableBackgroundPlayback: Bool = true,
        enableAutoNext: Bool = true,
        repeatMode: RepeatMode = .none
    ) {
        self.playbackRate = playbackRate
        self.volume = volume
        self.enableBackgroundPlayback = enableBackgroundPlayback
        self.enableAutoNext = enableAutoNext
        self.repeatMode = repeatMode
    }

    public enum RepeatMode: String, Codable {
        case none       // 不重复
        case one        // 单曲循环
        case all        // 列表循环
    }
}

// MARK: - 播放会话

/// 播放会话（用于保存和恢复播放状态）
struct PlaybackSession: Codable {
    let playlistId: UUID
    let currentItemIndex: Int
    let currentTime: TimeInterval
    let lastPlayedDate: Date

    init(
        playlistId: UUID,
        currentItemIndex: Int,
        currentTime: TimeInterval,
        lastPlayedDate: Date = Date()
    ) {
        self.playlistId = playlistId
        self.currentItemIndex = currentItemIndex
        self.currentTime = currentTime
        self.lastPlayedDate = lastPlayedDate
    }
}

// MARK: - 播放历史

/// 播放历史记录
struct PlaybackHistory: Codable, Identifiable {
    let id: UUID
    let playlistId: UUID
    let playlistTitle: String
    let playedDate: Date
    let duration: TimeInterval
    let progress: Double

    init(
        id: UUID = UUID(),
        playlistId: UUID,
        playlistTitle: String,
        playedDate: Date = Date(),
        duration: TimeInterval,
        progress: Double
    ) {
        self.id = id
        self.playlistId = playlistId
        self.playlistTitle = playlistTitle
        self.playedDate = playedDate
        self.duration = duration
        self.progress = progress
    }
}

// MARK: - 播放事件

/// 播放事件
enum PlaybackEvent {
    case stateChanged(PlaybackState)
    case progressUpdated(PlaybackProgress)
    case itemChanged(PlaybackItem)
    case playlistEnded
    case error(Error)
}
