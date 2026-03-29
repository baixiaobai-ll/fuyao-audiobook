import Foundation

/// 自建「发现」聚合 API。未配置 `DISCOVER_API_BASE_URL` 或请求失败时由调用方回退到 `BookSourceEngine`。
enum DiscoverAPIClient {

    private struct BooksEnvelope: Codable {
        let books: [BookSearchResult]
    }

    static func fetchRanking() async -> [BookSearchResult]? {
        await fetchBooks(pathComponent: "v1/discover/ranking")
    }

    static func fetchCategory(sort: String) async -> [BookSearchResult]? {
        let encoded = sort.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sort
        return await fetchBooks(pathComponent: "v1/discover/category?sort=\(encoded)")
    }

    private static func fetchBooks(pathComponent: String) async -> [BookSearchResult]? {
        guard let base = Config.discoverAPIBaseURL else { return nil }
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, let url = URL(string: "\(trimmed)/\(pathComponent)") else { return nil }

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
            return list
        }
        if let env = try? decoder.decode(BooksEnvelope.self, from: data), !env.books.isEmpty {
            return env.books
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let arr = obj["data"] as? [[String: Any]] {
            return arr.compactMap { dict in
                guard let title = dict["title"] as? String,
                      let author = dict["author"] as? String,
                      let bookId = dict["bookId"] as? String ?? dict["id"] as? String else { return nil }
                let cover = dict["coverURL"] as? String ?? dict["cover"] as? String
                let bookURL = dict["bookURL"] as? String ?? dict["url"] as? String ?? ""
                let intro = dict["intro"] as? String ?? ""
                return BookSearchResult(
                    title: title,
                    author: author,
                    coverURL: cover,
                    bookURL: bookURL,
                    bookId: bookId,
                    intro: intro
                )
            }
        }
        return nil
    }
}
