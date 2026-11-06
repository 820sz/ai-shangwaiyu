/// P0-1 单元测试:真题卷面身份抽取(年份 / 月份 / 套数 / 来源站点)。
///
/// 纪律:只从真实来源抽,抽不到就是空 —— 这些用例就是在钉死"不猜"。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:readflow/services/output_composer.dart';

void main() {
  group('parsePaperMeta · 年份/月份/套数', () {
    test('中文标题:2023 年 12 月第 1 套', () {
      final meta = parsePaperMeta(
        url: 'https://www.neea.edu.cn/html1/report/2306/1-1.htm',
        title: '2023年12月大学英语四级考试真题第1套（写作）',
        siteName: '中国教育考试网',
      );
      expect(meta.year, 2023);
      expect(meta.month, 12);
      expect(meta.setNo, 1);
      expect(meta.siteName, '中国教育考试网');
      expect(meta.label, '2023 年 12 月 · 第 1 套');
      expect(meta.plainLabel, '2023 年 12 月第 1 套');
      expect(meta.compactLabel, '2023.12');
    });

    test('中文套数用汉字:第一套 / 第十二套', () {
      expect(
        parsePaperMeta(title: '2022年6月四级真题第一套').setNo,
        1,
      );
      expect(
        parsePaperMeta(title: '2021年12月六级真题第十二套').setNo,
        12,
      );
      expect(
        parsePaperMeta(title: '2020年9月四级真题第十套').setNo,
        10,
      );
    });

    test('URL 里带年月:2023-12 路径', () {
      final meta = parsePaperMeta(
        url: 'https://example.com/cet4/2023-12/writing',
        title: '大学英语四级写作真题',
      );
      expect(meta.year, 2023);
      expect(meta.month, 12);
      expect(meta.setNo, isNull, reason: 'URL 里没有套数就留空,不猜');
    });

    test('英文站点:December 2023 + Set 2', () {
      final meta = parsePaperMeta(
        url: 'https://example.com/ielts-writing-2023',
        title: 'IELTS Writing Task 2 - December 2023 (Set 2)',
        pageText: 'Cambridge practice paper',
      );
      expect(meta.year, 2023);
      expect(meta.month, 12);
      expect(meta.setNo, 2);
    });

    test('只有年份:标题写「2023 年」→ 月份/套数留空', () {
      final meta = parsePaperMeta(title: '2023 年四级写作真题汇总');
      expect(meta.year, 2023);
      expect(meta.month, isNull);
      expect(meta.setNo, isNull);
      expect(meta.label, '2023 年');
      expect(meta.compactLabel, '2023');
    });

    test('页面正文抬头能抽到(只取前 400 字)', () {
      final meta = parsePaperMeta(
        url: 'https://example.com/a',
        title: '四级写作',
        pageText: '2023年6月大学英语四级真题\n第2套\nDirections: ...',
      );
      expect(meta.year, 2023);
      expect(meta.month, 6);
      expect(meta.setNo, 2);
    });

    test('抽不到就是空(绝不把裸数字当年份)', () {
      final meta = parsePaperMeta(
        url: 'https://example.com/news/12345',
        title: '大学英语四级写作技巧:120 词怎么写',
        pageText: '第 3 页 共 10 页',
      );
      expect(meta.isEmpty, isTrue);
      expect(meta.label, '');
      expect(meta.siteName, 'example.com');
    });

    test('非法月份/套数不采信', () {
      expect(parsePaperMeta(title: '2023年13月四级真题').month, isNull);
      expect(parsePaperMeta(title: '2023年12月四级真题第0套').setNo, isNull);
      expect(parsePaperMeta(title: '2023年12月四级真题第99套').setNo, isNull);
    });

    test('全角数字归一', () {
      final meta = parsePaperMeta(title: '２０２３年１２月四级真题第１套');
      expect(meta.year, 2023);
      expect(meta.month, 12);
      expect(meta.setNo, 1);
    });

    test('站点名:优先检索结果给的 siteName,其次按域名映射,未知显示 host', () {
      expect(
        parsePaperMeta(url: 'https://www.neea.edu.cn/x', siteName: '考试院')
            .siteName,
        '考试院',
      );
      expect(
        parsePaperMeta(url: 'https://www.neea.edu.cn/x').siteName,
        '中国教育考试网',
      );
      expect(
        parsePaperMeta(url: 'https://i.xdf.cn/a/1.html').siteName,
        '新东方',
      );
      expect(
        parsePaperMeta(url: 'https://blog.example.org/p').siteName,
        'blog.example.org',
      );
    });
  });

  group('mergePaperMeta · 多页来源按字段合并', () {
    test('第一页缺套数、第二页有 → 取第二页', () {
      final merged = mergePaperMeta(<PaperMeta>[
        const PaperMeta(year: 2023, month: 12, siteName: '中国教育考试网'),
        const PaperMeta(year: 2021, setNo: 2, siteName: '新东方'),
      ]);
      expect(merged.year, 2023, reason: '按字段取第一个可确认值');
      expect(merged.month, 12);
      expect(merged.setNo, 2);
      expect(merged.siteName, '中国教育考试网');
    });
  });

  group('siteOfLicenseNote / inferExamTypeFromText', () {
    test('从 license_note 里提第一个 URL 的站点名', () {
      const note = '题目来自公开网页抓取(https://www.neea.edu.cn/a.htm , '
          'https://i.xdf.cn/b.htm),仅本地学习使用。';
      expect(siteOfLicenseNote(note), '中国教育考试网');
      expect(siteOfLicenseNote(''), '');
      expect(siteOfLicenseNote('没有链接的说明'), '');
    });

    test('显式写法才推断等级,「四六级」不猜', () {
      expect(inferExamTypeFromText(title: '2023 年 12 月四级真题'), 'cet4');
      expect(inferExamTypeFromText(title: '六级翻译真题'), 'cet6');
      expect(inferExamTypeFromText(title: 'CET-6 writing'), 'cet6');
      expect(inferExamTypeFromText(title: '大学英语四六级真题'), isNull);
      expect(inferExamTypeFromText(title: '考研英语一'), 'kaoyan');
      expect(inferExamTypeFromText(title: 'IELTS task 2'), 'ielts');
      expect(inferExamTypeFromText(title: '随便练练'), isNull);
    });
  });

  group('examSourceLine · 统一来源行', () {
    test('全字段', () {
      expect(
        examSourceLine(
          examType: 'cet4',
          paperYear: 2023,
          paperLabel: '2023 年 12 月 · 第 1 套',
          sourceSite: '中国教育考试网',
          verifyStatus: 'pending',
        ),
        'CET-4 · 2023 年 12 月 · 第 1 套 · 中国教育考试网 · 待校对',
      );
    });

    test('无卷面身份 → 只显示年份/站点,不留空槽', () {
      expect(
        examSourceLine(
          examType: 'cet6',
          paperYear: 2022,
          sourceSite: '新东方',
          verifyStatus: 'verified',
        ),
        'CET-6 · 2022 年 · 新东方 · 已校对',
      );
      expect(
        examSourceLine(examType: 'none', verifyStatus: 'pending'),
        '待校对',
      );
      expect(examSourceLine(examType: 'none'), '');
    });
  });

  group('examTypeFromGoalIds · 中文标签不再落 none(P0-2 修复)', () {
    test('中文目标标签', () {
      expect(examTypeFromGoalIds(const <String>['四六级']), 'cet4');
      expect(examTypeFromGoalIds(const <String>['四级']), 'cet4');
      expect(examTypeFromGoalIds(const <String>['六级']), 'cet6');
      expect(examTypeFromGoalIds(const <String>['考研']), 'kaoyan');
      expect(examTypeFromGoalIds(const <String>['雅思']), 'ielts');
      expect(examTypeFromGoalIds(const <String>['四级', '六级']), 'cet4');
    });

    test('「四六级」泛化档不压过明确目标', () {
      expect(
        examTypeFromGoalIds(const <String>['四六级', '六级']),
        'cet6',
      );
    });

    test('没有考试目标 → none(不猜)', () {
      expect(examTypeFromGoalIds(const <String>[]), 'none');
      expect(examTypeFromGoalIds(const <String>['兴趣阅读']), 'none');
    });

    test('英文 id 兼容', () {
      expect(examTypeFromGoalIds(const <String>['cet6']), 'cet6');
      expect(examTypeFromGoalIds(const <String>['cet']), 'cet4');
    });
  });

  group('resolveExamType · 入口等级筛选优先(P2-1)', () {
    test('设置页筛 CET-6 → 材料出题落 cet6(不被泛化目标盖掉)', () {
      expect(
        resolveExamType(
          examGoals: const <String>['四六级'],
          examTypeOverride: 'cet6',
        ),
        'cet6',
      );
      // 无筛选时才回落到学习目标推导
      expect(
        resolveExamType(examGoals: const <String>['四六级']),
        'cet4',
      );
      expect(
        resolveExamType(examGoals: const <String>['六级']),
        'cet6',
      );
      // 空/'none' 等于没传,不覆盖已有推导
      expect(
        resolveExamType(examGoals: const <String>['考研'], examTypeOverride: ''),
        'kaoyan',
      );
      expect(
        resolveExamType(
          examGoals: const <String>['雅思'],
          examTypeOverride: 'none',
        ),
        'ielts',
      );
    });
  });

  group('OutputSetSpec · paper 字段可持久化', () {
    test('toJson / fromJson 往返', () {
      const spec = OutputSetSpec(
        title: '英语四级(CET-4) · 2023 年 12 月第 1 套 · 写作真题',
        tier: OutputTier.essay,
        source: 'exam',
        examType: 'cet4',
        section: 'writing',
        paperYear: 2023,
        paperLabel: '2023 年 12 月 · 第 1 套',
        sourceSite: '中国教育考试网',
        sourceUrls: <String>['https://www.neea.edu.cn/a.htm'],
        verifyStatus: 'pending',
        tasks: <OutputTaskSpec>[
          OutputTaskSpec(
            tier: OutputTier.essay,
            type: 'exam_writing',
            promptZh: '写一篇关于校园生活的短文',
            reference: '',
            rubricId: 'cet4_writing',
            wordCount: 120,
            sourceUrl: 'https://www.neea.edu.cn/a.htm',
          ),
        ],
      );
      final json = spec.toJson();
      expect(json['paper_year'], 2023);
      expect(json['paper_label'], '2023 年 12 月 · 第 1 套');
      expect(json['source_site'], '中国教育考试网');

      final restored = OutputSetSpec.fromJson(json);
      expect(restored, isNotNull);
      expect(restored!.paperYear, 2023);
      expect(restored.paperLabel, '2023 年 12 月 · 第 1 套');
      expect(restored.sourceSite, '中国教育考试网');
      expect(restored.examType, 'cet4');
      expect(restored.tasks.single.sourceUrl, 'https://www.neea.edu.cn/a.htm');
    });

    test('老 JSON(没有 paper 字段)不崩,字段为空', () {
      final restored = OutputSetSpec.fromJson(<String, Object?>{
        'title': '旧题组',
        'tier': 'sentence',
        'source': 'builtin',
        'tasks': <Object?>[
          <String, Object?>{'type': 'back_translation', 'prompt_zh': '译一句'},
        ],
      });
      expect(restored, isNotNull);
      expect(restored!.paperYear, isNull);
      expect(restored.paperLabel, '');
      expect(restored.sourceSite, '');
    });
  });

  group('buildExamSearchQuery · 年份/套数进检索词', () {
    test('年份 + 套数', () {
      expect(
        buildExamSearchQuery(
          examType: 'cet4',
          section: 'writing',
          year: 2023,
          setNo: 2,
        ),
        'CET-4 writing prompts past exam 2023 set 2',
      );
    });

    test('都不传 → 原样', () {
      expect(
        buildExamSearchQuery(examType: 'cet6', section: 'translation'),
        'CET-6 translation past exam',
      );
    });
  });
}
