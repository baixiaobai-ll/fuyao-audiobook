import SwiftUI
import UniformTypeIdentifiers

struct BookshelfView: View {
    @EnvironmentObject var store: BookshelfStore
    @State private var showFileImporter = false
    @State private var importError: String? = nil
    @State private var selectedBook: Book? = nil
    @State private var isEditingShelf = false
    @State private var showImportMenu = false

    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 188), spacing: 16)]
    private let actionBlue = Color(red: 0.43, green: 0.66, blue: 0.97)
    private let actionPurple = Color(red: 0.62, green: 0.49, blue: 0.95)

    private var localBookCount: Int {
        store.books.filter { $0.source == .local }.count
    }

    private var onlineBookCount: Int {
        store.books.count - localBookCount
    }

    var body: some View {
        NavigationStack {
            ZStack {
                bookshelfBackground

                if showImportMenu {
                    Color.black.opacity(0.001)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                showImportMenu = false
                            }
                        }
                }

                Group {
                    if store.books.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                shelfSummaryCard
                                shelfSectionHeader

                                LazyVGrid(columns: columns, spacing: 18) {
                                    ForEach(store.books) { book in
                                        bookshelfCard(for: book)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 24)
                        }
                    }
                }

                if showImportMenu {
                    VStack {
                        HStack {
                            Spacer()
                            bookshelfImportPopover
                        }
                        Spacer()
                    }
                    .padding(.top, 176)
                    .padding(.trailing, 16)
                    .zIndex(3)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .topTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.96, anchor: .topTrailing).combined(with: .opacity)
                    ))
                }
            }
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: Binding(
                get: { selectedBook != nil },
                set: { if !$0 { selectedBook = nil } }
            )) {
                if let book = selectedBook {
                    BookDetailView(book: book)
                }
            }
            .toolbar {
                if isEditingShelf {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("完成") {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                isEditingShelf = false
                            }
                        }
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

    private var bookshelfBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.94, green: 0.96, blue: 1.0),
                Color(red: 0.90, green: 0.93, blue: 1.0),
                Color(red: 0.97, green: 0.97, blue: 1.0),
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color(red: 0.66, green: 0.72, blue: 0.98).opacity(0.22))
                .frame(width: 240, height: 240)
                .blur(radius: 18)
                .offset(x: 88, y: -48)
        }
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(Color(red: 0.58, green: 0.84, blue: 1.0).opacity(0.16))
                .frame(width: 190, height: 190)
                .blur(radius: 20)
                .offset(x: -70, y: -60)
        }
        .ignoresSafeArea()
    }

    private var shelfSummaryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    shelfMetricCard(
                        title: "本地导入",
                        value: "\(localBookCount)",
                        tint: AppTheme.Colors.brandPrimary
                    ) {
                        metricAssetIcon("bookshelf_metric_local")
                    }
                    shelfMetricCard(
                        title: "在线书籍",
                        value: "\(onlineBookCount)",
                        tint: AppTheme.Colors.brandAccent
                    ) {
                        metricAssetIcon("bookshelf_metric_online")
                    }
                }
            }
        }
    }

    private var shelfSectionHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("书籍列表")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(isEditingShelf ? "轻点右上角的红色按钮移除书籍" : "轻点封面进入详情，长按书籍进入整理模式")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    showImportMenu.toggle()
                }
            } label: {
                Image("bookshelf_import_action")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .shadow(color: Color(red: 0.48, green: 0.54, blue: 0.92).opacity(0.14), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(LiftPressButtonStyle(scale: 0.94))
        }
        .padding(.horizontal, 2)
    }

    private func bookshelfImportMenuItem(title: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [actionBlue, actionPurple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)

                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
    }

    private var bookshelfImportPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            bookshelfImportActionButton(title: "选择文件", systemImage: "doc.badge.plus") {
                showImportMenu = false
                showFileImporter = true
            }

            bookshelfImportActionButton(title: "扫描本地文件", systemImage: "folder.badge.plus") {
                showImportMenu = false
                importFromDocuments()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    LinearGradient(
                        colors: [
                            actionBlue.opacity(0.14),
                            actionPurple.opacity(0.16),
                            Color.white.opacity(0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 1)
                )
        )
        .shadow(color: actionPurple.opacity(0.16), radius: 16, x: 0, y: 10)
        .frame(width: 172)
    }

    private func bookshelfImportActionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [actionBlue, actionPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.48))
            )
        }
        .buttonStyle(LiftPressButtonStyle(scale: 0.97))
    }

    @ViewBuilder
    private func bookshelfCard(for book: Book) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                guard !isEditingShelf else { return }
                selectedBook = book
            } label: {
                BookCard(book: book, isEditing: isEditingShelf)
            }
            .buttonStyle(LiftPressButtonStyle(scale: 0.98))
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        isEditingShelf = true
                    }
                }
            )

            if isEditingShelf {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.removeBook(id: book.id)
                        if store.books.count <= 1 {
                            isEditingShelf = false
                        }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.red.gradient)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                                )
                        )
                        .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 4)
                }
                .offset(x: 8, y: -8)
                .buttonStyle(LiftPressButtonStyle(scale: 0.9))
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("empty_bookshelf")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 190)

                VStack(spacing: 18) {
                    Text("书架空空如也")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    ViewThatFits {
                        HStack(spacing: 12) {
                            GlassIconButton(title: "导入文件", icon: "doc.badge.plus") {
                                showFileImporter = true
                            }

                            GlassIconButton(title: "智能扫描", icon: "doc.viewfinder") {
                                importFromDocuments()
                            }
                        }

                        VStack(spacing: 12) {
                            GlassIconButton(title: "导入文件", icon: "doc.badge.plus") {
                                showFileImporter = true
                            }

                            GlassIconButton(title: "智能扫描", icon: "doc.viewfinder") {
                                importFromDocuments()
                            }
                        }
                    }
                }

                SurfaceCard {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.title3)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [actionBlue, actionPurple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("小提示")
                                .font(.subheadline.bold())
                            Text("点击下方导入按钮，或在“发现”页搜索想听的故事。")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private func shelfMetricCard<Icon: View>(
        title: String,
        value: String,
        tint: Color,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 10) {
            icon()

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 1)
                )
        )
    }

    private func metricAssetIcon(_ assetName: String) -> some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: 38, height: 38)
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
    var isEditing: Bool = false
    @State private var wiggle = false
    private let progressBlue = Color(red: 0.49, green: 0.72, blue: 0.97)
    private let progressPurple = Color(red: 0.66, green: 0.54, blue: 0.95)
    private let progressIndigo = Color(red: 0.38, green: 0.46, blue: 0.84)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BookCoverView(
                coverURL: book.coverURL,
                title: book.title,
                size: CGSize(width: 116, height: 158)
            )
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: progressIconName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [progressBlue, progressPurple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(progressText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        progressBlue.opacity(0.14),
                                        progressPurple.opacity(0.14),
                                        Color.white.opacity(0.30)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        progressBlue.opacity(0.92),
                                        progressPurple.opacity(0.84),
                                        progressIndigo.opacity(0.78)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geometry.size.width * progressFraction, progressFraction > 0 ? 16 : 0))
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 82, maxHeight: 82, alignment: .top)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 276, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(isEditing ? 0.82 : 0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(isEditing ? AppTheme.Colors.brandAccent.opacity(0.34) : Color.white.opacity(0.78), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
        .frame(maxWidth: .infinity)
        .rotationEffect(.degrees(isEditing ? (wiggle ? 1.8 : -1.8) : 0))
        .animation(
            isEditing
                ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true)
                : .default,
            value: wiggle
        )
        .onAppear {
            if isEditing {
                wiggle = true
            }
        }
        .onChange(of: isEditing) { editing in
            wiggle = editing
        }
    }

    private var hasStartedPlayback: Bool {
        !book.chapters.isEmpty && book.lastReadChapter > 0
    }

    private var progressFraction: CGFloat {
        guard !book.chapters.isEmpty else { return 0.18 }
        let denominator = max(book.chapters.count, 1)
        let progress = CGFloat(min(max(book.lastReadChapter + 1, 1), denominator)) / CGFloat(denominator)
        return min(max(progress, 0.12), 1)
    }

    private var progressText: String {
        if !book.chapters.isEmpty {
            let chapterIndex = min(max(book.lastReadChapter + 1, 1), book.chapters.count)
            if book.lastReadChapter > 0 {
                return "听到第 \(chapterIndex) 章"
            }
            return "\(book.chapters.count) 章可播放"
        }
        return book.source == .local ? "等待开始收听" : "进入详情查看章节"
    }

    private var progressIconName: String {
        if !book.chapters.isEmpty, book.lastReadChapter > 0 {
            return "headphones"
        }
        return "sparkles"
    }
}
