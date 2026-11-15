# 实测验证报告

本报告中的每一个数字都来自对 Apple 公开接口的真实请求，脚本为 `scripts/probe_175.py`，
原始响应快照保存在 `data/probe_<appId>.json`（含每区 HTTP 状态与完整 IAP 列表）。

- 执行环境：iPhone 上的 iSH Linux（Alpine / aarch64），Python 3.11，标准库实现
- 并发：5，最大重试 2 次，HTTP 429 / 5xx 指数退避
- 商店集合：`GlobalIAPRadar/Resources/storefronts.json`，共 **175** 个（来自 appstore-ppp-pricing-agent-skill 的 `countries.csv`，经 mledoze/countries 映射 alpha-3 → alpha-2，并手工补充 Apple 专用代码 `xk` = Kosovo）
- 汇率未参与本报告（报告只统计"是否取到当地原始价格"）

## 1. 覆盖结果（2026-11-15 重跑，带 429/5xx 退避重试，并发 3）

| 应用 | App ID | 有 IAP 数据 | 未上架（lookup 空） | 限流失败 | 数据源确无 IAP | SKU 数 | 单 SKU 最高覆盖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ChatGPT | 6448311069 | **164 (93.7%)** | 6 | 5 | 0 | 10 | 164 |
| Notion | 1232780281 | **174 (99.4%)** | 1 | 0 | 0 | 4 | 174 |
| Genshin Impact | 1517783697 | **171 (97.7%)** | 2 | 2 | 0 | 23 | 165 |
| Clash Royale | 1053012308 | **167 (95.4%)** | 4 | 4 | 0 | 58 | 142 |
| WeChat | 414478124 | **166 (94.9%)** | 1 | 8 | 0 | 76 | 123 |
| Spotify | 324684580 | **0** | 6 | 9 | **160** | 0 | — |

### 怎么读这张表

- **有 IAP 数据**：catalog 接口返回 200 且 `views.top-in-app-purchasables.data` 非空。
- **未上架（lookup 空）**：iTunes Lookup 返回 200 但 `resultCount = 0`（Apple 自己说的「该商店不出售此 App」），且 catalog 同时 404——两处来源一致才标「未上架」。**绝不会把网络失败标成未上架**。
- **限流失败**：重试后仍 HTTP 429，明确标为「请求被限流」，可一键重试，不是价格数据。
- **数据源确无 IAP**：catalog 返回 200 但内购视图为空（Spotify 属此类，其 App Store 公开页面本身也不展示内购区块）。
- **错误 App ID**：误用 ID（如 Clash Royale 的 1504435335）会 175/175 查空，被标「未上架/查询失败」，绝不输出 0 元价格。

> 早期快照（无退避重试）因大量 429 把覆盖率低估到 55–85%；带退避后 ChatGPT 实际可达 164/175。应用内引擎同样对 429 做指数退避，并允许对失败区重扫。

## 2. 数据源能力边界（关键结论）

### iTunes Search / Lookup API —— 不含 IAP

`https://itunes.apple.com/lookup?id=6448311069&country=us` 返回的全部字段中与价格相关的只有：

```json
{ "price": 0.00, "currency": "USD", "formattedPrice": "Free" }
```

字段全集里不存在任何应用内购买字段。它能回答"这个 App 在这个商店卖多少钱、是否上架"，**不能**回答"这个 App 的订阅在各个国家多少钱"。

### apps.apple.com catalog 接口 —— 真实 IAP 数据

`https://apps.apple.com/api/apps/v1/catalog/{storefront}/apps/{appId}?platform=web&views=top-in-app-purchasables&l=en-us`

请求头需要 `Authorization: Bearer`（空值即可）与 `Referer: https://apps.apple.com/{storefront}/app/id{appId}`。
这是 App Store 公开商品页自身使用的数据源，**不是** App Store Connect 开发者私有接口，不需要任何密钥。

返回结构（ChatGPT / 美国区，实测节选）：

```json
{ "id": "6448311597",
  "attributes": {
    "name": "ChatGPT Plus",
    "subscriptionFamilyName": "ChatGPT Plan",
    "subscriptionFamilyRank": 4,
    "isSubscription": true,
    "type": "AUTO_RENEWABLE_SUBSCRIPTION",
    "offers": [{ "price": 19.99, "priceFormatted": "$19.99",
                 "currencyCode": "USD", "recurringSubscriptionPeriod": "P1M" }] } }
```

可拿到：商品 ID、名称、订阅家族、等级 rank、是否订阅、计费周期、当地价格与货币。

## 3. 跨商店 SKU 对齐验证

对 ChatGPT 的同一批商品，在 TR / IN / JP / AE / AM 等商店取回的 **Apple 商品 ID 与美区完全一致**：

| 商品 ID | 商品 | 出现商店数 | 价格样例 |
| --- | --- | --- | --- |
| 6448311597 | ChatGPT Plus（ChatGPT Plan · L4 · P1M） | 164 | AE AED 79.99 · US USD 19.99 · AM USD 22.99 · TR TRY 999,99 · IN ₹399 · JP ¥3,000 |
| 6749460546 | ChatGPT Go（ChatGPT Plan · L5 · P1M） | 164 | AE AED 29.99 · US USD 8.00 · AF USD 5.00 |
| 6759817441 | ChatGPT Pro 100（ChatGPT Plan · L3 · P1M） | 164 | AE AED 384.99 · US USD 100.00 · AM USD 119.99 |
| 6745416289 | ChatGPT Plus（P1Y 年度） | 164 | 与月付 ID 不同，未被合并 |
| 6757568473 | 100 Credits（非订阅消耗型） | — | AE AED 15.99 / US USD 4.00 |

结论：**同一商品在不同商店共用同一个 Apple 商品 ID**，因此对齐是精确匹配（置信度 1.0），
月付与年付、Plus 与 Pro、100 钻与 1000 钻天然是不同 ID，不会被错误合并。

## 4. 已知数据异常与处理

| 现象 | 实测 | 应用处理 |
| --- | --- | --- |
| App Store ID 写错 | Clash Royale 误用 1504435335 → 175/175 查空 | 标记"未上架/查询失败"，不会输出 0 元价格 |
| App 在某商店不可售 | ChatGPT 在 `cn`：lookup 200 + resultCount 0，catalog 404 | **两处来源一致**才标"该地区未上架"；任一查询失败都绝不标未上架 |
| catalog 404 但 lookup 说已上架 | 引擎旧版曾误标"未上架"，已修复 | 标记"内购目录查询失败"（`catalogUnavailable`），可重试 |
| HTTP 429 限流 | 重试退避后仍可能发生（单 App 全量扫描 5–9 个区） | 标记"请求被限流"，可一键重试失败区；绝不当成无数据 |
| 中国商店接口可用 | WeChat 在 `cn` 返回正常数据 | 中国区纳入统计 |
| 无内购视图 | Spotify 在 160 个商店返回 200 但内购为空 | 标记"数据源未返回 IAP"（与"查询失败"严格区分） |
| 商店代码非 ISO | Kosovo 的 ISO 3166 无对应项 | 手工补充 Apple 代码 `xk`，实测 iTunes 与 catalog 均返回 200 |

## 5. 构建与测试验证（GitHub Actions，macOS 真机工具链）

- 工作流 `.github/workflows/ios-build.yml`，run **43736153825**（commit 8ae8b7e）**全绿**：
  - `data-engine`：Ubuntu 上对 Apple 真实 API 做 175 区全量扫描，成功并上传快照
  - `ios`：Xcode 16.4 + iPhone SE (3rd generation) iOS 18.5 模拟器（脚本按 SDK 版本自动配对，见 `scripts/select_simulator.py`）
    - Release `iphoneos` 构建 **BUILD SUCCEEDED**
    - 单元测试 **Executed 16 tests, 0 failures — TEST SUCCEEDED**（含状态合成诚实性测试 `StatusCompositionTests` 6 例）
    - 产出未签名 IPA artifact `GlobalIAPRadar-unsigned-ipa`（约 0.5 MB，含可执行文件 + 175 区数据库）
- 本地 IPA 已归档：`GlobalIAPRadar-unsigned.ipa`，SHA-256 `064d5f0e21781d669b9258ab8a95f64e90dfbeaf94a3b073e841165a6ce2edc5`
- 签名 IPA 走 `signed-ipa.yml`（workflow_dispatch，证书/描述文件放在仓库 secrets，个人免费 Apple ID 可用，7 天重签）

## 6. 复现方式

```bash
# 全量扫描一个应用（175 个商店，输出 JSON 快照 + 覆盖率摘要）
python3 scripts/probe_apps.py "ChatGPT=6448311069"

# 重建 175 区数据库
python3 scripts/build_storefronts.py
```

CI 中的 `data-engine` 任务每次 push 都会跑一遍真实扫描并上传快照，用于长期监控数据源可用性的变化。
