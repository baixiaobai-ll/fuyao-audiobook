import Foundation

/// 章节 TTS 生成与连续收听节奏的粗算（启发式，用于预取时机与文档说明）。
enum PlaybackGenerationPacing {

    /// 粗略估计平均每段合成耗时（秒），可随线上统计调整。
    private static let defaultAvgSynthesisSeconds: Double = 2.2

    /// 粗略估计每段播放时长（秒），与语速/段长相关。
    private static let defaultAvgPlayedSecondsPerSegment: Double = 7.0

    /// 在「边播边生成」且并发为 `concurrent` 时，估计从**首段开始播放**起，队列追上「按序听完当前已生成段」所需墙钟时间是否充足的大致判据。
    ///
    /// 简化模型：生成速率 ≈ `concurrent / avgSynthesisSeconds` 段/秒；消费速率 ≈ `1 / avgPlayedSecondsPerSegment` 段/秒（1x 倍速）。
    /// 若生成速率 ≤ 消费速率，理论上无法无限连续听，需要更高并发或更短段/更快 TTS。
    static func canGenerationKeepPaceWithPlayback(
        concurrent: Int,
        avgSynthesisSecondsPerSegment: Double = defaultAvgSynthesisSeconds,
        avgPlayedSecondsPerSegment: Double = defaultAvgPlayedSecondsPerSegment,
        playbackRate: Float = 1.0
    ) -> Bool {
        let c = max(1, concurrent)
        let genPerSec = Double(c) / max(0.1, avgSynthesisSecondsPerSegment)
        let consumePerSec = Double(playbackRate) / max(0.1, avgPlayedSecondsPerSegment)
        return genPerSec > consumePerSec * 1.05
    }

    /// 建议的「提前预拉下一章正文」的播放进度比例（0～1）。并发低或章偏长时略提前。
    static func suggestedChapterPrefetchProgressThreshold(
        estimatedSegmentCount: Int,
        concurrent: Int,
        baseThreshold: Double = 0.18
    ) -> Double {
        let n = max(1, estimatedSegmentCount)
        let c = max(1, concurrent)
        // 段数多或并发低 → 更早预取正文，给下一章分析+TTS 留时间
        let load = Double(n) / Double(c) / 40.0
        let adjusted = baseThreshold - min(0.12, load * 0.04)
        return min(0.45, max(0.08, adjusted))
    }

    /// 下一章正文建议提前完成的「墙钟秒」粗估值（在点开本章前或本章极早进度时后台准备更从容）。
    static func estimatedPrefetchLeadSecondsForNextChapter(
        estimatedNextChapterChars: Int,
        concurrent: Int,
        avgSynthesisSecondsPerSegment: Double = defaultAvgSynthesisSeconds
    ) -> TimeInterval {
        let segEst = max(4, estimatedNextChapterChars / 350)
        let c = max(1, concurrent)
        let waves = ceil(Double(segEst) / Double(c))
        return waves * avgSynthesisSecondsPerSegment + 8
    }
}
