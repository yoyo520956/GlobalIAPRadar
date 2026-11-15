import Foundation

// MARK: - Storefront

/// One Apple App Store storefront. `storefront` is the two-letter code used by
/// both the iTunes Lookup API (`country=`) and the apps.apple.com catalog API.
struct Storefront: Identifiable, Codable, Hashable, Sendable {
    let storefront: String
    let alpha3: String
    let nameEn: String
    let nameZh: String
    let currency: String?
    let isoCurrency: String?
    let note: String?

    var id: String { storefront }
    var displayName: String { nameZh.isEmpty ? nameEn : nameZh }
}

// MARK: - App

struct AppInfo: Identifiable, Codable, Hashable, Sendable {
    let appID: String
    let name: String
    let seller: String
    let bundleID: String?
    let artworkURL: URL?
    let description: String
    let genres: [String]
    let primaryGenre: String?
    let price: Double?
    let currency: String?
    let formattedPrice: String?

    var id: String { appID }
}

// MARK: - In-app purchase

enum IAPKind: String, Codable, Sendable {
    case consumable
    case nonConsumable
    case subscription
    case unknown
}

struct IAPProduct: Identifiable, Codable, Hashable, Sendable {
    let productID: String
    let name: String
    let offerName: String?
    let familyName: String?
    let familyRank: Int?
    let rawType: String?
    let isSubscription: Bool
    /// ISO-8601 duration as reported by Apple: P1W / P1M / P3M / P6M / P1Y
    let period: String?
    let price: Double?
    let currency: String?
    let formattedPrice: String?

    var id: String { productID }

    var kind: IAPKind {
        if let rawType {
            switch rawType.uppercased() {
            case "CONSUMABLE": return .consumable
            case "NON_CONSUMABLE": return .nonConsumable
            case "AUTO_RENEWABLE_SUBSCRIPTION", "NON_RENEWING_SUBSCRIPTION": return .subscription
            default: break
            }
        }
        if isSubscription { return .subscription }
        return period == nil ? .consumable : .unknown
    }

    /// Subscription tier label, e.g. "ChatGPT Plan · L4".
    var tierLabel: String {
        guard let familyName else { return name }
        guard let familyRank else { return familyName }
        return "\(familyName) · L\(familyRank)"
    }
}

// MARK: - Prices

struct IAPPrice: Identifiable, Codable, Hashable, Sendable {
    let productID: String
    let storefront: String
    let price: Double?
    let currency: String?
    let formattedPrice: String?
    let capturedAt: Date

    var id: String { "\(productID)-\(storefront)" }
}

// MARK: - Query status

enum StorefrontQueryStatus: String, Codable, Sendable {
    case success
    case productNotFound
    case notListed
    case noIAPData
    case networkError
    case rateLimited
    case identityUnverified
    case notVerified

    /// Key used by the localisation table.
    var labelKey: String {
        switch self {
        case .success: return "status.success"
        case .productNotFound: return "status.productNotFound"
        case .notListed: return "status.notListed"
        case .noIAPData: return "status.noIAPData"
        case .networkError: return "status.networkError"
        case .rateLimited: return "status.rateLimited"
        case .identityUnverified: return "status.identityUnverified"
        case .notVerified: return "status.notVerified"
        }
    }

    var isUsable: Bool { self == .success }
}

struct StorefrontProgress: Identifiable, Codable, Hashable, Sendable {
    let storefront: String
    var status: StorefrontQueryStatus
    var iapCount: Int
    var finishedAt: Date?

    var id: String { storefront }
}

struct StorefrontResult: Codable, Hashable, Sendable {
    let storefront: String
    let status: StorefrontQueryStatus
    let appPrice: Double?
    let appCurrency: String?
    let appFormattedPrice: String?
    let products: [IAPProduct]
    let capturedAt: Date
}

// MARK: - Currency

struct CurrencyRate: Codable, Hashable, Sendable {
    let base: String
    /// Uppercased keys: "USD", "CNY", "GBP" ...
    let rates: [String: Double]
    let date: String
    let fetchedAt: Date

    /// Converts an amount into the rate table's base currency.
    func converted(_ amount: Double?, from source: String?) -> Double? {
        guard let amount, let source else { return nil }
        guard let rate = rates[source.uppercased()] else { return nil }
        return amount / rate
    }

    /// Convert an amount from `source` currency into `target` currency.
    func convert(_ amount: Double, from source: String, to target: String) -> Double? {
        let src = source.uppercased()
        let dst = target.uppercased()
        guard let sourceRate = rates[src], let targetRate = rates[dst] else { return nil }
        return amount / sourceRate * targetRate
    }
}

// MARK: - History

struct PriceSnapshot: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let appID: String
    let appName: String
    let productID: String
    let productName: String
    let storefront: String
    let price: Double?
    let currency: String?
    let capturedAt: Date

    init(id: UUID = UUID(), appID: String, appName: String, productID: String,
         productName: String, storefront: String, price: Double?, currency: String?,
         capturedAt: Date = Date()) {
        self.id = id
        self.appID = appID
        self.appName = appName
        self.productID = productID
        self.productName = productName
        self.storefront = storefront
        self.price = price
        self.currency = currency
        self.capturedAt = capturedAt
    }
}

struct Favorite: Identifiable, Codable, Hashable, Sendable {
    let appID: String
    let name: String
    let seller: String
    let artworkURL: URL?

    var id: String { appID }
}
