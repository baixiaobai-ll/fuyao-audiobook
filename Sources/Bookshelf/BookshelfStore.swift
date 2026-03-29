import Foundation

@MainActor
class BookshelfStore: ObservableObject {
    @Published var books: [Book] = []

    private let storageKey = "bookshelf_books"

    init() {
        load()
    }

    func addBook(_ book: Book) {
        guard existingBook(matching: book) == nil else { return }
        books.append(book)
        save()
    }

    /// 书架上是否已有与 `book` 逻辑相同的书（发现页每次进入可能生成新 UUID）
    func containsSameBook(as book: Book) -> Bool {
        existingBook(matching: book) != nil
    }

    /// 返回书架上已存在的同书记录（用于统一缓存 id、展示「已添加」）
    func existingBook(matching book: Book) -> Book? {
        books.first { $0.isSameLogicalBook(as: book) }
    }

    func removeBook(id: UUID) {
        books.removeAll { $0.id == id }
        save()
        Task {
            try? await ChapterContentManager.shared.deleteBook(bookId: id)
        }
    }

    func updateLastRead(bookId: UUID, chapterIndex: Int) {
        guard let i = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[i].lastReadChapter = chapterIndex
        save()
    }

    func updateChapters(bookId: UUID, chapters: [Chapter]) {
        guard let i = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[i].chapters = chapters
        save()
    }

    func updateVoiceBindings(bookId: UUID, bindings: [String: String]) {
        guard let i = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[i].voiceBindings.merge(bindings) { _, new in new }
        save()
    }

    func containsBook(id: UUID) -> Bool {
        books.contains { $0.id == id }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(books) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Book].self, from: data) else { return }
        books = saved
    }
}
