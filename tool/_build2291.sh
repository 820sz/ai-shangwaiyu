#!/usr/bin/env bash
cd /d/readflow || exit 1
python - <<'PY'
p='pubspec.yaml'
s=open(p,encoding='utf-8').read().replace('version: 2.29.0+98','version: 2.29.1+99',1)
open(p,'w',encoding='utf-8',newline='\n').write(s)
print('bumped')
PY
cat > docs/release-notes-v2.29.1.md <<'MD'
# ReadFlow v2.29.1 · 搜不到原版时的正确兜底（二手解读 + 模型知识改写）

## 修复 v2.29.0 的两个实际问题

1. **书被"只搜 Gutenberg"卡死**：v2.29.0 按类型把书类查询收窄到公版书源，而《原子习惯》这类商业书没有公版原文 → 0 条；
   补搜用的还是同一个书源 → 三次都在 Gutenberg 里空转。
   - 现在：公开源没有结果时，**用官方搜索（DeepSeek）补搜「这本书的二手解读/书评/读后感」**，
     结果同样过严格相关性（标题/摘要必须出现书名/核心词）。
2. **AI 改写被"必须有来源"挡住**：v2.29.0 改了知识型 prompt，但服务层仍拒绝"0 线索"请求，
   真机上直接提示"不能凭空编"。
   - 现在：只要给了**作品/主题**（书名中文名/原版名），即使 0 条外部线索也允许生成：
     AI 先用自己掌握的知识梳理该作品的 4~8 个核心要点（主旨/观点/方法/结构/结论），再逐点覆盖改写成英文学习版；
     明确标注「AI 改写学习版（非原文）」，禁止编造引文/页码/数据/链接。
   - AI 卡片文案同步更新（不再说"依据 0 条真实线索"这种打击人的话）。

## 验证

- `flutter analyze --no-pub lib`：0 error / 0 warning
- `find_material_free_search_test`、`find_material_ai_rewrite_test`：34 passed
- 发布：`2.29.1+99`，应用内检查更新拉到即装。

## 下一版（已确认方向）

- AI 思考强度做成可调设置（搜索规划/改写/补救轮），并检查是否该用更高模型档位；
- 全 App 灰字冗余注释做一轮"文案瘦身"（删重复解释、长句缩一行），减轻视觉疲劳。
MD
bash tool/lockrun.sh build apk --release --target-platform android-arm64 --no-pub 2>&1 | tail -3
