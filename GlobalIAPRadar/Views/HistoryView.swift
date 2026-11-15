import Foundation
import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedAppID: String?
    @State private var selectedProductID: String?
    @State private var range: HistoryRange = .days30

    enum HistoryRange: Int, CaseIterable, Identifiable {
        case days7 = 7
        case days30 = 30
        case days90 = 90
        case days180 = 180

        var id: Int { rawValue }

        func label(_ language: AppLanguage) -> String {
            switch self {
            case .days7: return L10n.t("history.range7", language)
            case .days30: return L10n.t("history.range30", language)
            case .days90: return L10n.t("history.range90", language)
            case .days180: return L10n.t("history.range180", language)
            }
        }
    }

    private var language: AppLanguage { appState.settings.language }

    private var appIDs: [String] {
        Array(Set(appState.snapshots.map(\.appID))).sorted()
    }

    private var productIDs: [String] {
        let scope = appState.snapshots.filter { $0.appID == selectedAppID }
        var names: [String: String] = [:]
        for snapshot in scope { names[snapshot.productID] = snapshot.productName }
        return names.keys.sorted { (names[$0] ?? "") < (names[$1] ?? "") }
    }

    private var series: [PriceSnapshot] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.rawValue, to: Date()) ?? .distantPast
        return appState.snapshots
            .filter { $0.capturedAt >= cutoff }
            .filter { selectedAppID == nil || $0.appID == selectedAppID }
            .filter { selectedProductID == nil || $0.productID == selectedProductID }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private var chartPoints: [(snapshot: PriceSnapshot, converted: Double)] {
        series.compactMap { snapshot in
            guard let converted = appState.converted(snapshot.price, from: snapshot.currency) else { return nil }
            return (snapshot, converted)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    pickers
                }
                if chartPoints.count < 2 {
                    Section {
                        Text(L10n.t("history.empty", language))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Chart(chartPoints) { point in
                            LineMark(
                                x: .value("date", point.date),
                                y: .value("price", point.value)
                            )
                            .interpolationMethod(.monotone)
                            .foregroundStyle(Color.accentColor)

                            PointMark(
                                x: .value("date", point.date),
                                y: .value("price", point.value)
                            )
                            .foregroundStyle(Color.accentColor)
                        }
                        .chartYAxis {
                            AxisMarks { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let amount = value.as(Double.self) {
                                        Text(amount.formatted(.currency(code: appState.settings.displayCurrency)))
                                            .font(.caption2)
                                    }
                                }
                            }
                        }
                        .frame(height: 190)
                    } header: {
                        Text(selectedProductName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.t("history.title", language))
            .onAppear {
                if selectedAppID == nil { selectedAppID = appIDs.first }
            }
            .onChange(of: selectedAppID) { _, _ in
                selectedProductID = productIDs.first
            }
        }
    }

    private var pickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L10n.t("history.app", language), selection: $selectedAppID) {
                Text(L10n.t("common.all", language)).tag(String?.none)
                ForEach(appIDs, id: \.self) { id in
                    Text(appName(id)).tag(String?.some(id))
                }
            }
            Picker(L10n.t("compare.filter.product", language), selection: $selectedProductID) {
                Text(L10n.t("common.all", language)).tag(String?.none)
                ForEach(productIDs, id: \.self) { id in
                    Text(productName(id)).tag(String?.some(id))
                }
            }
            Picker(L10n.t("history.title", language), selection: $range) {
                ForEach(HistoryRange.allCases) { item in
                    Text(item.label(language)).tag(item)
                }
            }
        }
        .font(.caption)
    }

    private var selectedProductName: String {
        guard let selectedProductID else { return L10n.t("common.all", language) }
        return productName(selectedProductID)
    }

    private func appName(_ id: String) -> String {
        appState.snapshots.first { $0.appID == id }?.appName ?? id
    }

    private func productName(_ id: String) -> String {
        appState.snapshots.first { $0.productID == id }?.productName ?? id
    }
}
