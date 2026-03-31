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

                    if isLoading && categoryBooks.isEmpty && rankingBooks.isEmpty {
                        Spacer()
                        ProgressView().padding()
                        Spacer()
                    } else if let err = errorMessage, categoryBooks.isEmpty, rankingBooks.isEmpty {
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

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("搜索书名...", text: $keyword)
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
            if isLoading {
                Spacer()
                ProgressView().padding()
                Spacer()
            } else if let err = errorMessage {
                Spacer()
                Text(err).foregroundColor(.red).font(.footnote).padding()
                Spacer()
            } else {
                List(searchResults, id: \.bookId) { result in
                    NavigationLink(destination: bookDetailDestination(result)) {
                        bookRow(result)
                    }
                }
                .listStyle(.plain)
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
        BookDetailView(book: Book(
            title: result.title,
            author: result.author,
            coverURL: result.coverURL,
            sourceURL: result.bookURL,
            bookId: result.bookId,
            source: .biquge
        ))
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

    private func searchByKeyword() {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return }

        let token = UUID()
        searchToken = token
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
            let key = result.bookId.isEmpty
                ? "\(result.title.lowercased())|\(result.author.lowercased())"
                : result.bookId
            return seen.insert(key).inserted
        }
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

        return all.filter {
            $0.title.localizedCaseInsensitiveContains(keyword) ||
            $0.author.localizedCaseInsensitiveContains(keyword)
        }
    }
}
