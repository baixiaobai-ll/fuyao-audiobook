import Foundation

actor ChapterContentManager {
    static let shared = ChapterContentManager()

    private let baseDirectory: URL
    private var memoryCache: [String: String] = [:]
    private var memoryOrder: [String] = []
    private let maxMemoryEntries = 48

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDirectory = documents.appendingPathComponent("BookContent")
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    func getContent(bookId: UUID, chapterIndex: Int) -> String? {
        let key = cacheKey(bookId: bookId, chapterIndex: chapterIndex)
        if let cached = memoryCache[key] {
            touchMemoryKey(key)
            return cached
        }

        guard let content = try? String(
            contentsOf: contentFileURL(bookId: bookId, chapterIndex: chapterIndex),
            encoding: .utf8
        ) else {
            return nil
        }
        storeInMemory(content, forKey: key)
        return content
    }

    func saveContent(bookId: UUID, chapterIndex: Int, content: String) throws {
        let dir = baseDirectory.appendingPathComponent(bookId.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appendingPathComponent("\(chapterIndex).txt"), atomically: true, encoding: .utf8)
        storeInMemory(content, forKey: cacheKey(bookId: bookId, chapterIndex: chapterIndex))
    }

    func hasContent(bookId: UUID, chapterIndex: Int) -> Bool {
        let key = cacheKey(bookId: bookId, chapterIndex: chapterIndex)
        if memoryCache[key] != nil {
            return true
        }
        return FileManager.default.fileExists(atPath: contentFileURL(bookId: bookId, chapterIndex: chapterIndex).path)
    }

    func deleteBook(bookId: UUID) throws {
        let dir = baseDirectory.appendingPathComponent(bookId.uuidString)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
        let prefix = "\(bookId.uuidString)|"
        memoryCache.keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { key in
                memoryCache.removeValue(forKey: key)
                memoryOrder.removeAll { $0 == key }
            }
    }

    private func contentFileURL(bookId: UUID, chapterIndex: Int) -> URL {
        baseDirectory
            .appendingPathComponent(bookId.uuidString)
            .appendingPathComponent("\(chapterIndex).txt")
    }

    private func cacheKey(bookId: UUID, chapterIndex: Int) -> String {
        "\(bookId.uuidString)|\(chapterIndex)"
    }

    private func storeInMemory(_ content: String, forKey key: String) {
        memoryCache[key] = content
        touchMemoryKey(key)
        if memoryOrder.count > maxMemoryEntries, let oldest = memoryOrder.first {
            memoryOrder.removeFirst()
            memoryCache.removeValue(forKey: oldest)
        }
    }

    private func touchMemoryKey(_ key: String) {
        memoryOrder.removeAll { $0 == key }
        memoryOrder.append(key)
    }
}
