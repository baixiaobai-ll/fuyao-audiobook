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
    let apiBase = "https://www.bqg291.cc/api"
    let imgBase = "https://www.bqg291.cc"

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
        let url = URL(string: "\(apiBase)/sort?sort=\(sort)")!
        let data = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { parseBookResult($0) }
    }

    func fetchRanking() async throws -> [BookSearchResult] {
        let results = try await fetchCategory(sort: "finish")
        return Array(results.prefix(10))
    }

    func search(keyword: String) async throws -> [BookSearchResult] {
        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let url = URL(string: "\(apiBase)/search?q=\(encoded)")!
        let data = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { parseBookResult($0) }
    }

    func fetchChapters(bookId: String) async throws -> [Chapter] {
        let url = URL(string: "\(apiBase)/booklist?id=\(bookId)")!
        let data = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["list"] as? [String] else { return [] }
        return list.enumerated().map { i, title in
            Chapter(title: title, url: "\(apiBase)/chapter?id=\(bookId)&chapterid=\(i + 1)", index: i)
        }
    }

    func fetchChapterContent(bookId: String, chapterId: Int) async throws -> String {
        let url = URL(string: "\(apiBase)/chapter?id=\(bookId)&chapterid=\(chapterId)")!
        let data = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let txt = json["txt"] as? String, !txt.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return txt
    }

    // MARK: - Private

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func parseBookResult(_ dict: [String: Any]) -> BookSearchResult? {
        guard let id = dict["id"] as? String,
              let title = dict["title"] as? String else { return nil }
        let author = (dict["author"] as? String ?? "未知").trimmingCharacters(in: .whitespacesAndNewlines)
        let cover = "\(imgBase)/bookimg/\(max(0, (Int(id) ?? 0) / 1000))/\(id).jpg"
        let intro = (dict["intro"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return BookSearchResult(
            title: title,
            author: author,
            coverURL: cover,
            bookURL: "\(apiBase)/book?id=\(id)",
            bookId: id,
            intro: intro
        )
    }
}
