# ReadFlow v2.28.1 · 你的 Logo + 4 个小 bug 修复

> 本版在 v2.28.0 基础上：
> ① 换成你生成的 Logo（琉璃气泡 +「語」+ AI），开屏与桌面图标一起换；
> ② 修 4 个真机小问题；③ 更新检查更及时。

## 1. 新 Logo（你提供的图）

- 开屏：琉璃极光底 + 琉璃块凝结 → **你的 Logo 淡入**（1.5s，点击可跳过，文案仍可自定义）；不再出现旧的手绘「引号+星芒」。
- 桌面图标：用同一张图生成 **5 个密度**的方形图标（48/72/96/144/192），Android 8+ 用自适应图标（前景用抠图版 108~432 + monochrome 单色层），Android 12+ 系统开屏底色也调成同一套浅蓝紫，启动不闪白。
- 资源：`assets/logo/app_logo_full.png`（整图，开屏/图标源）、`app_logo_fg.png`（透明底，自适应图标/单色层）。

## 2. 四个小修复

1. **「我的」名片背景被遮**：照片模糊 6px→3px，纸色遮罩从 92/84/94 降到 **52/22/86**（上淡下重：照片主体看得见，底部数据区仍清晰）；顺手修了三栏「约 4250 词」被截成「约 425…」的问题（改等比缩放）。
2. **软件思想措辞**：删掉「学术合理化」整段，现在就是 **你的原文 + 参考文献（21 条真实文献，含 DOI/馆藏链接）**；内容页也去掉了重复标题（顶栏「软件思想」+ 正文「谈谈语言学习的本质」两层，不再三层同名）。
3. **语境选词填空**：上方「来自《…》」长标题不再被右边界裁断，改为单行省略。
4. **更新检查更及时**：启动自动检查从每天一次收紧到 **每 2 小时**；并新增「从后台回到前台再查一次」，有新版本就弹更新窗；手动「检查更新」不受限。

## 3. 验证

- `flutter analyze --no-pub lib`：**0 error / 0 warning**（仅 7 条存量 info）
- 定点测试：`splash_screen_test` 5/5、`splash_preview_test` 20/20（含线上组件真实帧）、`profile_about_test` 8/8、`profile_about_render_test` 5/5、`cloze_practice_test`、`update_service_test` 全绿
- 渲染对照：`docs/ui-preview/real/splash-real-a-f4.png`（开屏终帧）、`app-icon-1024.png`（图标主图）、`assist-mine-impl-namecard-photo.png`（名片背景）、`assist-mine-impl-about-doc.png`（软件思想页）
- 未跑全量测试套件（按用户要求省时间）；无新依赖、无数据库结构变更、dbVersion 未动

## 4. 发布

- `2.28.1+94`，GitHub Release 资产 `app-release.apk`；用户走应用内「检查更新」验收。
