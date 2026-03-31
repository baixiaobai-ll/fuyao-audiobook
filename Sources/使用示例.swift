//
//  使用示例.swift
//  AI有声书
//
//  展示如何使用 AI 有声书生成器
//

import Foundation

/// 使用示例
class UsageExample {

    // MARK: - 基础使用示例

    /// 示例 1: 基础生成
    func example1_BasicGeneration() async throws {
        // 1. 创建生成器
        let generator = AudioBookGenerator(
            aiApiKey: "your-ai-api-key",
            ttsApiKey: "your-tts-api-key",
            ttsProvider: .azure
        )

        // 2. 准备小说文本
        let novelText = """
        第一章 相遇

        "你好，我叫李明。"年轻人微笑着伸出手。

        张华愣了一下，随即也伸出手握住对方："你好，我是张华。"

        两人的手握在一起，这是一段传奇友谊的开始。

        窗外，阳光明媚，鸟儿在枝头欢快地歌唱。
        """

        // 3. 生成有声书
        let playlist = try await generator.generate(
            text: novelText,
            metadata: NovelMetadata(
                title: "传奇友谊",
                author: "佚名",
                chapterTitle: "第一章 相遇",
                wordCount: novelText.count
            )
        ) { progress in
            print("进度: \(Int(progress.progress * 100))% - \(progress.message)")
        }

        // 4. 播放
        let player = AudioBookPlayer()
        player.load(playlist: playlist)
        player.play()

        print("✅ 生成完成！共 \(playlist.items.count) 个片段")
    }

    // MARK: - 批量生成示例

    /// 示例 2: 批量生成多个章节
    func example2_BatchGeneration() async throws {
        let generator = AudioBookGenerator(
            aiApiKey: "your-ai-api-key",
            ttsApiKey: "your-tts-api-key"
        )

        // 准备多个章节
        let chapters = [
            (title: "第一章 相遇", text: "章节内容..."),
            (title: "第二章 冒险", text: "章节内容..."),
            (title: "第三章 成长", text: "章节内容...")
        ]

        // 批量生成
        let playlists = try await generator.generateBatch(chapters: chapters) { progress in
            print("章节 \(progress.currentChapter + 1)/\(progress.totalChapters): \(progress.chapterTitle)")
            print("进度: \(Int(progress.chapterProgress * 100))%")
        }

        print("✅ 批量生成完成！共 \(playlists.count) 个章节")
    }

    // MARK: - 自定义配置示例

    /// 示例 3: 自定义配置
    func example3_CustomConfiguration() async throws {
        // 创建自定义 AI 服务
        let aiService = QwenAnalysisService(
            apiKey: "your-qwen-api-key"
        )

        let textAnalyzer = NovelTextAnalyzer(aiService: aiService)

        // 创建自定义 TTS 配置
        let ttsConfig = TTSConfig(
            provider: .azure,
            apiKey: "your-azure-key",
            baseURL: "https://eastasia.tts.speech.microsoft.com",
            enableCache: true,
            maxConcurrentRequests: 5
        )

        let ttsEngine = TTSEngine(config: ttsConfig)

        // 创建自定义音频混合配置
        let audioMixConfig = AudioMixConfig(
            enableBackgroundMusic: true,
            backgroundMusicVolume: 0.2,
            voiceVolume: 1.0,
            enableSoundEffects: true,
            soundEffectsVolume: 0.4,
            fadeInDuration: 3.0,
            fadeOutDuration: 3.0
        )

        let audioMixer = AudioMixer()
        let voiceManager = VoiceManager()

        // 创建生成器配置
        let generatorConfig = GeneratorConfig(
            enableBackgroundMusic: true,
            enableSoundEffects: true,
            enableAudioMixing: true,
            audioMixConfig: audioMixConfig,
            maxConcurrentTasks: 5
        )

        let generator = AudioBookGenerator(
            textAnalyzer: textAnalyzer,
            ttsEngine: ttsEngine,
            audioMixer: audioMixer,
            voiceManager: voiceManager,
            config: generatorConfig
        )

        // 生成
        let playlist = try await generator.generate(text: "小说内容...")

        print("✅ 自定义配置生成完成！")
    }

    // MARK: - 手动控制示例

    /// 示例 4: 手动控制每个步骤
    func example4_ManualControl() async throws {
        // 1. 文本分析
        let aiService = QwenAnalysisService(apiKey: "your-api-key")
        let textAnalyzer = NovelTextAnalyzer(aiService: aiService)

        let text = "小说内容..."
        let analysisResult = try await textAnalyzer.analyze(text: text)

        print("分析结果:")
        print("- 片段数: \(analysisResult.segments.count)")
        print("- 角色数: \(analysisResult.characters.count)")
        print("- 场景数: \(analysisResult.scenes.count)")

        // 2. 手动分配音色
        let voiceManager = VoiceManager()

        for character in analysisResult.characters {
            // 获取推荐音色
            let recommendedVoices = voiceManager.getRecommendedVoices(for: character.gender)
            print("\n角色: \(character.name)")
            print("推荐音色:")
            for voice in recommendedVoices.prefix(3) {
                print("  - \(voice.name) (\(voice.description ?? ""))")
            }

            // 分配音色
            let voice = voiceManager.assignVoice(for: character)
            print("已分配: \(voice.name)")
        }

        // 3. 逐个合成语音
        let ttsConfig = TTSConfig(provider: .azure, apiKey: "your-tts-key")
        let ttsEngine = TTSEngine(config: ttsConfig)

        for segment in analysisResult.segments.prefix(3) {
            let voice: Voice
            if let speaker = segment.speaker {
                voice = voiceManager.getVoice(for: speaker) ?? voiceManager.getNarrationVoice()
            } else {
                voice = voiceManager.getNarrationVoice()
            }

            let audioData = try await ttsEngine.synthesize(segment: segment, voice: voice)
            print("✅ 合成完成: \(segment.text.prefix(20))... (\(audioData.duration)秒)")
        }

        print("✅ 手动控制示例完成！")
    }

    // MARK: - 播放器控制示例

    /// 示例 5: 播放器控制
    func example5_PlayerControl() async throws {
        // 假设已经生成了播放列表
        let playlist = Playlist(
            title: "测试小说",
            items: []  // 实际使用时需要有真实的播放项
        )

        let player = AudioBookPlayer()

        // 加载播放列表
        player.load(playlist: playlist)

        // 播放
        player.play()

        // 等待 5 秒
        try await Task.sleep(nanoseconds: 5_000_000_000)

        // 暂停
        player.pause()

        // 设置播放速度
        player.setPlaybackRate(1.5)  // 1.5 倍速

        // 继续播放
        player.play()

        // 跳转到 30 秒位置
        player.seek(to: 30)

        // 下一项
        player.next()

        // 上一项
        player.previous()

        // 设置重复模式
        player.setRepeatMode(.all)

        // 停止
        player.stop()

        print("✅ 播放器控制示例完成！")
    }

    // MARK: - 缓存管理示例

    /// 示例 6: 缓存管理
    func example6_CacheManagement() {
        // 文本分析缓存
        let analysisCache = AnalysisCache()
        print("分析缓存大小: \(analysisCache.getFormattedCacheSize())")
        // analysisCache.clearAll()  // 清空缓存

        // TTS 缓存
        let ttsCache = TTSCache()
        print("TTS 缓存大小: \(ttsCache.getFormattedCacheSize())")
        print("TTS 缓存文件数: \(ttsCache.getCacheCount())")
        // ttsCache.clearAll()  // 清空缓存

        // 播放器缓存
        let audioCacheManager = AudioCacheManager()
        // audioCacheManager.clearCache()  // 清空缓存

        print("✅ 缓存管理示例完成！")
    }

    // MARK: - 从文件读取示例

    /// 示例 7: 从文件读取小说
    func example7_ReadFromFile() async throws {
        // 读取 TXT 文件
        let fileURL = URL(fileURLWithPath: "/path/to/novel.txt")
        let novelText = try String(contentsOf: fileURL, encoding: .utf8)

        // 生成有声书
        let generator = AudioBookGenerator(
            aiApiKey: "your-ai-api-key",
            ttsApiKey: "your-tts-api-key"
        )

        let playlist = try await generator.generate(text: novelText)

        print("✅ 从文件生成完成！")
    }

    // MARK: - 导出音频文件示例

    /// 示例 8: 导出音频文件
    func example8_ExportAudio() async throws {
        // 假设已经生成了播放列表
        let playlist = Playlist(title: "测试小说", items: [])

        // 导出每个片段
        let outputDirectory = URL(fileURLWithPath: "/path/to/output")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for (index, item) in playlist.items.enumerated() {
            let segmentPrefix = String(item.segment.text.prefix(10))
            let fileName = String(format: "%03d_%@.%@", index + 1, segmentPrefix, item.audioData.format.rawValue)
            let fileURL = outputDirectory.appendingPathComponent(fileName)

            try item.audioData.data.write(to: fileURL)
            print("✅ 导出: \(fileName)")
        }

        print("✅ 导出完成！共 \(playlist.items.count) 个文件")
    }
}

// MARK: - 快速开始

/// 快速开始示例
func quickStart() async throws {
    print("🚀 AI 有声书快速开始\n")

    // 1. 创建生成器（需要替换为真实的 API Key）
    let generator = AudioBookGenerator(
        aiApiKey: "your-qwen-api-key",
        ttsApiKey: "your-azure-tts-key",
        ttsProvider: .azure
    )

    // 2. 准备小说文本
    let novelText = """
    "今天天气真好啊！"小明高兴地说。

    "是啊，我们去公园玩吧。"小红建议道。

    两个孩子手拉手，向着公园的方向跑去。阳光洒在他们身上，温暖而美好。
    """

    // 3. 生成有声书
    print("开始生成有声书...\n")

    let playlist = try await generator.generate(
        text: novelText,
        metadata: NovelMetadata(
            title: "美好的一天",
            wordCount: novelText.count
        )
    ) { progress in
        let percentage = Int(progress.progress * 100)
        print("[\(String(repeating: "=", count: percentage / 2))\(String(repeating: " ", count: 50 - percentage / 2))] \(percentage)%")
        print("\(progress.message)\n")
    }

    // 4. 播放
    print("\n开始播放...\n")

    let player = AudioBookPlayer()
    player.load(playlist: playlist)
    player.play()

    print("✅ 完成！")
    print("📊 统计信息:")
    print("   - 片段数: \(playlist.items.count)")
    print("   - 总时长: \(formatDuration(playlist.totalDuration))")
}

/// 格式化时长
private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d分%d秒", minutes, seconds)
}
