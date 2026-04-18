import Foundation

struct BookSearchResult: Codable, Sendable {
    let title: String
    let author: String
    let coverURL: String?
    let bookURL: String
    let bookId: String
    let intro: String
}

struct BookSourceEngine: Sendable {
    private struct SourceEndpoint: Sendable {
        let apiBase: String
        let imgBase: String
    }

    private static let sourceEndpoints: [SourceEndpoint] = [
        .init(apiBase: "https://www.bqg277.xyz/api", imgBase: "https://www.bqg277.xyz"),
        .init(apiBase: "https://www.bqg291.cc/api", imgBase: "https://www.bqg291.cc"),
    ]

    let apiBase = Self.sourceEndpoints[0].apiBase
    let imgBase = Self.sourceEndpoints[0].imgBase
    private let cache = BookSourceCache()

    static let categoryPaths: [(name: String, sort: String)] = [
        ("玄幻", "xuanhuan"),
        ("武侠", "wuxia"),
        ("都市", "dushi"),
        ("历史", "lishi"),
        ("网游", "wangyou"),
        ("科幻", "kehuan"),
        ("女生", "mm"),
        ("完本", "finish"),
    ]

    // MARK: - Public API

    func fetchCategory(sort: String) async throws -> [BookSearchResult] {
        guard DiscoverAccessGate.canUseDiscover() else {
            throw URLError(.userAuthenticationRequired)
        }
        let data = try await fetchFirstSuccessfulData(
            path: "sort",
            queryItems: [URLQueryItem(name: "sort", value: sort)]
        )
        let list = try parseObjectList(from: data, arrayKeys: ["data", "list", "books"])
        return list.compactMap { parseBookResult($0) }
    }

    func fetchRanking() async throws -> [BookSearchResult] {
        guard DiscoverAccessGate.canUseDiscover() else {
            throw URLError(.userAuthenticationRequired)
        }
        let results = try await fetchCategory(sort: "finish")
        return Array(results.prefix(10))
    }

    func search(keyword: String) async throws -> [BookSearchResult] {
        guard DiscoverAccessGate.canUseDiscover() else {
            throw URLError(.userAuthenticationRequired)
        }
        let data = try await fetchFirstSuccessfulData(
            path: "search",
            queryItems: [URLQueryItem(name: "q", value: keyword)]
        )
        let list = try parseObjectList(from: data, arrayKeys: ["data", "list", "books"])
        return list.compactMap { parseBookResult($0) }
    }

    func fetchChapters(bookId: String) async throws -> [Chapter] {
        let normalizedBookId = Self.normalizedBookId(from: bookId) ?? bookId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBookId.isEmpty else {
            throw URLError(.badURL)
        }

        let cacheKey = BookSourceCache.chapterListKey(normalizedBookId)
        let cached = cache.retrieveChapters(forKey: cacheKey)
        if let cached, !cached.isStale, !cached.chapters.isEmpty {
            return cached.chapters
        }

        var lastError: Error = URLError(.resourceUnavailable)
        for endpoint in Self.sourceEndpoints {
            do {
                let url = buildURL(
                    apiBase: endpoint.apiBase,
                    path: "booklist",
                    queryItems: [URLQueryItem(name: "id", value: normalizedBookId)]
                )
                let data = try await get(url)
                let json = try parseJSONObject(from: data)
                let titles = try parseChapterTitles(from: json)
                guard !titles.isEmpty else {
                    throw URLError(.zeroByteResource)
                }
                let chapters = titles.enumerated().map { i, title in
                    Chapter(
                        title: title,
                        url: buildURL(
                            apiBase: endpoint.apiBase,
                            path: "chapter",
                            queryItems: [
                                URLQueryItem(name: "id", value: normalizedBookId),
                                URLQueryItem(name: "chapterid", value: String(i + 1)),
                            ]
                        ).absoluteString,
                        index: i
                    )
                }
                cache.storeChapters(chapters, forKey: cacheKey)
                return chapters
            } catch {
                lastError = error
            }
        }

        if let cached, !cached.chapters.isEmpty {
            return cached.chapters
        }

        throw lastError
    }

    func fetchChapterContent(bookId: String, chapterId: Int) async throws -> String {
        let normalizedBookId = Self.normalizedBookId(from: bookId) ?? bookId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBookId.isEmpty else {
            throw URLError(.badURL)
        }

        let cacheKey = BookSourceCache.chapterContentKey(bookId: normalizedBookId, chapterId: chapterId)
        let cached = cache.retrieveChapterContent(forKey: cacheKey)
        if let cached,
           !cached.isStale,
           !cached.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return cached.text
        }

        do {
            var lastError: Error = URLError(.resourceUnavailable)
            for endpoint in Self.sourceEndpoints {
                do {
                    let url = buildURL(
                        apiBase: endpoint.apiBase,
                        path: "chapter",
                        queryItems: [
                            URLQueryItem(name: "id", value: normalizedBookId),
                            URLQueryItem(name: "chapterid", value: String(chapterId)),
                        ]
                    )
                    let data = try await get(url)
                    let json = try parseJSONObject(from: data)
                    guard let txt = stringValue(in: json, keys: ["txt", "content", "data"]),
                          !txt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw URLError(.badServerResponse)
                    }
                    cache.storeChapterContent(txt, forKey: cacheKey)
                    return txt
                } catch {
                    lastError = error
                }
            }

            throw lastError
        } catch {
            if let cached,
               !cached.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return cached.text
            }
            throw error
        }
    }

    static func normalizedBookId(from rawBookId: String?, bookURL: String? = nil) -> String? {
        if let normalized = normalizedIdentifier(from: rawBookId) {
            return normalized
        }
        return normalizedIdentifier(from: bookURL)
    }

    static func normalizedBookURL(from rawBookURL: String?, bookId: String?) -> String? {
        if let normalizedId = normalizedBookId(from: bookId, bookURL: rawBookURL) {
            return canonicalBookURL(bookId: normalizedId)
        }

        guard let trimmed = rawBookURL?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Private

    private static func canonicalBookURL(bookId: String) -> String {
        "\(sourceEndpoints[0].apiBase)/book?id=\(bookId)"
    }

    private func fetchFirstSuccessfulData(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Data {
        var lastError: Error = URLError(.resourceUnavailable)
        for endpoint in Self.sourceEndpoints {
            do {
                return try await get(buildURL(apiBase: endpoint.apiBase, path: path, queryItems: queryItems))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func buildURL(
        apiBase: String,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL {
        var components = URLComponents(string: apiBase)!
        components.path = "\(components.path)/\(path)"
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, text/plain;q=0.9, */*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func parseBookResult(_ dict: [String: Any]) -> BookSearchResult? {
        let rawURL = stringValue(in: dict, keys: ["bookURL", "url", "detailUrl", "detailURL"])
        guard let id = Self.normalizedBookId(
                from: stringValue(in: dict, keys: ["id", "bookId"]),
                bookURL: rawURL
              ),
              let title = stringValue(in: dict, keys: ["title", "bookName", "name"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty,
              !title.isEmpty else {
            return nil
        }
        let author = (stringValue(in: dict, keys: ["author", "writer"]) ?? "未知")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let intro = (stringValue(in: dict, keys: ["intro", "desc", "description"]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cover = resolvedCoverURL(from: dict, bookId: id)
        return BookSearchResult(
            title: title,
            author: author,
            coverURL: cover,
            bookURL: Self.normalizedBookURL(from: rawURL, bookId: id) ?? Self.canonicalBookURL(bookId: id),
            bookId: id,
            intro: intro
        )
    }

    private func parseJSONObject(from data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }

    private func parseObjectList(from data: Data, arrayKeys: [String]) throws -> [[String: Any]] {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        if let list = extractObjectList(from: jsonObject, preferredKeys: arrayKeys), !list.isEmpty {
            return list
        }
        throw URLError(.cannotParseResponse)
    }

    private func parseChapterTitles(from json: [String: Any]) throws -> [String] {
        if let titles = extractChapterTitles(from: json), !titles.isEmpty {
            return titles
        }
        throw URLError(.cannotParseResponse)
    }

    private func stringValue(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                return value
            }
            if let value = dict[key] as? Int {
                return String(value)
            }
            if let value = dict[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private func resolvedCoverURL(from dict: [String: Any], bookId: String) -> String? {
        if let raw = stringValue(in: dict, keys: ["coverURL", "cover", "img", "pic"]),
           !raw.isEmpty {
            if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
                return raw
            }
            if raw.hasPrefix("/") {
                return "\(imgBase)\(raw)"
            }
        }
        return "\(imgBase)/bookimg/\(max(0, (Int(bookId) ?? 0) / 1000))/\(bookId).jpg"
    }

    private func extractObjectList(
        from object: Any,
        preferredKeys: [String]
    ) -> [[String: Any]]? {
        if let list = object as? [[String: Any]], !list.isEmpty {
            return list
        }

        guard let dict = object as? [String: Any] else { return nil }

        for key in preferredKeys {
            if let value = dict[key],
               let list = extractObjectList(from: value, preferredKeys: preferredKeys),
               !list.isEmpty {
                return list
            }
        }

        for value in dict.values {
            if let list = extractObjectList(from: value, preferredKeys: preferredKeys), !list.isEmpty {
                return list
            }
        }

        return nil
    }

    private func extractChapterTitles(from object: Any) -> [String]? {
        if let titles = normalizeTitles(from: object), !titles.isEmpty {
            return titles
        }

        guard let dict = object as? [String: Any] else { return nil }

        for key in ["list", "data", "chapters", "rows", "result"] {
            if let value = dict[key],
               let titles = extractChapterTitles(from: value),
               !titles.isEmpty {
                return titles
            }
        }

        for value in dict.values {
            if let titles = extractChapterTitles(from: value), !titles.isEmpty {
                return titles
            }
        }

        return nil
    }

    private func normalizeTitles(from object: Any) -> [String]? {
        if let titles = object as? [String] {
            let cleaned = titles
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        }

        if let rows = object as? [[String: Any]] {
            let titles = rows.compactMap { row -> String? in
                guard let title = stringValue(in: row, keys: ["title", "chapterTitle", "name"]) else {
                    return nil
                }
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return titles.isEmpty ? nil : titles
        }

        return nil
    }

    private static func normalizedIdentifier(from raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        if trimmed.allSatisfy(\.isNumber) {
            return trimmed
        }

        if let components = URLComponents(string: trimmed) {
            for key in ["id", "bookId", "bid"] {
                if let value = components.queryItems?.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value,
                   let normalized = normalizedIdentifier(from: value) {
                    return normalized
                }
            }

            for segment in components.path.split(separator: "/").reversed() {
                let piece = String(segment).trimmingCharacters(in: .whitespacesAndNewlines)
                if piece.allSatisfy(\.isNumber) {
                    return piece
                }
            }
        }

        for pattern in ["id=([0-9]+)", "bookId=([0-9]+)", "bid=([0-9]+)"] {
            if let match = trimmed.firstMatch(for: pattern) {
                return match
            }
        }

        return nil
    }
}

private extension String {
    func firstMatch(for pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[valueRange])
    }
}
