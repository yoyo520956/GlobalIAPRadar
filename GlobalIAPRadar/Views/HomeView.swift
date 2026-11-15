import Foundation
import SwiftUI

enum AppRoute: Hashable {
    case results
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var query = ""
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var path: [AppRoute] = []
    @FocusState private var isFieldFocused: Bool

    private var language: AppLanguage { appState.settings.language }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    searchCard
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                    coverageCard
                    recentSection
                    favoritesSection
                    disclaimer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .results:
                    SearchResultsView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appState.selectedTab = .settings
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(L10n.t("tab.settings", language))
                }
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Global IAP Radar")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
            Text(L10n.t("app.tagline", language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L10n.t("home.search.placeholder", language), text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isFieldFocused)
                    .onSubmit(performSearch)
                if isSearching {
                    ProgressView()
                } else {
                    Button(action: performSearch) {
                        Text(L10n.t("home.search.button", language))
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var coverageCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("home.coverage", language)).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(appState.storefronts.count)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
            }
            Text(L10n.t("home.coverage.hint", language))
                .font(.caption)
                .foregroundStyle(.secondary)
            if appState.storefronts.count < 175 {
                Label("Storefront database incomplete: \(appState.storefronts.count)/175",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var recentSection: some View {
        if !appState.recentSearches.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("home.recent", language))
                    .font(.subheadline.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.recentSearches, id: \.self) { term in
                            Button {
                                query = term
                                performSearch()
                            } label: {
                                Text(term)
                                    .font(.footnote)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("home.favorites", language))
                .font(.subheadline.weight(.semibold))
            if appState.favorites.isEmpty {
                Text(L10n.t("home.noFavorites", language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.favorites) { favorite in
                    HStack(spacing: 10) {
                        AppIconView(url: favorite.artworkURL, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(favorite.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text(favorite.seller).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button {
                            query = favorite.appID
                            performSearch()
                        } label: {
                            Image(systemName: "globe.asia.australia")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var disclaimer: some View {
        Text(L10n.t("home.dataNote", language))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func performSearch() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isFieldFocused = false
        isSearching = true
        errorMessage = nil
        Task {
            do {
                let results = try await appState.scan.searchApps(term: term)
                appState.searchResults = results
                appState.recordSearch(term)
                isSearching = false
                if results.isEmpty {
                    errorMessage = L10n.t("search.empty", language)
                } else {
                    path.append(.results)
                }
            } catch {
                isSearching = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
