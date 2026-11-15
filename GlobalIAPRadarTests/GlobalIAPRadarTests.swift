import XCTest
@testable import GlobalIAPRadar

final class StorefrontDatabaseTests: XCTestCase {
    func testStorefrontDatabaseHasAll175Storefronts() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "storefronts", withExtension: "json"))
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
