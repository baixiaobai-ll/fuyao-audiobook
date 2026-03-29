//
//  NovelTextAnalyzer.swift
//  AI有声书
//
//  小说文本分析器 - 使用 AI API 进行智能分析
//

import Foundation

/// 文本分析器协议
protocol TextAnalyzerProtocol {
    func analyze(text: String, metadata: NovelMetadata?) async throws -> AnalysisResult
}

/// 小说文本分析器
class NovelTextAnalyzer: TextAnalyzerProtocol, @unchecked Sendable {

    private let aiService: AIAnalysisService
    private let cache: AnalysisCache

    init(aiService: AIAnalysisService, cache: AnalysisCache = AnalysisCache()) {
        self.aiService = aiService
        self.cache = cache
    }

    /// 分析小说文本
    /// - Parameters:
    ///   - text: 小说文本
    ///   - metadata: 小说元数据（可选）
    /// - Returns: 分析结果
    func analyze(text: String, metadata: NovelMetadata? = nil) async throws -> AnalysisResult {

        // 检查缓存
        let cacheKey = generateCacheKey(for: text)
        if let cachedResult = cache.retrieve(key: cacheKey) {
            print("📦 使用缓存的分析结果")
            return cachedResult
        }

        print("🔍 开始分析文本...")

        // 预处理文本
        let preprocessedText = preprocessText(text)

        // 分段处理（避免单次请求过大）
        let chunks = splitIntoChunks(preprocessedText, maxChunkSize: 3000)

        var allSegments: [TextSegment] = []
        var allCharacters: Set<Character> = []
        var allScenes: [NovelScene] = []
        var segmentOrder = 0

        // 并发分析各个文本块
        try await withThrowingTaskGroup(of: ChunkAnalysisResult.self) { group in
            for (index, chunk) in chunks.enumerated() {
                group.addTask {
                    try await self.analyzeChunk(chunk, chunkIndex: index)
                }
            }

            for try await result in group {
                // 更新片段顺序
                let orderedSegments = result.segments.map { segment in
                    var updated = segment
                    updated = TextSegment(
                        id: segment.id,
                        text: segment.text,
                        type: segment.type,
                        speaker: segment.speaker,
                        emotion: segment.emotion,
                        scene: segment.scene,
                        order: segmentOrder
                    )
                    segmentOrder += 1
                    return updated
                }

                allSegments.append(contentsOf: orderedSegments)
                allCharacters.formUnion(result.characters)
                allScenes.append(contentsOf: result.scenes)
            }
        }

        // 按顺序排序
        allSegments.sort { $0.order < $1.order }

        // 合并相同场景
        let mergedScenes = mergeScenes(allScenes)

        // 生成元数据
        let finalMetadata = metadata ?? generateMetadata(
            from: text,
            segments: allSegments
        )

        let result = AnalysisResult(
            segments: allSegments,
            characters: Array(allCharacters),
            scenes: mergedScenes,
            metadata: finalMetadata
        )

        // 缓存结果
        cache.store(result, key: cacheKey)

        print("✅ 分析完成: \(allSegments.count) 个片段, \(allCharacters.count) 个角色")

        return result
    }

    // MARK: - Private Methods

    /// 分析单个文本块
    private func analyzeChunk(_ chunk: String, chunkIndex: Int) async throws -> ChunkAnalysisResult {
        let prompt = buildAnalysisPrompt(for: chunk)
        let response = try await aiService.analyze(prompt: prompt)
        return try parseAnalysisResponse(response, originalText: chunk)
    }

    /// 构建分析提示词
    private func buildAnalysisPrompt(for text: String) -> String {
        return """
        请分析以下小说文本，提取以下信息：

        1. 将文本分段，每段标注：
           - 类型（对话/旁白/描述/内心独白）
           - 说话人（如果是对话）
           - 情感（平静/开心/悲伤/愤怒/兴奋/恐惧/惊讶/温柔）
           - 场景类型（平和/紧张/战斗/浪漫/神秘/悲伤/欢庆）

        **重要分段规则**：
        - "XX说"、"XX道"、"XX喊道"、"XX笑道"等引导语必须作为 narration（旁白）类型单独分段，不要和引号内的对话合并
        - 只有引号（""、「」、''）内的实际说话内容才标记为 dialogue（对话）类型
        - 例如："张三笑着说：'你好啊！'" 应拆为两段：
          1. type=narration, text="张三笑着说：", speaker=null
          2. type=dialogue, text="你好啊！", speaker="张三"

        2. 提取所有角色信息：
           - 姓名
           - 性别（男/女/中性/儿童/老年）

        3. 识别场景变化

        请以 JSON 格式返回，结构如下：
        {
          "segments": [
            {
              "text": "对话或旁白内容",
              "type": "dialogue|narration|description|thought",
              "speaker": "角色名（对话时）",
              "emotion": "neutral|happy|sad|angry|excited|fearful|surprised|tender",
              "sceneType": "peaceful|tense|battle|romantic|mysterious|sad|festive",
              "sceneIntensity": 0.5
            }
          ],
          "characters": [
            {
              "name": "角色名",
              "gender": "male|female|neutral|child|elder"
            }
          ]
        }

        文本内容：
        \(text)
        """
    }

    /// 解析 AI 返回的分析结果
    private func parseAnalysisResponse(_ response: String, originalText: String) throws -> ChunkAnalysisResult {
        // 提取 JSON（AI 可能返回带解释的文本）
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8) else {
            throw AnalysisError.invalidResponse
        }

        let decoder = JSONDecoder()
        let aiResult = try decoder.decode(AIAnalysisResponse.self, from: data)

        // 转换为内部模型
        var segments: [TextSegment] = []
        var characters: Set<Character> = []
        var scenes: [NovelScene] = []

        for (index, segmentData) in aiResult.segments.enumerated() {
            // 创建场景
            let scene = NovelScene(
                type: SceneType(rawValue: segmentData.sceneType) ?? .peaceful,
                description: segmentData.sceneType,
                intensity: segmentData.sceneIntensity
            )
            scenes.append(scene)

            // 查找或创建角色
            var speaker: Character?
            if let speakerName = segmentData.speaker, !speakerName.isEmpty {
                if let existingChar = characters.first(where: { $0.name == speakerName }) {
                    speaker = existingChar
                } else {
                    // 从角色列表中查找性别
                    let gender = aiResult.characters.first(where: { $0.name == speakerName })?.gender ?? "neutral"
                    let newChar = Character(
                        name: speakerName,
                        gender: Character.Gender(rawValue: gender) ?? .neutral
                    )
                    characters.insert(newChar)
                    speaker = newChar
                }
            }

            // 创建片段
            let segment = TextSegment(
                text: segmentData.text,
                type: SegmentType(rawValue: segmentData.type) ?? .narration,
                speaker: speaker,
                emotion: Emotion(rawValue: segmentData.emotion) ?? .neutral,
                scene: scene,
                order: index
            )
            segments.append(segment)
        }

        // 添加所有角色
        for charData in aiResult.characters {
            let character = Character(
                name: charData.name,
                gender: Character.Gender(rawValue: charData.gender) ?? .neutral
            )
            characters.insert(character)
        }

        return ChunkAnalysisResult(
            segments: segments,
            characters: characters,
            scenes: scenes
        )
    }

    /// 预处理文本（与 `canonicalTextForPlayback` 一致，供分析与云端索引共用同一字节空间）
    private func preprocessText(_ text: String) -> String {
        Self.canonicalTextForPlayback(text)
    }

    /// 与 `analyze` 内部使用的规范化文本一致；`textHash` 与 UTF-8 分段偏移均基于此串。
    static func canonicalTextForPlayback(_ text: String) -> String {
        var processed = text
        processed = processed.replacingOccurrences(of: "\r\n", with: "\n")
        processed = processed.replacingOccurrences(of: "\r", with: "\n")
        processed = processed.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        processed = processed.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return processed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 将文本分割成块
    private func splitIntoChunks(_ text: String, maxChunkSize: Int) -> [String] {
        let paragraphs = text.components(separatedBy: "\n\n")
        var chunks: [String] = []
        var currentChunk = ""

        for paragraph in paragraphs {
            if currentChunk.count + paragraph.count > maxChunkSize && !currentChunk.isEmpty {
                chunks.append(currentChunk)
                currentChunk = paragraph
            } else {
                if !currentChunk.isEmpty {
                    currentChunk += "\n\n"
                }
                currentChunk += paragraph
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks.isEmpty ? [text] : chunks
    }

    /// 提取 JSON 字符串
    private func extractJSON(from text: String) -> String {
        // 尝试提取 ```json ... ``` 代码块
        if let range = text.range(of: "```json\\s*\\n([\\s\\S]*?)\\n```", options: .regularExpression) {
            let jsonBlock = String(text[range])
            return jsonBlock
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 尝试提取 { ... } JSON 对象
        if let startIndex = text.firstIndex(of: "{"),
           let endIndex = text.lastIndex(of: "}") {
            return String(text[startIndex...endIndex])
        }

        return text
    }

    /// 合并相似场景
    private func mergeScenes(_ scenes: [NovelScene]) -> [NovelScene] {
        var merged: [NovelScene] = []
        var currentScene: NovelScene?

        for scene in scenes {
            if let current = currentScene, current.type == scene.type {
                // 相同类型的场景，更新强度为平均值
                let avgIntensity = (current.intensity + scene.intensity) / 2
                  currentScene = NovelScene(
                    id: current.id,
                    type: current.type,
                    description: current.description,
                    intensity: avgIntensity
                )
            } else {
                if let current = currentScene {
                    merged.append(current)
                }
                currentScene = scene
            }
        }

        if let current = currentScene {
            merged.append(current)
        }

        return merged
    }

    /// 生成元数据
    private func generateMetadata(from text: String, segments: [TextSegment]) -> NovelMetadata {
        let wordCount = text.count
        // 估算时长：平均每分钟 300 字
        let estimatedMinutes = Double(wordCount) / 300.0
        let estimatedDuration = estimatedMinutes * 60.0

        return NovelMetadata(
            title: "未命名小说",
            wordCount: wordCount,
            estimatedDuration: estimatedDuration
        )
    }

    /// 生成缓存键
    private func generateCacheKey(for text: String) -> String {
        return text.prefix(100).hash.description
    }
}

// MARK: - Supporting Types

/// 文本块分析结果
private struct ChunkAnalysisResult: Sendable {
    let segments: [TextSegment]
    let characters: Set<Character>
    let scenes: [NovelScene]
}

/// AI 返回的分析响应
private struct AIAnalysisResponse: Codable {
    let segments: [SegmentData]
    let characters: [CharacterData]

    struct SegmentData: Codable {
        let text: String
        let type: String
        let speaker: String?
        let emotion: String
        let sceneType: String
        let sceneIntensity: Double
    }

    struct CharacterData: Codable {
        let name: String
        let gender: String
    }
}

/// 分析错误
enum AnalysisError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case networkError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "无法解析 AI 返回的分析结果"
        case .apiError(let message):
            return "API 错误: \(message)"
        case .networkError:
            return "网络连接失败"
        }
    }
}
