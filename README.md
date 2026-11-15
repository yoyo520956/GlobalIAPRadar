# Global IAP Radar

**全球苹果应用内购价格比较器** · One Search. 175 Storefronts.

一个真正的 **SwiftUI 原生 iPhone 应用**：搜索任意 App Store 应用，逐一查询 Apple 全部 175 个国家/地区商店，抓取公开的应用内购买（IAP）商品与当地价格，跨区对齐同一 SKU，并换算成人民币 / 美元 / 英镑生成全球排行。

> 原则：查不到就写"查不到"。不伪造价格、不填充假数据、不把失败标成"未上架"。

---

## 一、已验证的事实（不是宣称，是实测）

以下数字来自本机对真实 Apple 接口的完整 175 区扫描，脚本在 `scripts/probe_175.py`，原始快照在 `data/probe_*.json`。

| 应用 | App ID | 有 IAP 数据 | 未上架 | 限流失败 | 数据源确无 IAP | SKU 数 | 单品最高覆盖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ChatGPT | 6448311069 | **164 / 175 (93.7%)** | 6 | 5 | 0 | 10 | 164 区 |
| Notion | 1232780281 | **174 / 175 (99.4%)** | 1 | 0 | 0 | 4 | 174 区 |
| Genshin Impact | 1517783697 | **171 / 175 (97.7%)** | 2 | 2 | 0 | 23 | 165 区 |
| Clash Royale | 1053012308 | **167 / 175 (95.4%)** | 4 | 4 | 0 | 58 | 142 区 |
| WeChat | 414478124 | **166 / 175 (94.9%)** | 1 | 8 | 0 | 76 | 123 区 |
| Spotify | 324684580 | 0 / 175 | 6 | 9 | 160 | 0 | — |

> 2026-11-15 重跑口径：带 429/5xx 指数退避重试、并发 3。早期无退避快照因限流把覆盖率低估到 55–85%。"未上架"只在 iTunes lookup 与 catalog 两处来源一致时才标注；限流/失败一律单独计数，绝不当成无数据。

三条关键结论：

1. **Apple 的公开 iTunes Search/Lookup API 根本不返回第三方应用内购信息**。它的 60 多个字段里只有 App 自身的 `price` / `currency` / `formattedPrice`，没有任何 IAP 字段。想做全球内购比价，必须用第二个数据源。
2. **可用数据源是 App Store 公开商品页所用的 catalog 接口**：
   `https://apps.apple.com/api/apps/v1/catalog/{storefront}/apps/{appId}?platform=web&views=top-in-app-purchasables`
   它返回结构化 IAP：Apple 商品 ID、名称、订阅家族与等级、计费周期（P1W/P1M/P1Y…）、当地货币价格。不需要 API Key，不需要 Apple ID 登录。
3. **跨区 SKU 对齐可以做到精确，不需要模糊匹配**。实测 TR / IN / JP 三个商店返回的 IAP 商品 ID 与美区 **100% 一致**（6/6），价格则各按当地货币不同（如 ChatGPT Plus 月付：AED 79.99 / USD 19.99 / TRY 999,99 / ₹399 / ¥3,000）。因此 SKU 主键直接采用 Apple 商品 ID。

详细报告见 [`docs/VERIFICATION-REPORT.md`](docs/VERIFICATION-REPORT.md)，数据完整性规则见 [`docs/DATA_ACCURACY.md`](docs/DATA_ACCURACY.md)。

---

## 二、功能

| 页面 | 能力 |
| --- | --- |
| 首页 | 全局搜索（应用名 / App Store ID / 任意 App Store 链接）、最近搜索、收藏、全球覆盖自检、数据来源提示 |
| 搜索结果 | 图标、开发者、App ID、简介、分类；一键收藏 / 一键全球扫描 |
| 全球扫描 | 175 区进度、完成/成功/失败计数、已发现商品数、耗时、**暂停 / 继续 / 取消 / 失败重试**、逐地区状态清单 |
| 全球比价 | 地区 × 商品 × 当地价格 / CNY / USD / GBP；按价格或地区排序；按商品、周期筛选；只看最低价；显示缺失数据 |
| 价格排行 | 每商品最低价 / 最高价商店、绝对价差、价差比例 |
| 商品详情 | 商品 ID、类型（消耗型 / 非消耗型 / 订阅）、订阅周期与等级、全部商店价格、覆盖率、来源与时间 |
| 价格历史 | 本地快照，7 / 30 / 90 / 180 天折线图（Swift Charts） |
| 设置 | 中文 / English、默认换算货币、并发请求数、缓存管理与清理、数据来源说明、许可证清单 |

- 完整简体中文界面，深色 / 浅色自适应，适配 iPhone SE 3（4.7"）小屏，无横向溢出。
- 纯原生 SwiftUI，**没有 WebView 套壳**。
- 本地存储，不注册、不登录、不收集个人信息、不上传搜索历史。

---

## 三、技术架构

```
Swift 6 + SwiftUI + Swift Concurrency + Swift Charts
iOS 17.0+（目标设备 iPhone SE 3，A15 / 4GB）
```

```
GlobalIAPRadar/
├── App/            应用入口、AppState（@Observable）、TabView
├── Models/         Storefront / AppInfo / IAPProduct / IAPPrice / 状态枚举 / 快照
├── Core/           HTTPClient（重试 + 退避 + 429 处理）、AsyncSemaphore、RateLimiter
├── Services/       ITunesClient（actor）、IAPCatalogClient、CurrencyService（actor）
├── Engine/         GlobalScanner（175 区并发扫描）、ScanEngine（状态机）、SKUResolver / SKUAligner
├── Persistence/    SnapshotStore（Application Support 下的 JSON 快照）
├── Views/          8 个功能页面
├── Components/     StatusPill / StatTile / CoverageBar / AppIconView / 格式化
├── Localization/   L10n（中文 / 英文全量文案）
└── Resources/      Info.plist、storefronts.json（175 区数据）
```

关键实现要点：

- **扫描并发**：`AsyncSemaphore` 限流 + `RateLimiter` 请求间隔（默认 0.12s），默认并发 6，可在设置中调 2–12；`TaskGroup` 内每个商店独立请求，单店失败不影响整体。
- **状态语义**：每个商店独立记录 8 种状态（成功 / 商品未发现 / 未上架 / 数据源未返回 IAP / 网络错误 / 被限流 / 身份无法确认 / 未验证），首页与扫描页实时显示分布。
- **SKU 对齐**：主键 = Apple 商品 ID；无 ID 时降级为"订阅家族 + 等级 + 周期"（置信度 0.92）或"归一化名称 + 类型 + 周期"（置信度 0.7），无法确认者保持独立，绝不强行合并。
- **汇率**：Frankfurter（欧洲央行参考汇率，免费无 Key），本地缓存 6 小时；换算值与原始当地价并列展示，接口不可用时只显示当地价。
- **持久化**：刻意使用 JSON 文件而非 SwiftData——数据量小、零依赖、规避 SwiftData 宏在 4GB 设备上的坑。

---

## 四、构建与安装

### 方式 A：使用 GitHub Actions 云端编译（无需 Mac）

1. Fork 本仓库或直接使用 Actions 页面。
2. 打开 **Actions → iOS Build, Test & Data Smoke → Run workflow**。
3. 等待 `Build unsigned IPA` 任务完成，在 Artifacts 下载 `GlobalIAPRadar-unsigned-ipa`。
4. 用 SideStore / AltStore / Feather / TrollStore 之类工具，用你自己的 Apple ID 重签后安装到 iPhone。

> Swift 6 需要 Xcode 16+，因此 CI 使用 `macos-15` + Xcode 16.2。

### 方式 B：在 CI 里用你自己的证书直接签出 IPA

仓库提供 `signed-ipa.yml`（手动触发）。在仓库 **Settings → Secrets and variables → Actions** 添加：

| Secret | 内容 |
| --- | --- |
| `P12_BASE64` | 你的个人签名证书 `.p12` 的 base64（`base64 -i cert.p12 -o cert.b64`） |
| `P12_PASSWORD` | 该 p12 的密码 |
| `PROFILE_BASE64` | `.mobileprovision` 的 base64 |
| `PROFILE_NAME` | 描述文件名称，如 `iOS Developer: 你的名字 (TEAMID)` |
| `TEAM_ID` | Apple Team ID |

**永远不要把 Apple ID 密码交给任何工具**。Apple ID 密码只在你自己的电脑上、用于生成证书时使用。个人 Apple ID 签出的 IPA 通常 **7 天有效期**，到期需重新签名。

### 方式 C：本地 Xcode 构建

```bash
brew install xcodegen
xcodegen generate
open GlobalIAPRadar.xcodeproj
```

命令行打包未签名 IPA：

```bash
xcodebuild -project GlobalIAPRadar.xcodeproj -scheme GlobalIAPRadar \
  -sdk iphoneos -configuration Release -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/GlobalIAPRadar.app Payload/
zip -qr GlobalIAPRadar-unsigned.ipa Payload
```

---

## 五、数据准确性规则（不可妥协）

1. 查询失败 ≠ 未上架；未上架 ≠ 价格 0；缺失数据绝不填 0。
2. 每条价格都带 App ID、商品 ID、商店、当地价格、当地货币、换算价、来源、抓取时间、查询状态。
3. 同时统计两个覆盖率：**地区查询成功率** 与 **IAP 商品信息完整率**，分开显示。
4. 换算价永远与当地原始价同时展示，并标注汇率来源与日期。
5. 商品身份无法确认的条目单独显示，不做强行匹配。

---

## 六、已知限制

- **IAP 覆盖率取决于 Apple 公开数据本身**：某些商店对某应用返回 404（该应用未在该商店上架），某些返回 200 但不含内购视图（如实测的 Spotify：160 个商店上架但都不返回 IAP 列表），另有少数商店限流失败。应用会如实标注各自原因，不做补齐。
- **不保证 App 的内购列表完整**：Apple 只公开商品页上展示的那部分 IAP，且数量可能随时间变化。
- **汇率是 ECB 参考汇率**，不是 Apple 的结算汇率；实际到手价还会受当地税费、App Store 抽成、支付方式影响。
- **地区差异 ≠ 一定能买到**：低价区可能存在支付方式、账号地区、礼品卡等限制。
- 本项目**不能**读取开发者自有应用的 App Store Connect 私有定价接口，也不试图绕过 Apple 的任何授权控制。

---

## 七、许可

MIT，见 [`LICENSE`](LICENSE)。第三方依赖与数据服务说明见 [`THIRD_PARTY_LICENSES.md`](THIRD_PARTY_LICENSES.md)。

数据来源均为公开免费接口，运行时不需要任何付费 API、账号或密钥。
