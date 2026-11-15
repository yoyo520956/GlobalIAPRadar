import Foundation

enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case zh
    case en

    var label: String {
        switch self {
        case .zh: return "简体中文"
        case .en: return "English"
        }
    }
}

/// Minimal in-app localisation table. The UI ships in Simplified Chinese by
/// default; English is a complete alternative, not a partial fallback.
enum L10n {
    static let table: [String: (zh: String, en: String)] = [
        "app.tagline": ("一次搜索 · 175 个商店 · 全球比价", "One search · 175 storefronts · global pricing"),
        "app.subtitle": ("全球苹果应用内购价格比较器", "Global App Store in-app purchase comparator"),

        "tab.home": ("首页", "Home"),
        "tab.scan": ("扫描", "Scan"),
        "tab.rank": ("排行", "Rank"),
        "tab.history": ("历史", "History"),
        "tab.settings": ("设置", "Settings"),

        "home.search.placeholder": ("搜索应用名称 / App Store ID / 链接", "App name, App Store ID or URL"),
        "home.search.button": ("搜索", "Search"),
        "home.recent": ("最近搜索", "Recent searches"),
        "home.favorites": ("收藏", "Favourites"),
        "home.coverage": ("全球覆盖", "Global coverage"),
        "home.coverage.hint": ("175 个 Apple 商店，已实测校验", "175 Apple storefronts, empirically validated"),
        "home.noFavorites": ("还没有收藏", "No favourites yet"),
        "home.noRecent": ("暂无记录", "Nothing here yet"),
        "home.dataNote": ("所有价格均为公开数据，标注时间与来源", "All prices are public data, timestamped and attributed"),

        "search.title": ("搜索结果", "Search results"),
        "search.empty": ("没有找到应用", "No app found"),
        "search.resultCount": ("找到 %d 个结果", "%d results"),
        "search.scan": ("全球扫描", "Global scan"),
        "search.favorite": ("收藏", "Favourite"),
        "search.unfavorite": ("取消收藏", "Unfavourite"),

        "scan.title": ("全球扫描", "Global scan"),
        "scan.progress": ("进度", "Progress"),
        "scan.completed": ("已完成", "Completed"),
        "scan.success": ("成功", "Success"),
        "scan.failed": ("失败", "Failed"),
        "scan.discovered": ("发现商品", "Products found"),
        "scan.remaining": ("剩余地区", "Remaining"),
        "scan.pause": ("暂停", "Pause"),
        "scan.resume": ("继续", "Resume"),
        "scan.cancel": ("取消", "Cancel"),
        "scan.retry": ("重试失败地区", "Retry failed"),
        "scan.compare": ("查看比价结果", "Open comparison"),
        "scan.idle": ("先搜索一个应用", "Search for an app first"),
        "scan.elapsed": ("耗时", "Elapsed"),
        "scan.storefrontStatus": ("地区状态", "Storefront status"),

        "compare.title": ("全球比价", "Comparison"),
        "compare.sort.price": ("按价格", "By price"),
        "compare.sort.region": ("按地区", "By region"),
        "compare.filter.product": ("商品", "Product"),
        "compare.filter.period": ("周期", "Period"),
        "compare.onlyLowest": ("只看最低价", "Lowest only"),
        "compare.showAll": ("显示全部 175 区", "Show all 175"),
        "compare.local": ("当地价格", "Local price"),
        "compare.region": ("地区", "Region"),
        "compare.product": ("商品", "Product"),
        "compare.missing": ("该地区未返回数据", "No data returned for this storefront"),
        "compare.empty": ("扫描完成后显示比价结果", "Comparison appears after a scan"),
        "compare.converted": ("换算价格（%@）", "Converted (%@)"),

        "rank.title": ("价格排行", "Price ranking"),
        "rank.lowest": ("最低价", "Lowest"),
        "rank.highest": ("最高价", "Highest"),
        "rank.diff": ("价差", "Gap"),
        "rank.diffPct": ("价差比例", "Gap %"),
        "rank.byCurrency": ("按 %@ 换算排序", "Ranked by %@"),
        "rank.empty": ("暂无排行数据", "No ranking data yet"),

        "detail.title": ("商品详情", "Product detail"),
        "detail.productID": ("商品 ID", "Product ID"),
        "detail.type": ("类型", "Type"),
        "detail.period": ("订阅周期", "Billing period"),
        "detail.source": ("数据来源", "Source"),
        "detail.updated": ("更新时间", "Updated"),
        "detail.status": ("查询状态", "Query status"),
        "detail.coverage": ("覆盖地区", "Storefronts covered"),

        "history.title": ("价格历史", "Price history"),
        "history.range7": ("7 天", "7 days"),
        "history.range30": ("30 天", "30 days"),
        "history.range90": ("90 天", "90 days"),
        "history.range180": ("180 天", "180 days"),
        "history.empty": ("还没有历史快照", "No snapshots yet"),
        "history.app": ("选择应用", "Choose an app"),

        "settings.title": ("设置", "Settings"),
        "settings.language": ("语言", "Language"),
        "settings.currency": ("默认换算货币", "Default currency"),
        "settings.concurrency": ("并发请求数", "Concurrent requests"),
        "settings.cache": ("缓存管理", "Cache"),
        "settings.cacheSize": ("占用", "Size"),
        "settings.clearCache": ("清空缓存", "Clear cache"),
        "settings.licenses": ("开源许可证", "Open-source licences"),
        "settings.sources": ("数据来源说明", "Data sources"),
        "settings.about": ("关于", "About"),
        "settings.version": ("版本", "Version"),

        "status.success": ("查询成功", "Success"),
        "status.productNotFound": ("商品未发现", "Product not found"),
        "status.notListed": ("该地区未上架", "Not listed here"),
        "status.noIAPData": ("数据源未返回 IAP", "Source returned no IAP"),
        "status.catalogUnavailable": ("内购目录查询失败", "IAP catalog query failed"),
        "status.networkError": ("网络错误", "Network error"),
        "status.rateLimited": ("请求被限流", "Rate limited"),
        "status.identityUnverified": ("商品身份无法确认", "Identity unverified"),
        "status.notVerified": ("数据尚未验证", "Not verified"),

        "common.close": ("关闭", "Close"),
        "common.retry": ("重试", "Retry"),
        "common.loading": ("加载中…", "Loading…"),
        "common.unknown": ("未知", "Unknown"),
        "common.none": ("无", "None"),
        "common.all": ("全部", "All"),
        "common.source": ("来源", "Source"),
        "common.error": ("出错了", "Error")
    ]

    static func t(_ key: String, _ language: AppLanguage) -> String {
        guard let entry = table[key] else { return key }
        return language == .zh ? entry.zh : entry.en
    }

    static func periodLabel(_ period: String?, _ language: AppLanguage) -> String {
        guard let period else { return t("common.unknown", language) }
        switch period {
        case "P1W": return language == .zh ? "周付" : "Weekly"
        case "P1M": return language == .zh ? "月付" : "Monthly"
        case "P3M": return language == .zh ? "季付" : "Quarterly"
        case "P6M": return language == .zh ? "半年付" : "Semi-annual"
        case "P1Y": return language == .zh ? "年付" : "Yearly"
        default: return period
        }
    }

    static func kindLabel(_ kind: IAPKind, _ language: AppLanguage) -> String {
        switch kind {
        case .consumable: return language == .zh ? "消耗型内购" : "Consumable"
        case .nonConsumable: return language == .zh ? "非消耗型内购" : "Non-consumable"
        case .subscription: return language == .zh ? "订阅" : "Subscription"
        case .unknown: return language == .zh ? "未知类型" : "Unknown"
        }
    }
}
