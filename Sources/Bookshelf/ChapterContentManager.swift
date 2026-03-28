import Foundation

actor ChapterContentManager {
    static let shared = ChapterContentManager()

    private let baseDirectory: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        baseDirectory = documents.appendingPathComponent("BookContent")
        try? FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }

    func getContent(bookId: UUID, chapterIndex: Int) -> String? {
        try? String(contentsOf: contentFileURL(bookId: bookId, chapterIndex: chapterIndex), encoding: .utf8)
    }

    func saveContent(bookId: UUID, chapterIndex: Int, content: String) throws {
        let dir = baseDirectory.appendingPathComponent(bookId.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: dir.appendingPathComponent("\(chapterIndex).txt"), atomically: true, encoding: .utf8)
    }

    func hasContent(bookId: UUID, chapterIndex: Int) -> Bool {
        FileManager.default.fileExists(atPath: contentFileURL(bookId: bookId, chapterIndex: chapterIndex).path)
    }

    func deleteBook(bookId: UUID) throws {
        let dir = baseDirectory.appendingPathComponent(bookId.uuidString)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private func contentFileURL(bookId: UUID, chapterIndex: Int) -> URL {
        baseDirectory
            .appendingPathComponent(bookId.uuidString)
            .appendingPathComponent("\(chapterIndex).txt")
    }
}
