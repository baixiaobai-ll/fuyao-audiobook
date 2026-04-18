import SwiftUI

struct BookSearchView: View {
    @EnvironmentObject var store: BookshelfStore
    @EnvironmentObject var profileStore: UserProfileStore
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
    @State private var accessState = DiscoverAccessGate.currentState()

    private let engine = BookSourceEngine()
    private let cache = BookSourceCache()
    private let pageBlue = Color(red: 0.52, green: 0.76, blue: 0.98)
    private let pagePurple = Color(red: 0.66, green: 0.54, blue: 0.96)
    private let pageIndigo = Color(red: 0.35, green: 0.45, blue: 0.82)

    private var isSearching: Bool {
        !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasDiscoverAccess: Bool {
        accessState.canUseDiscover
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
                refreshAccessState()
                handleDiscoverAccessOnAppear()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                let previous = accessState
                refreshAccessState()
                guard previous != accessState else { return }
                handleDiscoverAccessStateChanged(from: previous, to: accessState)
            }
            .onChange(of: profileStore.isLoggedIn) { _ in
                refreshAccessState()
            }
            .onChange(of: profileStore.isActivated) { _ in
                refreshAccessState()
            }
            .onReceive(Timer.publish(every: 20 * 60, on: .main, in: .common).autoconnect()) { _ in
                guard scenePhase == .active, !isSearching, hasDiscoverAccess else { return }
                Task { await silentRefreshDiscover() }
            }
            .onDisappear {
                searchDebounceTask?.cancel()
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
                    .onSubmit {
                        searchDebounceTask?.cancel()
                        guard hasDiscoverAccess else {
                            applyDiscoverAccessRestrictedState()
                            return
                        }
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

                        guard hasDiscoverAccess else {
                            searchDebounceTask?.cancel()
                            searchResults = []
                            isSearchLoading = false
                            searchNoticeMessage = nil
                            searchErrorMessage = discoverAccessMessage
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
                    Button(action: {
                        guard hasDiscoverAccess else {
                            applyDiscoverAccessRestrictedState()
                            return
                        }
                        loadCategory(cat)
                    }) {
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
        if isDiscoverLoading && categoryBooks.isEmpty && rankingBooks.isEmpty {
            loadingCard(text: "正在整理今晚推荐…")
        } else if let err = discoverErrorMessage, categoryBooks.isEmpty, rankingBooks.isEmpty {
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
        if isSearchLoading && searchResults.isEmpty {
            loadingCard(text: "正在搜索相关书籍…")
        } else if let err = searchErrorMessage {
            messageCard(icon: "magnifyingglass.circle", title: "这次没有搜到结果", message: err)
        } else if searchResults.isEmpty {
            messageCard(icon: "book.closed", title: "还没有搜索结果", message: "输入书名或作者后回车搜索，我们会把相关内容列在这里。")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SoftSectionHeader(
                    title: "搜索结果",
                    subtitle: "共找到 \(searchResults.count) 本相关书籍"
                )

                if let notice = searchNoticeMessage, !notice.isEmpty {
                    SurfaceCard {
                        HStack(spacing: 10) {
                            if isSearchLoading {
                                ProgressView()
                                    .tint(pageIndigo)
                            } else {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(pagePurple)
                            }

                            Text(notice)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.Colors.textSecondary)

                            Spacer(minLength: 0)
                        }
                    }
                }

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

            if categoryBooks.isEmpty && !isDiscoverLoading {
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
        let normalizedBookId = BookSourceEngine.normalizedBookId(from: result.bookId, bookURL: result.bookURL)
        return Book(
            title: result.title,
            author: result.author,
            coverURL: result.coverURL,
            sourceURL: BookSourceEngine.normalizedBookURL(from: result.bookURL, bookId: normalizedBookId) ?? result.bookURL,
            bookId: normalizedBookId ?? result.bookId,
            source: .biquge
        )
    }

    private func bookDetailDestination(_ result: BookSearchResult) -> BookDetailView {
        let book = discoverBook(for: result)
        return BookDetailView(book: store.existingBook(matching: book) ?? book)
    }

    // MARK: - Data Loading

    private func loadInitialDiscover() {
        guard hasDiscoverAccess else {
            applyDiscoverAccessRestrictedState()
            return
        }
        let first = BookSourceEngine.categoryPaths[0]
        selectedCategory = first.name
        loadRanking()
        loadCategory(first)
    }

    private func loadRanking() {
        guard hasDiscoverAccess else {
            applyDiscoverAccessRestrictedState()
            return
        }
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
        guard DiscoverAccessGate.canUseDiscover() else { return }
        if let remote = await DiscoverAPIClient.fetchRanking(), !remote.isEmpty {
            let normalizedRemote = normalized(remote)
            guard DiscoverAccessGate.canUseDiscover() else { return }
            cache.store(normalizedRemote, forKey: BookSourceCache.rankingKey)
            rankingBooks = normalizedRemote
            return
        }
        guard let results = try? await engine.fetchRanking(), !results.isEmpty else { return }
        let normalizedResults = normalized(results)
        guard DiscoverAccessGate.canUseDiscover() else { return }
        cache.store(normalizedResults, forKey: BookSourceCache.rankingKey)
        rankingBooks = normalizedResults
    }

    private func loadCategory(_ cat: (name: String, sort: String)) {
        guard hasDiscoverAccess else {
            applyDiscoverAccessRestrictedState()
            return
        }
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
        guard DiscoverAccessGate.canUseDiscover() else { return }
        if let remote = await DiscoverAPIClient.fetchCategory(sort: cat.sort), !remote.isEmpty {
            let normalizedRemote = normalized(remote)
            guard DiscoverAccessGate.canUseDiscover() else { return }
            cache.store(normalizedRemote, forKey: BookSourceCache.categoryKey(cat.sort))
            if selectedCategory == cat.name {
                categoryBooks = normalizedRemote
                discoverErrorMessage = nil
            }
            if selectedCategory == cat.name { isDiscoverLoading = false }
            return
        }
        do {
            let results = normalized(try await engine.fetchCategory(sort: cat.sort))
            guard DiscoverAccessGate.canUseDiscover() else { return }
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
        guard DiscoverAccessGate.canUseDiscover() else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await refreshRankingFromNetwork() }
            if let cat = BookSourceEngine.categoryPaths.first(where: { $0.name == selectedCategory }) {
                group.addTask { await refreshCategoryFromNetwork(cat) }
            }
        }
    }

    private func silentRefreshDiscover() async {
        guard DiscoverAccessGate.canUseDiscover() else { return }
        await refreshRankingFromNetwork()
        if let cat = BookSourceEngine.categoryPaths.first(where: { $0.name == selectedCategory }) {
            await refreshCategoryFromNetwork(cat)
        }
    }

    // MARK: - Search

    private func searchByKeyword(immediateKeyword: String? = nil) {
        let kw = (immediateKeyword ?? keyword).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        guard hasDiscoverAccess else {
            applyDiscoverAccessRestrictedState()
            searchErrorMessage = discoverAccessMessage
            return
        }

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
        guard DiscoverAccessGate.canUseDiscover() else { return nil }
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
        guard DiscoverAccessGate.canUseDiscover() else { return [] }
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

        let lower = normalizedDiscoverText(keyword)
        return deduplicated(all).filter {
            normalizedDiscoverText($0.title).contains(lower)
                || normalizedDiscoverText($0.author).contains(lower)
                || normalizedDiscoverText($0.intro).contains(lower)
        }
    }

    private func fallbackBooks(for category: (name: String, sort: String)) async -> [BookSearchResult] {
        guard DiscoverAccessGate.canUseDiscover() else { return [] }
        let key = BookSourceCache.categoryKey(category.sort)
        let cached = cache.retrieve(forKey: key)
        let staleFallback = cached?.books ?? []

        if let cached, !cached.isStale, !cached.books.isEmpty {
            return normalized(cached.books)
        }

        if let remote = await DiscoverAPIClient.fetchCategory(sort: category.sort), !remote.isEmpty {
            let normalizedRemote = normalized(remote)
            cache.store(normalizedRemote, forKey: key)
            return normalizedRemote
        }

        if let results = try? await engine.fetchCategory(sort: category.sort), !results.isEmpty {
            let normalizedResults = normalized(results)
            cache.store(normalizedResults, forKey: key)
            return normalizedResults
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

    private var discoverAccessMessage: String {
        if !accessState.isLoggedIn {
            return "登录后可使用发现页与云端书籍"
        }
        if !accessState.isActivated {
            return "激活成功后可使用发现页与云端书籍"
        }
        return "当前账号暂不可使用发现页"
    }

    private func handleDiscoverAccessOnAppear() {
        guard hasDiscoverAccess else {
            applyDiscoverAccessRestrictedState()
            return
        }
        guard !didLoadInitialDiscover else { return }
        didLoadInitialDiscover = true
        loadInitialDiscover()
    }

    private func handleDiscoverAccessStateChanged(
        from previous: DiscoverAccessGate.AccessState,
        to current: DiscoverAccessGate.AccessState
    ) {
        if current.canUseDiscover {
            discoverErrorMessage = nil
            searchErrorMessage = nil
            if !didLoadInitialDiscover {
                didLoadInitialDiscover = true
                loadInitialDiscover()
            } else {
                Task { await silentRefreshDiscover() }
            }

            let trimmedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedKeyword.isEmpty {
                searchByKeyword(immediateKeyword: trimmedKeyword)
            }
            return
        }

        applyDiscoverAccessRestrictedState()
    }

    private func refreshAccessState() {
        accessState = DiscoverAccessGate.currentState()
    }

    private func applyDiscoverAccessRestrictedState() {
        searchDebounceTask?.cancel()
        searchToken = UUID()
        rankingBooks = []
        categoryBooks = []
        searchResults = []
        isDiscoverLoading = false
        isSearchLoading = false
        searchNoticeMessage = nil
        discoverErrorMessage = discoverAccessMessage
        searchErrorMessage = keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : discoverAccessMessage
    }
}
