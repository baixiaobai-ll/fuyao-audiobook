import Foundation

/// 与 `DISCOVER_API_BASE_URL` 同源服务的「文本分析索引」缓存（**不含正文**，仅 UTF-8 偏移与结构字段）。
///
/// **GET** `.../v1/playback/analysis?bookId={id}&chapterIndex={n}&textHash={sha256hex}`
/// - `textHash` 为 `SHA256(NovelTextAnalyzer.canonicalTextForPlayback(原始章文本).utf8)` 的小写 hex。
/// - 200：响应体为 `PlaybackAnalysisIndex` JSON，或 `{ "analysisIndex": { ... } }` / `{ "data": { ... } }`
///
/// **POST** `.../v1/playback/analysis`（可选，回写索引）
/// - JSON：`{ "analysisIndex": { "schemaVersion", "bookId", "chapterIndex", "textHash", "characters", "segmentDescriptors", "metadata" } }`
public struct PlaybackRemoteCacheKey: Sendable {
    public let bookId: String
    public let chapterIndex: Int

    public init(bookId: String, chapterIndex: Int) {
        self.bookId = bookId
        self.chapterIndex = chapterIndex
    }
}

enum PlaybackAnalysisCloudClient {

    /// 与送入 `generate` 的原始章文本对应的规范化串的 SHA256（hex），与索引内 `textHash` 一致。
    static func textFingerprintForPlaybackInput(_ rawChapterText: String) -> String {
        let canonical = NovelTextAnalyzer.canonicalTextForPlayback(rawChapterText)
        return PlaybackAnalysisIndexBuilder.textHash(forCanonicalText: canonical)
    }

    static func fetchAnalysisIndex(
        bookId: String,
        chapterIndex: Int,
        textFingerprint: String
    ) async -> PlaybackAnalysisIndex? {
        guard let base = normalizedDiscoverBaseURL() else { return nil }
        var components = URLComponents(string: "\(base)/v1/playback/analysis")
        components?.queryItems = [
            URLQueryItem(name: "bookId", value: bookId),
            URLQueryItem(name: "chapterIndex", value: String(chapterIndex)),
            URLQueryItem(name: "textHash", value: textFingerprint),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            if let decoded = decodeIndexEnvelope(data) {
                print("☁️ 已命中云端分析索引: bookId=\(bookId) chapter=\(chapterIndex)")
                return decoded
            }
            return nil
        } catch {
            print("⚠️ PlaybackAnalysisCloud fetch: \(error.localizedDescription)")
            return nil
        }
    }

    /// 本地分析完成后异步回写索引（无正文），不阻塞播放。
    static func uploadAnalysisIndexInBackground(index: PlaybackAnalysisIndex) {
        guard let base = normalizedDiscoverBaseURL() else { return }
        guard let url = URL(string: "\(base)/v1/playback/analysis") else { return }

        struct Body: Encodable {
            let analysisIndex: PlaybackAnalysisIndex
        }

        let body = Body(analysisIndex: index)
        guard let data = try? JSONEncoder().encode(body) else { return }

        var request = URLRequest(url: url, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = data

        Task.detached(priority: .utility) {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    print("☁️ 已上传分析索引: bookId=\(index.bookId) chapter=\(index.chapterIndex)")
                }
            } catch {
                print("⚠️ PlaybackAnalysisCloud upload: \(error.localizedDescription)")
            }
        }
    }

    private static func normalizedDiscoverBaseURL() -> String? {
        guard let base = Config.discoverAPIBaseURL else { return nil }
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeIndexEnvelope(_ data: Data) -> PlaybackAnalysisIndex? {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(PlaybackAnalysisIndex.self, from: data) {
            return direct
        }
        struct WrapA: Codable {
            let analysisIndex: PlaybackAnalysisIndex
        }
        if let w = try? decoder.decode(WrapA.self, from: data) {
            return w.analysisIndex
        }
        struct WrapD: Codable {
            let data: PlaybackAnalysisIndex
        }
        if let w = try? decoder.decode(WrapD.self, from: data) {
            return w.data
        }
        return nil
    }
}
