import SwiftUI

struct RankingView: View {
    @Environment(AppState.self) private var appState

    private var language: AppLanguage { appState.settings.language }
    private var skus: [AlignedSKU] { appState.scan.alignedSKUs }

    var body: some View {
        NavigationStack {
            List {
                if skus.isEmpty {
                    Section {
                        Text(L10n.t("rank.empty", language))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(String(format: L10n.t("rank.byCurrency", language), appState.settings.displayCurrency))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(skus) { sku in
                        Section {
                            ForEach(extremes(for: sku), id: \.storefront) { entry in
                                HStack(spacing: 8) {
                                    StorefrontBadge(code: entry.storefront,
                                                    tint: entry.isCheapest ? .green : .red)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(storefrontName(entry.storefront)).font(.caption).lineLimit(1)
                                        Text(PriceFormat.money(entry.price, currency: entry.currency))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(appState.formattedConverted(entry.price, from: entry.currency))
                                            .font(.caption.weight(.semibold))
                                        if let gap = entry.gapAmount, let pct = entry.gapPercent {
                                            Text(String(format: "%@ · %.0f%%",
                                                         PriceFormat.money(gap, currency: appState.settings.displayCurrency),
                                                         pct * 100))
                                                .font(.system(size: 9))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(sku.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        } footer: {
                            Text("\(sku.coveredStorefronts)/\(sku.totalStorefronts) · \(sku.distinctCurrencies) 种货币")
                                .font(.caption2)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.t("rank.title", language))
        }
    }

    private struct ExtremeEntry: Identifiable {
        let storefront: String
        let price: Double?
        let currency: String?
        let isCheapest: Bool
        let gapAmount: Double?
        let gapPercent: Double?

        var id: String { storefront }
    }

    /// Lowest and highest storefront for one SKU, expressed in the display currency.
    private func extremes(for sku: AlignedSKU) -> [ExtremeEntry] {
        let priced = sku.entries.compactMap { entry -> (SKUPriceEntry, Double)? in
            guard let price = entry.price,
                  let converted = appState.converted(price, from: entry.currency) else { return nil }
            return (entry, converted)
        }
        guard let min = priced.min(by: { $0.1 < $1.1 }),
              let max = priced.max(by: { $0.1 < $1.1 }) else { return [] }

        let gap = max.1 - min.1
        let percent = min.1 > 0 ? gap / min.1 : nil

        return [
            ExtremeEntry(storefront: min.0.storefront, price: min.0.price, currency: min.0.currency,
                         isCheapest: true, gapAmount: nil, gapPercent: nil),
            ExtremeEntry(storefront: max.0.storefront, price: max.0.price, currency: max.0.currency,
                         isCheapest: false, gapAmount: gap, gapPercent: percent)
        ]
    }

    private func storefrontName(_ code: String) -> String {
        appState.storefronts.first { $0.storefront == code }?.displayName ?? code.uppercased()
    }
}
