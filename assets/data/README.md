# assets/data — 词频数据（v2.0 地基）

这两份文件是「材料难度分析」与「词汇量测试」的数据基础，**全部本地计算，不调用任何 API**。

| 文件 | 规模 | 格式 | 来源与许可 |
|---|---|---|---|
| `en_freq_50k.txt` | 50000 行 / 约 608KB | 每行 `词 出现次数`，按出现次数降序 | [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) 的 `content/2018/en/en_50k.txt`（仓库声明 MIT；数据由 OpenSubtitles 2018 语料统计而来，OPUS 语料库） |
| `en_10k_clean.txt` | 9894 行 / 约 73KB | 每行一个词，按频次降序 | [first20hours/google-10000-english](https://github.com/first20hours/google-10000-english) 的 `google-10000-english-no-swears.txt`（来自 Google Trillion Word Corpus，已剔除不雅词） |

## 分工

- **`en_10k_clean.txt`**：书面语register、干净 → 用于**词汇量测试的抽样池**（避免给用户展示字幕里的语气词/不雅词）与前 10k 档位划分。
- **`en_freq_50k.txt`**：覆盖到 50k → 用于**覆盖率 / 生词密度 / CEFR 估计 / 词表记忆**，以及 10k 以上档位的抽样（抽样时会再过一遍"可测词"过滤）。
- 两个文件都只做**本地**统计；App 不上传、不再分发这些数据。

## 换成别的词表

加载与解析都在 `lib/services/word_frequency.dart`，接口与文件格式解耦（`parseFrequencyText` 是纯函数）。
如果要换成更严格许可的词表（例如 NGSL / CC-BY 数据），只要保持"每行 `词 次数`、按降序"的格式替换本文件即可，代码无需改动。
