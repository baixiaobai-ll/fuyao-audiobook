//
//  AudioBookGenerator.swift
//  AI有声书
//
//  有声书生成器 - 整合所有模块的核心协调器
//

import Foundation

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

        // 创建 TTS 配置和引擎
        let ttsConfig = TTSConfig(provider: ttsProvider, apiKey: ttsApiKey)
        let ttsEngine = TTSEngine(config: ttsConfig)

        // 创建音频混合器
        let audioMixer = AudioMixer()

        // 创建音色管理器
        let voiceManager = VoiceManager()

        self.init(
            textAnalyzer: textAnalyzer,
            ttsEngine: ttsEngine,
            audioMixer: audioMixer,
            voiceManager: voiceManager,
            ttsProvider: ttsProvider
        )
    }

    // MARK: - Public Methods

    /// 生成有声书
    /// - Parameters:
    ///   - text: 小说文本
    ///   - metadata: 小说元数据
    ///   - progressHandler: 进度回调
    /// - Returns: 播放列表
    func generate(
        text: String,
        metadata: NovelMetadata? = nil,
        existingVoiceBindings: [String: String] = [:],
        progressHandler: (@Sendable (GenerationProgress) -> Void)? = nil,
        onItemReady: (@Sendable (PlaybackItem) -> Void)? = nil,
        onVoiceBindingsUpdated: (@Sendable ([String: String]) -> Void)? = nil
    ) async throws -> Playlist {

        print("🚀 开始生成有声书...")

        // 1. 分析文本
        progressHandler?(GenerationProgress(stage: .analyzing, progress: 0, message: "正在分析文本..."))
        let analysisResult = try await textAnalyzer.analyze(text: text, metadata: metadata)

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

        // 3. 生成语音并混合音频
        var playbackItems: [PlaybackItem] = []
        let totalSegments = analysisResult.segments.count

        for (index, segment) in analysisResult.segments.enumerated() {
            let progress = 0.1 + (Double(index) / Double(totalSegments)) * 0.9
            progressHandler?(GenerationProgress(
                stage: .synthesizing,
                progress: progress,
                message: "正在生成第 \(index + 1)/\(totalSegments) 段..."
            ))

            // 选择音色
            let voice: Voice
            if segment.type == .dialogue, let speaker = segment.speaker {
                voice = voiceAssignments[speaker] ?? voiceManager.getNarrationVoice()
            } else {
                voice = voiceManager.getNarrationVoice()
            }

            // 合成语音
            let voiceAudio = try await ttsEngine.synthesize(segment: segment, voice: voice)

            // 混合音频（添加背景音乐和音效）
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

            // 创建播放项
            let playbackItem = PlaybackItem(
                segment: segment,
                audioData: mixedAudio,
                order: index
            )

            playbackItems.append(playbackItem)
            onItemReady?(playbackItem)

            print("✅ 第 \(index + 1)/\(totalSegments) 段完成")
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
        maxConcurrentTasks: Int = 3
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
