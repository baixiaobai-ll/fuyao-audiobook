import Foundation

enum DiscoverAccessGate {
    struct AccessState: Equatable, Sendable {
        let isLoggedIn: Bool
        let isActivated: Bool

        var canUseDiscover: Bool {
            isLoggedIn && isActivated
        }
    }

    static let userProfileDataKey = "userprofile_data"
    static let activationStatusKey = "fuyao_activation_status"
    static let dailyQuotaTotalKey = "fuyao_daily_quota_total"
    static let dailyQuotaUsedKey = "fuyao_daily_quota_used"
    static let dailyQuotaResetKey = "fuyao_daily_quota_reset"

    static func currentState(userDefaults: UserDefaults = .standard) -> AccessState {
        let profile = storedProfile(from: userDefaults)
        let isLoggedIn = profile?.isLoggedIn ?? false
        let isActivated = activationStatus(from: userDefaults) ?? profile?.isActivated ?? false
        return AccessState(isLoggedIn: isLoggedIn, isActivated: isActivated)
    }

    static func canUseDiscover(userDefaults: UserDefaults = .standard) -> Bool {
        currentState(userDefaults: userDefaults).canUseDiscover
    }

    static func activationStatus(from userDefaults: UserDefaults = .standard) -> Bool? {
        guard let object = userDefaults.object(forKey: activationStatusKey) else {
            return nil
        }
        return normalizedActivationStatus(from: object)
    }

    static func persistActivationStatus(_ isActivated: Bool, userDefaults: UserDefaults = .standard) {
        userDefaults.set(isActivated, forKey: activationStatusKey)
    }

    private struct StoredUserProfile: Decodable {
        let isLoggedIn: Bool
        let isActivated: Bool?
    }

    private static func storedProfile(from userDefaults: UserDefaults) -> StoredUserProfile? {
        guard let data = userDefaults.data(forKey: userProfileDataKey) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredUserProfile.self, from: data)
    }

    private static func normalizedActivationStatus(from object: Any) -> Bool? {
        switch object {
        case let value as Bool:
            return value
        case let value as Int:
            return value > 0
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalized.isEmpty {
                return nil
            }
            if ["1", "true", "yes", "active", "activated", "success", "redeemed", "valid", "enabled", "已激活", "激活成功"].contains(normalized) {
                return true
            }
            if ["0", "false", "no", "inactive", "pending", "expired", "invalid", "disabled", "not_activated", "未激活", "待激活", "失效"].contains(normalized) {
                return false
            }
            if let data = value.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data) {
                return normalizedActivationStatus(from: decoded)
            }
            return nil
        case let value as [String: Any]:
            for key in ["isActivated", "activated", "active", "status", "activationStatus"] {
                if let candidate = value[key], let normalized = normalizedActivationStatus(from: candidate) {
                    return normalized
                }
            }
            return nil
        case let value as Data:
            if let decoded = try? JSONSerialization.jsonObject(with: value) {
                return normalizedActivationStatus(from: decoded)
            }
            return nil
        default:
            return nil
        }
    }
}

/// 自建「发现」聚合 API。未配置 `DISCOVER_API_BASE_URL` 或请求失败时由调用方回退到 `BookSourceEngine`。
enum DiscoverAPIClient {

    private struct BooksEnvelope: Codable {
        let books: [BookSearchResult]
    }

    static func fetchRanking() async -> [BookSearchResult]? {
        await fetchBooks(path: "v1/discover/ranking")
    }

    static func fetchCategory(sort: String) async -> [BookSearchResult]? {
        await fetchBooks(
            path: "v1/discover/category",
            queryItems: [URLQueryItem(name: "sort", value: sort)]
        )
    }

    static func fetchSearch(keyword: String) async -> [BookSearchResult]? {
        await fetchBooks(
            path: "v1/discover/search",
            queryItems: [URLQueryItem(name: "q", value: keyword)]
        )
    }

    private static func fetchBooks(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async -> [BookSearchResult]? {
        guard DiscoverAccessGate.canUseDiscover() else { return nil }
        guard let base = Config.discoverAPIBaseURL else { return nil }
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              let baseURL = URL(string: trimmed),
              var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return decodeBookList(data)
        } catch {
            print("⚠️ DiscoverAPI: \(error.localizedDescription)")
            return nil
        }
    }

    private static func decodeBookList(_ data: Data) -> [BookSearchResult]? {
        let decoder = JSONDecoder()
        if let list = try? decoder.decode([BookSearchResult].self, from: data), !list.isEmpty {
            return normalized(list)
        }
        if let env = try? decoder.decode(BooksEnvelope.self, from: data), !env.books.isEmpty {
            return normalized(env.books)
        }
        if let object = try? JSONSerialization.jsonObject(with: data),
           let list = extractBookList(from: object),
           !list.isEmpty {
            return normalized(list)
        }
        return nil
    }

    private static func normalized(_ results: [BookSearchResult]) -> [BookSearchResult] {
        results.map { result in
            let bookId = BookSourceEngine.normalizedBookId(from: result.bookId, bookURL: result.bookURL) ?? result.bookId
            let bookURL = BookSourceEngine.normalizedBookURL(from: result.bookURL, bookId: bookId) ?? result.bookURL
            return BookSearchResult(
                title: result.title.trimmingCharacters(in: .whitespacesAndNewlines),
                author: result.author.trimmingCharacters(in: .whitespacesAndNewlines),
                coverURL: result.coverURL,
                bookURL: bookURL,
                bookId: bookId,
                intro: result.intro.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private static func extractBookList(from object: Any) -> [BookSearchResult]? {
        if let rows = object as? [[String: Any]] {
            let list = rows.compactMap { parseBookResult($0) }
            return list.isEmpty ? nil : list
        }

        guard let dict = object as? [String: Any] else { return nil }

        for key in ["data", "list", "books", "results", "items"] {
            if let value = dict[key],
               let list = extractBookList(from: value),
               !list.isEmpty {
                return list
            }
        }

        for value in dict.values {
            if let list = extractBookList(from: value), !list.isEmpty {
                return list
            }
        }

        return nil
    }

    private static func parseBookResult(_ dict: [String: Any]) -> BookSearchResult? {
        guard let title = stringValue(in: dict, keys: ["title", "bookName", "name"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }

        let rawURL = stringValue(in: dict, keys: ["bookURL", "url", "detailUrl", "detailURL"])
        let rawBookId = stringValue(in: dict, keys: ["bookId", "id"])
        let normalizedBookId = BookSourceEngine.normalizedBookId(from: rawBookId, bookURL: rawURL) ?? rawBookId ?? ""
        let normalizedBookURL = BookSourceEngine.normalizedBookURL(from: rawURL, bookId: normalizedBookId) ?? rawURL ?? ""

        return BookSearchResult(
            title: title,
            author: (stringValue(in: dict, keys: ["author", "writer"]) ?? "未知")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            coverURL: stringValue(in: dict, keys: ["coverURL", "cover", "img", "pic"]),
            bookURL: normalizedBookURL,
            bookId: normalizedBookId,
            intro: (stringValue(in: dict, keys: ["intro", "desc", "description"]) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func stringValue(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                return value
            }
            if let value = dict[key] as? Int {
                return String(value)
            }
            if let value = dict[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }
}
