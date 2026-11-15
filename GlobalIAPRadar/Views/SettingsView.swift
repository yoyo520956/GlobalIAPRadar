import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var cacheSize: Int64 = 0
    @State private var showSources = false
    @State private var showLicenses = false

    private var language: AppLanguage { appState.settings.language }

    var body: some View {
        @Bindable var appState = appState
        NavigationStack {
            Form {
                Section(L10n.t("settings.language", language)) {
                    Picker(L10n.t("settings.language", language), selection: $appState.settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { item in
                            Text(item.label).tag(item)
                        }
                    }
                }

                Section(L10n.t("settings.currency", language)) {
                    Picker(L10n.t("settings.currency", language), selection: $appState.settings.displayCurrency) {
                        ForEach(["CNY", "USD", "GBP", "EUR", "JPY"], id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    if let rate = appState.currencyRate {
                        LabeledContent {
                            Text(rate.date).foregroundStyle(.secondary)
                        } label: {
                            Text("ECB / \(rate.base)")
                        }
                    }
                    if let message = appState.currencyMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section(L10n.t("settings.concurrency", language)) {
                    Stepper(value: $appState.settings.maxConcurrent, in: 2...12) {
                        Text("\(appState.settings.maxConcurrent)")
                    }
                }

                Section(L10n.t("settings.cache", language)) {
                    LabeledContent(L10n.t("settings.cacheSize", language)) {
                        Text(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        Task {
                            await appState.clearCache()
                            await refreshCacheSize()
                        }
                    } label: {
                        Label(L10n.t("settings.clearCache", language), systemImage: "trash")
                    }
                }

                Section {
                    Button { showSources = true } label: {
                        Label(L10n.t("settings.sources", language), systemImage: "doc.text.magnifyingglass")
                    }
                    Button { showLicenses = true } label: {
                        Label(L10n.t("settings.licenses", language), systemImage: "shippingbox")
                    }
                }

                Section(L10n.t("settings.about", language)) {
                    LabeledContent(L10n.t("settings.version", language)) {
                        Text(version).foregroundStyle(.secondary)
                    }
                    LabeledContent(L10n.t("common.source", language)) {
                        Text("apps.apple.com").foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com/yoyo520956/GlobalIAPRadar")!) {
                        Label("GitHub", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .navigationTitle(L10n.t("settings.title", language))
            .sheet(isPresented: $showSources) { DataSourcesView() }
            .sheet(isPresented: $showLicenses) { LicensesView() }
            .task { await refreshCacheSize() }
        }
    }

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func refreshCacheSize() async {
        cacheSize = await appState.refreshCacheSize()
    }
}

struct DataSourcesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var language: AppLanguage { appState.settings.language }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    block(title: "iTunes Search / Lookup API",
                          body: "https://itunes.apple.com/search 与 https://itunes.apple.com/lookup —— 免费、无需密钥。用于应用身份、上架状态与 App 本身的当地价格。官方接口不返回第三方应用内购商品。")
                    block(title: "apps.apple.com catalog API",
                          body: "https://apps.apple.com/api/apps/v1/catalog/{storefront}/apps/{appId}?platform=web&views=top-in-app-purchasables —— App Store 公开商品页所用的同一数据源，返回应用内购买商品的本地货币价格、订阅周期与等级。")
                    block(title: "Frankfurter (ECB 参考汇率)",
                          body: "https://api.frankfurter.app —— 免费、无需密钥的欧洲央行参考汇率。换算结果仅为估算，不代表 Apple 实际结账价，界面中始终与当地原始价格同时展示。")
                    block(title: "覆盖范围与限制",
                          body: "并非所有应用在所有商店都公开内购清单：部分商店会返回 404（该应用未上架），部分商店返回 200 但不含内购视图，另有部分应用的 App Store 页面根本不展示内购商品。应用会把这些情况分别标记为「未上架」「数据源未返回 IAP」，绝不用 0 元或假数据填充。")
                    block(title: "本地数据",
                          body: "收藏、搜索历史与价格快照全部保存在设备本地 Application Support 目录，不上传服务器，不需要账号，也不收集任何个人信息。")
                }
                .padding(16)
            }
            .navigationTitle(L10n.t("settings.sources", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("common.close", language)) { dismiss() }
                }
            }
        }
    }

    private func block(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct LicensesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var language: AppLanguage { appState.settings.language }

    private let entries: [(String, String, String)] = [
        ("Global IAP Radar", "MIT", "本项目源码许可，版权归贡献者所有。"),
        ("AppPriceTracker-iOS (paradossio)", "MIT", "全球地区查询与内购数据接口的研究参考。"),
        ("appstore-ppp-pricing-agent-skill (duceum)", "MIT", "175 个 App Store 国家与地区清单来源。"),
        ("mledoze/countries", "CC0 1.0", "国家代码、中英文名称与货币映射数据集。"),
        ("Frankfurter", "MIT", "免费汇率数据服务。")
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries, id: \.0) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.0).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(entry.1)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }
                        Text(entry.2).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle(L10n.t("settings.licenses", language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("common.close", language)) { dismiss() }
                }
            }
        }
    }
}
