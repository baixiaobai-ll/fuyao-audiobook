//
//  AIAnalysisService.swift
//  AI有声书
//
//  AI 分析服务 - 支持多种 AI API
//

import Foundation

/// AI 分析服务协议
protocol AIAnalysisService {
    func analyze(prompt: String) async throws -> String
}

/// 通义千问分析服务
class QwenAnalysisService: AIAnalysisService {

    private let apiKey: String
    private let model: String
    private let baseURL: String

    init(apiKey: String, model: String = "qwen-plus", baseURL: String = "https://dashscope.aliyuncs.com/compatible-mode/v1") {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    func analyze(prompt: String) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是一个专业的小说文本分析助手，擅长识别对话、角色、情感和场景。请严格按照 JSON 格式返回结果。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3,
            "result_format": "message"
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var lastError: Error = AnalysisError.networkError
        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            var request = URLRequest(url: url, timeoutInterval: 120)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch let urlError as URLError {
                if urlError.code == .timedOut {
                    throw AnalysisError.apiError("通义千问分析超时，请检查网络后重试")
                }
                throw AnalysisError.apiError("通义千问网络请求失败：\(urlError.localizedDescription)")
            } catch {
                throw AnalysisError.apiError("通义千问请求失败：\(error.localizedDescription)")
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AnalysisError.networkError
            }
            if httpResponse.statusCode == 200 {
                let result = try JSONDecoder().decode(QwenResponse.self, from: data)
                guard let content = result.choices.first?.message.content else {
                    throw AnalysisError.invalidResponse
                }
                return content
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw AnalysisError.apiError("通义千问鉴权失败，请检查 AI_API_KEY 是否正确，并确认 AI_PROVIDER=qwen")
            }
            if httpResponse.statusCode == 429 {
                throw AnalysisError.apiError("通义千问请求过于频繁，请稍后重试")
            }

            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            lastError = AnalysisError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
            let retryable = [502, 503, 504].contains(httpResponse.statusCode)
            if !retryable { throw lastError }
            print("⚠️ 通义千问 \(httpResponse.statusCode)，第 \(attempt + 1) 次重试...")
        }
        throw lastError
    }

    private struct QwenResponse: Codable {
        let choices: [Choice]

        struct Choice: Codable {
            let message: Message
        }

        struct Message: Codable {
            let content: String
        }
    }
}

/// 本地规则分析服务（降级方案）
class LocalRuleAnalysisService: AIAnalysisService {

    func analyze(prompt: String) async throws -> String {
        // 从 prompt 中提取文本内容
        guard let textRange = prompt.range(of: "文本内容：\n") else {
            throw AnalysisError.invalidResponse
        }

        let text = String(prompt[textRange.upperBound...])

        // 简单的规则分析
        let segments = analyzeWithRules(text)
        let characters = extractCharacters(from: segments)

        let response: [String: Any] = [
            "segments": segments.map { segment in
                [
                    "text": segment.text,
                    "type": segment.type,
                    "speaker": segment.speaker ?? "",
                    "emotion": segment.emotion,
                    "sceneType": segment.sceneType,
                    "sceneIntensity": segment.sceneIntensity
                ]
            },
            "characters": characters.map { char in
                [
                    "name": char.name,
                    "gender": char.gender
                ]
            }
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: response, options: .prettyPrinted)
        return String(data: jsonData, encoding: .utf8) ?? "{}"
    }

    private func analyzeWithRules(_ text: String) -> [SimpleSegment] {
        var segments: [SimpleSegment] = []
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 检测对话（引号包裹）
            let leftQuote = "\u{201C}"  // "
            let rightQuote = "\u{201D}" // "
            if trimmed.contains("\"") || trimmed.contains("'") || trimmed.contains(leftQuote) || trimmed.contains(rightQuote) {
                // 提取说话人
                let speaker = extractSpeaker(from: trimmed)
                let dialogueText = extractDialogue(from: trimmed)

                segments.append(SimpleSegment(
                    text: dialogueText,
                    type: "dialogue",
                    speaker: speaker,
                    emotion: detectEmotion(from: dialogueText),
                    sceneType: "peaceful",
                    sceneIntensity: 0.5
                ))
            } else {
                // 旁白
                segments.append(SimpleSegment(
                    text: trimmed,
                    type: "narration",
                    speaker: nil,
                    emotion: "neutral",
                    sceneType: detectScene(from: trimmed),
                    sceneIntensity: 0.5
                ))
            }
        }

        return segments
    }

    private func extractSpeaker(from text: String) -> String? {
        // 匹配 "XXX说：" 或 "XXX道：" 等模式
        let patterns = [
            "([^：:]+)[说道喊叫问答][:：]",
            "([^：:]+)[:：]"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range]).trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }

    private func extractDialogue(from text: String) -> String {
        // 提取引号内的内容
        let patterns = ["[\"\\u201C\\u201D]([^\"\\u201C\\u201D]+)[\"\\u201C\\u201D]", "\"([^\"]+)\"", "'([^']+)'"]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                return String(text[range])
            }
        }

        return text
    }

    private func detectEmotion(from text: String) -> String {
        let emotionKeywords: [String: [String]] = [
            "happy": ["哈哈", "开心", "高兴", "笑", "喜悦"],
            "sad": ["哭", "悲伤", "难过", "伤心", "流泪"],
            "angry": ["愤怒", "生气", "怒", "吼", "骂"],
            "excited": ["激动", "兴奋", "太好了", "棒"],
            "fearful": ["害怕", "恐惧", "可怕", "吓"],
            "surprised": ["惊讶", "震惊", "天啊", "什么"]
        ]

        for (emotion, keywords) in emotionKeywords {
            if keywords.contains(where: { text.contains($0) }) {
                return emotion
            }
        }

        return "neutral"
    }

    private func detectScene(from text: String) -> String {
        let sceneKeywords: [String: [String]] = [
            "battle": ["战斗", "打斗", "厮杀", "攻击", "剑"],
            "tense": ["紧张", "危险", "小心", "警惕"],
            "romantic": ["爱", "温柔", "亲吻", "拥抱"],
            "mysterious": ["神秘", "奇怪", "诡异", "阴森"],
            "sad": ["悲伤", "哀伤", "凄凉"]
        ]

        for (scene, keywords) in sceneKeywords {
            if keywords.contains(where: { text.contains($0) }) {
                return scene
            }
        }

        return "peaceful"
    }

    private func extractCharacters(from segments: [SimpleSegment]) -> [SimpleCharacter] {
        var characters: [String: SimpleCharacter] = [:]

        for segment in segments {
            if let speaker = segment.speaker, !speaker.isEmpty {
                if characters[speaker] == nil {
                    // 简单的性别判断
                    let gender = detectGender(from: speaker)
                    characters[speaker] = SimpleCharacter(name: speaker, gender: gender)
                }
            }
        }

        return Array(characters.values)
    }

    private func detectGender(from name: String) -> String {
        let maleKeywords = ["先生", "公子", "少爷", "大哥", "兄"]
        let femaleKeywords = ["小姐", "姑娘", "夫人", "妹", "姐"]

        if maleKeywords.contains(where: { name.contains($0) }) {
            return "male"
        }
        if femaleKeywords.contains(where: { name.contains($0) }) {
            return "female"
        }

        return "neutral"
    }

    private struct SimpleSegment {
        let text: String
        let type: String
        let speaker: String?
        let emotion: String
        let sceneType: String
        let sceneIntensity: Double
    }

    private struct SimpleCharacter {
        let name: String
        let gender: String
    }
}
