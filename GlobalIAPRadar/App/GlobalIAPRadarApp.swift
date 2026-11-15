import SwiftUI
import Observation

enum AppTab: Hashable, Sendable {
    case home
    case scan
    case ranking
    case history
    case settings
}

struct AppSettings: Codable, Sendable, Equatable {
    var language: AppLanguage = .zh
    var displayCurrency: String = "CNY"
    var queryAllStorefronts: Bool = true
    var maxConcurrent: Int = 6
    var requestInterval: Double = 0.12
}

@MainActor
@Observable
final class AppState {
    var selectedTab: AppTab = .home
    var settings = AppSettings() {
        didSet { persistSettings() }
    }
    var storefronts: [Storefront] = []
    var favorites: [Favorite] = []
    var recentSearches: [String] = []
    var snapshots: [PriceSnapshot] = []
    var searchResults: [AppInfo] = []
    var currencyRate: CurrencyRate?
    var currencyMessage: String?
    var lastUpdated: Date?
    var isBootstrapping = true

    let scan = ScanEngine()
    private let store = SnapshotStore()
    private let currency = CurrencyService()

    init() {
        loadStorefronts()
        loadSettings()
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        async let loadedFavorites = store.loadFavorites()
        async let loadedRecent = store.loadRecentSearches()
        async let loadedSnapshots = store.loadSnapshots()
        self.favorites = await loadedFavorites
        self.recentSearches = await loadedRecent
        self.snapshots = await loadedSnapshots
        await refreshRates()
        isBootstrapping = false
    }

    func refreshRates() async {
        do {
            currencyRate = try await currency.latest()
            currencyMessage = nil
        } catch {
            currencyMessage = error.localizedDescription
        }
    }

    // MARK: - Storefronts

    private func loadStorefronts() {
        guard let url = Bundle.main.url(forResource: "storefronts", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        storefronts = (try? decoder.decode([Storefront].self, from: data)) ?? []
    }

    // MARK: - Favourites / history

    func toggleFavorite(_ app: AppInfo) {
        if let index = favorites.firstIndex(where: { $0.appID == app.appID }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(Favorite(appID: app.appID, name: app.name,
                                      seller: app.seller, artworkURL: app.artworkURL), at: 0)
        }
        let snapshot = favorites
        Task { await store.saveFavorites(snapshot) }
    }

    func isFavorite(_ appID: String) -> Bool {
        favorites.contains { $0.appID == appID }
    }

    func recordSearch(_ term: String) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 12 { recentSearches.removeLast(recentSearches.count - 12) }
        let snapshot = recentSearches
        Task { await store.saveRecentSearches(snapshot) }
    }

    /// Persists the prices of the last scan so history charts have something to show.
    func persistSnapshots(for app: AppInfo) async {
        var rows: [PriceSnapshot] = []
        for result in scan.results {
            for product in result.products where product.price != nil {
                rows.append(PriceSnapshot(appID: app.appID,
                                          appName: app.name,
                                          productID: product.productID,
                                          productName: product.name,
                                          storefront: result.storefront,
                                          price: product.price,
                                          currency: product.currency))
            }
        }
        guard !rows.isEmpty else { return }
        snapshots = await store.mergeSnapshots(rows)
        lastUpdated = Date()
    }

    // MARK: - Cache

    func refreshCacheSize() async -> Int64 {
        await store.cacheSizeInBytes()
    }

    func clearCache() async {
        await store.clearCache()
        snapshots = []
        recentSearches = []
    }

    // MARK: - Currency

    func converted(_ price: Double?, from source: String?) -> Double? {
        guard let rate = currencyRate else { return nil }
        return rate.convert(price ?? 0, from: source ?? "USD", to: settings.displayCurrency)
    }

    func formattedConverted(_ price: Double?, from source: String?) -> String {
        guard let price, let converted = converted(price, from: source) else { return "—" }
        return converted.formatted(.currency(code: settings.displayCurrency))
    }

    // MARK: - Settings persistence

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: "app.settings"),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        settings = decoded
    }

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: "app.settings")
    }
}

// MARK: - Root

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label(L10n.t("tab.home", appState.settings.language), systemImage: "magnifyingglass") }
                .tag(AppTab.home)

            ScanView()
                .tabItem { Label(L10n.t("tab.scan", appState.settings.language), systemImage: "globe.asia.australia.fill") }
                .tag(AppTab.scan)

            RankingView()
                .tabItem { Label(L10n.t("tab.rank", appState.settings.language), systemImage: "list.number") }
                .tag(AppTab.ranking)

            HistoryView()
                .tabItem { Label(L10n.t("tab.history", appState.settings.language), systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)

            SettingsView()
                .tabItem { Label(L10n.t("tab.settings", appState.settings.language), systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .task {
            if appState.isBootstrapping {
                await appState.bootstrap()
            }
        }
    }
}

@main
struct GlobalIAPRadarApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}
