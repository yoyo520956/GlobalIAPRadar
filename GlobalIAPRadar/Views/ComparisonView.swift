import SwiftUI

struct ComparisonView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedProductID: String?
    @State private var selectedPeriod = "all"
    @State private var onlyLowest = false
    @State private var showMissing = false

    private var language: AppLanguage { appState.settings.language }

    private var skus: [AlignedSKU] { appState.scan.alignedSKUs }

    private var periods: [String] {
        Array(Set(skus.compactMap(\.period))).sorted()
    }

    private var visibleSKUs: [AlignedSKU] {
        skus.filter { sku in
            (selectedProductID == nil || sku.id == selectedProductID) &&
            (selectedPeriod == "all" || sku.period == selectedPeriod)
        }
    }

    var body: some View {
        List {
            Section {
                filterControls
            }
            if visibleSKUs.isEmpty {
                Section {
                    Text(L10n.t("compare.empty", language))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(visibleSKUs) { sku in
                Section {
                    ForEach(rows(for: sku)) { entry in
                        NavigationLink {
                            ProductDetailView(sku: sku)
                        } label: {
                            row(entry, sku: sku)
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sku.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text(L10n.kindLabel(sku.kind, language))
                            if let period = sku.period {
                                Text(L10n.periodLabel(period, language))
                            }
                            Text("\(sku.coveredStorefronts)/\(sku.totalStorefronts)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("compare.title", language))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Filters

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.t("compare.filter.product", language)).font(.caption)
                Picker("", selection: $selectedProductID) {
                    Text(L10n.t("common.all", language)).tag(String?.none)
                    ForEach(skus) { sku in
                        Text(sku.displayName).tag(String?.some(sku.id))
                    }
                }
                .labelsHidden()
            }
            HStack {
                Text(L10n.t("compare.filter.period", language)).font(.caption)
                Picker("", selection: $selectedPeriod) {
                    Text(L10n.t("common.all", language)).tag("all")
                    ForEach(periods, id: \.self) { period in
                        Text(L10n.periodLabel(period, language)).tag(period)
                    }
                }
                .labelsHidden()
            }
            Toggle(L10n.t("compare.onlyLowest", language), isOn: $onlyLowest)
                .font(.caption)
            Toggle(L10n.t("compare.showAll", language), isOn: $showMissing)
                .font(.caption)
        }
    }

    // MARK: - Rows

    private func rows(for sku: AlignedSKU) -> [SKUPriceEntry] {
        var entries = sku.entries
        if !showMissing {
            entries = entries.filter { $0.price != nil }
        }
        let sorted = entries.sorted { lhs, rhs in
            let left = appState.converted(lhs.price, from: lhs.currency) ?? .greatestFiniteMagnitude
            let right = appState.converted(rhs.price, from: rhs.currency) ?? .greatestFiniteMagnitude
            if left == right { return lhs.storefront < rhs.storefront }
            return left < right
        }
        guard onlyLowest, let cheapest = sorted.first, cheapest.price != nil else { return sorted }
        return sorted.filter { $0.price == cheapest.price }
    }

    private func row(_ entry: SKUPriceEntry, sku: AlignedSKU) -> some View {
        HStack(spacing: 8) {
            StorefrontBadge(code: entry.storefront)
            VStack(alignment: .leading, spacing: 1) {
                Text(storefrontName(entry.storefront))
                    .font(.caption)
                    .lineLimit(1)
                Text(PriceFormat.money(entry.price, currency: entry.currency))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(appState.formattedConverted(entry.price, from: entry.currency))
                    .font(.caption.weight(.semibold))
                Text(entry.currency ?? "—")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 1)
    }

    private func storefrontName(_ code: String) -> String {
        appState.storefronts.first { $0.storefront == code }?.displayName ?? code.uppercased()
    }
}
