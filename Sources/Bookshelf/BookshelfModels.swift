import Foundation

public struct Book: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var author: String
    public var coverURL: String?
    public var sourceURL: String?
    public var bookId: String?      // API book ID (e.g. "11493")
    public var chapters: [Chapter]
    public var lastReadChapter: Int
    public var addedDate: Date
    public var source: BookSource
    public var voiceBindings: [String: String]

    /// 是否为同一本书（用于书架去重：笔趣阁按 `bookId`，本地按 `id`）
    public func isSameLogicalBook(as other: Book) -> Bool {
        guard source == other.source else { return false }
        switch source {
        case .biquge:
            if let a = bookId, let b = other.bookId, !a.isEmpty, !b.isEmpty {
                return a == b
            }
            return id == other.id
        case .local:
            return id == other.id
        }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        author: String,
        coverURL: String? = nil,
        sourceURL: String? = nil,
        bookId: String? = nil,
        chapters: [Chapter] = [],
        lastReadChapter: Int = 0,
        addedDate: Date = Date(),
        source: BookSource,
        voiceBindings: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverURL = coverURL
        self.sourceURL = sourceURL
        self.bookId = bookId
        self.chapters = chapters
        self.lastReadChapter = lastReadChapter
        self.addedDate = addedDate
        self.source = source
        self.voiceBindings = voiceBindings
    }
}

public struct Chapter: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var url: String?
    public var index: Int
    public var isDownloaded: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        url: String? = nil,
        index: Int,
        isDownloaded: Bool = false
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.index = index
        self.isDownloaded = isDownloaded
    }
}

public enum BookSource: String, Codable, Hashable, Sendable {
    case local
    case biquge
}
