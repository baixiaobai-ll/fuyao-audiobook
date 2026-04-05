//
//  AIAnalysisService.swift
//  AI有声书
//
//  AI 分析服务 - 支持 Kimi / Qwen / 本地降级
//

import Foundation

/// AI 分析服务协议
protocol AIAnalysisService {
    func analyze(prompt: String) async throws -> String
}

private struct AIChatServiceConfig {
    let providerName: String
    let apiKey: String
    let model: String
    let baseURL: String
    let requestTimeout: TimeInterval
    let maxRetryAttempts: Int
    let temperature: Double
}

/// OpenAI 兼容的聊天补全分析服务。
private final class OpenAICompatibleAnalysisService: AIAnalysisService {
    private let config: AIChatServiceConfig

    init(config: AIChatServiceConfig) {
        self.config = config
    }

    func analyze(prompt: String) async throws -> String {
        let url = URL(string: "\(config.baseURL)/chat/completions")!
        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                [
                    "role": "system",
                    "content": "你是一个专业的小说文本分析助手，擅长识别对话、角色、情感和场景。请只返回合法 JSON，不要附加解释。"
                ],
                ["role": "user", "content": prompt]
            ],
            "temperature": config.temperature,
            "stream": false
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var lastError: Error = AnalysisError.networkError
        for attempt in 1...config.maxRetryAttempts {
            if attempt > 1 {
                let delaySeconds = Double(attempt - 1) * 0.8
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }

            var request = URLRequest(url: url, timeoutInterval: config.requestTimeout)
            request.httpMethod = "POST"
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AnalysisError.networkError
                }

                if httpResponse.statusCode == 200 {
                    let result = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                    guard let content = result.choices.first?.message.contentText,
                          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw AnalysisError.invalidResponse
                    }
                    return content
                }

                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw AnalysisError.apiError("\(config.providerName) 鉴权失败，请检查 AI key 与 provider 配置")
                }
                if httpResponse.statusCode == 429 {
                    lastError = AnalysisError.apiError("\(config.providerName) 请求过于频繁，请稍后重试")
                } else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                    lastError = AnalysisError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
                }

                if !Self.isRetryableStatusCode(httpResponse.statusCode) || attempt == config.maxRetryAttempts {
                    throw lastError
                }
                print("⚠️ \(config.providerName) HTTP \(httpResponse.statusCode)，第 \(attempt) 次重试后继续...")
            } catch let error as AnalysisError {
                lastError = error
                if !error.isRetryable || attempt == config.maxRetryAttempts {
                    throw error
                }
                print("⚠️ \(config.providerName) 分析失败，准备重试：\(error.localizedDescription)")
            } catch let urlError as URLError {
                let wrapped = Self.wrap(urlError, providerName: config.providerName, timeout: config.requestTimeout)
                lastError = wrapped
                if !wrapped.isRetryable || attempt == config.maxRetryAttempts {
                    throw wrapped
                }
                print("⚠️ \(config.providerName) 网络异常，准备重试：\(wrapped.localizedDescription)")
            } catch {
                let wrapped = AnalysisError.apiError("\(config.providerName) 请求失败：\(error.localizedDescription)")
                lastError = wrapped
                throw wrapped
            }
        }

        throw lastError
    }

    private static func wrap(_ error: URLError, providerName: String, timeout: TimeInterval) -> AnalysisError {
        switch error.code {
        case .timedOut:
            return .requestTimedOut(providerName: providerName, seconds: timeout)
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                .cannotConnectToHost, .dnsLookupFailed, .resourceUnavailable:
            return .networkError
        default:
            return .apiError("\(providerName) 网络请求失败：\(error.localizedDescription)")
        }
    }

    private static func isRetryableStatusCode(_ statusCode: Int) -> Bool {
        [408, 409, 425, 429, 500, 502, 503, 504].contains(statusCode)
    }
}

/// Kimi 分析服务。
final class KimiAnalysisService: AIAnalysisService {
    private let service: OpenAICompatibleAnalysisService

    init(
        apiKey: String,
        model: String = "kimi-k2-0905-preview",
        baseURL: String = "https://api.moonshot.cn/v1"
    ) {
        service = OpenAICompatibleAnalysisService(config: AIChatServiceConfig(
            providerName: "Kimi",
            apiKey: apiKey,
            model: model,
            baseURL: baseURL,
            requestTimeout: 60,
            maxRetryAttempts: 3,
            temperature: 0.2
        ))
    }

    func analyze(prompt: String) async throws -> String {
        try await service.analyze(prompt: prompt)
    }
}

/// 通义千问分析服务。
final class QwenAnalysisService: AIAnalysisService {
    private let service: OpenAICompatibleAnalysisService

    init(
        apiKey: String,
        model: String = "qwen-plus",
        baseURL: String = "https://dashscope.aliyuncs.com/compatible-mode/v1"
    ) {
        service = OpenAICompatibleAnalysisService(config: AIChatServiceConfig(
            providerName: "通义千问",
            apiKey: apiKey,
            model: model,
            baseURL: baseURL,
            requestTimeout: 90,
            maxRetryAttempts: 3,
            temperature: 0.3
        ))
    }

    func analyze(prompt: String) async throws -> String {
        try await service.analyze(prompt: prompt)
    }
}

/// 远端分析失败时的本地降级，避免整条播放链路被分析阶段完全阻塞。
final class ResilientAnalysisService: AIAnalysisService {
    private let primary: AIAnalysisService
    private let fallback: AIAnalysisService

    init(primary: AIAnalysisService, fallback: AIAnalysisService = LocalRuleAnalysisService()) {
        self.primary = primary
        self.fallback = fallback
    }

    func analyze(prompt: String) async throws -> String {
        do {
            return try await primary.analyze(prompt: prompt)
        } catch let error as AnalysisError {
            guard error.allowsLocalFallback else { throw error }
            print("⚠️ 远端文本分析失败，回退到本地规则分析：\(error.localizedDescription)")
            return try await fallback.analyze(prompt: prompt)
        }
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: ContentValue

        var contentText: String? {
            content.textValue
        }
    }

    enum ContentValue: Decodable {
        case text(String)
        case parts([ContentPart])

        var textValue: String? {
            switch self {
            case .text(let value):
                return value
            case .parts(let parts):
                let text = parts.compactMap(\.text).joined()
                return text.isEmpty ? nil : text
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }
            if let parts = try? container.decode([ContentPart].self) {
                self = .parts(parts)
                return
            }
            throw DecodingError.typeMismatch(
                ContentValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported content payload")
            )
        }
    }

    struct ContentPart: Decodable {
        let type: String?
        let text: String?
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
            let leftQuote = "\u{201C}"
            let rightQuote = "\u{201D}"
            if trimmed.contains("\"") || trimmed.contains("'") || trimmed.contains(leftQuote) || trimmed.contains(rightQuote) {
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
            if let speaker = segment.speaker, !speaker.isEmpty, characters[speaker] == nil {
                let gender = detectGender(from: speaker)
                characters[speaker] = SimpleCharacter(name: speaker, gender: gender)
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
