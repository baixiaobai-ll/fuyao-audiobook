import Foundation

final class BookSourceCache: Sendable {

    private struct CachedBookList: Codable {
        let books: [BookSearchResult]
        let timestamp: Date
    }

    /// 20 minutes before data is considered stale (triggers background refresh)
    private static let staleInterval: TimeInterval = 20 * 60
    /// 7 days before data is considered expired (deleted)
    private static let expiredInterval: TimeInterval = 7 * 24 * 60 * 60

    private let cacheDirectory: URL

    static func categoryKey(_ sort: String) -> String { "category_\(sort)" }
    static let rankingKey = "ranking"

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = docs.appendingPathComponent("BookSourceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cleanupExpired()
    }

    func store(_ results: [BookSearchResult], forKey key: String) {
        let entry = CachedBookList(books: results, timestamp: Date())
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        do {
            let data = try JSONEncoder().encode(entry)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("⚠️ BookSourceCache store failed: \(error.localizedDescription)")
        }
    }

    func retrieve(forKey key: String) -> (books: [BookSearchResult], isStale: Bool)? {
        let fileURL = cacheDirectory.appendingPathComponent("\(key).json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let entry = try JSONDecoder().decode(CachedBookList.self, from: data)
            let age = Date().timeIntervalSince(entry.timestamp)
            if age > Self.expiredInterval {
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            return (entry.books, age > Self.staleInterval)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    func clearAll() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files { try? fm.removeItem(at: file) }
        }
    }

    private func cleanupExpired() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let entry = try? JSONDecoder().decode(CachedBookList.self, from: data) else {
                try? fm.removeItem(at: file)
                continue
            }
            if Date().timeIntervalSince(entry.timestamp) > Self.expiredInterval {
                try? fm.removeItem(at: file)
            }
        }
    }
}
