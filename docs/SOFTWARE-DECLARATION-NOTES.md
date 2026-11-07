# 软件声明 · 调研依据与拍板记录（不随 App 发布）

> 用途：`assets/about/software_declaration.md` 的来源与写作依据；以及需要作者确认的事项。
> 声明正文由子代理按"个人非商业 + 不公开联系方式 + 防抄袭/防恶意举报"要求起草，Lead 审核后落库。

## 一、调研依据（均为实际打开的页面）

1. TermsFeed《App Disclaimer Template》https://www.termsfeed.com/blog/sample-app-DISCLAIMER-template/
   - 提供免责声明标准分块：informational purposes only / no guarantee / third-party / as-is / 不构成专业意见。
2. legal-pages-starter（GitHub）https://github.com/0xelitesystem/legal-pages-starter
   - 个人项目把服务条款/隐私/免责分开成文的最小模板集。
3. DeepSeek 开放平台服务协议 https://cdn.deepseek.com/policies/zh-CN/deepseek-open-platform-terms-of-service.html
   - 下游开发者对终端用户的披露义务（AI 生成内容、可能存在错误、输入输出权利、个人信息自行披露）；"按现状提供"的口径。
4. 《计算机软件保护条例》全文（最高法知识产权法庭）https://ipc.court.gov.cn/zh-cn/news/view-407.html
   - 著作权自开发完成产生；权利清单；合法复制品所有人权利；学习研究例外。
5. 中国版权保护中心《计算机软件著作权登记指南》https://www.ccopyright.com.cn/index.php?optionid=1033
   - 登记自愿、线上办理、登记证明是初步证明而非权利来源。
6. Flutter LICENSE（BSD-3-Clause）https://raw.githubusercontent.com/flutter/flutter/main/LICENSE
7. pub.dev 包许可证页示例（http 包，BSD-3-Clause）https://pub.dev/packages/http/license
8. Flutter API：showLicensePage https://api.flutter.dev/flutter/material/showLicensePage.html
   - 开源许可页面的低成本实现方式（LicenseRegistry 自动汇总）。
9. 国内个人开发者免责声明实例（塔吉多助手）http://www.mcyx.cc/tjd-tools/disclaimer
   - 中文语气/章节习惯参照。

## 二、写作红线（已遵守）

- 不写绝对化承诺（永久免费/绝对安全/100% 正确/最终解释权）；
- 不编法条编号（只写法律名称）；
- 不写"已获授权/官方合作"；
- 免责加"在适用法律允许的范围内"；
- 不写不存在的联系方式/真名/备案号/商店信息。

## 三、需要作者知道/确认的点

| 事项 | 说明 |
|---|---|
| 署名 | 全文用 `xi283`，未出现真实姓名；维权时以代码仓库提交记录/发布时间戳/早期版本作佐证 |
| 联系方式 | 用户已确认不公开；声明中以"发布渠道"泛指。若将来需要"通知-删除"协作入口，可留一个与身份脱钩的项目页 |
| 软著登记 | 非权利前提；如需维权可线上自行办理（声明中已留口，未写"已登记"） |
| 上架商店 | 当前按"私下分发给朋友"写；一旦上架国内商店，通常还需隐私政策、备案/资质、AI 生成内容标识等 |
| App 内「开源许可」入口 | 声明写了就必须有：用 `showLicensePage` 实现（成本极低），本轮由「关于」页接入 |
| 数据只在本地 | 若将来加崩溃统计/云同步/埋点/日志上报，第 7 节必须改 |
| API Key | 建议用户自填 Key（当前即如此）；不要把 Key 打包进 APK |
| 抓取只做即时展示 | 软件有本地保存材料功能（用户主动保存到自己的设备），声明第 6 节"不建立内容库、不汇编再发布"指**不带服务端内容库**；本地个人缓存与主动保存不改变该口径 |
