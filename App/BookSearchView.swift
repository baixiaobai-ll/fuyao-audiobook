import SwiftUI

struct BookSearchView: View {
    @EnvironmentObject var store: BookshelfStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var keyword = ""
    @State private var categoryBooks: [BookSearchResult] = []
    @State private var searchResults: [BookSearchResult] = []
    @State private var rankingBooks: [BookSearchResult] = []
    @State private var isLoading = false
    @State private var selectedCategory = BookSourceEngine.categoryPaths[0].name
    @State private var errorMessage: String? = nil
    @State private var searchToken = UUID()

    private let engine = BookSourceEngine()
    private let cache = BookSourceCache()
    private let pageBlue = Color(red: 0.52, green: 0.76, blue: 0.98)
    private let pagePurple = Color(red: 0.66, green: 0.54, blue: 0.96)
    private let pageIndigo = Color(red: 0.35, green: 0.45, blue: 0.82)

    private var isSearching: Bool {
        !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                discoverBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        searchBar

                        if isSearching {
                            searchResultsSection
                        } else {
                            categoryTabs
                            discoverSections
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.large)
            .tint(pageIndigo)
            .onAppear {
                loadRanking()
                let first = BookSourceEngine.categoryPaths[0]
                loadCategory(first)
            }
            .onReceive(Timer.publish(every: 20 * 60, on: .main, in: .common).autoconnect()) { _ in
                guard scenePhase == .active, !isSearching else { return }
                Task { await silentRefreshDiscover() }
            }
        }
    }

    private var discoverBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color(red: 0.92, green: 0.95, blue: 1.0),
                Color(red: 0.99, green: 0.99, blue: 1.0),
                Color.white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(pagePurple.opacity(0.18))
                .frame(width: 250, height: 250)
                .blur(radius: 24)
                .offset(x: 80, y: -56)
        }
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(pageBlue.opacity(0.14))
                .frame(width: 200, height: 200)
                .blur(radius: 20)
                .offset(x: -72, y: -74)
        }
        .ignoresSafeArea()
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        SurfaceCard(padding: 12) {
            HStack(spacing: 12) {
                TintedIconBadge(icon: "magnifyingglass", size: 34, iconSize: 13, primary: pageBlue, secondary: pagePurple)

                TextField("搜索书名、作者或关键词...", text: $keyword)
                    .submitLabel(.search)
                    .onSubmit { searchByKeyword() }
                    .onChange(of: keyword) { newValue in
                        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            searchResults = []
                            errorMessage = nil
                        }
                    }

                if !keyword.isEmpty {
                    Button(action: { keyword = ""; searchResults = []; errorMessage = nil }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(pagePurple)
                    }
                }
            }
        }
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(BookSourceEngine.categoryPaths, id: \.name) { cat in
                    Button(action: { loadCategory(cat) }) {
                        Text(cat.name)
                            .font(.subheadline.weight(selectedCategory == cat.name ? .semibold : .medium))
                            .foregroundStyle(selectedCategory == cat.name ? Color.white : AppTheme.Colors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Group {
                                    if selectedCategory == cat.name {
                                        LinearGradient(
                                            colors: [pageBlue, pagePurple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    } else {
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.72), pagePurple.opacity(0.10)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    }
                                }
                            )
                            .clipShape(Capsule(style: .continuous))
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(selectedCategory == cat.name ? 0.18 : 0.74), lineWidth: 1)
                            )
                    }
                    .buttonStyle(LiftPressButtonStyle(scale: 0.98))
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var discoverSections: some View {
        if isLoading && categoryBooks.isEmpty && rankingBooks.isEmpty {
            loadingCard(text: "正在整理今晚推荐…")
        } else if let err = errorMessage, categoryBooks.isEmpty, rankingBooks.isEmpty {
            messageCard(icon: "wifi.exclamationmark", title: "发现页暂时没刷出来", message: err)
        } else {
            if !rankingBooks.isEmpty {
                rankingSection
            }
            categoryListSection
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        if isLoading {
            loadingCard(text: "正在搜索相关书籍…")
        } else if let err = errorMessage {
            messageCard(icon: "magnifyingglass.circle", title: "这次没有搜到结果", message: err)
        } else if searchResults.isEmpty {
            messageCard(icon: "book.closed", title: "还没有搜索结果", message: "输入书名或作者后回车搜索，我们会把相关内容列在这里。")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SoftSectionHeader(
                    title: "搜索结果",
                    subtitle: "共找到 \(searchResults.count) 本相关书籍"
                )

                LazyVStack(spacing: 12) {
                    ForEach(searchResults, id: \.bookId) { result in
                        NavigationLink(destination: bookDetailDestination(result)) {
                            discoverResultCard(result, compact: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Ranking Section

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SoftSectionHeader(
                title: "热门排行",
                subtitle: "今晚最常被点开的内容，适合快速开听"
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(rankingBooks.enumerated()), id: \.element.bookId) { index, result in
                        NavigationLink(destination: bookDetailDestination(result)) {
                            VStack(alignment: .leading, spacing: 10) {
                                ZStack(alignment: .topLeading) {
                                    BookCoverView(
                                        coverURL: result.coverURL,
                                        title: result.title,
                                        size: CGSize(width: 112, height: 150)
                                    )

                                    Text("#\(index + 1)")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            LinearGradient(
                                                colors: [pageBlue, pagePurple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            in: Capsule(style: .continuous)
                                        )
                                        .padding(8)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                        .lineLimit(2)
                                    Text(result.author)
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(width: 118, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Category List Section

    private var categoryListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SoftSectionHeader(
                title: "分类推荐",
                subtitle: selectedCategory + " 分类下的推荐内容"
            )

            if categoryBooks.isEmpty && !isLoading {
                messageCard(icon: "books.vertical", title: "这个分类暂时没有内容", message: "可以先切换其他分类，或者直接搜索想听的书名。")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(categoryBooks, id: \.bookId) { result in
                        NavigationLink(destination: bookDetailDestination(result)) {
                            discoverResultCard(result, compact: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .refreshable {
            await refreshDiscoverPull()
        }
    }

    private func discoverResultCard(_ result: BookSearchResult, compact: Bool) -> some View {
        let isInShelf = store.containsSameBook(as: discoverBook(for: result))

        return SurfaceCard(padding: 14) {
            HStack(alignment: .top, spacing: 14) {
                BookCoverView(
                    coverURL: result.coverURL,
                    title: result.title,
                    size: compact ? CGSize(width: 66, height: 90) : CGSize(width: 72, height: 98)
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(result.title)
                                .font(.headline)
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                                .lineLimit(2)
                            Text(result.author)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)

                        if isInShelf {
                            CapsuleInfoTag(title: "已在书架", icon: "books.vertical.fill", tint: pagePurple)
                        }
                    }

                    if !result.intro.isEmpty {
                        Text(result.intro)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .lineLimit(compact ? 2 : 3)
                    }

                    HStack(spacing: 8) {
                        CapsuleInfoTag(
                            title: isInShelf ? "可继续收听" : "加入书架",
                            icon: isInShelf ? "headphones" : "books.vertical.fill",
                            tint: pageBlue
                        )
                        CapsuleInfoTag(title: compact ? "去详情页查看" : "轻点进入详情", icon: "arrow.right.circle", tint: pagePurple)
                    }
                }
            }
        }
    }

    private func loadingCard(text: String) -> some View {
        SurfaceCard {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(pageIndigo)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    private func messageCard(icon: String, title: String, message: String) -> some View {
        SurfaceCard {
            VStack(spacing: 14) {
                TintedIconBadge(icon: icon, primary: pageBlue, secondary: pagePurple)
                VStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func discoverBook(for result: BookSearchResult) -> Book {
        Book(
            title: result.title,
            author: result.author,
            coverURL: result.coverURL,
            sourceURL: result.bookURL,
            bookId: result.bookId,
            source: .biquge
        )
    }

    private func bookDetailDestination(_ result: BookSearchResult) -> BookDetailView {
        BookDetailView(book: discoverBook(for: result))
    }

    // MARK: - Data Loading

    private func loadRanking() {
        let key = BookSourceCache.rankingKey
        if let cached = cache.retrieve(forKey: key) {
            rankingBooks = cached.books
            if cached.isStale {
                Task { await refreshRankingFromNetwork() }
            }
        } else {
            Task { await refreshRankingFromNetwork() }
        }
    }

    @MainActor
    private func refreshRankingFromNetwork() async {
        if let remote = await DiscoverAPIClient.fetchRanking(), !remote.isEmpty {
            cache.store(remote, forKey: BookSourceCache.rankingKey)
            rankingBooks = remote
            return
        }
        guard let results = try? await engine.fetchRanking(), !results.isEmpty else { return }
        cache.store(results, forKey: BookSourceCache.rankingKey)
        rankingBooks = results
    }

    private func loadCategory(_ cat: (name: String, sort: String)) {
        selectedCategory = cat.name
        errorMessage = nil

        let key = BookSourceCache.categoryKey(cat.sort)
        if let cached = cache.retrieve(forKey: key) {
            categoryBooks = cached.books
            isLoading = false
            if cached.isStale {
                Task { await refreshCategoryFromNetwork(cat) }
            }
        } else {
            categoryBooks = []
            isLoading = true
            Task { await refreshCategoryFromNetwork(cat) }
        }
    }

    @MainActor
    private func refreshCategoryFromNetwork(_ cat: (name: String, sort: String)) async {
        if let remote = await DiscoverAPIClient.fetchCategory(sort: cat.sort), !remote.isEmpty {
            cache.store(remote, forKey: BookSourceCache.categoryKey(cat.sort))
            if selectedCategory == cat.name {
                categoryBooks = remote
                errorMessage = remote.isEmpty ? "暂无书籍" : nil
            }
            if selectedCategory == cat.name { isLoading = false }
            return
        }
        do {
            let results = try await engine.fetchCategory(sort: cat.sort)
            cache.store(results, forKey: BookSourceCache.categoryKey(cat.sort))
            guard selectedCategory == cat.name else { return }
            categoryBooks = results
            errorMessage = results.isEmpty ? "暂无书籍" : nil
        } catch {
            guard selectedCategory == cat.name, categoryBooks.isEmpty else {
                if selectedCategory == cat.name { isLoading = false }
                return
            }
            errorMessage = "加载失败: \(error.localizedDescription)"
        }
        if selectedCategory == cat.name { isLoading = false }
    }

    private func refreshDiscoverPull() async {
        await refreshRankingFromNetwork()
        if let cat = BookSourceEngine.categoryPaths.first(where: { $0.name == selectedCategory }) {
            await refreshCategoryFromNetwork(cat)
        }
    }

    private func silentRefreshDiscover() async {
        await refreshRankingFromNetwork()
        if let cat = BookSourceEngine.categoryPaths.first(where: { $0.name == selectedCategory }) {
            await refreshCategoryFromNetwork(cat)
        }
    }

    // MARK: - Search

    private func searchByKeyword() {
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }

        searchToken = UUID()
        let token = searchToken
        isLoading = true
        errorMessage = nil
        searchResults = []

        Task {
            let results: [BookSearchResult]
            let usedFallback: Bool

            do {
                results = try await engine.search(keyword: kw)
                usedFallback = false
            } catch {
                results = await fallbackSearchResults(for: kw)
                usedFallback = true
            }

            await MainActor.run {
                guard searchToken == token, keyword.trimmingCharacters(in: .whitespaces) == kw else { return }

                searchResults = deduplicated(results)
                if searchResults.isEmpty {
                    errorMessage = usedFallback
                        ? "未找到\"\(kw)\"相关书籍"
                        : "没有搜索到\"\(kw)\"相关书籍"
                } else if usedFallback {
                    errorMessage = "当前已切换为本地缓存搜索，结果可能不完整"
                }
                isLoading = false
            }
        }
    }

    private func deduplicated(_ results: [BookSearchResult]) -> [BookSearchResult] {
        var seen = Set<String>()
        return results.filter { result in
            let normalizedTitle = normalizedDiscoverText(result.title)
            let normalizedAuthor = normalizedDiscoverText(result.author)
            let normalizedBookId = result.bookId.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedBookId.isEmpty || normalizedBookId == "0"
                ? "\(normalizedTitle)|\(normalizedAuthor)"
                : "\(normalizedBookId)|\(normalizedTitle)|\(normalizedAuthor)"
            return seen.insert(key).inserted
        }
    }

    private func normalizedDiscoverText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private func fallbackSearchResults(for keyword: String) async -> [BookSearchResult] {
        var all: [BookSearchResult] = []

        for cat in BookSourceEngine.categoryPaths {
            let key = BookSourceCache.categoryKey(cat.sort)
            if let cached = cache.retrieve(forKey: key), !cached.isStale {
                all.append(contentsOf: cached.books)
                continue
            }

            if let remote = await DiscoverAPIClient.fetchCategory(sort: cat.sort), !remote.isEmpty {
                cache.store(remote, forKey: key)
                all.append(contentsOf: remote)
                continue
            }

            if let results = try? await engine.fetchCategory(sort: cat.sort) {
                cache.store(results, forKey: key)
                all.append(contentsOf: results)
            }
        }

        let lower = keyword.lowercased()
        return deduplicated(all).filter {
            $0.title.lowercased().contains(lower)
                || $0.author.lowercased().contains(lower)
                || $0.intro.lowercased().contains(lower)
        }
    }
}
