import Foundation
import SwiftUI

struct ProductDetailView: View {
    let sku: AlignedSKU
    @Environment(AppState.self) private var appState

    private var language: AppLanguage { appState.settings.language }

    var body: some View {
        List {
            Section {
                detailGrid
            }
            Section {
                ForEach(sortedEntries) { entry in
                    HStack(spacing: 8) {
                        StorefrontBadge(code: entry.storefront)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(storefrontName(entry.storefront)).font(.caption).lineLimit(1)
                            Text(PriceFormat.money(entry.price, currency: entry.currency))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(appState.formattedConverted(entry.price, from: entry.currency))
                            .font(.caption.weight(.semibold))
                    }
                }
            } header: {
                Text(L10n.t("detail.coverage", language))
            } footer: {
                Text("\(sku.coveredStorefronts)/\(sku.totalStorefronts) · \(sku.distinctCurrencies) 种货币 · \(L10n.t("common.source", language)): apps.apple.com")
                    .font(.caption2)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(sku.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("detail.type", language))
                Spacer()
                Text(L10n.kindLabel(sku.kind, language)).foregroundStyle(.secondary)
            }
            .font(.footnote)
            if let period = sku.period {
                HStack {
                    Text(L10n.t("detail.period", language))
                    Spacer()
                    Text(L10n.periodLabel(period, language)).foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
            HStack {
                Text(L10n.t("detail.productID", language))
                Spacer()
                Text(sku.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
            .font(.footnote)
            HStack {
                Text(L10n.t("detail.updated", language))
                Spacer()
                Text(PriceFormat.relative(appState.lastUpdated)).foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
    }

    private var sortedEntries: [SKUPriceEntry] {
        sku.entries.sorted { lhs, rhs in
            let left = appState.converted(lhs.price, from: lhs.currency) ?? .greatestFiniteMagnitude
            let right = appState.converted(rhs.price, from: rhs.currency) ?? .greatestFiniteMagnitude
            if left == right { return lhs.storefront < rhs.storefront }
            return left < right
        }
    }

    private func storefrontName(_ code: String) -> String {
        appState.storefronts.first { $0.storefront == code }?.displayName ?? code.uppercased()
    }
}
