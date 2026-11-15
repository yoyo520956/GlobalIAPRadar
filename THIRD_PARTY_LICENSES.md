# 第三方开源许可清单

Global IAPRadar 本体采用 MIT 许可（见 `LICENSE`）。

| 项目 | 许可 | 使用方式 |
| --- | --- | --- |
| [paradossio/AppPriceTracker-iOS](https://github.com/paradossio/AppPriceTracker-iOS) | MIT | 研究参考：全球地区查询流程、iTunes 与 apps.apple.com 两级数据源的组织方式。未直接复制其代码。 |
| [duceum/appstore-ppp-pricing-agent-skill](https://github.com/duceum/appstore-ppp-pricing-agent-skill) | MIT | 数据来源：`appstore_ppp_prices/countries.csv`（175 个 App Store 国家与地区清单）。已转换为 `GlobalIAPRadar/Resources/storefronts.json`，保留原作者版权声明。 |
| [mledoze/countries](https://github.com/mledoze/countries) | CC0 1.0 | 国家代码（alpha-2/alpha-3）、英文名、中文名与 ISO 货币代码映射。属公有领域数据集。 |
| [Frankfurter](https://github.com/frankfurter/frankfurter) | MIT | 运行时汇率数据服务（欧洲央行参考汇率），无需 API Key。 |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | MIT | 仅在 CI 中用于生成 `.xcodeproj`，不进入 App 二进制。 |

## 数据服务（非代码依赖）

| 服务 | 地址 | 说明 |
| --- | --- | --- |
| Apple iTunes Search / Lookup API | `https://itunes.apple.com/search`、`https://itunes.apple.com/lookup` | 免费、无需密钥。公开文档：Apple Developer "Search API"。 |
| Apple App Store 商品页数据 | `https://apps.apple.com/api/apps/v1/catalog/{storefront}/apps/{appId}` | 与 App Store 公开商品页使用同一数据源。属于公开可访问的产品页面数据，**不是** App Store Connect 开发者私有接口。 |
| Frankfurter | `https://api.frankfurter.app` | 免费、无需密钥的公开汇率 API。 |

## 使用限制说明

- 本项目**不**使用 App Store Connect API（该 API 仅能读取开发者自己应用的内购数据，需要 Key ID / Issuer ID / 私钥）。
- 本项目**不**要求 Apple ID 登录，**不**调用任何需要用户凭据的私有接口。
- 抓取频率遵循 `RateLimiter` 的节流设置（默认每次请求最小间隔 0.12 秒，并发上限可在设置中调节），避免对 Apple 服务器造成压力。
- 汇率换算结果为估算值，界面中始终与当地原始价格同时展示，不冒充 Apple 实际结账价。
