import XCTest
@testable import GlobalIAPRadar

final class StorefrontDatabaseTests: XCTestCase {

    /// The storefront table lives in the app bundle; fall back to the test bundle and the
    /// source checkout so the suite also runs without a host application.
    static func locateStorefrontsJSON() -> URL? {
        if let bundled = Bundle.main.url(forResource: "storefronts", withExtension: "json") {
            return bundled
        }
        if let testBundle = Bundle(for: StorefrontDatabaseTests.self).url(forResource: "storefronts", withExtension: "json") {
            return testBundle
        }
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GlobalIAPRadar/Resources/storefronts.json")
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
    }
    func testStorefrontDatabaseHasAll175Storefronts() throws {
        let url = try XCTUnwrap(Self.locateStorefrontsJSON(), "storefronts.json not found")
        let data = try Data(contentsOf: url)
        let storefronts = try JSONDecoder().decode([Storefront].self, from: data)
        XCTAssertEqual(storefronts.count, 175, "Apple exposes 175 storefronts; the database must be complete")
        XCTAssertEqual(Set(storefronts.map(\.storefront)).count, 175, "storefront codes must be unique")
        XCTAssertTrue(storefronts.contains { $0.storefront == "xk" }, "Kosovo uses Apple's own code")
        XCTAssertTrue(storefronts.allSatisfy { !$0.nameZh.isEmpty }, "every storefront needs a Chinese name")
        XCTAssertTrue(storefronts.contains { $0.storefront == "cn" })
        XCTAssertTrue(storefronts.contains { $0.storefront == "us" })
    }
}

final class AppIDExtractionTests: XCTestCase {
    func testExtractsNumericID() {
        XCTAssertEqual(ITunesClient.extractAppID(from: "6448311069"), "6448311069")
    }

    func testExtractsIDFromURL() {
        XCTAssertEqual(ITunesClient.extractAppID(from: "https://apps.apple.com/us/app/chatgpt/id6448311069"), "6448311069")
    }

    func testKeepsPlainNamesUntouched() {
        XCTAssertNil(ITunesClient.extractAppID(from: "ChatGPT"))
    }
}

final class SKUResolverTests: XCTestCase {
    private func product(id: String,
                         name: String,
                         family: String? = nil,
                         rank: Int? = nil,
                         period: String? = nil,
                         subscription: Bool = false) -> IAPProduct {
        IAPProduct(productID: id,
                   name: name,
                   offerName: nil,
                   familyName: family,
                   familyRank: rank,
                   rawType: subscription ? "AUTO_RENEWABLE_SUBSCRIPTION" : "CONSUMABLE",
                   isSubscription: subscription,
                   period: period,
                   price: 9.99,
                   currency: "USD",
                   formattedPrice: "$9.99")
    }

    func testExactProductIDWins() {
        let resolver = SKUResolver()
        let groups = resolver.resolve(products: [
            product(id: "111", name: "ChatGPT Plus", family: "ChatGPT Plan", rank: 4, period: "P1M", subscription: true),
            product(id: "111", name: "ChatGPT Plus", family: "ChatGPT Plan", rank: 4, period: "P1M", subscription: true),
            product(id: "222", name: "ChatGPT Plus", family: "ChatGPT Plan", rank: 4, period: "P1Y", subscription: true)
        ])
        XCTAssertEqual(groups.count, 2, "monthly and yearly plans must stay separate")
        XCTAssertTrue(groups.contains { $0.strategy == .exactID && $0.confidence == 1.0 })
    }

    func testSubscriptionTiersAreNotMerged() {
        let resolver = SKUResolver()
        let groups = resolver.resolve(products: [
            product(id: "1", name: "Plus", family: "Plan", rank: 2, period: "P1M", subscription: true),
            product(id: "2", name: "Pro", family: "Plan", rank: 3, period: "P1M", subscription: true)
        ])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.map(\.tierRank)), [2, 3])
    }

    func testNormalisationCollapsesFormatting() {
        XCTAssertEqual(SKUResolver.normalise("ChatGPT Plus  (Monthly)"), SKUResolver.normalise("chatgpt plus monthly"))
    }
}

final class SKUAlignerTests: XCTestCase {
    func testSameProductAcrossStorefrontsIsAligned() {
        let us = StorefrontResult(storefront: "us", status: .success, appPrice: 0, appCurrency: "USD",
                                  appFormattedPrice: "Free",
                                  products: [
                                    IAPProduct(productID: "6448311597", name: "ChatGPT Plus", offerName: nil,
                                               familyName: "ChatGPT Plan", familyRank: 4,
                                               rawType: "AUTO_RENEWABLE_SUBSCRIPTION", isSubscription: true,
                                               period: "P1M", price: 19.99, currency: "USD", formattedPrice: "$19.99")
                                  ],
                                  capturedAt: Date())
        let tr = StorefrontResult(storefront: "tr", status: .success, appPrice: 0, appCurrency: "TRY",
                                  appFormattedPrice: "Ücretsiz",
                                  products: [
                                    IAPProduct(productID: "6448311597", name: "ChatGPT Plus", offerName: nil,
                                               familyName: "ChatGPT Plan", familyRank: 4,
                                               rawType: "AUTO_RENEWABLE_SUBSCRIPTION", isSubscription: true,
                                               period: "P1M", price: 999.99, currency: "TRY", formattedPrice: "₺999,99")
                                  ],
                                  capturedAt: Date())

        let aligned = SKUAligner.align(results: [us, tr])
        XCTAssertEqual(aligned.count, 1)
        XCTAssertEqual(aligned[0].entries.count, 2)
        XCTAssertEqual(aligned[0].coveredStorefronts, 2)
        XCTAssertEqual(aligned[0].minPrice, 19.99)
        XCTAssertEqual(aligned[0].maxPrice, 999.99)
    }
}

/// Decodes a REAL captured catalog response. This test exists because the
/// shipping app reported "数据源未返回 IAP" for all 175 storefronts: the live
/// key is `top-in-app-purchasables` (kebab-case) but the model expected
/// `topInAppPurchasables`, so decoding silently yielded zero products.
final class CatalogDecodingTests: XCTestCase {

    /// The fixture is a real captured response. Resolve it from the test bundle
    /// first, then from the source tree (works under CI where the resource may
    /// not be copied), and fail loudly rather than crash if it is missing.
    private var fixture: Data {
        let candidates: [URL] = [
            Bundle(for: CatalogDecodingTests.self).url(forResource: "catalog_us_chatgpt", withExtension: "json") ?? nil,
            Bundle(for: CatalogDecodingTests.self).url(forResource: "catalog_us_chatgpt", withExtension: "json", subdirectory: "Fixtures") ?? nil,
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/catalog_us_chatgpt.json"),
        ].compactMap { $0 }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url) { return data }
        }
        return Data()
    }

    func testKebabCaseKeyDecodesProducts() throws {
        let payload = try JSONDecoder().decode(CatalogResponse.self, from: fixture)
        let items = payload.data.first?.views?.topInAppPurchasables?.data ?? []
        XCTAssertFalse(items.isEmpty, "the kebab-case key must decode -- otherwise every storefront silently shows 0 IAPs")
    }

    func testProductsCarryRealPrices() throws {
        let payload = try JSONDecoder().decode(CatalogResponse.self, from: fixture)
        let items = payload.data.first?.views?.topInAppPurchasables?.data ?? []
        XCTAssertEqual(items.count, 9, "ChatGPT US storefront has 9 IAPs")

        let products = IAPCatalogClient.products(from: payload)
        let plus = try XCTUnwrap(products.first { $0.productID == "6448311597" })
        XCTAssertEqual(plus.name, "ChatGPT Plus")
        XCTAssertEqual(plus.price ?? 0, 19.99, accuracy: 0.001)
        XCTAssertEqual(plus.currency, "USD")
        XCTAssertEqual(plus.formattedPrice, "$19.99")
        XCTAssertEqual(plus.period, "P1M")
        XCTAssertEqual(plus.familyName, "ChatGPT Plan")
        XCTAssertEqual(plus.familyRank, 4)
        XCTAssertEqual(plus.kind, .subscription, "a recurring period plus isSubscription must read as a subscription")

        let credits = try XCTUnwrap(products.first { $0.productID == "6757568473" })
        XCTAssertEqual(credits.price ?? 0, 4.0, accuracy: 0.001)
        XCTAssertEqual(credits.kind, .unknown,
                       "public catalog cannot distinguish consumable from non-consumable -- must not be claimed")
        XCTAssertNotNil(credits.rawType, "item-level type ('in-apps') is preserved for traceability")
    }

    func testMissingIapViewIsReportedAsFailureNotAbsence() throws {
        // Simulate the exact shipped bug: a 200 payload whose IAP view did not
        // decode. It must NOT be reported as "the app has no IAPs".
        var payload = try JSONDecoder().decode(CatalogResponse.self, from: fixture)
        payload.data[0].views = nil
        XCTAssertFalse(IAPCatalogClient.iapViewPresent(in: payload))
        XCTAssertTrue(IAPCatalogClient.products(from: payload).isEmpty)
    }

    func testIapViewIsDetectedInFixture() throws {
        let payload = try JSONDecoder().decode(CatalogResponse.self, from: fixture)
        XCTAssertTrue(IAPCatalogClient.iapViewPresent(in: payload),
                      "a real response carries the IAP view -- if this fails the key name drifted again")
    }
}

final class CurrencyConversionTests: XCTestCase {
    func testCrossCurrencyConversion() {
        let rate = CurrencyRate(base: "USD",
                                rates: ["USD": 1.0, "CNY": 7.1, "EUR": 0.92],
                                date: "2026-11-14",
                                fetchedAt: Date())
        let converted = rate.convert(19.99, from: "USD", to: "CNY")
        XCTAssertNotNil(converted)
        XCTAssertEqual(converted ?? 0, 19.99 * 7.1, accuracy: 0.001)
    }

    func testUnknownCurrencyReturnsNil() {
        let rate = CurrencyRate(base: "USD", rates: ["USD": 1.0], date: "2026-11-14", fetchedAt: Date())
        XCTAssertNil(rate.convert(10, from: "XYZ", to: "USD"))
    }
}

/// Locks the hard data-honesty rule: a query FAILURE must never be reported as
/// "not listed". `.notListed` may only come from Apple's own lookup saying so.
final class StatusCompositionTests: XCTestCase {
    private let sample = IAPProduct(productID: "sku-1", name: "Plus", offerName: nil,
                                    familyName: "Plan", familyRank: 4,
                                    rawType: "AUTO_RENEWABLE_SUBSCRIPTION", isSubscription: true,
                                    period: "P1M", price: 19.99, currency: "USD",
                                    formattedPrice: "$19.99")

    func testSuccessBeatsEverything() {
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .listed, catalog: .products([sample])), .success)
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .failed, catalog: .products([sample])), .success)
    }

    func testCatalog404WhileListedIsQueryFailureNotNotListed() {
        // The bug this guards against: iTunes says the App is sold here, the
        // catalog endpoint 404s -> that is a failed query, NOT "not listed".
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .listed, catalog: .notFound), .catalogUnavailable)
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .listed, catalog: .failed), .catalogUnavailable)
    }

    func testNotListedOnlyWhenAppleSaysSo() {
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .notListed, catalog: .empty), .notListed)
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .notListed, catalog: .notFound), .notListed)
        // But lookup failure alone must never claim absence:
        XCTAssertNotEqual(GlobalScanner.resolveStatus(lookup: .failed, catalog: .empty), .notListed)
        XCTAssertNotEqual(GlobalScanner.resolveStatus(lookup: .failed, catalog: .notFound), .notListed)
    }

    func testEmptyCatalogWithListedAppIsNoIAPData() {
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .listed, catalog: .empty), .noIAPData)
    }

    func testRateLimitedPropagates() {
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .rateLimited, catalog: .rateLimited), .rateLimited)
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .listed, catalog: .rateLimited), .rateLimited)
    }

    func testProductWithEmptyIDIsUnverified() {
        let broken = IAPProduct(productID: "", name: "?", offerName: nil, familyName: nil,
                                familyRank: nil, rawType: nil, isSubscription: false,
                                period: nil, price: nil, currency: nil, formattedPrice: nil)
        XCTAssertEqual(GlobalScanner.resolveStatus(lookup: .listed, catalog: .products([broken])), .identityUnverified)
    }
}
