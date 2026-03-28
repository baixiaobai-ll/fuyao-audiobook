import SwiftUI
import UniformTypeIdentifiers

struct BookshelfView: View {
    @EnvironmentObject var store: BookshelfStore
    @State private var showFileImporter = false
    @State private var importError: String? = nil
    @State private var selectedBook: Book? = nil

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180))]

    var body: some View {
        NavigationStack {
            Group {
                if store.books.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(store.books) { book in
                                NavigationLink(destination: BookDetailView(book: book)) {
                                    BookCard(book: book)
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.removeBook(id: book.id)
                                    } label: {
                                        Label("从书架移除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("书架")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showFileImporter = true }) {
                            Label("选择文件", systemImage: "doc.badge.plus")
                        }
                        Button(action: { importFromDocuments() }) {
                            Label("扫描本地文件", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Label("导入TXT", systemImage: "doc.badge.plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("确定") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("empty_bookshelf")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)

            Text("书架空空如也")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("点击右上角导入TXT文件，或在\"发现\"页搜索书籍")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            HStack(spacing: 16) {
                GlassIconButton(title: "导入文件", icon: "doc.badge.plus") {
                    showFileImporter = true
                }
                GlassIconButton(title: "智能扫描", icon: "doc.viewfinder") {
                    importFromDocuments()
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }

    // MARK: - Scan Documents

    private func importFromDocuments() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        guard let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else { return }
        let txts = files.filter { $0.pathExtension.lowercased() == "txt" }
        for url in txts {
            importTXT(url: url)
        }
        if txts.isEmpty {
            importError = "Documents 目录中没有找到 TXT 文件"
        }
    }

    // MARK: - TXT Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            importTXT(url: url)
        }
    }

    private func importTXT(url: URL) {
        Task {
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    importError = "无法访问该文件"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let text = try String(contentsOf: url, encoding: .utf8)
                let title = url.deletingPathExtension().lastPathComponent
                let (chapters, contents) = splitIntoChapters(text: text)

                let book = Book(title: title, author: "本地", source: .local)

                for (index, content) in contents.enumerated() {
                    try await ChapterContentManager.shared.saveContent(
                        bookId: book.id,
                        chapterIndex: index,
                        content: content
                    )
                }

                var bookWithChapters = book
                bookWithChapters.chapters = chapters
                store.addBook(bookWithChapters)

            } catch {
                importError = "导入失败: \(error.localizedDescription)"
            }
        }
    }

    private func splitIntoChapters(text: String) -> ([Chapter], [String]) {
        let pattern = #"第[一二三四五六七八九十百千零0-9\d]+章"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return splitByLength(text: text)
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard matches.count >= 2 else { return splitByLength(text: text) }

        var chapters: [Chapter] = []
        var contents: [String] = []
        for (i, match) in matches.enumerated() {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let start = matchRange.lowerBound
            let end: String.Index
            if i + 1 < matches.count, let nextRange = Range(matches[i + 1].range, in: text) {
                end = nextRange.lowerBound
            } else {
                end = text.endIndex
            }
            let titleEnd = text.index(start, offsetBy: nsText.substring(with: match.range).count, limitedBy: text.endIndex) ?? text.endIndex
            let title = String(text[start..<titleEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            let content = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            chapters.append(Chapter(title: title, index: i, isDownloaded: true))
            contents.append(content)
        }
        return (chapters, contents)
    }

    private func splitByLength(text: String, chunkSize: Int = 2000) -> ([Chapter], [String]) {
        let chars = Array(text)
        var chapters: [Chapter] = []
        var contents: [String] = []
        var index = 0
        var chapterIndex = 0
        while index < chars.count {
            let end = min(index + chunkSize, chars.count)
            let content = String(chars[index..<end])
            chapters.append(Chapter(title: "第 \(chapterIndex + 1) 段", index: chapterIndex, isDownloaded: true))
            contents.append(content)
            index = end
            chapterIndex += 1
        }
        return (chapters, contents)
    }
}

// MARK: - Book Card

struct BookCard: View {
    let book: Book

    var body: some View {
        VStack(spacing: 8) {
            BookCoverView(
                coverURL: book.coverURL,
                title: book.title,
                size: CGSize(width: 100, height: 140)
            )
            Text(book.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
            Text(book.author)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
