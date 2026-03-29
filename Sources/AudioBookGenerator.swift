//
//  AudioBookGenerator.swift
//  AI有声书
//
//  有声书生成器 - 整合所有模块的核心协调器
//

import Foundation

/// 按 `segmentIndex` 顺序依次调用 `onItemReady`（并发完成时仍保证播放顺序）。
private final class OrderedPlaybackEmitter: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [Int: PlaybackItem] = [:]
    private var nextEmit = 0
    private let onItemReady: (PlaybackItem) -> Void

    init(onItemReady: @escaping (PlaybackItem) -> Void) {
        self.onItemReady = onItemReady
    }

    func complete(segmentIndex: Int, item: PlaybackItem) {
        var batch: [PlaybackItem] = []
        lock.lock()
        pending[segmentIndex] = item
        while let next = pending[nextEmit] {
            pending.removeValue(forKey: nextEmit)
            batch.append(next)
            nextEmit += 1
        }
        lock.unlock()
        for x in batch {
            onItemReady(x)
        }
    }
}

/// 有声书生成器
public class AudioBookGenerator {

    // MARK: - Dependencies

    private let textAnalyzer: NovelTextAnalyzer
    private let ttsEngine: TTSEngine
    private let audioMixer: AudioMixer
    private let voiceManager: VoiceManager
    private let ttsProvider: TTSProvider

    // MARK: - Configuration

    private let config: GeneratorConfig

    // MARK: - Initialization

    init(
        textAnalyzer: NovelTextAnalyzer,
        ttsEngine: TTSEngine,
        audioMixer: AudioMixer,
        voiceManager: VoiceManager,
        config: GeneratorConfig = GeneratorConfig(),
        ttsProvider: TTSProvider = .xfyun
    ) {
        self.textAnalyzer = textAnalyzer
        self.ttsEngine = ttsEngine
        self.audioMixer = audioMixer
        self.voiceManager = voiceManager
        self.config = config
        self.ttsProvider = ttsProvider
    }

    /// 便捷初始化方法
    public convenience init(
        aiApiKey: String,
        ttsApiKey: String,
        aiProvider: AIProvider = .claude,
        ttsProvider: TTSProvider = .azure
    ) {
        // 创建 AI 分析服务
        let aiService: AIAnalysisService
        switch aiProvider {
        case .openai:
            aiService = OpenAIAnalysisService(apiKey: aiApiKey)
        case .claude:
            aiService = ClaudeAnalysisService(apiKey: aiApiKey)
        case .qwen:
            aiService = QwenAnalysisService(apiKey: aiApiKey)
        }

        // 创建文本分析器
        let textAnalyzer = NovelTextAnalyzer(aiService: aiService)

        // 创建音频混合器
        let audioMixer = AudioMixer()

        // 创建音色管理器
        let voiceManager = VoiceManager()

        let genConfig = GeneratorConfig(
            enableBackgroundMusic: true,
            enableSoundEffects: true,
            enableAudioMixing: false,
            maxConcurrentTasks: Config.maxConcurrentTasks
        )
        let ttsCfg = TTSConfig(
            provider: ttsProvider,
            apiKey: ttsApiKey,
            maxConcurrentRequests: Config.maxConcurrentTasks
        )
        let ttsEngineConfigured = TTSEngine(config: ttsCfg)

        self.init(
            textAnalyzer: textAnalyzer,
            ttsEngine: ttsEngineConfigured,
            audioMixer: audioMixer,
            voiceManager: voiceManager,
            config: genConfig,
            ttsProvider: ttsProvider
        )
    }

    // MARK: - Public Methods

    /// 生成有声书
    /// - Parameters:
    ///   - text: 小说文本
    ///   - metadata: 小说元数据
    ///   - remoteCacheKey: 若配置 `DISCOVER_API_BASE_URL` 且服务端提供**分析索引**（无正文），可先还原并跳过本地 AI 分析
    ///   - progressHandler: 进度回调
    /// - Returns: 播放列表
    func generate(
        text: String,
        metadata: NovelMetadata? = nil,
        existingVoiceBindings: [String: String] = [:],
        remoteCacheKey: PlaybackRemoteCacheKey? = nil,
        progressHandler: (@Sendable (GenerationProgress) -> Void)? = nil,
        onItemReady: (@Sendable (PlaybackItem) -> Void)? = nil,
        onVoiceBindingsUpdated: (@Sendable ([String: String]) -> Void)? = nil,
        streamItemsAsReady: Bool = true
    ) async throws -> Playlist {

        print("🚀 开始生成有声书...")

        // 1. 分析文本（优先云端「索引」；正文仅客户端持有，云端仅存 UTF-8 偏移等）
        progressHandler?(GenerationProgress(stage: .analyzing, progress: 0, message: "正在分析文本..."))
        let canonical = NovelTextAnalyzer.canonicalTextForPlayback(text)
        let textFingerprint = PlaybackAnalysisCloudClient.textFingerprintForPlaybackInput(text)

        let analysisResult: AnalysisResult
        if let key = remoteCacheKey,
           let cloudIndex = await PlaybackAnalysisCloudClient.fetchAnalysisIndex(
               bookId: key.bookId,
               chapterIndex: key.chapterIndex,
               textFingerprint: textFingerprint
           ),
           let restored = try? PlaybackAnalysisIndexBuilder.materialize(
               index: cloudIndex,
               canonicalText: canonical
           ) {
            analysisResult = Self.mergeClientMetadata(into: restored, metadata: metadata)
            progressHandler?(GenerationProgress(
                stage: .analyzing,
                progress: 1,
                message: "已使用云端分析索引"
            ))
        } else {
            analysisResult = try await textAnalyzer.analyze(text: text, metadata: metadata)
            if let key = remoteCacheKey, Config.discoverAPIBaseURL != nil {
                if let index = try? PlaybackAnalysisIndexBuilder.makeIndex(
                    bookId: key.bookId,
                    chapterIndex: key.chapterIndex,
                    canonicalText: canonical,
                    result: analysisResult
                ) {
                    PlaybackAnalysisCloudClient.uploadAnalysisIndexInBackground(index: index)
                }
            }
        }

        print("✅ 文本分析完成: \(analysisResult.segments.count) 个片段, \(analysisResult.characters.count) 个角色")

        // 2. 为角色分配音色
        progressHandler?(GenerationProgress(stage: .assigningVoices, progress: 0.1, message: "正在分配角色音色..."))
        voiceManager.loadAvailableVoices(for: ttsProvider)
        let (voiceAssignments, newBindings) = voiceManager.smartAssignVoices(
            for: analysisResult.characters,
            existingBindings: existingVoiceBindings
        )
        if !newBindings.isEmpty {
            onVoiceBindingsUpdated?(newBindings)
        }

        print("✅ 音色分配完成")

        // 3. 生成语音并混合音频（多段并发 TTS，由 TTSEngine 信号量与 `maxConcurrentTasks` 共同限流；边播边生成时仍按段序回调）
        let totalSegments = analysisResult.segments.count
        if totalSegments == 0 {
            progressHandler?(GenerationProgress(stage: .completed, progress: 1.0, message: "无分段可合成"))
            return Playlist(title: analysisResult.metadata.title, items: [])
        }
        let maxParallel = max(1, min(config.maxConcurrentTasks, max(1, totalSegments)))
        let orderedEmitter: OrderedPlaybackEmitter? = (streamItemsAsReady && onItemReady != nil)
            ? OrderedPlaybackEmitter(onItemReady: { onItemReady?($0) })
            : nil

        var byIndex: [Int: PlaybackItem] = [:]
        let indexLock = NSLock()
        var finishedCount = 0
        let countLock = NSLock()

        try await withThrowingTaskGroup(of: Void.self) { group in
            var nextScheduled = 0

            func schedule(_ i: Int) {
                let segment = analysisResult.segments[i]
                group.addTask {
                    let item = try await self.buildPlaybackItem(
                        segmentIndex: i,
                        segment: segment,
                        voiceAssignments: voiceAssignments
                    )
                    indexLock.lock()
                    byIndex[i] = item
                    indexLock.unlock()
                    orderedEmitter?.complete(segmentIndex: i, item: item)
                    countLock.lock()
                    finishedCount += 1
                    let fc = finishedCount
                    countLock.unlock()
                    let progress = 0.1 + (Double(fc) / Double(totalSegments)) * 0.9
                    progressHandler?(GenerationProgress(
                        stage: .synthesizing,
                        progress: progress,
                        message: "正在生成第 \(fc)/\(totalSegments) 段..."
                    ))
                    print("✅ 第 \(i + 1)/\(totalSegments) 段完成")
                }
            }

            while nextScheduled < min(maxParallel, totalSegments) {
                schedule(nextScheduled)
                nextScheduled += 1
            }

            while try await group.next() != nil {
                if nextScheduled < totalSegments {
                    schedule(nextScheduled)
                    nextScheduled += 1
                }
            }
        }

        let playbackItems = try (0..<totalSegments).map { idx -> PlaybackItem in
            guard let item = byIndex[idx] else {
                throw TTSError.apiError("分段 \(idx + 1) 合成结果缺失")
            }
            return item
        }

        // 4. 创建播放列表
        let playlist = Playlist(
            title: analysisResult.metadata.title,
            items: playbackItems
        )

        progressHandler?(GenerationProgress(stage: .completed, progress: 1.0, message: "生成完成！"))

        print("🎉 有声书生成完成！总时长: \(formatDuration(playlist.totalDuration))")

        return playlist
    }

    /// 批量生成（分章节）
    func generateBatch(
        chapters: [(title: String, text: String)],
        progressHandler: (@Sendable (BatchGenerationProgress) -> Void)? = nil
    ) async throws -> [Playlist] {

        var playlists: [Playlist] = []

        for (index, chapter) in chapters.enumerated() {
            print("📖 处理章节 \(index + 1)/\(chapters.count): \(chapter.title)")

            progressHandler?(BatchGenerationProgress(
                currentChapter: index,
                totalChapters: chapters.count,
                chapterTitle: chapter.title,
                chapterProgress: 0
            ))

            let metadata = NovelMetadata(
                title: chapter.title,
                chapterTitle: chapter.title,
                wordCount: chapter.text.count
            )

            let playlist = try await generate(
                text: chapter.text,
                metadata: metadata
            ) { progress in
                progressHandler?(BatchGenerationProgress(
                    currentChapter: index,
                    totalChapters: chapters.count,
                    chapterTitle: chapter.title,
                    chapterProgress: progress.progress
                ))
            }

            playlists.append(playlist)
        }

        print("🎉 批量生成完成！共 \(playlists.count) 个章节")

        return playlists
    }

    // MARK: - Private Methods

    private func buildPlaybackItem(
        segmentIndex: Int,
        segment: TextSegment,
        voiceAssignments: [Character: Voice]
    ) async throws -> PlaybackItem {
        let voice: Voice
        if segment.type == .dialogue, let speaker = segment.speaker {
            voice = voiceAssignments[speaker] ?? voiceManager.getNarrationVoice()
        } else {
            voice = voiceManager.getNarrationVoice()
        }

        let voiceAudio = try await ttsEngine.synthesize(segment: segment, voice: voice)

        let mixedAudio: AudioData
        if config.enableAudioMixing {
            let backgroundMusic = config.enableBackgroundMusic ? selectBackgroundMusic(for: segment) : nil
            let soundEffects = config.enableSoundEffects ? selectSoundEffects(for: segment) : []
            let mixTask = AudioMixTask(
                voiceAudio: voiceAudio,
                backgroundMusic: backgroundMusic,
                soundEffects: soundEffects,
                config: config.audioMixConfig,
                segment: segment
            )
            let mixResult = try await audioMixer.mix(task: mixTask)
            mixedAudio = mixResult.audioData
        } else {
            mixedAudio = voiceAudio
        }

        return PlaybackItem(segment: segment, audioData: mixedAudio, order: segmentIndex)
    }

    private static func mergeClientMetadata(into cached: AnalysisResult, metadata: NovelMetadata?) -> AnalysisResult {
        guard let m = metadata else { return cached }
        let mergedMeta = NovelMetadata(
            title: m.title,
            author: m.author,
            chapterTitle: m.chapterTitle,
            wordCount: m.wordCount,
            estimatedDuration: cached.metadata.estimatedDuration
        )
        return AnalysisResult(
            segments: cached.segments,
            characters: cached.characters,
            scenes: cached.scenes,
            metadata: mergedMeta
        )
    }

    /// 选择背景音乐
    private func selectBackgroundMusic(for segment: TextSegment) -> BackgroundMusic? {
        return MusicLibrary.randomMusic(for: segment.scene.type)
    }

    /// 选择音效
    private func selectSoundEffects(for segment: TextSegment) -> [SoundEffect] {
        return SoundEffectLibrary.matchEffects(for: segment.text)
    }

    /// 格式化时长
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d小时%d分%d秒", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%d分%d秒", minutes, seconds)
        } else {
            return String(format: "%d秒", seconds)
        }
    }
}

// MARK: - 生成器配置

/// 生成器配置
struct GeneratorConfig {
    var enableBackgroundMusic: Bool
    var enableSoundEffects: Bool
    var enableAudioMixing: Bool
    var audioMixConfig: AudioMixConfig
    var maxConcurrentTasks: Int

    init(
        enableBackgroundMusic: Bool = true,
        enableSoundEffects: Bool = true,
        enableAudioMixing: Bool = false,
        audioMixConfig: AudioMixConfig = AudioMixConfig(),
        maxConcurrentTasks: Int = 24
    ) {
        self.enableBackgroundMusic = enableBackgroundMusic
        self.enableSoundEffects = enableSoundEffects
        self.enableAudioMixing = enableAudioMixing
        self.audioMixConfig = audioMixConfig
        self.maxConcurrentTasks = maxConcurrentTasks
    }
}

// MARK: - AI 提供商

public enum AIProvider {
    case openai
    case claude
    case qwen
}

// MARK: - 生成进度

/// 生成进度
public struct GenerationProgress: Sendable {
    let stage: GenerationStage
    let progress: Double
    let message: String

    enum GenerationStage: Sendable {
        case analyzing          // 分析文本
        case assigningVoices    // 分配音色
        case synthesizing       // 合成语音
        case mixing             // 混合音频
        case completed          // 完成
    }
}

/// 批量生成进度
struct BatchGenerationProgress {
    let currentChapter: Int
    let totalChapters: Int
    let chapterTitle: String
    let chapterProgress: Double

    var overallProgress: Double {
        let chapterWeight = 1.0 / Double(totalChapters)
        let completedChapters = Double(currentChapter)
        return (completedChapters + chapterProgress) * chapterWeight
    }
}
