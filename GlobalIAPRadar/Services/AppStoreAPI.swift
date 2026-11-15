import Foundation

// MARK: - Flexible decoding helpers

struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
            return
        }
        if let text = try? container.decode(String.self), let number = Double(text) {
            value = number
            return
        }
        value = nil
    }
}

struct FlexibleInt: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
            return
        }
        if let text = try? container.decode(String.self), let number = Int(text) {
            value = number
            return
        }
        value = nil
    }
}

// MARK: - iTunes Search / Lookup

private struct ITunesLookupResponse: Decodable {
    let resultCount: Int
    let results: [ITunesApp]
}

private struct ITunesApp: Decodable {
    let trackId: Int
    let trackName: String
    let sellerName: String?
    let bundleId: String?
    let artworkUrl512: String?
    let description: String?
    let genres: [String]?
    let primaryGenreName: String?
    let price: FlexibleDouble?
    let currency: String?
    let formattedPrice: String?

    var appInfo: AppInfo {
        AppInfo(appID: String(trackId),
                name: trackName,
                seller: sellerName ?? "—",
                bundleID: bundleId,
                artworkURL: artworkUrl512.flatMap(URL.init(string:)),
                description: description ?? "",
                genres: genres ?? [],
                primaryGenre: primaryGenreName,
                price: price?.value,
                currency: currency,
                formattedPrice: formattedPrice)
    }
}

/// Free, key-less Apple API used for app identity, availability and the app's own price.
actor ITunesClient {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    private let http: HTTPClient
    private let limiter: RateLimiter

    init(http: HTTPClient = HTTPClient(), limiter: RateLimiter = RateLimiter(minInterval: 0.12)) {
        self.http = http
        self.limiter = limiter
    }

    /// Accepts an app name, a numeric App Store ID, or any App Store URL.
    func search(term: String, storefront: String = "us") async throws -> [AppInfo] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let appID = Self.extractAppID(from: trimmed) {
            return try await lookup(appID: appID, storefront: storefront)
        }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            .init(name: "term", value: trimmed),
            .init(name: "entity", value: "software"),
            .init(name: "limit", value: "25"),
            .init(name: "country", value: storefront),
            .init(name: "lang", value: "en_us")
        ]
        let data = try await fetch(components)
        let payload = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
        return payload.results.map(\.appInfo)
    }

    func lookup(appID: String, storefront: String) async throws -> [AppInfo] {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            .init(name: "id", value: appID),
            .init(name: "entity", value: "software"),
            .init(name: "country", value: storefront),
            .init(name: "lang", value: "en_us")
        ]
        let data = try await fetch(components)
        let payload = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)
        return payload.results.map(\.appInfo)
    }

    static func extractAppID(from text: String) -> String? {
        if let range = text.range(of: #"id(\d{5,})"#, options: .regularExpression) {
            return String(text[range].dropFirst(2))
        }
        let digits = text.filter(\.isNumber)
        if digits.count >= 6, text.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
            return digits
        }
        return nil
    }

    private func fetch(_ components: URLComponents) async throws -> Data {
        guard let url = components.url else { throw HTTPError.emptyResponse }
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        try await limiter.wait()
        return try await http.data(for: request)
    }
}

// MARK: - apps.apple.com catalog (in-app purchases)

/// Internal (not `private`) so the unit tests can decode a captured response
/// and lock the key names against the live API.
struct CatalogResponse: Decodable {
    var data: [CatalogApp]
}

struct CatalogApp: Decodable {
    let id: String?
    let attributes: CatalogAppAttributes?
    var views: CatalogViews?
}

struct CatalogAppAttributes: Decodable {
    let name: String?
    let artistName: String?
}

/// Apple writes this key as kebab-case (`top-in-app-purchasables`), not camelCase.
/// Accept all three spellings so a rename on Apple's side degrades instead of
/// silently producing an empty list -- the empty list was exactly the bug that
/// made every storefront report "数据源未返回 IAP".
struct CatalogViews: Decodable {
    let topInAppPurchasables: CatalogView?

    private enum CodingKeys: String, CodingKey {
        case topInAppPurchasables = "top-in-app-purchasables"
        case camel = "topInAppPurchasables"
        case snake = "top_in_app_purchasables"
    }

    init(topInAppPurchasables: CatalogView?) {
        self.topInAppPurchasables = topInAppPurchasables
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let view = try container.decodeIfPresent(CatalogView.self, forKey: .topInAppPurchasables)
            ?? container.decodeIfPresent(CatalogView.self, forKey: .camel)
            ?? container.decodeIfPresent(CatalogView.self, forKey: .snake)
        self.init(topInAppPurchasables: view)
    }
}

struct CatalogView: Decodable {
    let data: [CatalogItem]
}

struct CatalogItem: Decodable {
    let id: String?
    /// Item-level type, e.g. "in-apps". Apple's public catalog does NOT expose
    /// consumable vs non-consumable here, so this must not be used to claim one.
    let type: String?
    let attributes: CatalogItemAttributes?
}

struct CatalogItemAttributes: Decodable {
    let name: String?
    let offerName: String?
    let subscriptionFamilyName: String?
    let subscriptionFamilyRank: FlexibleInt?
    let isSubscription: Bool?
    let offers: [CatalogOffer]?
}

private struct CatalogOffer: Decodable {
    let price: FlexibleDouble?
    let priceFormatted: String?
    let currencyCode: String?
    let recurringSubscriptionPeriod: String?
}

/// Reads the in-app purchase list Apple renders on the public product page.
/// Public, key-less, and the only free source that exposes third-party IAP prices.
struct IAPCatalogClient: Sendable {
    let http: HTTPClient
    let limiter: RateLimiter

    init(http: HTTPClient = HTTPClient(), limiter: RateLimiter = RateLimiter(minInterval: 0.12)) {
        self.http = http
        self.limiter = limiter
    }

    struct CatalogSnapshot: Sendable {
        let appName: String?
        let seller: String?
        let products: [IAPProduct]
        /// False when the payload carried no IAP view at all. That is a
        /// structural/decoding failure, NOT "the app has no IAPs" -- reporting
        /// it as absence is how the 175/175 "未返回 IAP" bug reached the user.
        let iapViewPresent: Bool
    }

    /// Pure mapping from the raw payload to products, so the unit tests can
    /// exercise it against a captured response without touching the network.
    static func products(from payload: CatalogResponse) -> [IAPProduct] {
        guard let app = payload.data.first else { return [] }
        let items = app.views?.topInAppPurchasables?.data ?? []
        return items.compactMap { item in
            guard let productID = item.id, let attributes = item.attributes else { return nil }
            let offer = attributes.offers?.first
            return IAPProduct(productID: productID,
                              name: attributes.name ?? productID,
                              offerName: attributes.offerName,
                              familyName: attributes.subscriptionFamilyName,
                              familyRank: attributes.subscriptionFamilyRank?.value,
                              // Item-level type ("in-apps"); Apple does not expose
                              // consumable vs non-consumable through this endpoint.
                              rawType: item.type,
                              isSubscription: attributes.isSubscription ?? false,
                              period: offer?.recurringSubscriptionPeriod,
                              price: offer?.price?.value,
                              currency: offer?.currencyCode,
                              formattedPrice: offer?.priceFormatted)
        }
    }

    /// True when the response actually carried the IAP view. Used to tell
    /// "Apple says this app has no IAPs" apart from "we could not read the IAPs".
    static func iapViewPresent(in payload: CatalogResponse) -> Bool {
        payload.data.first?.views?.topInAppPurchasables != nil
    }

    func fetchProducts(appID: String, storefront: String) async throws -> CatalogSnapshot {
        var components = URLComponents(string: "https://apps.apple.com/api/apps/v1/catalog/\(storefront)/apps/\(appID)")!
        components.queryItems = [
            .init(name: "platform", value: "web"),
            .init(name: "views", value: "top-in-app-purchasables"),
            .init(name: "l", value: "en-us")
        ]
        guard let url = components.url else { throw HTTPError.emptyResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer", forHTTPHeaderField: "Authorization")
        request.setValue("https://apps.apple.com/\(storefront)/app/id\(appID)", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(ITunesClient.userAgent, forHTTPHeaderField: "User-Agent")
        try await limiter.wait()
        let data = try await http.data(for: request)
        let payload = try JSONDecoder().decode(CatalogResponse.self, from: data)
        return CatalogSnapshot(appName: payload.data.first?.attributes?.name,
                               seller: payload.data.first?.attributes?.artistName,
                               products: Self.products(from: payload),
                               iapViewPresent: Self.iapViewPresent(in: payload))
    }
}

// MARK: - Currency

struct FrankfurterResponse: Decodable {
    let base: String
    let date: String
    let rates: [String: Double]
}

/// Free exchange rates (ECB reference rates), no API key, cached on device.
actor CurrencyService {
    private let http: HTTPClient
    private var cached: CurrencyRate?

    init(http: HTTPClient = HTTPClient()) {
        self.http = http
    }

    func latest(base: String = "USD", maxAge: TimeInterval = 6 * 3600) async throws -> CurrencyRate {
        if let cached, Date().timeIntervalSince(cached.fetchedAt) < maxAge { return cached }
        var components = URLComponents(string: "https://api.frankfurter.app/latest")!
        components.queryItems = [.init(name: "from", value: base)]
        guard let url = components.url else { throw HTTPError.emptyResponse }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(ITunesClient.userAgent, forHTTPHeaderField: "User-Agent")
        let data = try await http.data(for: request)
        let payload = try JSONDecoder().decode(FrankfurterResponse.self, from: data)
        var normalised = payload.rates.reduce(into: [String: Double]()) { result, entry in
            result[entry.key.uppercased()] = entry.value
        }
        normalised[payload.base.uppercased()] = 1.0
        let rate = CurrencyRate(base: payload.base.uppercased(),
                                rates: normalised,
                                date: payload.date,
                                fetchedAt: Date())
        cached = rate
        return rate
    }
}
