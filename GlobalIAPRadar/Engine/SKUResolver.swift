import Foundation

/// How two IAP entries were proven to be the same product.
enum SKUMatchStrategy: String, Codable, Sendable {
    /// Identical Apple product identifier (the strongest possible signal).
    case exactID
    /// Same subscription family + tier rank + billing period.
    case familyTierPeriod
    /// Same normalised display name + kind + period.
    case nameAndType
    /// Could not be verified; kept separate on purpose.
    case unverified
}

struct SKUGroup: Identifiable, Hashable, Sendable {
    let key: String
    var displayName: String
    var strategy: SKUMatchStrategy
    var confidence: Double
    var productIDs: Set<String>
    var isSubscription: Bool
    var period: String?
    var familyName: String?
    var tierRank: Int?

    var id: String { key }
}

/// Groups a flat list of IAP products into verifiable product identities.
struct SKUResolver: Sendable {
    func resolve(products: [IAPProduct]) -> [SKUGroup] {
        var groups: [String: SKUGroup] = [:]

        for product in products where !product.productID.isEmpty {
            merge(product, into: &groups,
                 key: "id:\(product.productID)",
                 strategy: .exactID,
                 confidence: 1.0)
        }

        for product in products where product.productID.isEmpty {
            if let family = product.familyName, let rank = product.familyRank {
                let period = product.period ?? "-"
                merge(product, into: &groups,
                     key: "ftp:\(family.lowercased()):\(rank):\(period)",
                     strategy: .familyTierPeriod,
                     confidence: 0.92)
            } else {
                let key = "nt:\(Self.normalise(product.name)):\(product.kind.rawValue):\(product.period ?? "-")"
                merge(product, into: &groups,
                     key: key,
                     strategy: .nameAndType,
                     confidence: 0.7)
            }
        }

        return groups.values.sorted {
            if $0.isSubscription != $1.isSubscription { return $0.isSubscription }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func merge(_ product: IAPProduct,
                       into groups: inout [String: SKUGroup],
                       key: String,
                       strategy: SKUMatchStrategy,
                       confidence: Double) {
        if var existing = groups[key] {
            existing.productIDs.insert(product.productID)
            existing.confidence = max(existing.confidence, confidence)
            if existing.tierRank == nil { existing.tierRank = product.familyRank }
            if existing.familyName == nil { existing.familyName = product.familyName }
            groups[key] = existing
        } else {
            groups[key] = SKUGroup(key: key,
                                   displayName: product.name,
                                   strategy: strategy,
                                   confidence: confidence,
                                   productIDs: [product.productID],
                                   isSubscription: product.isSubscription,
                                   period: product.period,
                                   familyName: product.familyName,
                                   tierRank: product.familyRank)
        }
    }

    static func normalise(_ name: String) -> String {
        name.lowercased()
            .folding(options: [.diacriticInsensitive], locale: .current)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }
}

// MARK: - Cross-storefront alignment

struct SKUPriceEntry: Identifiable, Hashable, Sendable {
    let storefront: String
    let price: Double?
    let currency: String?
    let formattedPrice: String?

    var id: String { storefront }
}

struct AlignedSKU: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let kind: IAPKind
    let period: String?
    let tierRank: Int?
    let entries: [SKUPriceEntry]

    var coveredStorefronts: Int { entries.filter { $0.price != nil }.count }
    var totalStorefronts: Int { entries.count }
    var minPrice: Double? { entries.compactMap(\.price).min() }
    var maxPrice: Double? { entries.compactMap(\.price).max() }
    var distinctCurrencies: Int { Set(entries.compactMap(\.currency)).count }
}

/// Aligns the same product across storefronts.
///
/// Empirically validated: Apple product identifiers are identical in every
/// storefront that sells the product, so alignment is exact rather than fuzzy.
enum SKUAligner {
    static func align(results: [StorefrontResult]) -> [AlignedSKU] {
        var buckets: [String: [SKUPriceEntry]] = [:]
        var names: [String: String] = [:]
        var kinds: [String: IAPKind] = [:]
        var periods: [String: String?] = [:]
        var ranks: [String: Int?] = [:]

        for result in results {
            for product in result.products {
                buckets[product.productID, default: []].append(
                    SKUPriceEntry(storefront: result.storefront,
                                  price: product.price,
                                  currency: product.currency,
                                  formattedPrice: product.formattedPrice))
                if names[product.productID] == nil {
                    names[product.productID] = product.name
                    kinds[product.productID] = product.kind
                    periods[product.productID] = product.period
                    ranks[product.productID] = product.familyRank
                }
            }
        }

        return buckets.map { key, entries in
            AlignedSKU(id: key,
                       displayName: names[key] ?? key,
                       kind: kinds[key] ?? .unknown,
                       period: periods[key] ?? nil,
                       tierRank: ranks[key] ?? nil,
                       entries: entries.sorted { $0.storefront < $1.storefront })
        }
        .sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }
}
