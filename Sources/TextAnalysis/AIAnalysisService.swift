//
//  AIAnalysisService.swift
//  AI有声书
//
//  AI 分析服务 - 支持 Kimi / Qwen / 本地降级
//

import Foundation

/// AI 分析服务协议
protocol AIAnalysisService {
    /// 当前 provider，用于日志 / dump 文件名等场景。
    var provider: AIProvider { get }
    func analyze(prompt: String) async throws -> String
}

/// 输出 token 上限字段名。
///
/// - `maxTokens`：OpenAI 老规范，阿里 dashscope（Qwen 兼容模式）也只认这个名字。
/// - `maxCompletionTokens`：OpenAI 新规范（o1/o3 reasoning 模型）+ Moonshot Kimi K2.6 起的强制约定。
///   Moonshot 已把 `max_tokens` 标 deprecated，**服务端会静默丢弃**该字段并 fallback 到默认 1024 token，
///   表现就是输出无论怎么发都被切到 ~4400 字符（≈1024 token 中文）。必须发 `max_completion_tokens` 才生效。
private enum MaxTokensFieldName {
    case maxTokens
    case maxCompletionTokens
}

private struct AIChatServiceConfig {
    let providerName: String
    let apiKey: String
    let model: String
    let baseURL: String
    let requestTimeout: TimeInterval
    let maxRetryAttempts: Int
    /// `nil` 表示不传该字段（K2.6 等模型对 temperature 有"固定值校验"，传任意值会报错或被静默忽略）。
    let temperature: Double?
    let maxOutputTokens: Int
    let maxTokensFieldName: MaxTokensFieldName
    /// 额外注入到请求 body 的字段。Kimi K2.6 默认走 thinking 模式，这里用来注入
    /// `thinking: { type: "disabled" }` 关掉推理过程，结构化 JSON 输出无需 reasoning。
    let extraBody: [String: Any]
}

/// OpenAI 兼容的聊天补全分析服务。
///
/// 是 KimiAnalysisService / QwenAnalysisService 的内部实现细节，仅暴露 `analyze` 方法供包装类透传。
/// 不需要 conform 外部协议 `AIAnalysisService`：provider 标识由各个具体的包装类自己声明，
/// 避免在通用 HTTP 客户端里硬编码具体厂商。
private final class OpenAICompatibleAnalysisService {
    private let config: AIChatServiceConfig

    init(config: AIChatServiceConfig) {
        self.config = config
    }

    func analyze(prompt: String) async throws -> String {
        let url = URL(string: "\(config.baseURL)/chat/completions")!
        var body: [String: Any] = [
            "model": config.model,
            "messages": [
                [
                    "role": "system",
                    // 须含不区分大小写的 `json` 字样，通义在 `response_format: json_object` 时否则会报错；见百炼《错误信息》相关条目。
                    "content": "你是一个专业的小说文本分析助手，擅长识别对话、角色、情感和场景。请只返回 **合法 json 对象**（一个 JSON 对象即可），不要附加解释或 Markdown 代码围栏。"
                ],
                ["role": "user", "content": prompt]
            ],
            "response_format": [
                "type": "json_object"
            ],
            "stream": false
        ]
        if let temperature = config.temperature {
            body["temperature"] = temperature
        }
        switch config.maxTokensFieldName {
        case .maxTokens:
            body["max_tokens"] = config.maxOutputTokens
        case .maxCompletionTokens:
            body["max_completion_tokens"] = config.maxOutputTokens
        }
        for (k, v) in config.extraBody {
            body[k] = v
        }
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
                    guard let firstChoice = result.choices.first,
                          let content = firstChoice.message.contentText,
                          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw AnalysisError.invalidResponse
                    }
                    let finishReason = firstChoice.finish_reason ?? "unknown"
                    if finishReason != "stop" {
                        let prompt = result.usage?.prompt_tokens.map(String.init) ?? "?"
                        let completion = result.usage?.completion_tokens.map(String.init) ?? "?"
                        let total = result.usage?.total_tokens.map(String.init) ?? "?"
                        print("⚠️ \(config.providerName) finish_reason=\(finishReason) （非 stop，输出可能被截断），usage prompt=\(prompt) completion=\(completion) total=\(total)")
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
                    let head = String(errorMessage.prefix(800))
                    print("⚠️ \(config.providerName) HTTP \(httpResponse.statusCode) 响应: \(head)")
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
///
/// 默认使用 `kimi-k2.6`（K2 系列原 `kimi-k2-turbo-preview` 等将于 2026-05-25 下线，
/// K2.6 是官方指定继任，国内端点 `api.moonshot.cn` 已于 2026-04-21 上线）。
///
/// 三个关键字段必须按 K2.6 规范来，否则服务端会**静默降级**而不是报错：
/// 1. `max_completion_tokens`（不是已废弃的 `max_tokens`）：服务端丢弃 `max_tokens` 后会回退到默认
///    1024 token，输出会稳定截断在 ~4400 字符。这里给 32768 已远超 30000 字符 chunk 对应 JSON 体积。
/// 2. 不传 `temperature`：K2.6 强制 thinking 模式 temperature=1.0、non-thinking 模式 temperature=0.6，
///    传任何值都会"非默认值即报错"，让服务端按模式自选默认即可。
/// 3. `thinking: { type: "disabled" }`：关掉推理过程，结构化 JSON 输出不需要 reasoning，
///    省时延、省钱（reasoning token 计费同 output token），还避免 reasoning 挤占 max_completion_tokens。
final class KimiAnalysisService: AIAnalysisService {
    private let service: OpenAICompatibleAnalysisService
    let provider: AIProvider = .kimi

    /// - Parameter maxHTTPAttempts: 同一请求在**连接/读超时**等可重试错误下的最大尝试次数；用于与「超时后改走通义」组合时设为 `1`，避免再白等两轮 Kimi。
    init(
        apiKey: String,
        model: String = "kimi-k2.6",
        baseURL: String = "https://api.moonshot.cn/v1",
        maxHTTPAttempts: Int = 3
    ) {
        service = OpenAICompatibleAnalysisService(config: AIChatServiceConfig(
            providerName: "Kimi",
            apiKey: apiKey,
            model: model,
            baseURL: baseURL,
            requestTimeout: 120,
            maxRetryAttempts: max(1, maxHTTPAttempts),
            temperature: nil,
            maxOutputTokens: 32768,
            maxTokensFieldName: .maxCompletionTokens,
            extraBody: [
                "thinking": ["type": "disabled"]
            ]
        ))
    }

    func analyze(prompt: String) async throws -> String {
        try await service.analyze(prompt: prompt)
    }
}

/// Kimi 优先；Kimi 任意分析失败时立即改调通义 `qwen3.6-plus`，不再对 Kimi 做第 2、3 次重试。
final class KimiThenQwenFallbackAnalysisService: AIAnalysisService {
    let provider: AIProvider = .kimi
    private let kimi: KimiAnalysisService
    private let qwen: QwenAnalysisService?

    init(
        kimiApiKey: String,
        kimiModel: String,
        kimiBaseURL: String,
        qwenApiKey: String?
    ) {
        self.kimi = KimiAnalysisService(
            apiKey: kimiApiKey,
            model: kimiModel,
            baseURL: kimiBaseURL,
            maxHTTPAttempts: 1
        )
        if let key = qwenApiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
            self.qwen = QwenAnalysisService(
                apiKey: key,
                model: "qwen3.6-plus",
                baseURL: Config.qwenDashScopeCompatibleBaseURL,
                requestTimeout: 120,
                maxHTTPAttempts: 2,
                maxOutputTokens: 16_384
            )
        } else {
            self.qwen = nil
        }
    }

    func analyze(prompt: String) async throws -> String {
        do {
            return try await kimi.analyze(prompt: prompt)
        } catch let error as AnalysisError {
            let reason: String
            if case .requestTimedOut = error {
                reason = "120s 超时"
                print("⏱️ Kimi 分析 120s 超时，已跳过剩余 Kimi 重试，改调通义千问 qwen3.6-plus …")
            } else {
                reason = "失败"
                print("⚠️ Kimi 分析失败，已跳过 Kimi 重试，改调通义千问 qwen3.6-plus：\(error.localizedDescription)")
            }
            return try await analyzeWithQwen(prompt: prompt, kimiFailureReason: reason)
        } catch {
            print("⚠️ Kimi 分析请求异常，已跳过 Kimi 重试，改调通义千问 qwen3.6-plus：\(error.localizedDescription)")
            return try await analyzeWithQwen(prompt: prompt, kimiFailureReason: "请求异常")
        }
    }

    private func analyzeWithQwen(prompt: String, kimiFailureReason: String) async throws -> String {
        guard let qwen else {
            print("⚠️ 未配置通义千问 Qwen API Key，本段将交由旁白兜底。")
            throw AnalysisError.apiError(
                "Kimi 分析\(kimiFailureReason)，且未配置通义千问 API Key。将自动降级为旁白播放。"
            )
        }

        do {
            let out = try await qwen.analyze(prompt: prompt)
            print("✅ 通义千问 qwen3.6-plus 已接替完成本段分析（Kimi \(kimiFailureReason)后降级）")
            return out
        } catch {
            print("⚠️ 通义千问 qwen3.6-plus 分析失败，本段将交由旁白兜底：\(error.localizedDescription)")
            throw error
        }
    }
}

/// 通义千问分析服务。
///
/// 阿里 dashscope 兼容模式严格按 OpenAI 老规范，**只认 `max_tokens`，不识别 `max_completion_tokens`**，
/// 字段名不能跟 Kimi 共用。默认模型 `qwen3.6-plus`（与百炼开放模型名一致）；小说结构化 JSON 需足够 `max_tokens` 以免截断。
final class QwenAnalysisService: AIAnalysisService {
    private let service: OpenAICompatibleAnalysisService
    let provider: AIProvider = .qwen

    init(
        apiKey: String,
        model: String = "qwen3.6-plus",
        baseURL: String = Config.qwenDashScopeCompatibleBaseURL,
        requestTimeout: TimeInterval = 120,
        maxHTTPAttempts: Int = 3,
        maxOutputTokens: Int = 16_384,
        temperature: Double = 0.3
    ) {
        service = OpenAICompatibleAnalysisService(config: AIChatServiceConfig(
            providerName: "通义千问",
            apiKey: apiKey,
            model: model,
            baseURL: baseURL,
            requestTimeout: requestTimeout,
            maxRetryAttempts: max(1, maxHTTPAttempts),
            temperature: temperature,
            maxOutputTokens: maxOutputTokens,
            maxTokensFieldName: .maxTokens,
            // 百炼：Qwen3.6 等默认开启「思考模式」时，与 `response_format: json_object` 不兼容，会报 Json mode 相关错误，须显式关闭。
            extraBody: [
                "enable_thinking": false
            ]
        ))
    }

    func analyze(prompt: String) async throws -> String {
        try await service.analyze(prompt: prompt)
    }
}

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message
        /// `stop`：自然结束；`length`：达到 max_tokens / max_completion_tokens 被截断；
        /// 其他可能值如 `content_filter` 等。Moonshot 文档：`length` 时多余 token 会被丢弃。
        let finish_reason: String?
    }

    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
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
