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

    /// 当前 provider 在 dump 文件名里的标签（用于 KimiAnalysisDump/run_<provider>_<stamp>）。
    private var dumpProviderTag: String {
        switch aiService.provider {
        case .kimi: return "kimi"
        case .qwen: return "qwen"
        }
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
        // Kimi 在长文本结构化分析上更容易被“大块 + 并发”拖慢，因此按 provider 收紧块大小，并限制并发度，优先保稳定。
        let chunkSize = recommendedChunkSize
        let chunks = splitIntoChunks(preprocessedText, maxChunkSize: chunkSize)

        // 本次 run 的原始记录落盘工具（chunk 输入 / Kimi prompt / 原始返回 / 解析结果）。
        // 用于排查"旁白被错认 / speaker 给错"等纯靠 console 日志看不清楚的问题。
        // 创建失败（沙盒受限）时返回 nil，分析流程不受影响。
        let dumpWriter = AnalysisDumpWriter(provider: dumpProviderTag)

        var allSegments: [TextSegment] = []
        // 跨 chunk 合并使用 canonicalKey 主键，避免同一角色因不同 UUID 被当作两个角色。
        var allCharactersByKey: [String: Character] = [:]
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
                    let result = try await self.analyzeChunk(chunk, chunkIndex: index, dump: dumpWriter)
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
            // 1) 把当前 chunk 的角色按 canonicalKey 合并到全局表，已存在则保留首次出现的 Character（含其 UUID）。
            for character in result.characters {
                let key = mergeKey(forCharacterName: character.name)
                if allCharactersByKey[key] == nil {
                    allCharactersByKey[key] = character
                } else if var existing = allCharactersByKey[key] {
                    // 后出现的 chunk 补上 Kimi 标签 / 叙事项（首段未写时常见）
                    var changed = false
                    if existing.voiceArchetype == nil, let t = character.voiceArchetype {
                        existing.voiceArchetype = t
                        changed = true
                    }
                    if existing.narrativeRole == nil, let r = character.narrativeRole {
                        existing.narrativeRole = r
                        changed = true
                    }
                    if changed { allCharactersByKey[key] = existing }
                }
            }

            // 2) 重写本 chunk segments 的 speaker，让其引用全局表中的稳定 Character；
            //    这样 PlaybackAnalysisIndexBuilder 用 segment.speaker.id 反查 characters 才不会丢人。
            let orderedSegments = result.segments.map { segment -> TextSegment in
                let canonicalSpeaker: Character?
                if let original = segment.speaker {
                    let key = mergeKey(forCharacterName: original.name)
                    canonicalSpeaker = allCharactersByKey[key] ?? original
                } else {
                    canonicalSpeaker = nil
                }
                let updated = TextSegment(
                    id: segment.id,
                    text: segment.text,
                    type: segment.type,
                    speaker: canonicalSpeaker,
                    emotion: segment.emotion,
                    scene: segment.scene,
                    order: segmentOrder
                )
                segmentOrder += 1
                return updated
            }

            allSegments.append(contentsOf: orderedSegments)
            allScenes.append(contentsOf: result.scenes)
        }

        // 3) 全部 chunk 合并完后，用最终的 `allCharactersByKey` 再刷一遍 `segment.speaker`。
        //    否则：后段 chunk 才补上的 `voiceArchetype` 无法反映到前段已生成的对话副本上。
        let finalCharactersByKey = allCharactersByKey
        allSegments = allSegments.map { seg in
            guard let sp = seg.speaker else { return seg }
            let key = mergeKey(forCharacterName: sp.name)
            guard let global = finalCharactersByKey[key] else { return seg }
            return TextSegment(
                id: seg.id,
                text: seg.text,
                type: seg.type,
                speaker: global,
                emotion: seg.emotion,
                scene: seg.scene,
                order: seg.order
            )
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

        let mergedCharacters = Array(allCharactersByKey.values)
        let result = AnalysisResult(
            segments: allSegments,
            characters: mergedCharacters,
            scenes: mergedScenes,
            metadata: finalMetadata
        )

        // 缓存结果
        cache.store(result, key: cacheKey)

        print("✅ 分析完成: \(allSegments.count) 个片段, \(mergedCharacters.count) 个角色")

        if let dumpWriter {
            let summary = renderRunSummary(
                provider: dumpProviderTag,
                chunks: chunks,
                segments: allSegments,
                characters: mergedCharacters
            )
            dumpWriter.writeRunSummary(summary)
        }

        return result
    }

    // MARK: - Private Methods

    /// 分析单个文本块
    ///
    /// 当 JSON 解析失败（极少数情况下 Kimi 可能因网络抖动返回非合法 JSON）时：
    ///   1. 先让 Kimi 再请求若干次（默认 2 次），挡掉单次抖动；
    ///   2. 仍失败时**直接降级为整块旁白**（speaker=nil，按段落/句子切成 ≤200 字符的 narration），
    ///      让默认旁白音色把整段念出去。
    ///      已彻底删除 LocalRuleAnalysisService：本地正则会把"陆鸣固执的摇了摇头道："
    ///      这类引导语错抽成 speaker，污染角色识别和音色映射，体感比"全旁白"差得多。
    private func analyzeChunk(_ chunk: String, chunkIndex: Int, dump: AnalysisDumpWriter? = nil) async throws -> ChunkAnalysisResult {
        let prompt = buildAnalysisPrompt(for: chunk)
        let maxJsonRetries = 2

        // 提前把输入和 prompt 落盘，便于"返回出问题前 / 后"对比。
        dump?.writeChunkInput(index: chunkIndex, text: chunk)
        dump?.writeChunkPrompt(index: chunkIndex, prompt: prompt)

        var lastDiagnostic: (length: Int, balance: Int, preview: String, error: Error)?

        for attempt in 1...(maxJsonRetries + 1) {
            let response = try await aiService.analyze(prompt: prompt)
            // 不论解析成功与否都把原始返回落盘：成功路径只保留最后一份，失败路径每次重试单独保留。
            dump?.writeChunkRawResponse(index: chunkIndex, attempt: attempt, response: response)
            do {
                let parsed = try parseAnalysisResponse(response, originalText: chunk)
                dump?.writeChunkParsed(
                    index: chunkIndex,
                    parsedDescription: renderParsedDescription(chunkIndex: chunkIndex, result: parsed)
                )
                return parsed
            } catch {
                let previewLimit = 600
                let preview = response.count > previewLimit
                    ? String(response.prefix(previewLimit)) + "\n...<truncated>"
                    : response
                let balance = response.reduce(into: 0) { partial, character in
                    if character == "{" { partial += 1 }
                    if character == "}" { partial -= 1 }
                }
                lastDiagnostic = (response.count, balance, preview, error)

                if attempt <= maxJsonRetries {
                    print("⚠️ 第 \(chunkIndex + 1) 个分块 JSON 解析失败 (尝试 \(attempt)/\(maxJsonRetries + 1))，重新请求 Kimi：\(error.localizedDescription) 花括号平衡=\(balance)")
                    continue
                }
            }
        }

        let diagnostic = lastDiagnostic
        let diagnosticMessage = """
        第 \(chunkIndex + 1) 个分块经 \(maxJsonRetries + 1) 次重试仍无法解析，整块降级为旁白单段（speaker=nil）。
        - error: \(diagnostic?.error.localizedDescription ?? "未知错误")
        - 原文输入: \(chunk.count) 字符
        - 原始返回长度: \(diagnostic?.length ?? 0) 字符
        - 花括号平衡: \(diagnostic?.balance ?? 0)

        原始返回预览:
        \(diagnostic?.preview ?? "")
        """
        print("❌ \(diagnosticMessage)")
        dump?.writeChunkError(index: chunkIndex, message: diagnosticMessage)
        return makeNarrationFallbackChunk(originalText: chunk)
    }

    /// 把单个 chunk 的解析结果渲染为人眼可读的文本（segments + characters）。
    private func renderParsedDescription(chunkIndex: Int, result: ChunkAnalysisResult) -> String {
        var lines: [String] = []
        lines.append("# Chunk #\(chunkIndex + 1) 解析结果")
        lines.append("- segments: \(result.segments.count)")
        lines.append("- characters: \(result.characters.count)")
        lines.append("- scenes: \(result.scenes.count)")
        lines.append("")
        lines.append("## 角色")
        if result.characters.isEmpty {
            lines.append("（无）")
        } else {
            for character in result.characters {
                let arch = character.voiceArchetype.map { "voiceArchetype=\($0.rawValue)" } ?? "voiceArchetype=—"
                let nr = character.narrativeRole.map { "narrativeRole=\($0.rawValue)" } ?? "narrativeRole=—"
                lines.append("- \(character.name) | gender=\(character.gender.rawValue) | \(arch) | \(nr)")
            }
        }
        lines.append("")
        lines.append("## Segments")
        for (idx, segment) in result.segments.enumerated() {
            let speakerLabel: String
            if let speaker = segment.speaker {
                speakerLabel = "\(speaker.name)[\(speaker.gender.rawValue)]"
            } else {
                speakerLabel = "—"
            }
            let preview = segment.text.count > 80
                ? String(segment.text.prefix(80)) + "…"
                : segment.text
            lines.append("[\(idx + 1)] type=\(segment.type.rawValue) speaker=\(speakerLabel) emotion=\(segment.emotion.rawValue)")
            lines.append("    text: \(preview)")
        }
        return lines.joined(separator: "\n")
    }

    /// 整次 run 的汇总（chunk 数 / 段数 / 角色数 / 角色清单）。
    fileprivate func renderRunSummary(
        provider: String,
        chunks: [String],
        segments: [TextSegment],
        characters: [Character]
    ) -> String {
        var lines: [String] = []
        lines.append("- provider: \(provider)")
        lines.append("- chunks: \(chunks.count)")
        lines.append("- segments: \(segments.count)")
        lines.append("- characters: \(characters.count)")
        lines.append("")
        lines.append("## 角色清单")
        if characters.isEmpty {
            lines.append("（无）")
        } else {
            for character in characters {
                let arch = character.voiceArchetype.map { "voiceArchetype=\($0.rawValue)" } ?? "voiceArchetype=—"
                let nr = character.narrativeRole.map { "narrativeRole=\($0.rawValue)" } ?? "narrativeRole=—"
                lines.append("- \(character.name) | gender=\(character.gender.rawValue) | \(arch) | \(nr)")
            }
        }
        lines.append("")
        lines.append("## 各 chunk 字符数")
        for (idx, chunk) in chunks.enumerated() {
            lines.append("- chunk_\(String(format: "%03d", idx)): \(chunk.count) 字符")
        }
        return lines.joined(separator: "\n")
    }

    /// JSON 兜底：把整块文本切成若干 narration segment 直接交给旁白音色播。
    ///
    /// - 切分粒度：按段落 / 中文句号问号感叹号分号软切分，避免单段过长拖慢 TTS 节奏。
    /// - 所有 segment 一律 `speaker = nil`，让 `AudioBookGenerator.buildPlaybackItem`
    ///   走 `narrationVoice` 路径，使用书籍配音方案里的旁白音色。
    /// - characters / scenes 留空，不会污染跨 chunk 的角色合并表与场景表。
    private func makeNarrationFallbackChunk(originalText: String) -> ChunkAnalysisResult {
        let pieces = splitTextForNarrationFallback(originalText)
        let fallbackScene = NovelScene(type: .peaceful, description: "未识别段落", intensity: 0.4)
        let segments: [TextSegment] = pieces.enumerated().map { index, text in
            TextSegment(
                id: UUID(),
                text: text,
                type: .narration,
                speaker: nil,
                emotion: .neutral,
                scene: fallbackScene,
                order: index
            )
        }
        return ChunkAnalysisResult(
            segments: segments,
            characters: [],
            scenes: segments.isEmpty ? [] : [fallbackScene]
        )
    }

    /// 按段落 / 句号软切，单段最大 200 字。
    private func splitTextForNarrationFallback(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let paragraphs = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let maxLen = 200
        var pieces: [String] = []
        for paragraph in paragraphs {
            if paragraph.count <= maxLen {
                pieces.append(paragraph)
                continue
            }
            var buffer = ""
            for ch in paragraph {
                buffer.append(ch)
                if buffer.count >= maxLen, "。！？!?；;".contains(ch) {
                    pieces.append(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { pieces.append(tail) }
        }
        return pieces
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
           - **音色人设标签 `voiceArchetype`（必填）**：只描述「适合哪种听感人设」，**禁止**填写讯飞 vcn、禁止填中文音色商品名；取值只能是以下 **7 个英文 snake_case 之一**：
             - `elder_male`：老年男性 / 长辈 / 掌门 / 族长 / 老叟
             - `elder_female`：老年女性 / 婆婆 / 嬷嬷 / 太后类
             - `boy_young_male`：男童、小厮、店小二、少年感男配、音色偏轻的男角
             - `girl_young_female`：女童、少女、年轻女配
             - `adult_male`：成年男主、将军、沉稳男配、成年反派男等
             - `adult_female`：成年女主、温柔女性、贵妇、师姐等
             - `neutral`：性别年龄均无法从文本判断的龙套，或一闪而过的路人
           - `voiceArchetype` 必须与文本描写一致；与 `gender` 冲突时**以文本事实为准**并修正 `gender`（例如文本明确是少女则 `gender` 用 `female`、`voiceArchetype` 用 `girl_young_female`，不要标 `child`）。
           - **`narrativeRole`（必填）**：在本书语境下的**叙事位阶**，用于给客户端**区分男一号与男配**（同填 `adult_male` 时也不会抢错音色）：
             - `primary`：**全书视点主角**（如第一男主/第一女主/剧情围绕的核心人物，整章里戏份最多、视角跟随的那位）
             - `secondary`：有台词或反复出场的重要**配角**（家主/师父/反派的得力手下等，但**不是**第一男主/女主时）
             - `tertiary`：只出现少数次的龙套、路人、一次性 NPC
             - 若整章有**一个以上**成年男性，必须至少有一个是 `primary`（能判断出来的情况下），**不要把真正的男主标成 `secondary` 而配角标成 `primary`**

        3. 识别场景变化

        **输出约束**：
        - 必须只输出 JSON，不要输出解释、前后缀、markdown
        - `type` 只能是 `dialogue|narration|description|thought`
        - 只有当说话人能稳定确定时才填写 `speaker`，不确定时必须返回 `null` 或空字符串，不要猜测
        - 不要把“他/她/对方/众人/男人/女人”等无任何修饰的纯泛指代词当成稳定角色名
        - 同一角色请保持命名一致，不要一会儿用全名、一会儿用泛称或临时称呼
        - 当一段对话紧跟另一段同一人说的对话、中间没有场景切换或新的引导语时，`speaker` 必须保持不变，不要漏填或换人
        - 同一角色若出现尊称变体（如“张三/老张/张先生/三哥”），始终使用最完整的本名作为 `speaker`，不要拆成多个角色
        - **`speaker` 字段：优先用本名，没本名时可以用稳定外貌代号**，但禁止包含任何动词、动作、表情、姿态、副词、助词或标点：
          - 合法本名（≤6 字）：`李萍`、`陆鸣`、`李博文`、`上官云霄`
          - 合法外貌代号（≤8 字，仅当角色没有本名但本章会反复说话时使用）：`鸡冠头男`、`光头壮汉`、`独眼老者`、`白衣少女`、`瘸腿大叔`、`黑袍人`
          - **同一无名角色在整段文本中必须使用完全相同的代号**，不要写一次叫"光头壮汉"、下一次又改成"光头大汉"或"那壮汉"
          - 非法：`李萍惨然一笑`、`陆鸣接过酒杯`、`李博文踌躇了一下`、`陈伯笑着说`、`王二点了点头`、`一个声音`、`身影`
          - 遇到非法情况：把动作描写放到上一段 narration 里，把 `speaker` 只填角色名/代号本身；如果连稳定代号都给不出（一闪而过的群众、模糊的"一道声音"），`speaker` 必须填 `null`
        - **重要：`type=dialogue` 段允许 `speaker=null`**——系统会用专门的"未命名对话"音色（不是旁白音色）朗读，所以与其乱猜一个不准的 speaker，不如老实填 `null`
        - **`gender` 字段填写规则（按优先级判断，命中即用）**：
          1. **`elder`**：文本里有**明确的"年长 + 男性"标记**——"老者/老翁/老叟/老头/白发苍苍/须发皆白/年逾花甲/古稀/耄耋/老前辈/老爷子"等措辞，或被其他角色尊称为"X 老 / 老 X / X 公 / X 翁"。仅适用于**男性老者**；老年女性请填 `female`，由系统挑成熟女声兜底。
          2. **`child`**：文本里有**明确的"幼童 / 童年"标记**——"孩童/小孩/稚童/孩子/几岁/十来岁/总角/垂髫/童音"等措辞，或上下文明确说明是未成年的孩子在说话。**少年 / 少女（青春期）不算 child**，应该按性别填 `male` / `female`。
          3. **`male`**：除上述两条之外，文本里有明确男性信号（"他"代词、"少年/汉子/兄长/小哥/书生/将军/男弟子"等显式称呼、外貌描写）。
          4. **`female`**：除上述两条之外，文本里有明确女性信号（"她"代词、"少女/姑娘/小姐/女郎/婢女/女子"等显式称呼、外貌描写）。
          5. **`neutral`**：以上都不满足时**一律填 neutral**，不要根据角色名字猜性别、年龄。
          - 关键约束：`elder` / `child` 是**强标签**，只有文本里出现明确的年龄措辞才能用；不要因为名字带"老"字（"老张"是尊称不一定是老人）或"小"字（"小李"是昵称不一定是小孩）就误判。宁可填 `male` / `neutral`，也不要乱标 `elder` / `child`。
        - `emotion` 只能是 `neutral|happy|sad|angry|excited|fearful|surprised|tender`
        - `sceneType` 只能是 `peaceful|tense|battle|romantic|mysterious|sad|festive`
        - `gender` 只能是 `male|female|neutral|child|elder`
        - `voiceArchetype` 只能是 `elder_male|elder_female|boy_young_male|girl_young_female|adult_male|adult_female|neutral`
        - `narrativeRole` 只能是 `primary|secondary|tertiary`
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
              "gender": "male|female|neutral|child|elder",
              "voiceArchetype": "adult_male",
              "narrativeRole": "primary"
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
        var knownCharacterArchetypes: [String: VoiceArchetypeTag] = [:]
        var knownCharacterNarrativeRoles: [String: NarrativeRole] = [:]

        for charData in aiResult.characters {
            guard let stableName = stableSpeakerName(from: charData.name) else { continue }
            let normalizedGender = normalizeGender(charData.gender)
            let key = canonicalCharacterKey(for: stableName)
            let normalizedArchetype = normalizeVoiceArchetype(charData.voiceArchetype)
            let normalizedNarrative = normalizeNarrativeRole(charData.narrativeRole)
            if !key.isEmpty, knownCharacterGenders[key] == nil {
                knownCharacterGenders[key] = normalizedGender
            }
            if !key.isEmpty, let arch = normalizedArchetype, knownCharacterArchetypes[key] == nil {
                knownCharacterArchetypes[key] = arch
            }
            if !key.isEmpty, let nr = normalizedNarrative, knownCharacterNarrativeRoles[key] == nil {
                knownCharacterNarrativeRoles[key] = nr
            }
            _ = upsertCharacter(
                named: stableName,
                gender: normalizedGender,
                voiceArchetype: normalizedArchetype,
                narrativeRole: normalizedNarrative,
                characters: &characters
            )
        }

        for (index, segmentData) in aiResult.segments.enumerated() {
            var normalizedType = normalizeSegmentType(segmentData.type, text: segmentData.text)
            // Bug C 修复：Kimi 偶尔把"啊！/嗯？/哈哈/咳咳"这种拟声词标成 dialogue + speaker=null。
            // 这些在小说里一般是描述性叹词（壮汉惨叫、吃惊倒抽气），让它们走"未命名对话女声"
            // 听感会非常违和。识别到这种段落后统一改成 narration，让旁白音色朗读。
            // 判定条件三选一全满足：
            //   1. type 已被归一化为 dialogue
            //   2. speaker 字段为空（Kimi 拿不准谁说的）
            //   3. 文本去掉标点空白后**仅由"叹词字"构成**且总长 ≤ 4 字
            if normalizedType == .dialogue,
               (segmentData.speaker?.isEmpty ?? true) || stableSpeakerName(from: segmentData.speaker ?? "") == nil,
               Self.isOnomatopoeicShortUtterance(segmentData.text) {
                normalizedType = .narration
            }
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
                let cKey = canonicalCharacterKey(for: resolvedSpeakerName)
                let gender = knownCharacterGenders[cKey] ?? .neutral
                let arch = knownCharacterArchetypes[cKey]
                let nr = knownCharacterNarrativeRoles[cKey]
                speaker = upsertCharacter(
                    named: resolvedSpeakerName,
                    gender: gender,
                    voiceArchetype: arch,
                    narrativeRole: nr,
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

    /// 单次发给 Kimi 的原文 chunk 上限（字符）。
    ///
    /// `kimi-k2.6` 上下文窗口 256K（262144 token），输出 `max_tokens=32768` 已远超 30000 字符
    /// 原文对应 JSON 的体积（约 ~30K 字符 ≈ 10K token），单次完整产出毫无压力。
    /// 配合 thinking=disabled，单 chunk 端到端时延约 15-30s，并发 10 路足以让一整章一次性返回。
    private var recommendedChunkSize: Int {
        switch Config.aiProvider {
        case .kimi:
            return 30000
        case .qwen:
            return 2600
        }
    }

    private var recommendedAnalysisParallelism: Int {
        switch Config.aiProvider {
        // Kimi 账户：并发 50、RPM 200、TPM 2,000,000、TPD 无限制。
        // 30000 字符 chunk 下单本书通常 ≤ 3 个 chunks，并发 10 路对账户上限完全不构成压力，
        // 多书同时生成时也留足头部余量。
        case .kimi:
            return 10
        case .qwen:
            return 2
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

    /// 用来识别短拟声词类对话（"啊！/嗯？/哈哈/咳咳/哎呀/呃..."）的字集。
    /// 这些字在小说里出现时，绝大多数情况是动作描写或情绪叹词，不是真正的"对话内容"。
    /// 命中条件下我们把段落改成 narration，让旁白音色朗读，避免被未命名对话音色错读。
    /// 用 `Set<String>` 而不是 `Set<Character>`：部分汉字字符在 Swift 字面量场景下会被
    /// 默认当成 `String` 推断，统一用 String 集合避免类型推断踩坑。
    private static let onomatopoeicChars: Set<String> = [
        "啊", "嗯", "哎", "哦", "呃", "咦", "唉", "嘿", "哈", "呀", "哼",
        "呜", "嘻", "哟", "喂", "嗨", "咳", "哧", "噢", "哇", "呕", "呸",
        "呵", "哒", "嗷", "啧", "嘁", "嗤", "嘘", "嘶", "啐", "哽", "咕",
        "呢", "啪", "嗒", "咣", "咚", "嘎"
    ]

    /// 检查给定文本是否是"短拟声词类对话"——纯由叹词字+标点+空白组成且总长 ≤ 4 个汉字。
    /// 命中时调用方应把对应 segment 从 dialogue 改成 narration。
    ///
    /// 例：✅ "啊！" / "嗯？" / "哈哈哈！" / "咳咳。" / "哎呀！"
    /// 例：❌ "快走！"（"快走"非叹词字，不归并）
    /// 例：❌ "啊，你竟然敢..."（汉字数 > 4，不归并）
    private static func isOnomatopoeicShortUtterance(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        var meaningfulCharCount = 0
        for char in cleaned {
            if char.isWhitespace { continue }
            // 跳过中英文标点 / 符号
            if char.isPunctuation || char.isSymbol { continue }
            // 任意"非叹词字"字符直接放行（多半是真对话内容）
            if !onomatopoeicChars.contains(String(char)) { return false }
            meaningfulCharCount += 1
        }

        return meaningfulCharCount > 0 && meaningfulCharCount <= 4
    }

    /// 缓存版本号：每次修改分析 prompt 或客户端清洗规则（cleanedName / canonicalKey）时递增，
    /// 旧版本缓存会被自动跳过，避免历史结果里残留的"李萍惨然一笑"这类脏数据继续生效。
    private static let cacheVersion = "v12-2026-04-27-narrative-lead"

    /// 生成缓存键
    private func generateCacheKey(for text: String) -> String {
        let canonical = Self.canonicalTextForPlayback(text)
        let versioned = "\(Self.cacheVersion)|\(canonical)"
        guard let data = versioned.data(using: .utf8) else {
            return String(versioned.hashValue)
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

    /// Kimi `voiceArchetype` 归一化；无法识别时返回 `nil`，客户端音色分配退回 `gender` 推断。
    private func normalizeVoiceArchetype(_ raw: String?) -> VoiceArchetypeTag? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let normalized = raw.lowercased()
        if let tag = VoiceArchetypeTag(rawValue: normalized) {
            return tag
        }
        switch normalized {
        case "old_male", "old_man", "male_elder":
            return .elderMale
        case "old_female", "old_woman", "female_elder":
            return .elderFemale
        case "young_male", "boy", "child_male", "male_child":
            return .boyOrYoungMale
        case "young_female", "girl", "child_female", "female_child":
            return .girlOrYoungFemale
        case "mature_male":
            return .adultMale
        case "mature_female":
            return .adultFemale
        default:
            return nil
        }
    }

    /// Kimi `narrativeRole` 归一化；无法识别时返回 `nil`。
    private func normalizeNarrativeRole(_ raw: String?) -> NarrativeRole? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let s = raw.lowercased()
        if let r = NarrativeRole(rawValue: s) { return r }
        switch s {
        case "lead", "main", "protagonist", "hero", "heroine", "viewpoint", "pov", "第一主角", "主角":
            return .primary
        case "supporting", "side", "major", "deuteragonist", "配角", "男二", "女二":
            return .secondary
        case "minor", "extra", "cameo", "walk_on", "npc", "龙套", "路人":
            return .tertiary
        default:
            return nil
        }
    }

    private func cleanSpeakerName(_ raw: String) -> String {
        RoleIdentity.cleanedName(raw)
    }

    private func stableSpeakerName(from raw: String) -> String? {
        let cleaned = cleanSpeakerName(raw)
        guard !cleaned.isEmpty, !isUncertainSpeakerName(cleaned) else {
            return nil
        }
        return cleaned
    }

    private func canonicalCharacterKey(for name: String) -> String {
        RoleIdentity.canonicalKey(forRawName: name)
    }

    /// 跨 chunk 合并使用的主键。canonicalKey 为空（罕见，名字仅含标点）时退化到清洗后小写名，
    /// 再退化到原始名，避免多个无名角色被错误并到同一桶。
    private func mergeKey(forCharacterName name: String) -> String {
        let canonical = RoleIdentity.canonicalKey(forRawName: name)
        if !canonical.isEmpty { return canonical }
        let cleaned = RoleIdentity.cleanedName(name)
        if !cleaned.isEmpty { return cleaned.lowercased() }
        return name
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
        voiceArchetype: VoiceArchetypeTag? = nil,
        narrativeRole: NarrativeRole? = nil,
        characters: inout Set<Character>
    ) -> Character {
        let cleanedName = cleanSpeakerName(name)
        let canonical = canonicalCharacterKey(for: cleanedName)
        if let existing = characters.first(where: {
            cleanSpeakerName($0.name) == cleanedName
                || (!canonical.isEmpty && canonicalCharacterKey(for: $0.name) == canonical)
        }) {
            var merged = existing
            if let tag = voiceArchetype, merged.voiceArchetype == nil { merged.voiceArchetype = tag }
            if let role = narrativeRole, merged.narrativeRole == nil { merged.narrativeRole = role }
            if merged.voiceArchetype != existing.voiceArchetype || merged.narrativeRole != existing.narrativeRole {
                characters.remove(existing)
                characters.insert(merged)
                return merged
            }
            return existing
        }
        let character = Character(
            name: cleanedName,
            gender: gender,
            voiceArchetype: voiceArchetype,
            narrativeRole: narrativeRole
        )
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
        /// Kimi 音色人设标签；旧模型或省略时解码为 `nil`。
        let voiceArchetype: String?
        /// 叙事位阶；旧模型或省略时解码为 `nil`。
        let narrativeRole: String?
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
}
