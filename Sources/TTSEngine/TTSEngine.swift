//
//  TTSEngine.swift
//  AI有声书
//
//  TTS 引擎 - 语音合成核心
//

import Foundation
import CommonCrypto

/// TTS 引擎协议
protocol TTSEngineProtocol {
    func synthesize(segment: TextSegment, voice: Voice) async throws -> AudioData
    func synthesize(text: String, voice: Voice) async throws -> AudioData
}

/// TTS 引擎
final class TTSEngine: TTSEngineProtocol, @unchecked Sendable {

    private let config: TTSConfig
    private let ssmlGenerator: SSMLGenerator
    private let voiceManager: VoiceManager
    private let cache: TTSCache
    private let semaphore: AsyncSemaphore

    init(
        config: TTSConfig,
        ssmlGenerator: SSMLGenerator = SSMLGenerator(),
        voiceManager: VoiceManager = VoiceManager(),
        cache: TTSCache = TTSCache()
    ) {
        self.config = config
        self.ssmlGenerator = ssmlGenerator
        self.voiceManager = voiceManager
        self.cache = cache
        self.semaphore = AsyncSemaphore(value: config.maxConcurrentRequests)
    }

    /// 合成文本片段
    func synthesize(segment: TextSegment, voice: Voice) async throws -> AudioData {
        // 检查缓存
        let cacheKey = generateCacheKey(segment: segment, voice: voice)
        if config.enableCache, let cachedAudio = cache.retrieve(key: cacheKey) {
            print("🎵 使用缓存的音频: \(segment.text.prefix(20))...")
            return cachedAudio
        }

        // 限制并发请求数
        await semaphore.wait()
        defer { Task { await semaphore.signal() } }

        print("🎤 合成音频: \(segment.text.prefix(20))...")

        // 生成 SSML
        let ssml = ssmlGenerator.generate(segment: segment, voice: voice)

        // 调用 TTS 服务
        let audioData: AudioData
        switch config.provider {
        case .openai:
            audioData = try await synthesizeWithOpenAI(text: segment.text, voice: voice)
        case .azure:
            audioData = try await synthesizeWithAzure(ssml: ssml, voice: voice)
        case .aliyun:
            audioData = try await synthesizeWithAliyun(ssml: ssml, voice: voice)
        case .xfyun:
            audioData = try await synthesizeWithXfyunSuper(text: segment.text, voice: voice)
        case .local:
            throw TTSError.unsupportedProvider
        }

        // 缓存结果
        if config.enableCache {
            cache.store(audioData, key: cacheKey)
        }

        return audioData
    }

    /// 合成纯文本
    func synthesize(text: String, voice: Voice) async throws -> AudioData {
        let cacheKey = "\(text.hashValue)_\(voice.id)"
        if config.enableCache, let cachedAudio = cache.retrieve(key: cacheKey) {
            return cachedAudio
        }

        await semaphore.wait()
        defer { Task { await semaphore.signal() } }

        let audioData: AudioData
        switch config.provider {
        case .openai:
            audioData = try await synthesizeWithOpenAI(text: text, voice: voice)
        case .azure:
            let ssml = ssmlGenerator.generateSimple(text: text, voice: voice)
            audioData = try await synthesizeWithAzure(ssml: ssml, voice: voice)
        case .aliyun:
            let ssml = ssmlGenerator.generateSimple(text: text, voice: voice)
            audioData = try await synthesizeWithAliyun(ssml: ssml, voice: voice)
        case .xfyun:
            audioData = try await synthesizeWithXfyunSuper(text: text, voice: voice)
        case .local:
            throw TTSError.unsupportedProvider
        }

        if config.enableCache {
            cache.store(audioData, key: cacheKey)
        }

        return audioData
    }

    // MARK: - TTS 服务实现

    /// OpenAI TTS
    private func synthesizeWithOpenAI(text: String, voice: Voice) async throws -> AudioData {
        let url = URL(string: "\(config.baseURL ?? "https://api.openai.com/v1")/audio/speech")!
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "tts-1-hd",
            "input": text,
            "voice": voice.id,
            "response_format": "mp3",
            "speed": 1.0
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TTSError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        let estimatedDuration = estimateDuration(text: text)

        return AudioData(
            data: data,
            format: .mp3,
            duration: estimatedDuration,
            sampleRate: voice.sampleRate
        )
    }

    /// Azure TTS
    private func synthesizeWithAzure(ssml: String, voice: Voice) async throws -> AudioData {
        let region = extractRegion(from: config.baseURL) ?? "eastasia"
        let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")!

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("AI-AudioBook-iOS", forHTTPHeaderField: "User-Agent")

        request.httpBody = ssml.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TTSError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
        }

        let text = ssmlGenerator.extractText(from: ssml)
        let estimatedDuration = estimateDuration(text: text)

        return AudioData(
            data: data,
            format: .mp3,
            duration: estimatedDuration,
            sampleRate: 24000
        )
    }

    /// 阿里云 TTS（占位实现）
    private func synthesizeWithAliyun(ssml: String, voice: Voice) async throws -> AudioData {
        // TODO: 实现阿里云 TTS API 调用
        throw TTSError.unsupportedProvider
    }

    /// 科大讯飞 TTS (WebSocket)
    private func synthesizeWithXfyun(text: String, voice: Voice) async throws -> AudioData {
        let components = config.apiKey.components(separatedBy: ":")
        guard components.count == 3 else { throw TTSError.invalidConfiguration }
        let appId = components[0]
        let apiSecret = components[1]
        let apiKey = components[2]

        let host = "tts-api.xfyun.cn"
        let path = "/v2/tts"
        let date = makeRFC1123Date()
        let signOrigin = "host: \(host)\ndate: \(date)\nGET \(path) HTTP/1.1"
        guard let signData = signOrigin.data(using: .utf8),
              let secretData = apiSecret.data(using: .utf8) else {
            throw TTSError.invalidConfiguration
        }
        let signature = hmacSHA256Base64(data: signData, key: secretData)
        let authOrigin = "api_key=\"\(apiKey)\", algorithm=\"hmac-sha256\", headers=\"host date request-line\", signature=\"\(signature)\""
        let authorization = authOrigin.data(using: .utf8)!.base64EncodedString()
        let dateEncoded = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? date
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+=/")
        let authEncoded = authorization.addingPercentEncoding(withAllowedCharacters: allowed) ?? authorization
        let urlString = "wss://\(host)\(path)?authorization=\(authEncoded)&date=\(dateEncoded)&host=\(host)"
        print("🔗 讯飞 WebSocket URL: \(urlString)")
        guard let url = URL(string: urlString) else { throw TTSError.invalidConfiguration }

        return try await withCheckedThrowingContinuation { continuation in
            var accumulated = Data()
            var resumed = false

            func resumeOnce(with result: Result<AudioData, Error>) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }

            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()

            let voiceId = voice.id.isEmpty ? "x4_lingfei" : voice.id
            let body: [String: Any] = [
                "common": ["app_id": appId],
                "business": [
                    "aue": "lame",
                    "auf": "audio/L16;rate=16000",
                    "vcn": voiceId,
                    "tte": "utf8",
                    "speed": 47,
                    "volume": 55,
                    "pitch": 50,
                    "rdn": "0"
                ],
                "data": [
                    "status": 2,
                    "text": text.data(using: .utf8)!.base64EncodedString()
                ]
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else {
                resumeOnce(with: .failure(TTSError.invalidConfiguration))
                return
            }

            task.send(.string(jsonStr)) { err in
                if let err = err {
                    task.cancel()
                    resumeOnce(with: .failure(TTSError.apiError(err.localizedDescription)))
                }
            }

            func receive() {
                task.receive { result in
                    switch result {
                    case .failure(let err):
                        print("❌ 讯飞 WebSocket 错误: \(err)")
                        resumeOnce(with: .failure(TTSError.apiError(err.localizedDescription)))
                    case .success(let msg):
                        var data: Data?
                        switch msg {
                        case .string(let s): data = s.data(using: .utf8)
                        case .data(let d): data = d
                        @unknown default: break
                        }
                        guard let d = data,
                              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                            resumeOnce(with: .failure(TTSError.audioProcessingError))
                            return
                        }
                        let code = json["code"] as? Int ?? 0
                        if code != 0 {
                            let errMsg = json["message"] as? String ?? "Unknown"
                            task.cancel()
                            resumeOnce(with: .failure(TTSError.apiError("讯飞错误 \(code): \(errMsg)")))
                            return
                        }
                        if let data = json["data"] as? [String: Any],
                           let b64 = data["audio"] as? String,
                           let chunk = Data(base64Encoded: b64) {
                            accumulated.append(chunk)
                        }
                        let status = (json["data"] as? [String: Any])?["status"] as? Int ?? 0
                        if status == 2 {
                            task.cancel()
                            let result = AudioData(data: accumulated, format: .mp3,
                                duration: self.estimateDuration(text: text), sampleRate: 16000)
                            resumeOnce(with: .success(result))
                        } else {
                            receive()
                        }
                    }
                }
            }
            receive()
        }
    }

    /// 科大讯飞超拟人 TTS (WebSocket)
    private func synthesizeWithXfyunSuper(text: String, voice: Voice) async throws -> AudioData {
        let components = config.apiKey.components(separatedBy: ":")
        guard components.count == 3 else { throw TTSError.invalidConfiguration }
        let appId = components[0]
        let apiSecret = components[1]
        let apiKey = components[2]

        let host = "cbm01.cn-huabei-1.xf-yun.com"
        let path = "/v1/private/mcd9m97e6"
        let date = makeRFC1123Date()
        let signOrigin = "host: \(host)\ndate: \(date)\nGET \(path) HTTP/1.1"
        guard let signData = signOrigin.data(using: .utf8),
              let secretData = apiSecret.data(using: .utf8) else {
            throw TTSError.invalidConfiguration
        }
        let signature = hmacSHA256Base64(data: signData, key: secretData)
        let authOrigin = "api_key=\"\(apiKey)\", algorithm=\"hmac-sha256\", headers=\"host date request-line\", signature=\"\(signature)\""
        let authorization = authOrigin.data(using: .utf8)!.base64EncodedString()
        let dateEncoded = date.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? date
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+=/")
        let authEncoded = authorization.addingPercentEncoding(withAllowedCharacters: allowed) ?? authorization
        let urlString = "wss://\(host)\(path)?authorization=\(authEncoded)&date=\(dateEncoded)&host=\(host)"
        guard let url = URL(string: urlString) else { throw TTSError.invalidConfiguration }

        let vcn: String
        if voice.provider == .xfyun && !voice.id.isEmpty {
            vcn = voice.id
        } else {
            vcn = "x6_lingxiaoxuan_pro"
        }
        NSLog("🎙️ 超拟人使用声音: %@, voice.id=%@, voice.provider=%@", vcn, voice.id, voice.provider.rawValue)
        let textBase64 = text.data(using: .utf8)!.base64EncodedString()

        return try await withCheckedThrowingContinuation { continuation in
            var accumulated = Data()
            var done = false
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()

            let body: [String: Any] = [
                "header": [
                    "app_id": appId,
                    "status": 2
                ],
                "parameter": [
                    "oral": [
                        "oral_level": "mid"
                    ],
                    "tts": [
                        "vcn": vcn,
                        "speed": 50,
                        "volume": 50,
                        "pitch": 50,
                        "audio": [
                            "encoding": "lame",
                            "sample_rate": 24000,
                            "channels": 1,
                            "bit_depth": 16,
                            "frame_size": 0
                        ]
                    ]
                ],
                "payload": [
                    "text": [
                        "encoding": "utf8",
                        "compress": "raw",
                        "format": "plain",
                        "status": 2,
                        "seq": 0,
                        "text": textBase64
                    ]
                ]
            ]

            guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
                  let jsonStr = String(data: jsonData, encoding: .utf8) else {
                continuation.resume(throwing: TTSError.invalidConfiguration)
                return
            }

            task.send(.string(jsonStr)) { err in
                if let err = err {
                    continuation.resume(throwing: TTSError.apiError(err.localizedDescription))
                }
            }

            func receive() {
                task.receive { result in
                    switch result {
                    case .failure(let err):
                        if !done { continuation.resume(throwing: TTSError.apiError(err.localizedDescription)) }
                    case .success(let msg):
                        var data: Data?
                        switch msg {
                        case .string(let s): data = s.data(using: .utf8)
                        case .data(let d): data = d
                        @unknown default: break
                        }
                        guard let d = data,
                              let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else {
                            if !done { continuation.resume(throwing: TTSError.audioProcessingError) }
                            return
                        }
                        let code = (json["header"] as? [String: Any])?["code"] as? Int ?? 0
                        let hasPayload = json["payload"] != nil
                        print("🔍 超拟人帧: code=\(code), hasPayload=\(hasPayload)")
                        if code != 0 {
                            let errMsg = (json["header"] as? [String: Any])?["message"] as? String ?? "Unknown"
                            NSLog("🚨 讯飞超拟人错误 code=%d message=%@", code, errMsg)
                            if !done {
                                done = true
                                task.cancel()
                                continuation.resume(throwing: TTSError.apiError("讯飞超拟人错误 \(code): \(errMsg)"))
                            }
                            return
                        }
                        if let payload = json["payload"] as? [String: Any],
                           let audio = payload["audio"] as? [String: Any],
                           let b64 = audio["audio"] as? String,
                           let chunk = Data(base64Encoded: b64) {
                            accumulated.append(chunk)
                        }
                        let status = (json["payload"] as? [String: Any]).flatMap { ($0["audio"] as? [String: Any])?["status"] as? Int } ?? -1
                        print("🔍 超拟人状态: status=\(status), accumulated=\(accumulated.count) bytes")
                        if status == 2 {
                            task.cancel()
                            if !done {
                                done = true
                                let result = AudioData(data: accumulated, format: .mp3,
                                    duration: self.estimateDuration(text: text), sampleRate: 24000)
                                continuation.resume(returning: result)
                            }
                        } else {
                            receive()
                        }
                    }
                }
            }
            receive()
        }
    }

    private func makeRFC1123Date() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        f.timeZone = TimeZone(identifier: "GMT")
        return f.string(from: Date())
    }

    private func hmacSHA256Base64(data: Data, key: Data) -> String {
        var result = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { db in
            key.withUnsafeBytes { kb in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), kb.baseAddress, key.count, db.baseAddress, data.count, &result)
            }
        }
        return Data(result).base64EncodedString()
    }

    // MARK: - Helper Methods

    /// 生成缓存键
    private func generateCacheKey(segment: TextSegment, voice: Voice) -> String {
        let content = "\(segment.text)_\(segment.emotion.rawValue)_\(voice.id)"
        return String(content.hashValue)
    }

    /// 估算音频时长
    private func estimateDuration(text: String) -> TimeInterval {
        let charCount = text.count
        let minutes = Double(charCount) / 300.0
        return minutes * 60.0
    }

    /// 从 URL 中提取 Azure 区域
    private func extractRegion(from urlString: String?) -> String? {
        guard let urlString = urlString else { return nil }
        if let regex = try? NSRegularExpression(pattern: "https://([^.]+)\\.tts\\.speech"),
           let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
           let range = Range(match.range(at: 1), in: urlString) {
            return String(urlString[range])
        }
        return nil
    }
}

// MARK: - 异步信号量

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func wait() async {
        value -= 1
        if value >= 0 {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() async {
        value += 1
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}

// MARK: - TTS 错误

enum TTSError: LocalizedError {
    case invalidConfiguration
    case unsupportedProvider
    case apiError(String)
    case networkError
    case audioProcessingError

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "TTS 配置无效"
        case .unsupportedProvider:
            return "不支持的 TTS 提供商"
        case .apiError(let message):
            return "TTS API 错误: \(message)"
        case .networkError:
            return "网络连接失败"
        case .audioProcessingError:
            return "音频处理失败"
        }
    }
}
