# 哲学文献核验报告（21 条候选 · 2026-11-07）

> 目标：给 `assets/about/software_philosophy.md` 的「学术合理化」部分补**真实**文献与链接。
> 用户纪律：**不能胡编文献**。所以本报告只写**本轮真的核到**的东西；没核到的一律标出来，
> 不猜 DOI、不猜年份、不猜页码。
>
> 核验手段（都可复现，见文末 §6）：
> 1. **Crossref API** 低带宽 `select` 查询（核期刊文章：DOI / 卷期 / 页码 / 年份 / 刊名）；
> 2. **图书馆 MARC 记录**（Michigan eLibrary，核书籍：出版社 / 年份 / 版次 / ISBN）；
> 3. **官方/机构页面**（高等教育出版社产品库、Council of Europe 官方文件、Cambridge Core 书评页、mtmt 文献库）；
> 4. **DOI 直连**（`https://doi.org/...` 为真实可打开的落地页）。
>
> 结论速览：**21 条全部核到（采用 21）**，其中 **1 条必须改版次**（Saussure 1983→1986）、
> **1 条版本建议下修**（Nation 引 2001，别写 2013）、**2 条需改表述**（CEFR 不是「听说读写四技能」；
> 现代汉语教材没有「语言三要素」提法）；
> **0 条判为「未核到，不采用」**——但有 3 处细节（Saussure 1916 原版、Ebbinghaus 出版者、Nation 2013 版）
> 本轮**没有**在可打开页面逐字核到，已在表中单独标注，供你决定是否保留。

---

## 1. 主表（逐条结论）

| # | 论点 | 结论 | 完整引用 | DOI / 链接 | 核验来源与说明 |
|---|---|---|---|---|---|
| 1 | 符号系统 / 能指所指 | **采用（版次要改）** | Saussure, F. de. *Course in General Linguistics*（W. Baskin 译）. LaSalle, Ill.: Open Court, **1986**. ISBN 0-8126-9023-0 | [elibrary.mel.org/record=b15953880](https://elibrary.mel.org/record=b15953880) | 馆藏记录明确 `LaSalle, Ill. : Open Court, 1986`。**原稿写「Open Court, 1983」是错的**：1983 年那本是 Duckworth（Harris 译本，ISBN 0-7156-1670-6）。法文原版 1916（Paris: Payot）为通行著录，本轮未在可打开页面核到 |
| 2 | 语言作为社会符号 / 交际与思维 | **采用** | Halliday, M. A. K. *Language as Social Semiotic: The Social Interpretation of Language and Meaning*. London: Edward Arnold, 1978. | [Cambridge Core 书评页](https://www.cambridge.org/core/journals/language-in-society/article/abs/mak-hallidaylanguage-as-social-semiotic-the-social-interpretation-of-language-and-meaning-london-edwardarnold-1978-pp-256/12CEC8267EFAC14C9CAFAC76112A318F) | 《Language in Society》书评页标题即「…London: Edward Arnold, 1978. Pp. 256」，作者/出版者/年份/页数四项一致 |
| 3 | 语言定义 / 现代汉语体系 | **采用** | 黄伯荣, 廖序东. 现代汉语（增订六版）[M]. 北京: 高等教育出版社, 2017. ISBN 978-7-04-046593-8（上册） | [高教社产品信息检索](https://xuanshu.hep.com.cn/front/h5Mobile/bookDetails?bookId=59cf9518ba9eb884cf823c68#1) | 高教社官方产品页：作者「黄伯荣 廖序东」、**出版时间 2017 年 5 月**、ISBN 978-7-04-046593-8、ISBN 物料号 46593-00。下册另有记录（[商城页](https://mall.hep.com.cn/index.php/product-26075.html)），年份未单独核到 |
| 4 | 输入假设 | **采用** | Krashen, S. D. *Principles and Practice in Second Language Acquisition*. Oxford: Pergamon Press, 1982. ISBN 0-08-028628-3 | [elibrary.mel.org/record=b11489661](https://elibrary.mel.org/record=b11489661) | MARC 记录 imprint：`Oxford ; New York : Pergamon Press, 1982`，ISBN 0080286283，ix+202 p.。另有 1983 年两篇书评（Modern Language Journal 67:168；TESOL Quarterly 17:300）佐证 |
| 5 | 输出假设 | **采用** | Swain, M. Communicative competence: Some roles of comprehensible input and comprehensible output in its development[M]//Gass, S. M., Madden, C. G. (Eds.). *Input in Second Language Acquisition*. Rowley, MA: Newbury House, 1985: 235-253. | [mtmt 文献库 1780820](https://m2.mtmt.hu/api/reference/1780820) | 文献库条目逐字给出：`(1985) Input in Second Language Acquisition, pp. 235-253., S. M. Gass, & C. G. Madden (Eds.), Rowley, MA: Newbury House`（页码与原文一致） |
| 6 | 互动假设 | **采用** | Long, M. H. The role of the linguistic environment in second language acquisition[M]//Ritchie, W. C., Bhatia, T. K. (Eds.). *Handbook of Second Language Acquisition*. San Diego: Academic Press, 1996: 413-468. | [doi:10.1016/B978-012589042-7/50015-3](https://doi.org/10.1016/B978-012589042-7/50015-3) | Crossref：`book-chapter`，Elsevier（Academic Press 为其 imprint），issued 1996，**page 413-468**，作者 Michael H. Long——年份与页码都被 Crossref 直接核到 |
| 7 | 纠错反馈类型 / 学习者 uptake | **采用** | Lyster, R., & Ranta, L. Corrective feedback and learner uptake[J]. *Studies in Second Language Acquisition*, 1997, 19(1): 37-66. | [doi:10.1017/S0272263197001034](https://doi.org/10.1017/S0272263197001034) | Crossref：SSLA 19(1)，page 37-66，1997-03，作者 Lyster & Ranta。⚠️ 注意 DOI 结尾是 **1034**（不是常见的 1022） |
| 8 | 反馈效力模型 | **采用** | Hattie, J., & Timperley, H. The power of feedback[J]. *Review of Educational Research*, 2007, 77(1): 81-112. | [doi:10.3102/003465430298487](https://doi.org/10.3102/003465430298487) | Crossref 复核通过：RER 77(1): 81-112，2007，作者 John Hattie（University of Auckland）& Helen Timperley |
| 9 | 语言能力分级（接收/产出） | **采用（表述要改）** | Council of Europe. *Common European Framework of Reference for Languages: Learning, teaching, assessment*. Strasbourg: Council of Europe, 2001.（另有 *Companion Volume*, 2020） | [CEFR 官方文件](https://rm.coe.int/CoERMPublicCommonSearchServices/DisplayDCTMContent?documentId=0900001680697848) ／ [Companion Volume 官方页](https://www.coe.int/en/web/education/newsroom/-/asset_publisher/fkf5o6A9gZZK/content/common-european-framework-of-reference-for-languages-learning-teaching-assessment-companion-volume) | Council of Europe 官方文件库与官方新闻页两份都在线。⚠️ **CEFR 不是「听说读写四技能」**：框架按 **接收(reception) / 产出(production) / 互动(interaction) / 中介(mediation)** 四种模式组织，写「接收与产出」才贴原文 |
| 10 | 语言能力模型（测试用途） | **采用** | Bachman, L. F., & Palmer, A. S. *Language Testing in Practice: Designing and Developing Useful Language Tests*. Oxford: Oxford University Press, 1996. ISBN 0-19-437148-4 | [elibrary.mel.org/record=b10484581](https://elibrary.mel.org/record=b10484581) | MARC 记录 imprint：`Oxford, England ; New York, New York : Oxford University Press, [1996]`，vi+377 p.，ISBN 0194371484。目录含 test usefulness / language ability 等章，与「语言能力模型」论点对得上 |
| 11 | 词汇知识 / 覆盖率 | **采用（引 2001 版，别写 2013）** | Nation, I. S. P. *Learning Vocabulary in Another Language*. Cambridge: Cambridge University Press, 2001. | [doi:10.1017/CBO9781139524759](https://doi.org/10.1017/CBO9781139524759) ／ 第 3 版 [doi:10.1017/9781009093873](https://doi.org/10.1017/9781009093873) | Crossref 核到两版：**2001**（CUP，2001-03-15）与 **2022 第 3 版**（CUP，2022-06-02）。**2013 第 2 版本轮未核到**——建议引 2001（最常被引）或 2022 |
| 12 | SLA 综述（含个体差异/反馈/输入输出） | **采用** | Ellis, R. *The Study of Second Language Acquisition* (2nd ed.). Oxford: Oxford University Press, 2008. ISBN 978-0-19-442257-4 | [elibrary.mel.org/record=b11851082](https://elibrary.mel.org/record=b11851082) | MARC 记录：`Oxford ; New York : Oxford University Press, 2008`，**2nd ed.**，xxvii+1142 p.，ISBN 0194422577 / 9780194422574；目录含 input/interaction、individual learner differences、form-focused instruction 等章节 |
| 13 | 遗忘曲线 | **采用（馆藏/电子版已核）** | Ebbinghaus, H. *Über das Gedächtnis: Untersuchungen zur experimentellen Psychologie*. Leipzig: Duncker & Humblot, 1885.（英译 *Memory: A Contribution to Experimental Psychology*, 1913） | [HathiTrust 馆藏 010044672](https://catalog.hathitrust.org/Record/010044672) ／ [Internet Archive 扫描件](https://archive.org/details/berdasgedchtnis01ebbigoog) ／ [APA PsycNET doi:10.1037/10011-000](https://psycnet.apa.org/doiLanding?doi=10.1037/10011-000) | 1885 德文原版有馆藏记录 + 全文扫描；1913 英译有 APA 电子版。⚠️ **出版者「Duncker & Humblot」与英译「Teachers College, Columbia University」按通行著录，本轮未在可打开页面逐字核到**（相关馆藏站在反爬） |
| 14 | 间隔效应 | **采用** | Cepeda, N. J., Pashler, H., Vul, E., Wixted, J. T., & Rohrer, D. Distributed practice in verbal recall tasks: A review and quantitative synthesis[J]. *Psychological Bulletin*, 2006, 132(3): 354-380. | [doi:10.1037/0033-2909.132.3.354](https://doi.org/10.1037/0033-2909.132.3.354) | Crossref：Psychological Bulletin 132(3): 354-380，2006，五位作者与原文一致 |
| 15 | 测试效应 | **采用** | Roediger, H. L., & Karpicke, J. D. Test-enhanced learning: Taking memory tests improves long-term retention[J]. *Psychological Science*, 2006, 17(3): 249-255. | [doi:10.1111/j.1467-9280.2006.01693.x](https://doi.org/10.1111/j.1467-9280.2006.01693.x) | Crossref：Psychological Science 17(3): 249-255，2006-03，Roediger（Washington University in St. Louis）& Karpicke |
| 16 | 间隔重复 | **采用** | Kang, S. H. K. Spaced repetition promotes efficient and effective learning[J]. *Policy Insights from the Behavioral and Brain Sciences*, 2016, 3(1): 12-19. | [doi:10.1177/2372732215624708](https://doi.org/10.1177/2372732215624708) | Crossref：Policy Insights from the Behavioral and Brain Sciences 3(1): 12-19，2016-01-13，作者 Sean H. K. Kang（Dartmouth College） |
| 17 | 个体差异 | **采用** | Dörnyei, Z. *The Psychology of the Language Learner: Individual Differences in Second Language Acquisition*. Mahwah, NJ: Lawrence Erlbaum, 2005. | [mtmt 文献库 19109027](https://m2.mtmt.hu/api/reference/19109027) | 文献库条目逐字：`Dörnyei, Zoltán. 2005. The psychology of the language learner: Individual differences in second language acquisition. Mahwah, NJ: Lawrence Erlbaum.`（另有 SSLA 书评在线） |
| 18 | 自我决定理论 | **采用** | Deci, E. L., & Ryan, R. M. The "what" and "why" of goal pursuits: Human needs and the self-determination of behavior[J]. *Psychological Inquiry*, 2000, 11(4): 227-268. | [doi:10.1207/S15327965PLI1104_01](https://doi.org/10.1207/S15327965PLI1104_01) | Crossref：Psychological Inquiry 11(4): 227-268，2000-10，Deci & Ryan |
| 19 | 真实材料 | **采用** | Gilmore, A. Authentic materials and authenticity in foreign language learning[J]. *Language Teaching*, 2007, 40(2): 97-118. | [doi:10.1017/S0261444807004144](https://doi.org/10.1017/S0261444807004144) | Crossref：Language Teaching 40(2): 97-118，2007-03-07，作者 Alex Gilmore。⚠️ DOI 结尾是 **4144** |
| 20 | 泛读 | **采用** | Day, R. R., & Bamford, J. *Extensive Reading in the Second Language Classroom*. New York: Cambridge University Press, 1998. | [Cambridge Core 书评页](https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/abs/extensive-reading-in-the-second-language-classroom-richard-r-day-and-julian-bamford-new-york-cambridge-university-press-1998-pp-vii-238-5995-cloth-2195-paper/29ED77AA66949034652AECF72F159729) | SSLA 书评页标题即「…New York: Cambridge University Press, 1998. Pp. vii + 238」，四项一致 |
| 21 | 反拨效应 | **采用** | Bailey, K. M. Working for washback: A review of the washback concept in language testing[J]. *Language Testing*, 1996, 13(3): 257-279. | [doi:10.1177/026553229601300303](https://doi.org/10.1177/026553229601300303) | Crossref：Language Testing 13(3): 257-279，1996-11，作者 Kathleen M. Bailey |

---

## 2. 必须改的 3 处（不改会被懂行的人一眼看穿）

1. **Saussure 的 Open Court 版是 1986，不是 1983。**
   1983 年那本是 **Duckworth**（Roy Harris 译本，ISBN 0-7156-1670-6）；Open Court 出的是 **Baskin 译本，LaSalle, Ill., 1986**，ISBN 0-8126-9023-0。
   → 文末若写「Open Court, 1983」等于把两个版本缝在一起。
   建议写法：`Saussure, F. de. Course in General Linguistics[M]. Trans. W. Baskin. LaSalle, Ill.: Open Court, 1986.`（法文原版 1916 可写在正文里，不必做条目）
2. **Nation 别写 2013。** 本轮只核到 **2001**（DOI 10.1017/CBO9781139524759）与 **2022 第 3 版**（DOI 10.1017/9781009093873）。2013 第 2 版没有核到可打开记录 → 引 2001 最稳。
3. **现代汉语不是「语言三要素」的出处。** 我核了高教社官方书目：上册 = 绪论 / 语音 / 文字 / 词汇；下册 = 语法 / 修辞。**书里没有「三要素」这个提法**。文中若写「黄伯荣、廖序东认为语言有三要素」，属于**文献说过头**；改成「现代汉语教材把语音、词汇、语法分章讲授（修辞另列）」或直接引「语言是一种音义结合的符号系统」这类书里真有的表述。

## 3. 另外 4 处「文献别说过头」提醒

| 文献 | 它真正说的是 | 别写成 |
|---|---|---|
| Krashen 1982（#4） | 输入假设 + 情感过滤的完整表述；i+1 是**理论构想** | 「Krashen 证明了 i+1」「可理解输入被实验证实」 |
| Swain 1985（#5） | 「可理解输出」的**提出处**；注意/修正等功能是后续版本 | 把输出假设的成熟版（noticing / modified output）全挂到 1985 |
| CEFR 2001/2020（#9） | 接收 / 产出 / 互动 / 中介 四种模式 + A1–C2 六级 | 「CEFR 分听说读写四技能」 |
| Ebbinghaus 1885（#13） | 无意义音节 + **单一被试**（他自己）的节省法实验 | 「Ebbinghaus 证明了人类遗忘曲线」——它是**开创性个案实验**，不是普适定律 |

另：**Kang 2016（#16）是政策综述（Policy Insights），不是元分析**；正文若要写「元分析表明」，请改用 Cepeda 2006（#14，真正的 quantitative synthesis）或 Roediger & Karpicke 2006（#15）。

---

## 4. 参考文献（GB/T 7714，按主表序号）

```
[1]  SAUSSURE F de. Course in general linguistics[M]. BASKIN W, trans. LaSalle, Ill.: Open Court, 1986.
[2]  HALLIDAY M A K. Language as social semiotic: the social interpretation of language and meaning[M]. London: Edward Arnold, 1978.
[3]  黄伯荣, 廖序东. 现代汉语: 增订六版[M]. 北京: 高等教育出版社, 2017.
[4]  KRASHEN S D. Principles and practice in second language acquisition[M]. Oxford: Pergamon Press, 1982.
[5]  SWAIN M. Communicative competence: some roles of comprehensible input and comprehensible output in its development[M]//GASS S M, MADDEN C G. Input in second language acquisition. Rowley, MA: Newbury House, 1985: 235-253.
[6]  LONG M H. The role of the linguistic environment in second language acquisition[M]//RITCHIE W C, BHATIA T K. Handbook of second language acquisition. San Diego: Academic Press, 1996: 413-468.
[7]  LYSTER R, RANTA L. Corrective feedback and learner uptake[J]. Studies in Second Language Acquisition, 1997, 19(1): 37-66. DOI:10.1017/S0272263197001034.
[8]  HATTIE J, TIMPERLEY H. The power of feedback[J]. Review of Educational Research, 2007, 77(1): 81-112. DOI:10.3102/003465430298487.
[9]  COUNCIL OF EUROPE. Common European framework of reference for languages: learning, teaching, assessment[M]. Strasbourg: Council of Europe, 2001.（另见 Companion Volume, 2020）
[10] BACHMAN L F, PALMER A S. Language testing in practice: designing and developing useful language tests[M]. Oxford: Oxford University Press, 1996.
[11] NATION I S P. Learning vocabulary in another language[M]. Cambridge: Cambridge University Press, 2001. DOI:10.1017/CBO9781139524759.
[12] ELLIS R. The study of second language acquisition[M]. 2nd ed. Oxford: Oxford University Press, 2008.
[13] EBBINGHAUS H. Über das Gedächtnis: Untersuchungen zur experimentellen Psychologie[M]. Leipzig: Duncker & Humblot, 1885.
[14] CEPEDA N J, PASHLER H, VUL E, et al. Distributed practice in verbal recall tasks: a review and quantitative synthesis[J]. Psychological Bulletin, 2006, 132(3): 354-380. DOI:10.1037/0033-2909.132.3.354.
[15] ROEDIGER H L, KARPICKE J D. Test-enhanced learning: taking memory tests improves long-term retention[J]. Psychological Science, 2006, 17(3): 249-255. DOI:10.1111/j.1467-9280.2006.01693.x.
[16] KANG S H K. Spaced repetition promotes efficient and effective learning[J]. Policy Insights from the Behavioral and Brain Sciences, 2016, 3(1): 12-19. DOI:10.1177/2372732215624708.
[17] DÖRNYEI Z. The psychology of the language learner: individual differences in second language acquisition[M]. Mahwah, NJ: Lawrence Erlbaum, 2005.
[18] DECI E L, RYAN R M. The "what" and "why" of goal pursuits: human needs and the self-determination of behavior[J]. Psychological Inquiry, 2000, 11(4): 227-268. DOI:10.1207/S15327965PLI1104_01.
[19] GILMORE A. Authentic materials and authenticity in foreign language learning[J]. Language Teaching, 2007, 40(2): 97-118. DOI:10.1017/S0261444807004144.
[20] DAY R R, BAMFORD J. Extensive reading in the second language classroom[M]. New York: Cambridge University Press, 1998.
[21] BAILEY K M. Working for washback: a review of the washback concept in language testing[J]. Language Testing, 1996, 13(3): 257-279. DOI:10.1177/026553229601300303.
```

### 4.1 文末「可点击真实链接」清单（给非专业读者点的那种）

期刊文章统一用 DOI 落地页（**全部已核到**，点开即出版社官方页）：

- #7 https://doi.org/10.1017/S0272263197001034
- #8 https://doi.org/10.3102/003465430298487
- #14 https://doi.org/10.1037/0033-2909.132.3.354
- #15 https://doi.org/10.1111/j.1467-9280.2006.01693.x
- #16 https://doi.org/10.1177/2372732215624708
- #18 https://doi.org/10.1207/S15327965PLI1104_01
- #19 https://doi.org/10.1017/S0261444807004144
- #21 https://doi.org/10.1177/026553229601300303
- #6（书章）https://doi.org/10.1016/B978-012589042-7/50015-3
- #11（书）https://doi.org/10.1017/CBO9781139524759

书籍（无 DOI 的用馆藏/机构页，均为真实可打开页面）：

- #1 https://elibrary.mel.org/record=b15953880
- #2 https://www.cambridge.org/core/journals/language-in-society/article/abs/mak-hallidaylanguage-as-social-semiotic-the-social-interpretation-of-language-and-meaning-london-edwardarnold-1978-pp-256/12CEC8267EFAC14C9CAFAC76112A318F
- #3 https://xuanshu.hep.com.cn/front/h5Mobile/bookDetails?bookId=59cf9518ba9eb884cf823c68
- #4 https://elibrary.mel.org/record=b11489661
- #5 https://m2.mtmt.hu/api/reference/1780820
- #9 https://rm.coe.int/CoERMPublicCommonSearchServices/DisplayDCTMContent?documentId=0900001680697848
- #10 https://elibrary.mel.org/record=b10484581
- #12 https://elibrary.mel.org/record=b11851082
- #13 https://catalog.hathitrust.org/Record/010044672
- #17 https://m2.mtmt.hu/api/reference/19109027
- #20 https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/abs/extensive-reading-in-the-second-language-classroom-richard-r-day-and-julian-bamford-new-york-cambridge-university-press-1998-pp-vii-238-5995-cloth-2195-paper/29ED77AA66949034652AECF72F159729

---

## 5. 三条细节保留意见（要不要写进文末由你定）

| 位置 | 情况 | 建议 |
|---|---|---|
| #1 法文原版 1916（Paris: Payot） | 通行著录，本轮**未**找到可打开的权威记录（BnF/Gallica 未能访问） | 正文提「1916 年初版」可以，**别把它做成带链接的条目**；条目挂 1986 英文版 |
| #13 Ebbinghaus 出版者（Duncker & Humblot / Teachers College） | 1885 原版与 1913 英译都核实存在（馆藏 + 扫描件 + APA 电子版），但**出版者字串未逐字核到** | 条目保留出版者（学界通识），文末链接用 HathiTrust / PsycNET，别给出版社官网链接 |
| #11 Nation 2013 第 2 版 | 未核到 | 引 2001 或 2022，**不要写 2013** |

---

## 6. 核验方法与可复现命令

```bash
# 期刊文章（低带宽,只取需要的字段）
curl -s "https://api.crossref.org/works?query.bibliographic=Corrective+feedback+and+learner+uptake+Lyster+Ranta&rows=1&select=DOI,title,author,issued,container-title,page,volume,issue"
# → 10.1017/s0272263197001034 · Studies in Second Language Acquisition · 19(1) · 37-66 · 1997

# 书（MARC 记录，出版者/年份/版次/ISBN 都在）
#   https://elibrary.mel.org/search?/X<书名关键词>&SORT=D
#   → 结果里点进 /record=b######## 记录页
#   Krashen=b11489661 · Bachman&Palmer=b10484581 · Ellis=b11851082 · Saussure(Open Court)=b15953880

# 中文教材（高教社官方产品库，出版时间/ISBN/作者）
#   https://xuanshu.hep.com.cn/front/h5Mobile/bookDetails?bookId=59cf9518ba9eb884cf823c68
#   → 黄伯荣 廖序东 · 2017 年 5 月 · ISBN 978-7-04-046593-8

# 官方机构文件
#   https://rm.coe.int/...documentId=0900001680697848  (CEFR 原文)
#   https://m2.mtmt.hu/api/reference/<id>               (Swain 1780820 / Dörnyei 19109027)
```

**本轮没做的事**（避免误伤）：没有改 `assets/about/` 下任何 md、没改 `lib/`、没装依赖、没有 commit。
