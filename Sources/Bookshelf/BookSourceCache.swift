import CryptoKit
import Foundation

final class BookSourceCache: @unchecked Sendable {

    private struct CachedBookList: Codable {
        let books: [BookSearchResult]
        let timestamp: Date
    }

    private struct CachedChapterList: Codable {
        let chapters: [Chapter]
        let timestamp: Date
    }

    private struct CachedChapterText: Codable {
        let text: String
        let timestamp: Date
    }

    /// 20 minutes before data is considered stale (triggers background refresh)
    private static let staleInterval: TimeInterval = 20 * 60
    /// 7 days before data is considered expired (deleted)
    private static let expiredInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let chapterListStaleInterval: TimeInterval = 12 * 60 * 60
    private static let chapterListExpiredInterval: TimeInterval = 30 * 24 * 60 * 60
    private static let chapterTextStaleInterval: TimeInterval = 30 * 24 * 60 * 60
    private static let chapterTextExpiredInterval: TimeInterval = 90 * 24 * 60 * 60

    private let cacheDirectory: URL
    private let memoryLock = NSLock()
    private var memoryBookLists: [String: CachedBookList] = [:]
    private var memoryChapterLists: [String: CachedChapterList] = [:]
    private var memoryChapterTexts: [String: CachedChapterText] = [:]

    static func categoryKey(_ sort: String) -> String { "category_\(sort)" }
    static let rankingKey = "ranking"
    static func searchKey(_ keyword: String) -> String {
        "search_\(stableDigest(for: keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()))"
    }
    static func chapterListKey(_ bookId: String) -> String {
        "chapter_list_\(stableDigest(for: bookId))"
    }
    static func chapterContentKey(bookId: String, chapterId: Int) -> String {
        "chapter_text_\(stableDigest(for: "\(bookId)#\(chapterId)"))"
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        cacheDirectory = docs.appendingPathComponent("BookSourceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        cleanupExpired()
    }

    func store(_ results: [BookSearchResult], forKey key: String) {
        let entry = CachedBookList(books: results, timestamp: Date())
        setMemoryBookList(entry, forKey: key)
        write(entry, to: fileURL(for: key))
    }

    func retrieve(forKey key: String) -> (books: [BookSearchResult], isStale: Bool)? {
        if let entry = memoryBookList(forKey: key) {
            let age = Date().timeIntervalSince(entry.timestamp)
            if age <= Self.expiredInterval {
                return (entry.books, age > Self.staleInterval)
            }
            clearMemoryBookList(forKey: key)
        }

        guard let entry: CachedBookList = read(CachedBookList.self, from: fileURL(for: key)) else {
            return nil
        }

        let age = Date().timeIntervalSince(entry.timestamp)
        if age > Self.expiredInterval {
            removeFileAndMemory(forKey: key)
            return nil
        }

        setMemoryBookList(entry, forKey: key)
        return (entry.books, age > Self.staleInterval)
    }

    func storeChapters(_ chapters: [Chapter], forKey key: String) {
        let entry = CachedChapterList(chapters: chapters, timestamp: Date())
        setMemoryChapterList(entry, forKey: key)
        write(entry, to: fileURL(for: key))
    }

    func retrieveChapters(forKey key: String) -> (chapters: [Chapter], isStale: Bool)? {
        if let entry = memoryChapterList(forKey: key) {
            let age = Date().timeIntervalSince(entry.timestamp)
            if age <= Self.chapterListExpiredInterval {
                return (entry.chapters, age > Self.chapterListStaleInterval)
            }
            clearMemoryChapterList(forKey: key)
        }

        guard let entry: CachedChapterList = read(CachedChapterList.self, from: fileURL(for: key)) else {
            return nil
        }

        let age = Date().timeIntervalSince(entry.timestamp)
        if age > Self.chapterListExpiredInterval {
            removeFileAndMemory(forKey: key)
            return nil
        }

        setMemoryChapterList(entry, forKey: key)
        return (entry.chapters, age > Self.chapterListStaleInterval)
    }

    func storeChapterContent(_ text: String, forKey key: String) {
        let entry = CachedChapterText(text: text, timestamp: Date())
        setMemoryChapterText(entry, forKey: key)
        write(entry, to: fileURL(for: key))
    }

    func retrieveChapterContent(forKey key: String) -> (text: String, isStale: Bool)? {
        if let entry = memoryChapterText(forKey: key) {
            let age = Date().timeIntervalSince(entry.timestamp)
            if age <= Self.chapterTextExpiredInterval {
                return (entry.text, age > Self.chapterTextStaleInterval)
            }
            clearMemoryChapterText(forKey: key)
        }

        guard let entry: CachedChapterText = read(CachedChapterText.self, from: fileURL(for: key)) else {
            return nil
        }

        let age = Date().timeIntervalSince(entry.timestamp)
        if age > Self.chapterTextExpiredInterval {
            removeFileAndMemory(forKey: key)
            return nil
        }

        setMemoryChapterText(entry, forKey: key)
        return (entry.text, age > Self.chapterTextStaleInterval)
    }

    func clearAll() {
        let fm = FileManager.default
        memoryLock.lock()
        memoryBookLists.removeAll()
        memoryChapterLists.removeAll()
        memoryChapterTexts.removeAll()
        memoryLock.unlock()
        if let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files { try? fm.removeItem(at: file) }
        }
    }

    private func cleanupExpired() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files {
            guard let age = cachedAge(for: file) else {
                try? fm.removeItem(at: file)
                continue
            }
            if age > expiryInterval(for: file.deletingPathExtension().lastPathComponent) {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func fileURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).json")
    }

    private func expiryInterval(for key: String) -> TimeInterval {
        if key.hasPrefix("chapter_list_") {
            return Self.chapterListExpiredInterval
        }
        if key.hasPrefix("chapter_text_") {
            return Self.chapterTextExpiredInterval
        }
        return Self.expiredInterval
    }

    private func cachedAge(for fileURL: URL) -> TimeInterval? {
        guard let data = try? Data(contentsOf: fileURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestampString = object["timestamp"] as? String else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        guard let timestamp = formatter.date(from: timestampString) else { return nil }
        return Date().timeIntervalSince(timestamp)
    }

    private func write<T: Codable>(_ value: T, to fileURL: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("⚠️ BookSourceCache store failed: \(error.localizedDescription)")
        }
    }

    private func read<T: Codable>(_ type: T.Type, from fileURL: URL) -> T? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    private func removeFileAndMemory(forKey key: String) {
        clearMemoryBookList(forKey: key)
        clearMemoryChapterList(forKey: key)
        clearMemoryChapterText(forKey: key)
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    private func memoryBookList(forKey key: String) -> CachedBookList? {
        memoryLock.lock()
        defer { memoryLock.unlock() }
        return memoryBookLists[key]
    }

    private func setMemoryBookList(_ entry: CachedBookList, forKey key: String) {
        memoryLock.lock()
        memoryBookLists[key] = entry
        memoryLock.unlock()
    }

    private func clearMemoryBookList(forKey key: String) {
        memoryLock.lock()
        memoryBookLists.removeValue(forKey: key)
        memoryLock.unlock()
    }

    private func memoryChapterList(forKey key: String) -> CachedChapterList? {
        memoryLock.lock()
        defer { memoryLock.unlock() }
        return memoryChapterLists[key]
    }

    private func setMemoryChapterList(_ entry: CachedChapterList, forKey key: String) {
        memoryLock.lock()
        memoryChapterLists[key] = entry
        memoryLock.unlock()
    }

    private func clearMemoryChapterList(forKey key: String) {
        memoryLock.lock()
        memoryChapterLists.removeValue(forKey: key)
        memoryLock.unlock()
    }

    private func memoryChapterText(forKey key: String) -> CachedChapterText? {
        memoryLock.lock()
        defer { memoryLock.unlock() }
        return memoryChapterTexts[key]
    }

    private func setMemoryChapterText(_ entry: CachedChapterText, forKey key: String) {
        memoryLock.lock()
        memoryChapterTexts[key] = entry
        memoryLock.unlock()
    }

    private func clearMemoryChapterText(forKey key: String) {
        memoryLock.lock()
        memoryChapterTexts.removeValue(forKey: key)
        memoryLock.unlock()
    }

    private static func stableDigest(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
