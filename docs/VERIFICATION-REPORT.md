# 实测验证报告

本报告中的每一个数字都来自对 Apple 公开接口的真实请求，脚本为 `scripts/probe_175.py`，
原始响应快照保存在 `data/probe_<appId>.json`（含每区 HTTP 状态与完整 IAP 列表）。

- 执行环境：iPhone 上的 iSH Linux（Alpine / aarch64），Python 3.11，标准库实现
- 并发：5，最大重试 2 次，HTTP 429 / 5xx 指数退避
- 商店集合：`GlobalIAPRadar/Resources/storefronts.json`，共 **175** 个（来自 appstore-ppp-pricing-agent-skill 的 `countries.csv`，经 mledoze/countries 映射 alpha-3 → alpha-2，并手工补充 Apple 专用代码 `xk` = Kosovo）
- 汇率未参与本报告（报告只统计"是否取到当地原始价格"）

## 1. 覆盖结果

| 应用 | App ID | 有 IAP 数据 | 上架但未返回 IAP | 查询失败（查空） | SKU 数 | 单 SKU 最高覆盖 |
| --- | --- | --- | --- | --- | --- | --- |
| ChatGPT | 6448311069 | 148 (84.6%) | 21 | 6 | 10 | 148 |
| Clash Royale | 1053012308 | 97 (55.4%) | 74 | 4 | 51 | 83 |
| WeChat | 414478124 | 87 (49.7%) | 87 | 1 | 66 | 64 |
| Genshin Impact | 1517783697 | 78 (44.6%) | 94 | 3 | 22 | 74 |
| Notion | 1232780281 | 55 (31.4%) | 119 | 1 | 4 | 55 |
| Spotify | 324684580 | 0 (0%) | 169 | 6 | 0 | — |

### 怎么读这张表

- **有 IAP 数据**：catalog 接口返回 200 且 `views.top-in-app-purchasables.data` 非空。
- **上架但未返回 IAP**：iTunes Lookup 有该应用（证明已在该商店上架），但 catalog 的内购视图为空。实测 Spotify 属于这一类——其 App Store 公开商品页本身也不展示内购商品列表，因此这不是接口缺陷，而是 Apple 公开数据本身没有。
- **查询失败（查空）**：iTunes Lookup `resultCount = 0`，通常意味着该商店没有这个 App（如 ChatGPT 在中国大陆商店不可用）。**这类状态在应用里被标记为"该地区未上架"，绝不会当成 0 元。**

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
| 6448311597 | ChatGPT Plus（ChatGPT Plan · L4 · P1M） | 148 | AE AED 79.99 · AG USD 19.99 · AM USD 22.99 · TR TRY 999,99 · IN ₹399 · JP ¥3,000 |
| 6749460546 | ChatGPT Go（ChatGPT Plan · L5 · P1M） | 148 | AE AED 29.99 · US USD 8.00 · AM USD 6.99 |
| 6759817441 | ChatGPT Pro 100（ChatGPT Plan · L3 · P1M） | 148 | AE AED 384.99 · US USD 100.00 · AM USD 119.99 |
| 6745416289 | ChatGPT Plus（P1Y 年度） | 148 | 与月付 ID 不同，未被合并 |
| 6757568473 | 100 Credits（非订阅消耗型） | 148 | AE AED 15.99 / US USD 4.00 |

结论：**同一商品在不同商店共用同一个 Apple 商品 ID**，因此对齐是精确匹配（置信度 1.0），
月付与年付、Plus 与 Pro、100 钻与 1000 钻天然是不同 ID，不会被错误合并。

## 4. 已知数据异常与处理

| 现象 | 实测 | 应用处理 |
| --- | --- | --- |
| App Store ID 写错 | Clash Royale 误用 1504435335 → 175/175 查空 | 标记"未上架/查询失败"，不会输出 0 元价格 |
| App 在某商店不可售 | ChatGPT 在 `cn` 返回 404 | 标记"该地区未上架"，并区分于网络错误 |
| 中国商店接口可用 | WeChat 在 `cn` 返回正常数据 | 中国区纳入统计 |
| 无内购视图 | Spotify 在 169 个商店返回 200 但内购为空 | 标记"数据源未返回 IAP" |
| 商店代码非 ISO | Kosovo 的 ISO 3166 无对应项 | 手工补充 Apple 代码 `xk`，实测 iTunes 与 catalog 均返回 200 |

## 5. 复现方式

```bash
# 全量扫描一个应用（175 个商店，输出 JSON 快照 + 覆盖率摘要）
python3 scripts/probe_apps.py "ChatGPT=6448311069"

# 重建 175 区数据库
python3 scripts/build_storefronts.py
```

CI 中的 `data-engine` 任务每次 push 都会跑一遍真实扫描并上传快照，用于长期监控数据源可用性的变化。
