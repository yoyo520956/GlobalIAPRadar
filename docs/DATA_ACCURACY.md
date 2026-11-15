# 数据准确性与完整性规范

本文件是 Global IAP Radar 的硬性规则，任何功能改动都不得违反。

## 1. 状态语义（8 种，互不混淆）

| 状态 | 触发条件 | 界面含义 |
| --- | --- | --- |
| `success` | catalog 接口 200 且内购列表非空，且每条都带 Apple 商品 ID | 查询成功 |
| `productNotFound` | 响应正常但目标商品在该商店不存在 | 商品未发现 |
| `notListed` | iTunes Lookup `resultCount = 0`，或 catalog 返回 404 | 该地区未上架 |
| `noIAPData` | 应用在该商店上架，但数据源未返回任何内购条目 | 数据源未返回 IAP |
| `networkError` | 连接失败、超时、5xx 重试耗尽 | 网络错误 |
| `rateLimited` | 收到 HTTP 429 | 请求被限流 |
| `identityUnverified` | 取到条目但缺少商品 ID，无法确认身份 | 商品身份无法确认 |
| `notVerified` | 尚未完成查询 | 数据尚未验证 |

**关键区分**：`notListed`（商店里没这个应用）、`noIAPData`（商店里有这个应用但没公开内购）、`networkError`（根本没问成功）三者必须分开显示，不得合并成"无此商品"。

## 2. 禁止事项

1. 禁止把未查询到的地区写成价格 0。
2. 禁止把查询失败标记为"未上架"，反之亦然。
3. 禁止在数据缺失时用邻区价格、均价或历史值填补。
4. 禁止把换算价当作 Apple 实际结账价展示——换算价必须与当地原始价并列，并标注汇率来源与日期。
5. 禁止在无法确认商品身份时强行合并 SKU。
6. 禁止在界面或报告中把"覆盖率"写成 100%，除非确实每个商店都取到了数据。

## 3. 每条价格必须携带的字段

```
appID, productID, storefront, productName, kind, period,
price(当地), currency(当地), convertedPrice, rateSource, rateDate,
source(接口), capturedAt, status
```

落库快照（`PriceSnapshot`）保留 appID / productID / storefront / price / currency / capturedAt，
以便历史曲线重算时使用当时的原始价。

## 4. 两套覆盖率

- **地区查询成功率** = 完成查询且状态为 success / 175
- **IAP 商品信息完整率** = 在已成功查询的商店中，商品条目带完整 ID 与价格的商店数 / 175

两者分开显示。例如 ChatGPT 实测：地区成功率 148/175，商品完整率同为 148/175（所有成功商店都返回了带 ID 的商品）；
而 Notion 实测 55/175，其余 119 个商店虽有应用但无内购数据。

## 5. SKU 对齐规则

| 情形 | 键 | 置信度 |
| --- | --- | --- |
| 两地商品 ID 相同 | Apple 商品 ID | 1.00（精确） |
| 无 ID，订阅家族 + 等级 + 周期一致 | `family + rank + period` | 0.92 |
| 无 ID，归一化名称 + 类型 + 周期一致 | `name + kind + period` | 0.70 |
| 无法确认 | 不合并，单独展示 | — |

归一化规则：小写、去除变音符号、仅保留字母数字。因此 "ChatGPT Plus (Monthly)" 与 "chatgpt plus monthly" 视为同名。
不同周期（月付 vs 年付）、不同等级（L4 vs L5）、不同数量（100 Credits vs 1000 Credits）永不合并。

## 6. 数据来源与失败记录

每次扫描产出一份原始快照（`data/probe_<appId>.json`），保留每区的 HTTP 状态码与原始响应摘要，
用于长期监控 Apple 公开数据可用性的变化。CI 的 `data-engine` 任务每次 push 都会重跑并上传新快照。

## 7. 汇率规则

- 数据源：Frankfurter（欧洲央行参考汇率），免费、无需密钥。
- 缓存 6 小时；接口不可用时只显示当地原始价格，不显示换算价，也不用过期汇率冒充新汇率。
- 展示时必须同时给出：当地价格 + 当地货币、换算价格 + 目标货币、汇率日期。
- 汇率换算仅用于横向比较，**不代表**用户在对应商店的实际支付金额（税费、抽成、支付方式均可能不同）。
