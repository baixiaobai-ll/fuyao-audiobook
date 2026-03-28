import Foundation

@MainActor
class BookshelfStore: ObservableObject {
    @Published var books: [Book] = []

    private let storageKey = "bookshelf_books"

    init() {
        load()
    }

    func addBook(_ book: Book) {
        guard !books.contains(where: { $0.id == book.id }) else { return }
        books.append(book)
        save()
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
