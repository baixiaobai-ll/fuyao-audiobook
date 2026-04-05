import SwiftUI

struct BookSearchView: View {
    @EnvironmentObject var store: BookshelfStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var keyword = ""
    @State private var categoryBooks: [BookSearchResult] = []
    @State private var searchResults: [BookSearchResult] = []
    @State private var rankingBooks: [BookSearchResult] = []
    @State private var isDiscoverLoading = false
    @State private var isSearchLoading = false
    @State private var selectedCategory = BookSourceEngine.categoryPaths[0].name
    @State private var discoverErrorMessage: String? = nil
    @State private var searchErrorMessage: String? = nil
    @State private var searchNoticeMessage: String? = nil
    @State private var searchToken = UUID()
    @State private var didLoadInitialDiscover = false
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    private let engine = BookSourceEngine()
    private let cache = BookSourceCache()

    private var isSearching: Bool {
        !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar

                if isSearching {
                    bookList
                } else {
                    categoryTabs

                    if isDiscoverLoading && categoryBooks.isEmpty && rankingBooks.isEmpty {
                        Spacer()
                        ProgressView().padding()
                        Spacer()
                    } else if let err = discoverErrorMessage, categoryBooks.isEmpty, rankingBooks.isEmpty {
                        Spacer()
                        Text(err).foregroundColor(.red).font(.footnote).padding()
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if !rankingBooks.isEmpty {
                                    rankingSection
                                }
                                categoryListSection
                            }
                        }
                        .refreshable {
                            await refreshDiscoverPull()
                        }
                    }
                }
            }
            .navigationTitle("发现")
            .onAppear {
                guard !didLoadInitialDiscover else { return }
                didLoadInitialDiscover = true
                loadInitialDiscover()
            }
            .onReceive(Timer.publish(every: 20 * 60, on: .main, in: .common).autoconnect()) { _ in
                guard scenePhase == .active, !isSearching else { return }
                Task { await silentRefreshDiscover() }
            }
            .onDisappear {
                searchDebounceTask?.cancel()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("搜索书名...", text: $keyword)
                .submitLabel(.search)
                .onSubmit {
                    searchDebounceTask?.cancel()
                    searchByKeyword(immediateKeyword: keyword)
                }
                .onChange(of: keyword) { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        searchDebounceTask?.cancel()
                        searchResults = []
                        isSearchLoading = false
                        searchErrorMessage = nil
                        searchNoticeMessage = nil
                        searchToken = UUID()
                        return
                    }

                    searchDebounceTask?.cancel()
                    searchDebounceTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            searchByKeyword(immediateKeyword: trimmed)
                        }
                    }
                }
            if !keyword.isEmpty {
                Button(action: {
                    searchDebounceTask?.cancel()
                    keyword = ""
                    searchResults = []
                    isSearchLoading = false
                    searchErrorMessage = nil
                    searchNoticeMessage = nil
                }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding([.horizontal, .top])
    }

    // MARK: - Category Tabs

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BookSourceEngine.categoryPaths, id: \.name) { cat in
                    Button(action: { loadCategory(cat) }) {
                        Text(cat.name)
                            .font(.subheadline)
                            .fontWeight(selectedCategory == cat.name ? .bold : .regular)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(selectedCategory == cat.name ? Color.accentColor : Color(.systemGray6))
                            .foregroundColor(selectedCategory == cat.name ? .white : .primary)
                            .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Ranking Section

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("热门排行")
                .font(.title3.bold())
                .padding(.horizontal)
                .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(rankingBooks, id: \.bookId) { result in
                        NavigationLink(destination: bookDetailDestination(result)) {
                            VStack(spacing: 6) {
                                BookCoverView(
                                    coverURL: result.coverURL,
                                    title: result.title,
                                    size: CGSize(width: 80, height: 110)
                                )
                                Text(result.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.primary)
                                    .frame(width: 80)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }

            Divider().padding(.horizontal)
        }
    }

    // MARK: - Category List Section

    private var categoryListSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("分类推荐")
                .font(.title3.bold())
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ForEach(categoryBooks, id: \.bookId) { result in
                NavigationLink(destination: bookDetailDestination(result)) {
                    bookRow(result)
                }
                Divider().padding(.leading, 84)
            }
        }
    }

    // MARK: - Book List (search results)

    private var bookList: some View {
        Group {
            if isSearchLoading && searchResults.isEmpty {
                Spacer()
                ProgressView().padding()
                Spacer()
            } else if let err = searchErrorMessage {
                Spacer()
                Text(err).foregroundColor(.red).font(.footnote).padding()
                Spacer()
            } else {
                VStack(spacing: 0) {
                    if let notice = searchNoticeMessage, !notice.isEmpty {
                        HStack(spacing: 8) {
                            if isSearchLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                            }
                            Text(notice)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }

                    List(searchResults, id: \.bookId) { result in
                        NavigationLink(destination: bookDetailDestination(result)) {
                            bookRow(result)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    // MARK: - Book Row

    private func bookRow(_ result: BookSearchResult) -> some View {
        HStack(spacing: 12) {
            BookCoverView(
                coverURL: result.coverURL,
                title: result.title,
                size: CGSize(width: 60, height: 80)
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Text(result.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if !result.intro.isEmpty {
                    Text(result.intro)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func bookDetailDestination(_ result: BookSearchResult) -> BookDetailView {
        let normalizedBookId = BookSourceEngine.normalizedBookId(from: result.bookId, bookURL: result.bookURL)
        let book = Book(
            title: result.title,
            author: result.author,
            coverURL: result.coverURL,
            sourceURL: BookSourceEngine.normalizedBookURL(from: result.bookURL, bookId: normalizedBookId),
            bookId: normalizedBookId,
            source: .biquge
        )
        return BookDetailView(book: store.existingBook(matching: book) ?? book)
    }

    // MARK: - Data Loading

    private func loadInitialDiscover() {
        let first = BookSourceEngine.categoryPaths[0]
        selectedCategory = first.name
        loadRanking()
        loadCategory(first)
    }

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
            let normalized = normalized(remote)
            cache.store(normalized, forKey: BookSourceCache.rankingKey)
            rankingBooks = normalized
            return
        }
        guard let results = try? await engine.fetchRanking(), !results.isEmpty else { return }
        let normalized = normalized(results)
        cache.store(normalized, forKey: BookSourceCache.rankingKey)
        rankingBooks = normalized
    }

    private func loadCategory(_ cat: (name: String, sort: String)) {
        selectedCategory = cat.name
        discoverErrorMessage = nil

        let key = BookSourceCache.categoryKey(cat.sort)
        if let cached = cache.retrieve(forKey: key) {
            categoryBooks = cached.books
            isDiscoverLoading = false
            if cached.isStale {
                Task { await refreshCategoryFromNetwork(cat) }
            }
        } else {
            categoryBooks = []
            isDiscoverLoading = true
            Task { await refreshCategoryFromNetwork(cat) }
        }
    }

    @MainActor
    private func refreshCategoryFromNetwork(_ cat: (name: String, sort: String)) async {
        if let remote = await DiscoverAPIClient.fetchCategory(sort: cat.sort), !remote.isEmpty {
            let normalized = normalized(remote)
            cache.store(normalized, forKey: BookSourceCache.categoryKey(cat.sort))
            if selectedCategory == cat.name {
                categoryBooks = normalized
                discoverErrorMessage = nil
            }
            if selectedCategory == cat.name { isDiscoverLoading = false }
            return
        }
        do {
            let results = normalized(try await engine.fetchCategory(sort: cat.sort))
            cache.store(results, forKey: BookSourceCache.categoryKey(cat.sort))
            guard selectedCategory == cat.name else { return }
            categoryBooks = results
            discoverErrorMessage = results.isEmpty ? "暂无书籍" : nil
        } catch {
            guard selectedCategory == cat.name, categoryBooks.isEmpty else {
                if selectedCategory == cat.name { isDiscoverLoading = false }
                return
            }
            discoverErrorMessage = "加载失败: \(error.localizedDescription)"
        }
        if selectedCategory == cat.name { isDiscoverLoading = false }
    }

    private func refreshDiscoverPull() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await refreshRankingFromNetwork() }
            if let cat = BookSourceEngine.categoryPaths.first(where: { $0.name == selectedCategory }) {
                group.addTask { await refreshCategoryFromNetwork(cat) }
            }
        }
    }

    private func silentRefreshDiscover() async {
        await refreshDiscoverPull()
    }

    private func searchByKeyword(immediateKeyword: String? = nil) {
        let kw = (immediateKeyword ?? keyword).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }

        let token = UUID()
        let cacheKey = BookSourceCache.searchKey(kw)
        let cachedSearch = cache.retrieve(forKey: cacheKey)
        let cachedResults = deduplicated(normalized(cachedSearch?.books ?? []))

        searchToken = token
        searchResults = cachedResults
        isSearchLoading = cachedResults.isEmpty || (cachedSearch?.isStale ?? true)
        searchErrorMessage = nil
        searchNoticeMessage = cachedResults.isEmpty
            ? nil
            : ((cachedSearch?.isStale ?? false)
                ? "已显示缓存结果，正在刷新搜索..."
                : "已显示最近搜索结果")

        Task {
            let preferredResults = await preferredSearchResults(for: kw)
            let finalResults: [BookSearchResult]
            let fallbackUsed: Bool

            if let preferredResults, !preferredResults.isEmpty {
                finalResults = preferredResults
                fallbackUsed = false
            } else {
                let fallback = await fallbackSearchResults(for: kw)
                finalResults = fallback.isEmpty ? cachedResults : fallback
                fallbackUsed = true
            }

            await MainActor.run {
                guard searchToken == token,
                      keyword.trimmingCharacters(in: .whitespacesAndNewlines) == kw else {
                    return
                }

                searchResults = deduplicated(finalResults)
                if !searchResults.isEmpty {
                    cache.store(searchResults, forKey: cacheKey)
                }

                if searchResults.isEmpty {
                    searchErrorMessage = fallbackUsed
                        ? "未找到\"\(kw)\"相关书籍"
                        : "没有搜索到\"\(kw)\"相关书籍"
                    searchNoticeMessage = nil
                } else if fallbackUsed {
                    searchNoticeMessage = cachedResults.isEmpty
                        ? "书源暂时不可用，已切换到缓存搜索，结果可能不完整"
                        : "书源暂时不可用，已优先显示缓存结果"
                } else {
                    searchNoticeMessage = nil
                }

                isSearchLoading = false
            }
        }
    }

    private func preferredSearchResults(for keyword: String) async -> [BookSearchResult]? {
        if let remote = await DiscoverAPIClient.fetchSearch(keyword: keyword), !remote.isEmpty {
            return normalized(remote)
        }
        if let results = try? await engine.search(keyword: keyword), !results.isEmpty {
            return normalized(results)
        }
        return nil
    }

    private func deduplicated(_ results: [BookSearchResult]) -> [BookSearchResult] {
        var seen = Set<String>()
        return results.filter { result in
            let normalizedBookId = BookSourceEngine.normalizedBookId(from: result.bookId, bookURL: result.bookURL)
            let key = (normalizedBookId ?? result.bookId).isEmpty
                ? "\(result.title.lowercased())|\(result.author.lowercased())"
                : (normalizedBookId ?? result.bookId)
            return seen.insert(key).inserted
        }
    }

    private func fallbackSearchResults(for keyword: String) async -> [BookSearchResult] {
        let all = await withTaskGroup(of: [BookSearchResult].self, returning: [BookSearchResult].self) { group in
            for cat in BookSourceEngine.categoryPaths {
                group.addTask {
                    await fallbackBooks(for: cat)
                }
            }

            var combined: [BookSearchResult] = []
            for await results in group {
                combined.append(contentsOf: results)
            }
            return combined
        }

        return deduplicated(all).filter {
            $0.title.localizedCaseInsensitiveContains(keyword) ||
            $0.author.localizedCaseInsensitiveContains(keyword)
        }
    }

    private func fallbackBooks(for category: (name: String, sort: String)) async -> [BookSearchResult] {
        let key = BookSourceCache.categoryKey(category.sort)
        let cached = cache.retrieve(forKey: key)
        let staleFallback = cached?.books ?? []

        if let cached, !cached.isStale, !cached.books.isEmpty {
            return normalized(cached.books)
        }

        if let remote = await DiscoverAPIClient.fetchCategory(sort: category.sort), !remote.isEmpty {
            let normalized = normalized(remote)
            cache.store(normalized, forKey: key)
            return normalized
        }

        if let results = try? await engine.fetchCategory(sort: category.sort), !results.isEmpty {
            let normalized = normalized(results)
            cache.store(normalized, forKey: key)
            return normalized
        }

        return normalized(staleFallback)
    }

    private func normalized(_ results: [BookSearchResult]) -> [BookSearchResult] {
        results.map { result in
            let normalizedBookId = BookSourceEngine.normalizedBookId(from: result.bookId, bookURL: result.bookURL)
            return BookSearchResult(
                title: result.title.trimmingCharacters(in: .whitespacesAndNewlines),
                author: result.author.trimmingCharacters(in: .whitespacesAndNewlines),
                coverURL: result.coverURL,
                bookURL: BookSourceEngine.normalizedBookURL(from: result.bookURL, bookId: normalizedBookId) ?? result.bookURL,
                bookId: normalizedBookId ?? result.bookId.trimmingCharacters(in: .whitespacesAndNewlines),
                intro: result.intro.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
