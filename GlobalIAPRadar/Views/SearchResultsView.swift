import Foundation
import SwiftUI

struct SearchResultsView: View {
    @Environment(AppState.self) private var appState

    private var language: AppLanguage { appState.settings.language }

    var body: some View {
        List {
            Section {
                ForEach(appState.searchResults) { app in
                    row(app)
                }
            } header: {
                Text(String(format: L10n.t("search.resultCount", language), appState.searchResults.count))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.t("search.title", language))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ app: AppInfo) -> some View {
        HStack(spacing: 10) {
            AppIconView(url: app.artworkURL, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(app.seller)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(app.appID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    appState.toggleFavorite(app)
                } label: {
                    Image(systemName: appState.isFavorite(app.appID) ? "star.fill" : "star")
                        .foregroundStyle(appState.isFavorite(app.appID) ? .yellow : .secondary)
                }
                .buttonStyle(.borderless)

                Button {
                    startScan(app)
                } label: {
                    Image(systemName: "globe.asia.australia.fill")
                        .font(.headline)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.t("search.scan", language))
            }
        }
        .padding(.vertical, 3)
    }

    private func startScan(_ app: AppInfo) {
        appState.scan.startScan(app: app,
                                storefronts: appState.storefronts,
                                maxConcurrent: appState.settings.maxConcurrent)
        appState.selectedTab = .scan
    }
}
