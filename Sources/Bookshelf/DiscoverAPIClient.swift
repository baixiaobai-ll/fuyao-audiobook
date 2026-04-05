import Foundation

/// 自建「发现」聚合 API。未配置 `DISCOVER_API_BASE_URL` 或请求失败时由调用方回退到 `BookSourceEngine`。
enum DiscoverAPIClient {

    private struct BooksEnvelope: Codable {
        let books: [BookSearchResult]
    }

    static func fetchRanking() async -> [BookSearchResult]? {
        await fetchBooks(path: "v1/discover/ranking")
    }

    static func fetchCategory(sort: String) async -> [BookSearchResult]? {
        await fetchBooks(
            path: "v1/discover/category",
            queryItems: [URLQueryItem(name: "sort", value: sort)]
        )
    }

    static func fetchSearch(keyword: String) async -> [BookSearchResult]? {
        await fetchBooks(
            path: "v1/discover/search",
            queryItems: [URLQueryItem(name: "q", value: keyword)]
        )
    }

    private static func fetchBooks(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async -> [BookSearchResult]? {
        guard let base = Config.discoverAPIBaseURL else { return nil }
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              let baseURL = URL(string: trimmed),
              var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return decodeBookList(data)
        } catch {
            print("⚠️ DiscoverAPI: \(error.localizedDescription)")
            return nil
        }
    }

    private static func decodeBookList(_ data: Data) -> [BookSearchResult]? {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BookSearchResult].self, from: data), !list.isEmpty {
            return normalized(list)
        }
        if let env = try? decoder.decode(BooksEnvelope.self, from: data), !env.books.isEmpty {
            return normalized(env.books)
        }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let list = extractBookList(from: object),
           !list.isEmpty {
            return normalized(list)
        }
        return nil
    }

    private static func normalized(_ results: [BookSearchResult]) -> [BookSearchResult] {
        results.map { result in
            let bookId = BookSourceEngine.normalizedBookId(from: result.bookId, bookURL: result.bookURL) ?? result.bookId
            let bookURL = BookSourceEngine.normalizedBookURL(from: result.bookURL, bookId: bookId) ?? result.bookURL
            return BookSearchResult(
                title: result.title.trimmingCharacters(in: .whitespacesAndNewlines),
                author: result.author.trimmingCharacters(in: .whitespacesAndNewlines),
                coverURL: result.coverURL,
                bookURL: bookURL,
                bookId: bookId,
                intro: result.intro.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func extractBookList(from object: Any) -> [BookSearchResult]? {
        if let rows = object as? [[String: Any]] {
            let list = rows.compactMap { parseBookResult($0) }
            return list.isEmpty ? nil : list
        }

        guard let dict = object as? [String: Any] else { return nil }

        for key in ["data", "list", "books", "results", "items"] {
            if let value = dict[key],
               let list = extractBookList(from: value),
               !list.isEmpty {
                return list
            }
        }

        for value in dict.values {
            if let list = extractBookList(from: value), !list.isEmpty {
                return list
            }
        }

        return nil
    }

    private static func parseBookResult(_ dict: [String: Any]) -> BookSearchResult? {
        guard let title = stringValue(in: dict, keys: ["title", "bookName", "name"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }

        let rawURL = stringValue(in: dict, keys: ["bookURL", "url", "detailUrl", "detailURL"])
        let rawBookId = stringValue(in: dict, keys: ["bookId", "id"])
        let normalizedBookId = BookSourceEngine.normalizedBookId(from: rawBookId, bookURL: rawURL) ?? rawBookId ?? ""
        let normalizedBookURL = BookSourceEngine.normalizedBookURL(from: rawURL, bookId: normalizedBookId) ?? rawURL ?? ""

        return BookSearchResult(
            title: title,
            author: (stringValue(in: dict, keys: ["author", "writer"]) ?? "未知")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            coverURL: stringValue(in: dict, keys: ["coverURL", "cover", "img", "pic"]),
            bookURL: normalizedBookURL,
            bookId: normalizedBookId,
            intro: (stringValue(in: dict, keys: ["intro", "desc", "description"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func stringValue(in dict: [String: Any], keys: [String]) -> String? {
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
}
