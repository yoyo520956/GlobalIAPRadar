import Foundation
import SwiftUI
import Charts

enum HistoryRange: Int, CaseIterable, Identifiable {
    case d7 = 7
    case d30 = 30
    case d90 = 90
    case d180 = 180

    var id: Int { rawValue }

    func label(_ language: AppLanguage) -> String {
        // Labels come from the localisation table so both languages stay in
        // one place and a missing translation fails the audit, not the build.
        switch self {
        case .d7: return L10n.t("history.range7", language)
        case .d30: return L10n.t("history.range30", language)
        case .d90: return L10n.t("history.range90", language)
        case .d180: return L10n.t("history.range180", language)
        }
    }
}

struct HistoryView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedAppID: String?
    @State private var selectedProductID: String?
    @State private var range: HistoryRange = .d30

    private var language: AppLanguage { appState.settings.language }

    private var appIDs: [String] {
        Array(Set(appState.snapshots.map(\.appID))).sorted()
    }

    private var productIDs: [String] {
        appState.snapshots
            .filter { selectedAppID == nil || $0.appID == selectedAppID }
            .map(\.productID)
            .reduce(into: [String]()) { result, id in
                if !result.contains(id) { result.append(id) }
            }
            .sorted()
    }

    private var series: [PriceSnapshot] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -range.rawValue, to: Date()) ?? .distantPast
        return appState.snapshots
            .filter { $0.capturedAt >= cutoff }
            .filter { selectedAppID == nil || $0.appID == selectedAppID }
            .filter { selectedProductID == nil || $0.productID == selectedProductID }
            .sorted { $0.capturedAt < $1.capturedAt }
    }

    private struct HistoryPoint: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    private var chartPoints: [HistoryPoint] {
        series.compactMap { snapshot in
            guard let converted = appState.converted(snapshot.price, from: snapshot.currency) else { return nil }
            return HistoryPoint(id: snapshot.id, date: snapshot.capturedAt, value: converted)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { pickers }
                if chartPoints.count < 2 {
                    Section {
                        Text(L10n.t("history.empty", language))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        chart
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

    /// Split out so the Chart builder closure stays small enough for the
    /// compiler to type-check in reasonable time.
    @ViewBuilder
    private var chart: some View {
        let currency = appState.settings.displayCurrency
        Chart(chartPoints) { point in
            LineMark(x: .value("date", point.date), y: .value("price", point.value))
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
            PointMark(x: .value("date", point.date), y: .value("price", point.value))
                .foregroundStyle(Color.accentColor)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.formatted(.currency(code: currency)))
                            .font(.caption2)
                    }
                }
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
            Picker(L10n.t("history.range", language), selection: $range) {
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
