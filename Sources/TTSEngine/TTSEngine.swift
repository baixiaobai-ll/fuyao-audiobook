//
//  TTSEngine.swift
//  AI有声书
//
//  TTS 引擎 - 语音合成核心
//

import Foundation
import CommonCrypto
#if canImport(AVFoundation)
import AVFoundation
#endif

/// TTS 引擎协议
protocol TTSEngineProtocol {
    func synthesize(segment: TextSegment, voice: Voice) async throws -> AudioData
    func synthesize(text: String, voice: Voice) async throws -> AudioData
}

/// TTS 引擎
final class TTSEngine: TTSEngineProtocol, @unchecked Sendable {

    private enum TTSRequestPolicy {
        static let httpTimeout: TimeInterval = 45
        static let webSocketTimeout: TimeInterval = 60
        static let maxRetryAttempts = 3
        static let baseRetryDelay: TimeInterval = 0.6
    }

    private struct RetryableHTTPError: Error {
        let statusCode: Int
        let message: String
    }

    private struct XfyunSynthesisTuning {
        let speed: Int
        let pitch: Int
        let volume: Int
        let oralLevel: String
    }

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
            audioData = try await synthesizeWithXfyunSuper(segment: segment, voice: voice)
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
        let cacheKey = sha256Hex([
            config.provider.rawValue,
            text,
            voice.provider.rawValue,
            voice.id
        ].joined(separator: "|"))
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
        var request = URLRequest(url: url, timeoutInterval: TTSRequestPolicy.httpTimeout)
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

        let data = try await executeHTTPRequest(request, serviceName: "OpenAI TTS")

        let estimatedDuration = estimateDuration(text: text)
        return buildAudioData(
            data: data,
            format: .mp3,
            fallbackDuration: estimatedDuration,
            sampleRate: voice.sampleRate
        )
    }

    /// Azure TTS
    private func synthesizeWithAzure(ssml: String, voice: Voice) async throws -> AudioData {
        let region = extractRegion(from: config.baseURL) ?? "eastasia"
        let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")!

        var request = URLRequest(url: url, timeoutInterval: TTSRequestPolicy.httpTimeout)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("AI-AudioBook-iOS", forHTTPHeaderField: "User-Agent")

        request.httpBody = ssml.data(using: .utf8)

        let data = try await executeHTTPRequest(request, serviceName: "Azure TTS")

        let text = ssmlGenerator.extractText(from: ssml)
        let estimatedDuration = estimateDuration(text: text)

        return buildAudioData(
            data: data,
            format: .mp3,
            fallbackDuration: estimatedDuration,
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
            var timeoutWorkItem: DispatchWorkItem?

            func resumeOnce(with result: Result<AudioData, Error>) {
                guard !resumed else { return }
                resumed = true
                timeoutWorkItem?.cancel()
                continuation.resume(with: result)
            }

            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            timeoutWorkItem = scheduleWebSocketTimeout(
                for: task,
                seconds: TTSRequestPolicy.webSocketTimeout
            ) {
                resumeOnce(with: .failure(TTSError.requestTimedOut(TTSRequestPolicy.webSocketTimeout)))
            }

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
                            let result = self.buildAudioData(
                                data: accumulated,
                                format: .mp3,
                                fallbackDuration: self.estimateDuration(text: text),
                                sampleRate: 16000
                            )
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
    private func synthesizeWithXfyunSuper(segment: TextSegment, voice: Voice) async throws -> AudioData {
        let tuning = makeXfyunTuning(for: segment)
        return try await performRetriedOperation(
            label: "讯飞超拟人 TTS",
            shouldRetry: { [weak self] error in
                guard let self else { return false }
                if Self.isRetryableTransportError(error) {
                    return true
                }
                let message = self.errorMessage(for: error)
                return self.isRetryableXfyunConnectionError(message)
            }
        ) {
            try await synthesizeWithXfyunSuperAttempt(text: segment.text, voice: voice, tuning: tuning)
        }
    }

    private func synthesizeWithXfyunSuper(text: String, voice: Voice) async throws -> AudioData {
        try await performRetriedOperation(
            label: "讯飞超拟人 TTS",
            shouldRetry: { [weak self] error in
                guard let self else { return false }
                if Self.isRetryableTransportError(error) {
                    return true
                }
                let message = self.errorMessage(for: error)
                return self.isRetryableXfyunConnectionError(message)
            }
        ) {
            try await synthesizeWithXfyunSuperAttempt(
                text: text,
                voice: voice,
                tuning: defaultXfyunTuning()
            )
        }
    }

    private func synthesizeWithXfyunSuperAttempt(
        text: String,
        voice: Voice,
        tuning: XfyunSynthesisTuning
    ) async throws -> AudioData {
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

        let originalVoiceId = (voice.provider == .xfyun && !voice.id.isEmpty) ? voice.id : "x6_lingxiaoxuan_pro"
        let vcn = VoiceLibrary.compatibleXfyunSuperVoiceId(for: originalVoiceId)
        if vcn != originalVoiceId {
            NSLog("⚠️ 发音人 %@ 与当前超拟人接口不兼容，自动回退到 %@", originalVoiceId, vcn)
        }
        NSLog("🎙️ 超拟人使用声音: %@, voice.id=%@, voice.provider=%@", vcn, voice.id, voice.provider.rawValue)
        let textBase64 = text.data(using: .utf8)!.base64EncodedString()

        return try await withCheckedThrowingContinuation { continuation in
            var accumulated = Data()
            var resumed = false
            var timeoutWorkItem: DispatchWorkItem?

            func resumeOnce(with result: Result<AudioData, Error>) {
                guard !resumed else { return }
                resumed = true
                timeoutWorkItem?.cancel()
                continuation.resume(with: result)
            }

            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            timeoutWorkItem = scheduleWebSocketTimeout(
                for: task,
                seconds: TTSRequestPolicy.webSocketTimeout
            ) {
                resumeOnce(with: .failure(TTSError.requestTimedOut(TTSRequestPolicy.webSocketTimeout)))
            }

            let body: [String: Any] = [
                "header": [
                    "app_id": appId,
                    "status": 2
                ],
                "parameter": [
                    "oral": [
                        "oral_level": tuning.oralLevel
                    ],
                    "tts": [
                        "vcn": vcn,
                        "speed": tuning.speed,
                        "volume": tuning.volume,
                        "pitch": tuning.pitch,
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
                resumeOnce(with: .failure(TTSError.invalidConfiguration))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) {
                task.send(.string(jsonStr)) { err in
                    if let err = err {
                        task.cancel()
                        resumeOnce(with: .failure(TTSError.apiError(err.localizedDescription)))
                    }
                }
            }

            func receive() {
                task.receive { result in
                    switch result {
                    case .failure(let err):
                        task.cancel()
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
                            task.cancel()
                            resumeOnce(with: .failure(TTSError.audioProcessingError))
                            return
                        }
                        let code = (json["header"] as? [String: Any])?["code"] as? Int ?? 0
                        if code != 0 {
                            let errMsg = (json["header"] as? [String: Any])?["message"] as? String ?? "Unknown"
                            NSLog("🚨 讯飞超拟人错误 code=%d message=%@", code, errMsg)
                            task.cancel()
                            let friendly = "讯飞发音失败（\(vcn)）：\(errMsg) [code \(code)]"
                            resumeOnce(with: .failure(TTSError.apiError(friendly)))
                            return
                        }
                        if let payload = json["payload"] as? [String: Any],
                           let audio = payload["audio"] as? [String: Any],
                           let b64 = audio["audio"] as? String,
                           let chunk = Data(base64Encoded: b64) {
                            accumulated.append(chunk)
                        }
                        let status = (json["payload"] as? [String: Any]).flatMap { ($0["audio"] as? [String: Any])?["status"] as? Int } ?? -1
                        if status == 2 {
                            task.cancel()
                            let audioResult = self.buildAudioData(
                                data: accumulated,
                                format: .mp3,
                                fallbackDuration: self.estimateDuration(text: text),
                                sampleRate: 24000
                            )
                            resumeOnce(with: .success(audioResult))
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

    private func isRetryableXfyunConnectionError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("socket")
            || normalized.contains("not connected")
            || normalized.contains("tls")
            || message.contains("未连接")
            || message.contains("超时")
            || message.contains("安全连接失败")
            || normalized.contains("network connection was lost")
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

    private func executeHTTPRequest(_ request: URLRequest, serviceName: String) async throws -> Data {
        try await performRetriedOperation(
            label: serviceName,
            shouldRetry: { error in
                error is RetryableHTTPError || Self.isRetryableTransportError(error)
            }
        ) {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TTSError.networkError
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                if Self.isRetryableHTTPStatus(httpResponse.statusCode) {
                    throw RetryableHTTPError(statusCode: httpResponse.statusCode, message: errorMessage)
                }
                throw TTSError.apiError("HTTP \(httpResponse.statusCode): \(errorMessage)")
            }

            return data
        }
    }

    private func performRetriedOperation<T>(
        label: String,
        maxAttempts: Int = TTSRequestPolicy.maxRetryAttempts,
        shouldRetry: (Error) -> Bool,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch is CancellationError {
                throw TTSError.networkError
            } catch {
                let normalized = normalize(error)
                lastError = normalized
                guard shouldRetry(error), attempt < maxAttempts else {
                    throw normalized
                }

                let delaySeconds = TTSRequestPolicy.baseRetryDelay * Double(attempt)
                NSLog(
                    "⚠️ %@ 失败，%.1f 秒后重试第 %d/%d 次。error=%@",
                    label,
                    delaySeconds,
                    attempt + 1,
                    maxAttempts,
                    errorMessage(for: normalized)
                )
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            }
        }

        throw lastError ?? TTSError.networkError
    }

    private func normalize(_ error: Error) -> Error {
        if let error = error as? TTSError {
            return error
        }
        if let error = error as? RetryableHTTPError {
            return TTSError.apiError("HTTP \(error.statusCode): \(error.message)")
        }
        if let error = error as? URLError {
            switch error.code {
            case .timedOut:
                return TTSError.requestTimedOut(TTSRequestPolicy.httpTimeout)
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                    .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff,
                    .resourceUnavailable:
                return TTSError.networkError
            default:
                return TTSError.apiError(error.localizedDescription)
            }
        }
        return error
    }

    private static func isRetryableTransportError(_ error: Error) -> Bool {
        if let error = error as? RetryableHTTPError {
            return isRetryableHTTPStatus(error.statusCode)
        }
        if let error = error as? TTSError {
            switch error {
            case .networkError, .requestTimedOut:
                return true
            default:
                return false
            }
        }
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .timedOut, .notConnectedToInternet, .networkConnectionLost,
                .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private static func isRetryableHTTPStatus(_ statusCode: Int) -> Bool {
        [408, 409, 425, 429, 500, 502, 503, 504].contains(statusCode)
    }

    private func scheduleWebSocketTimeout(
        for task: URLSessionWebSocketTask,
        seconds: TimeInterval,
        onTimeout: @escaping () -> Void
    ) -> DispatchWorkItem {
        let workItem = DispatchWorkItem {
            task.cancel(with: .goingAway, reason: nil)
            onTimeout()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: workItem)
        return workItem
    }

    private func buildAudioData(
        data: Data,
        format: AudioData.AudioFormat,
        fallbackDuration: TimeInterval,
        sampleRate: Int
    ) -> AudioData {
        let resolvedDuration = actualDuration(for: data) ?? fallbackDuration
        return AudioData(
            data: data,
            format: format,
            duration: resolvedDuration,
            sampleRate: sampleRate
        )
    }

    /// 生成缓存键
    private func generateCacheKey(segment: TextSegment, voice: Voice) -> String {
        let content = [
            config.provider.rawValue,
            segment.text,
            segment.type.rawValue,
            segment.emotion.rawValue,
            segment.scene.type.rawValue,
            String(format: "%.2f", segment.scene.intensity),
            voice.provider.rawValue,
            voice.id
        ].joined(separator: "|")
        return sha256Hex(content)
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

    private func errorMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return localized
        }
        return error.localizedDescription
    }

    private func sha256Hex(_ value: String) -> String {
        guard let data = value.data(using: .utf8) else {
            return String(value.hashValue)
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { rawBuffer in
            _ = CC_SHA256(rawBuffer.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func actualDuration(for data: Data) -> TimeInterval? {
        #if canImport(AVFoundation)
        guard let player = try? AVAudioPlayer(data: data) else { return nil }
        let duration = player.duration
        return (duration.isFinite && duration > 0) ? duration : nil
        #else
        return nil
        #endif
    }

    private func defaultXfyunTuning() -> XfyunSynthesisTuning {
        XfyunSynthesisTuning(speed: 50, pitch: 50, volume: 50, oralLevel: "mid")
    }

    /// 讯飞超拟人音色（`x6_*_pro` / `x5_*_flow`）**没有原生 emotion 入参**——它只接受
    /// `vcn`（发音人 ID）和 `speed / pitch / volume / oral_level` 这几个 prosody 参数。
    /// 历史上我们曾用 `segment.emotion / scene / type` 间接驱动 prosody，目的是给"愤怒段"
    /// 加 pitch、给"悲伤段"减 speed 等，但实际效果是：
    /// 1. 同一角色在不同情绪下 pitch 偏移 ≥ 8 单位 → 听感**像是换了发音人**；
    /// 2. `oralLevel` 切档（low/mid/high）对超拟人音色极敏感 → 听感等同于切发音人；
    /// 3. 跟讯飞超拟人本身**自带的情绪表达能力**打架，反而失控。
    ///
    /// 2026-04-26 决策（方案 A，用户拍板）：
    /// **彻底放弃在 prosody 层模拟 emotion**。所有 segment 都用固定的中位参数合成，让讯飞
    /// 发音人按它自己的内置表演力去读。氛围感由 `BGM + 音效`（按 scene.type 选）补偿，
    /// 而不是由 TTS 调制做。emotion / scene / type 字段在数据层照常保留，未来切到支持
    /// emotion SSML 的引擎（Azure `<express-as>` / OpenAI `instructions`）时直接复用即可。
    ///
    /// **保留 segment 参数签名**（虽然函数体内不读它）：方便未来切引擎时直接重新接回来，
    /// 不必改调用方。Swift 编译器对未使用的参数无警告（与未使用的局部变量不同）。
    private func makeXfyunTuning(for segment: TextSegment) -> XfyunSynthesisTuning {
        _ = segment
        return defaultXfyunTuning()
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
    case requestTimedOut(TimeInterval)
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
        case .requestTimedOut(let seconds):
            return "TTS 请求超时（\(Int(seconds)) 秒）"
        case .audioProcessingError:
            return "音频处理失败"
        }
    }
}
