import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

private struct LocalTXTScanCandidate: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let title: String
    let folderPath: String
    let sizeText: String
}

private enum LocalImportMode {
    case file
    case folder
}

struct BookshelfView: View {
    @EnvironmentObject var store: BookshelfStore
    @State private var showLocalImporter = false
    @State private var localImportMode: LocalImportMode = .file
    @State private var showScanSelectionSheet = false
    @State private var importError: String? = nil
    @State private var selectedBook: Book? = nil
    @State private var isEditingShelf = false
    @State private var showImportMenu = false
    @State private var scannedTXTFiles: [LocalTXTScanCandidate] = []
    @State private var selectedScanFileIDs: Set<UUID> = []
    @State private var scopedScanFolderURL: URL? = nil
    @State private var hasActiveScanFolderAccess = false
    @State private var isImportingScannedFiles = false

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
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isEditingShelf {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                isEditingShelf = false
                            }
                        }
                    }

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
                            .background(
                                // 透明兜底层：仅在子按钮（书籍、X 角标、导入入口）未消费的"留白"区域接管点击。
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isEditingShelf {
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                                isEditingShelf = false
                                            }
                                        }
                                    }
                            )
                        }
                        .scrollIndicators(.hidden)
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
            .fileImporter(
                isPresented: $showLocalImporter,
                allowedContentTypes: localImportMode == .file ? [UTType.plainText] : [UTType.folder],
                allowsMultipleSelection: false
            ) { result in
                switch localImportMode {
                case .file:
                    handleFileImport(result)
                case .folder:
                    handleFolderScan(result)
                }
            }
            .sheet(isPresented: $showScanSelectionSheet, onDismiss: releaseScannedFolderAccess) {
                scanSelectionSheet
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
                Text(isEditingShelf ? "轻点角标移除书籍，点击其他区域退出整理" : "轻点封面进入详情，长按书籍进入整理模式")
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
                presentLocalImporter(.file)
            }

            bookshelfImportActionButton(title: "扫描本地文件", systemImage: "folder.badge.plus") {
                showImportMenu = false
                presentLocalImporter(.folder)
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
                // 整理模式下书籍卡片本身不响应——避免长按结束、手指抬起时
                // 被 SwiftUI 误判为一次 tap 而立刻退出整理模式。
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
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
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
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(Color(red: 0.94, green: 0.42, blue: 0.45).opacity(0.92))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.85), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.10), radius: 3, x: 0, y: 1.5)
                }
                .offset(x: 4, y: -4)
                .buttonStyle(LiftPressButtonStyle(scale: 0.9))
                .accessibilityLabel("移除《\(book.title)》")
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("empty_bookshelf")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 214)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)

                VStack(spacing: 18) {
                    Text("书架空空如也")
                        .font(.title3.bold())
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    ViewThatFits {
                        HStack(spacing: 12) {
                            GlassIconButton(title: "导入文件", icon: "doc.badge.plus") {
                                presentLocalImporter(.file)
                            }

                            GlassIconButton(title: "智能扫描", icon: "doc.viewfinder") {
                                presentLocalImporter(.folder)
                            }
                        }

                        VStack(spacing: 12) {
                            GlassIconButton(title: "导入文件", icon: "doc.badge.plus") {
                                presentLocalImporter(.file)
                            }

                            GlassIconButton(title: "智能扫描", icon: "doc.viewfinder") {
                                presentLocalImporter(.folder)
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
                            Text("可以选择单个 TXT，也可以授权一个文件夹后批量扫描并勾选导入。")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .scrollIndicators(.hidden)
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

    private func presentLocalImporter(_ mode: LocalImportMode) {
        localImportMode = mode
        DispatchQueue.main.async {
            showLocalImporter = true
        }
    }

    private var scanSelectionSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if scannedTXTFiles.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundStyle(actionPurple)
                        Text("没有找到 TXT 文件")
                            .font(.headline)
                        Text("可以返回重新选择一个包含小说文件的文件夹。")
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(28)
                    Spacer()
                } else {
                    List(scannedTXTFiles) { file in
                        Button {
                            toggleScannedFile(file)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedScanFileIDs.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 21, weight: .semibold))
                                    .foregroundStyle(selectedScanFileIDs.contains(file.id) ? actionPurple : AppTheme.Colors.textSecondary.opacity(0.55))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                        .lineLimit(2)
                                    Text(file.folderPath)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .lineLimit(1)
                                    Text(file.sizeText)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(actionPurple)
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .safeAreaInset(edge: .bottom) {
                        VStack(spacing: 10) {
                            HStack {
                                Button(selectedScanFileIDs.count == scannedTXTFiles.count ? "取消全选" : "全选") {
                                    if selectedScanFileIDs.count == scannedTXTFiles.count {
                                        selectedScanFileIDs.removeAll()
                                    } else {
                                        selectedScanFileIDs = Set(scannedTXTFiles.map(\.id))
                                    }
                                }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(actionPurple)

                                Spacer()

                                Text("已选 \(selectedScanFileIDs.count)/\(scannedTXTFiles.count)")
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }

                            Button {
                                importSelectedScannedFiles()
                            } label: {
                                HStack(spacing: 8) {
                                    if isImportingScannedFiles {
                                        ProgressView()
                                            .tint(.white)
                                    }
                                    Text(isImportingScannedFiles ? "正在导入..." : "导入选中的 TXT")
                                        .font(.headline)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(
                                    LinearGradient(
                                        colors: [actionBlue, actionPurple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .disabled(selectedScanFileIDs.isEmpty || isImportingScannedFiles)
                            .opacity(selectedScanFileIDs.isEmpty ? 0.55 : 1)
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                    }
                }
            }
            .navigationTitle("扫描到的 TXT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showScanSelectionSheet = false
                    }
                    .disabled(isImportingScannedFiles)
                }
            }
        }
    }

    private func toggleScannedFile(_ file: LocalTXTScanCandidate) {
        if selectedScanFileIDs.contains(file.id) {
            selectedScanFileIDs.remove(file.id)
        } else {
            selectedScanFileIDs.insert(file.id)
        }
    }

    private func handleFolderScan(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let folderURL = urls.first else { return }
            scanTXTFiles(in: folderURL)
        }
    }

    private func scanTXTFiles(in folderURL: URL) {
        releaseScannedFolderAccess()

        let didAccess = folderURL.startAccessingSecurityScopedResource()
        scopedScanFolderURL = folderURL
        hasActiveScanFolderAccess = didAccess

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            releaseScannedFolderAccess()
            importError = "无法读取所选文件夹"
            return
        }

        var results: [LocalTXTScanCandidate] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == "txt" else { continue }
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile != false else { continue }

            results.append(
                LocalTXTScanCandidate(
                    url: fileURL,
                    title: fileURL.deletingPathExtension().lastPathComponent,
                    folderPath: relativeFolderPath(for: fileURL, root: folderURL),
                    sizeText: formattedFileSize(values?.fileSize ?? 0)
                )
            )

            if results.count >= 500 { break }
        }

        scannedTXTFiles = results.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        selectedScanFileIDs = Set(scannedTXTFiles.map(\.id))

        if scannedTXTFiles.isEmpty {
            releaseScannedFolderAccess()
            importError = "所选文件夹中没有找到 TXT 文件"
        } else {
            showScanSelectionSheet = true
        }
    }

    private func importSelectedScannedFiles() {
        let selectedFiles = scannedTXTFiles.filter { selectedScanFileIDs.contains($0.id) }
        guard !selectedFiles.isEmpty, !isImportingScannedFiles else { return }
        isImportingScannedFiles = true

        Task {
            var failedTitles: [String] = []
            for file in selectedFiles {
                do {
                    try await importTXTBook(url: file.url, accessSecurityScope: false)
                } catch {
                    failedTitles.append(file.title)
                }
            }

            await MainActor.run {
                isImportingScannedFiles = false
                showScanSelectionSheet = false
                releaseScannedFolderAccess()
                if !failedTitles.isEmpty {
                    importError = "以下文件导入失败：\(failedTitles.prefix(3).joined(separator: "、"))"
                }
            }
        }
    }

    private func releaseScannedFolderAccess() {
        if hasActiveScanFolderAccess {
            scopedScanFolderURL?.stopAccessingSecurityScopedResource()
        }
        scopedScanFolderURL = nil
        hasActiveScanFolderAccess = false
        if !showScanSelectionSheet {
            scannedTXTFiles = []
            selectedScanFileIDs = []
        }
    }

    private func relativeFolderPath(for fileURL: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let parentPath = fileURL.deletingLastPathComponent().standardizedFileURL.path
        guard parentPath.hasPrefix(rootPath) else {
            return fileURL.deletingLastPathComponent().lastPathComponent
        }
        let suffix = parentPath.dropFirst(rootPath.count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return suffix.isEmpty ? root.lastPathComponent : "\(root.lastPathComponent)/\(suffix)"
    }

    private func formattedFileSize(_ bytes: Int) -> String {
        guard bytes > 0 else { return "未知大小" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
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
                try await importTXTBook(url: url, accessSecurityScope: true)
            } catch {
                importError = "导入失败: \(error.localizedDescription)"
            }
        }
    }

    private func importTXTBook(url: URL, accessSecurityScope: Bool) async throws {
        var didAccess = false
        if accessSecurityScope {
            didAccess = url.startAccessingSecurityScopedResource()
            guard didAccess else {
                throw CocoaError(.fileReadNoPermission)
            }
        }
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

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
        await MainActor.run {
            store.addBook(bookWithChapters)
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
