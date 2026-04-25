//
//  NovelTextAnalyzer.swift
//  AI有声书
//
//  小说文本分析器 - 使用 AI API 进行智能分析
//

import Foundation
import CommonCrypto

/// 文本分析器协议
protocol TextAnalyzerProtocol {
    func analyze(text: String, metadata: NovelMetadata?) async throws -> AnalysisResult
}

/// 小说文本分析器
class NovelTextAnalyzer: TextAnalyzerProtocol, @unchecked Sendable {

    private let aiService: AIAnalysisService
    private let cache: AnalysisCache
    private static let speechVerbMarkers = [
        "笑着说", "轻声说", "低声说", "沉声说", "冷冷说道", "轻声说道", "低声说道",
        "沉声说道", "提醒道", "解释道", "吩咐道", "喃喃道", "嘀咕道", "回头说道",
        "开口说道", "回应道", "回道", "应道", "说道", "说", "问道", "问", "答道",
        "答", "喊道", "喊", "叫道", "叫", "道"
    ]
    private static let speakerStyleSuffixes = [
        "笑着", "轻声", "低声", "沉声", "冷冷地", "冷冷", "淡淡地", "淡淡",
        "认真地", "认真", "无奈地", "无奈", "平静地", "平静", "咬牙切齿地", "咬牙切齿"
    ]
    private static let removableHonorificPrefixes = ["老", "小", "阿"]
    private static let removableHonorificSuffixes = [
        "先生", "小姐", "姑娘", "夫人", "老师", "医生", "警官", "将军", "老板", "掌柜",
        "殿下", "大人", "公子", "少爷", "哥哥", "姐姐", "弟弟", "妹妹", "叔叔", "阿姨"
    ]
    private static let uncertainSpeakerNames: Set<String> = [
        "他", "她", "它", "他们", "她们", "对方", "对面", "众人", "所有人", "两人",
        "二人", "三人", "一人", "男人", "女人", "少年", "少女", "青年", "老人",
        "老者", "老妇", "孩子", "小孩", "男孩", "女孩", "壮汉", "黑衣人", "路人",
        "店员", "店小二", "仆人", "侍女", "下人", "士兵", "官兵"
    ]

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

        // 分段处理（避免单次请求过大）。
        // Kimi 在长文本结构化分析上更容易被“大块 + 并发”拖慢，
        // 因此这里按 provider 收紧块大小，并限制并发度，优先保稳定。
        let chunkSize = recommendedChunkSize
        let chunks = splitIntoChunks(preprocessedText, maxChunkSize: chunkSize)

        var allSegments: [TextSegment] = []
        var allCharacters: Set<Character> = []
        var allScenes: [NovelScene] = []
        var segmentOrder = 0

        // 并发分析各个文本块
        var chunkResults: [(index: Int, result: ChunkAnalysisResult)] = []

        let maxParallelChunks = recommendedAnalysisParallelism
        try await withThrowingTaskGroup(of: (Int, ChunkAnalysisResult).self) { group in
            var nextScheduled = 0

            func schedule(_ index: Int) {
                let chunk = chunks[index]
                group.addTask {
                    let result = try await self.analyzeChunk(chunk, chunkIndex: index)
                    return (index, result)
                }
            }

            while nextScheduled < min(maxParallelChunks, chunks.count) {
                schedule(nextScheduled)
                nextScheduled += 1
            }

            while let chunkResult = try await group.next() {
                chunkResults.append(chunkResult)
                if nextScheduled < chunks.count {
                    schedule(nextScheduled)
                    nextScheduled += 1
                }
            }
        }

        for (_, result) in chunkResults.sorted(by: { $0.index < $1.index }) {
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
        do {
            return try parseAnalysisResponse(response, originalText: chunk)
        } catch {
            let previewLimit = 600
            let preview = response.count > previewLimit
                ? String(response.prefix(previewLimit)) + "\n...<truncated>"
                : response
            let responseLength = response.count
            let braceBalance = response.reduce(into: 0) { partial, character in
                if character == "{" { partial += 1 }
                if character == "}" { partial -= 1 }
            }
            print("""
            ⚠️ 第 \(chunkIndex + 1) 个分析分块 JSON 解析失败，回退到本地规则分析：\(error.localizedDescription)
            📄 原始返回长度: \(responseLength) 字符
            🧩 花括号平衡: \(braceBalance)
            📄 原始返回预览:
            \(preview)
            """)
            let localResponse = try await LocalRuleAnalysisService().analyze(prompt: prompt)
            return try parseAnalysisResponse(localResponse, originalText: chunk)
        }
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

        **输出约束**：
        - 必须只输出 JSON，不要输出解释、前后缀、markdown
        - `type` 只能是 `dialogue|narration|description|thought`
        - 只有当说话人能稳定确定时才填写 `speaker`，不确定时必须返回 `null` 或空字符串，不要猜测
        - 不要把“他/她/对方/众人/男人/女人/少年/少女”等泛指称呼当成稳定角色名
        - 同一角色请保持命名一致，不要一会儿用全名、一会儿用泛称或临时称呼
        - `emotion` 只能是 `neutral|happy|sad|angry|excited|fearful|surprised|tender`
        - `sceneType` 只能是 `peaceful|tense|battle|romantic|mysterious|sad|festive`
        - `gender` 只能是 `male|female|neutral|child|elder`
        - `sceneIntensity` 必须是 0.0 到 1.0 之间的小数

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
        var knownCharacterGenders: [String: Character.Gender] = [:]

        for charData in aiResult.characters {
            guard let stableName = stableSpeakerName(from: charData.name) else { continue }
            let normalizedGender = normalizeGender(charData.gender)
            let key = canonicalCharacterKey(for: stableName)
            if !key.isEmpty, knownCharacterGenders[key] == nil {
                knownCharacterGenders[key] = normalizedGender
            }
            _ = upsertCharacter(
                named: stableName,
                gender: normalizedGender,
                characters: &characters
            )
        }

        for (index, segmentData) in aiResult.segments.enumerated() {
            let normalizedType = normalizeSegmentType(segmentData.type, text: segmentData.text)
            let normalizedSceneType = normalizeSceneType(segmentData.sceneType, text: segmentData.text)
            let normalizedEmotion = normalizeEmotion(
                segmentData.emotion,
                text: segmentData.text,
                segmentType: normalizedType,
                sceneType: normalizedSceneType
            )
            let normalizedIntensity = normalizeSceneIntensity(segmentData.sceneIntensity)

            // 创建场景
            let scene = NovelScene(
                type: normalizedSceneType,
                description: normalizedSceneType.rawValue,
                intensity: normalizedIntensity
            )
            scenes.append(scene)

            // 查找或创建角色
            var speaker: Character?
            if normalizedType == .dialogue,
               let speakerName = segmentData.speaker,
               let resolvedSpeakerName = stableSpeakerName(from: speakerName) {
                let gender = knownCharacterGenders[canonicalCharacterKey(for: resolvedSpeakerName)] ?? .neutral
                speaker = upsertCharacter(
                    named: resolvedSpeakerName,
                    gender: gender,
                    characters: &characters
                )
            }

            // 创建片段
            let segment = TextSegment(
                text: segmentData.text,
                type: normalizedType,
                speaker: speaker,
                emotion: normalizedEmotion,
                scene: scene,
                order: index
            )
            segments.append(segment)
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

    private var recommendedChunkSize: Int {
        switch Config.aiProvider {
        case .kimi:
            return 50000
        case .qwen:
            return 2600
        case .local:
            return 3000
        }
    }

    private var recommendedAnalysisParallelism: Int {
        switch Config.aiProvider {
        case .kimi:
            return 1
        case .qwen:
            return 2
        case .local:
            return 4
        }
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
        let canonical = Self.canonicalTextForPlayback(text)
        guard let data = canonical.data(using: .utf8) else {
            return String(canonical.hashValue)
        }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { rawBuffer in
            _ = CC_SHA256(rawBuffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizeSegmentType(_ raw: String, text: String) -> SegmentType {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "dialogue", "dialog", "speech", "对话":
            return .dialogue
        case "narration", "narrative", "旁白", "叙述":
            return .narration
        case "description", "描述", "场景描述":
            return .description
        case "thought", "inner_thought", "monologue", "内心独白", "心理活动":
            return .thought
        default:
            if text.contains("“") || text.contains("”") || text.contains("\"") {
                return .dialogue
            }
            return .narration
        }
    }

    private func normalizeEmotion(
        _ raw: String,
        text: String,
        segmentType: SegmentType,
        sceneType: SceneType
    ) -> Emotion {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "neutral", "calm", "平静", "平和", "自然":
            return .neutral
        case "happy", "joy", "joyful", "开心", "高兴", "愉快":
            return .happy
        case "sad", "悲伤", "难过", "哀伤":
            return .sad
        case "angry", "anger", "愤怒", "生气":
            return .angry
        case "excited", "excitement", "激动", "兴奋":
            return .excited
        case "fearful", "fear", "scared", "nervous", "恐惧", "害怕", "紧张":
            return .fearful
        case "surprised", "surprise", "惊讶", "震惊":
            return .surprised
        case "tender", "gentle", "soft", "温柔", "柔和":
            return .tender
        default:
            if segmentType == .thought {
                return .tender
            }
            if sceneType == .battle {
                return .excited
            }
            if sceneType == .sad {
                return .sad
            }
            if text.contains("怒") || text.contains("吼") || text.contains("喝道") {
                return .angry
            }
            if text.contains("笑") || text.contains("开心") {
                return .happy
            }
            if text.contains("惊") || text.contains("啊") {
                return .surprised
            }
            return .neutral
        }
    }

    private func normalizeSceneType(_ raw: String, text: String) -> SceneType {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "peaceful", "calm", "平和", "平静", "日常":
            return .peaceful
        case "tense", "紧张", "压迫":
            return .tense
        case "battle", "action", "fight", "战斗", "打斗":
            return .battle
        case "romantic", "romance", "暧昧", "浪漫":
            return .romantic
        case "mysterious", "mystery", "神秘", "诡异":
            return .mysterious
        case "sad", "悲伤", "压抑":
            return .sad
        case "festive", "celebration", "欢庆", "热闹":
            return .festive
        default:
            if text.contains("剑") || text.contains("杀") || text.contains("轰") {
                return .battle
            }
            if text.contains("温柔") || text.contains("拥抱") || text.contains("亲") {
                return .romantic
            }
            if text.contains("阴森") || text.contains("诡异") || text.contains("黑暗") {
                return .mysterious
            }
            return .peaceful
        }
    }

    private func normalizeSceneIntensity(_ raw: Double) -> Double {
        if raw.isFinite {
            return min(max(raw, 0.05), 1.0)
        }
        return 0.5
    }

    private func normalizeGender(_ raw: String) -> Character.Gender {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "male", "man", "男":
            return .male
        case "female", "woman", "女":
            return .female
        case "child", "kid", "儿童", "小孩":
            return .child
        case "elder", "old", "老年", "老人":
            return .elder
        default:
            return .neutral
        }
    }

    private func cleanSpeakerName(_ raw: String) -> String {
        var candidate = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "‘", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "「", with: "")
            .replacingOccurrences(of: "」", with: "")
            .replacingOccurrences(of: "『", with: "")
            .replacingOccurrences(of: "』", with: "")
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        candidate = candidate.replacingOccurrences(
            of: "^[：:、，,。！？!？；;\\s]+|[：:、，,。！？!？；;\\s]+$",
            with: "",
            options: .regularExpression
        )

        if let splitIndex = Self.speechVerbMarkers
            .compactMap({ marker in
                candidate.range(of: marker).flatMap { range in
                    range.lowerBound == candidate.startIndex ? nil : range.lowerBound
                }
            })
            .min() {
            candidate = String(candidate[..<splitIndex])
        }

        var trimmed = true
        while trimmed {
            trimmed = false
            for suffix in Self.speakerStyleSuffixes {
                if candidate.hasSuffix(suffix), candidate.count > suffix.count {
                    candidate.removeLast(suffix.count)
                    trimmed = true
                    break
                }
            }
        }

        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stableSpeakerName(from raw: String) -> String? {
        let cleaned = cleanSpeakerName(raw)
        guard !cleaned.isEmpty, !isUncertainSpeakerName(cleaned) else {
            return nil
        }
        return cleaned
    }

    private func canonicalCharacterKey(for name: String) -> String {
        let cleaned = cleanSpeakerName(name)
        guard !cleaned.isEmpty else { return "" }

        var candidate = cleaned
        for prefix in Self.removableHonorificPrefixes where candidate.hasPrefix(prefix) && candidate.count > prefix.count {
            candidate.removeFirst(prefix.count)
            break
        }

        let sortedSuffixes = Self.removableHonorificSuffixes.sorted { $0.count > $1.count }
        for suffix in sortedSuffixes where candidate.hasSuffix(suffix) && candidate.count > suffix.count {
            candidate.removeLast(suffix.count)
            break
        }

        let normalized = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
        return normalized.isEmpty ? cleaned.lowercased() : normalized
    }

    private func isUncertainSpeakerName(_ raw: String) -> Bool {
        let candidate = cleanSpeakerName(raw)
        guard !candidate.isEmpty else { return true }

        let canonical = canonicalCharacterKey(for: candidate)
        let lowercased = candidate.lowercased()
        if Self.uncertainSpeakerNames.contains(lowercased) || Self.uncertainSpeakerNames.contains(canonical) {
            return true
        }

        if candidate.count > 8 || canonical.count > 8 {
            return true
        }

        if candidate.contains(" ") {
            return true
        }

        if candidate.range(of: "[，。！？；：、“”\"'（）()【】\\[\\]/\\\\]", options: .regularExpression) != nil {
            return true
        }

        let ambiguousPrefixes = ["一个", "那位", "这位", "那名", "这名", "某位", "某个", "某名"]
        if ambiguousPrefixes.contains(where: { candidate.hasPrefix($0) }) {
            return true
        }

        let ambiguousFragments = ["众人", "两人", "二人", "三人", "几人", "人群", "声音", "话音", "身影", "脚步"]
        return ambiguousFragments.contains(where: { candidate.contains($0) })
    }

    private func upsertCharacter(
        named name: String,
        gender: Character.Gender,
        characters: inout Set<Character>
    ) -> Character {
        let cleanedName = cleanSpeakerName(name)
        let canonical = canonicalCharacterKey(for: cleanedName)
        if let existing = characters.first(where: {
            cleanSpeakerName($0.name) == cleanedName
                || (!canonical.isEmpty && canonicalCharacterKey(for: $0.name) == canonical)
        }) {
            return existing
        }
        let character = Character(name: cleanedName, gender: gender)
        characters.insert(character)
        return character
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
    case requestTimedOut(providerName: String, seconds: TimeInterval)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "无法解析 AI 返回的分析结果"
        case .apiError(let message):
            return "API 错误: \(message)"
        case .networkError:
            return "网络连接失败"
        case .requestTimedOut(let providerName, let seconds):
            return "\(providerName) 分析超时（\(Int(seconds)) 秒）"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .networkError, .requestTimedOut(_, _):
            return true
        case .apiError(let message):
            return message.contains("HTTP 408")
                || message.contains("HTTP 409")
                || message.contains("HTTP 425")
                || message.contains("HTTP 429")
                || message.contains("HTTP 500")
                || message.contains("HTTP 502")
                || message.contains("HTTP 503")
                || message.contains("HTTP 504")
        case .invalidResponse:
            return false
        }
    }

    var allowsLocalFallback: Bool {
        switch self {
        case .invalidResponse, .networkError, .requestTimedOut(_, _):
            return true
        case .apiError(let message):
            return !message.contains("鉴权失败")
        }
    }
}
