import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:readflow/config/constants.dart';
import 'package:readflow/config/design_tokens.dart';
import 'package:readflow/config/theme.dart';
import 'package:readflow/services/profile_card.dart';
import 'package:readflow/widgets/profile_name_card.dart';

/// 名片"大小与形状"回归测试(v2.10,用户第 6 条;v2.11 精简后同步更新)。
///
/// 用户原话:"'我的'界面的个人名片**无法编辑**呀,用户导入的头像、背景,
/// **全都无法编辑大小和形状**。" —— 这条他提了两次,所以这里要钉三件事:
/// 1. **老数据必须还能读**(老用户的 Hive 串里没有 v2.10 的七个 key);
/// 2. **脏数据必须回落**(越界/NaN/乱填的形状名不能把「我的」打崩);
/// 3. **入口必须真的能点开**(v2.11 起是卡右上角的小铅笔 → 弹层 → 改完能落到库里)。
///
/// **这个文件里的等待一律用它,不要用 `tester.pumpAndSettle()`。**
///
/// v2.10 排查结论(50 分钟的"卡死"就是这个):这个页面在测试环境里永远"稳定"不下来 ——
/// `pumpAndSettle` 会一直等到"没有待处理帧",等不满就一直等到默认的 **10 分钟**才抛错,
/// 于是 5 个 widget 用例连起来 = **50 分钟**。
/// 换成本函数:泵一帧 + 有界推进 400ms(足够跑完弹层的进出场动画),永不空转。
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 名片"大小与形状"**数据与换算**回归测试的说明。
///
/// 上面三条合同里,第 1、2 条与渲染换算是纯函数(秒级);
/// 第 3 条与"选中即预览"是 widget 用例(在本文件末尾的 `界面` 组里)。
///
/// **已知问题(交接文档记着的那条)**:widget 用例会真实点「保存名片」→
/// `ProfileCardSettings.save()` 是 `await box.put(...)` 的真实写盘;测试跑在假时钟里,
/// 那次写完不成、一直挂在 Hive 队列上,下一条用例开头 `clear()` 排它后面 → 曾导致
/// **整文件跑永久挂住**(单独跑每条都秒过)。v2.11 已试过 5 种清理姿势都不稳,
/// 现在给清理加了 **3 秒上界**(见 setUp 注释),文件不会再无限挂。
/// 彻底修法:把名片设置的存储抽成可注入接口,测试用内存实现(以后排期)。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUpAll(() async {
    // `save()`/`load()` 往返用例要一个真实 box —— 用临时目录,不碰用户数据
    tmp = Directory.systemTemp.createTempSync('readflow_profile_card_test_');
    Hive.init(tmp.path);
    await Hive.openBox(AppConstants.hiveBoxSettings);
  });

  setUp(() async {
    // ⚠️ **有界清理(v2.11)**:清不掉就 3 秒后放弃,绝不无限等。
    //
    // 已知问题(交接文档记着的那条"整文件跑会挂住"):
    // 本文件里有界面用例会点「保存名片」→ `ProfileCardSettings.save()` 是
    // `await box.put(...)` 的**真实写盘**;widget 测试跑在假时钟里,那次写会一直
    // 挂在 Hive 内部队列上,下一条用例的 `clear()` 排在它后面 → **永久等待**。
    // 表现是"整文件跑挂住、每条单独跑都秒过"。
    //
    // v2.11 已试过 5 种"清干净"的姿势(box.clear+runAsync / deleteBoxFromDisk 重开 /
    // 真时钟空转 / 超时兜底 / 把界面用例拆到另一个文件)都不能稳定解决 ——
    // 根因是**假时钟 vs Hive 写队列**的对冲,不是清理写法。
    // 现在给它一个上界:3 秒清不掉就带着旧数据继续跑,文件不会无限挂。
    // 彻底修法(留给以后排期):把 `ProfileCardSettings` 的存储抽成可注入接口
    // (Hive / 内存两套实现),测试用内存实现 → 零真实 I/O,这个坑连根消失。
    try {
      await Hive.box(AppConstants.hiveBoxSettings)
          .clear()
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('ReadFlow 名片测试:清 Hive box 超时($e),已跳过');
    }
  });

  tearDownAll(() async {
    // ⚠️ **不要在这里调 `Hive.close()`**。
    // v2.10 排查记录:加上它之后 tearDownAll 会卡住(日志里从 40:01 一直挂到 82:13),
    // 因为 Hive 的关闭要 flush 异步写,而 widget 测试用的是假时钟 —— flush 永远等不到。
    // 临时目录里的 box 文件随进程退出自生自灭,留着不影响任何断言。
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // Windows 上 Hive 的 .lock 可能还没释放;删不掉就留着,不影响测试结果
    }
  });

  // ─────────────────────────────────────────────────────────
  // 默认值(写死在测试里:默认值是"老名片不长歪"的合同,改动必须是有意的)
  // ─────────────────────────────────────────────────────────
  group('默认值', () {
    test('七个新字段的默认值 = v2.9 的样子', () {
      const d = ProfileCardSettings.defaults;
      expect(d.avatarSize, 64.0, reason: '中号 64 = v2.9 卡片上写死的尺寸');
      expect(d.avatarShape, 'circle');
      expect(d.avatarBorder, 'none');
      expect(d.bgScale, 1.0);
      expect(d.bgAlign, 'center');
      expect(d.bgDim, 0.45, reason: '≈ v2.9 那层固定压暗(黑 130/90 的均值)');
      expect(d.bgBlur, 0.0);
    });

    test('界面档位齐了:头像三档尺寸 / 三种形状 / 三种边框 / 三种位置', () {
      expect(ProfileCardSettings.avatarSizes.map((e) => e['size']).toList(),
          [48.0, 64.0, 84.0]);
      expect(ProfileCardSettings.avatarShapes.map((e) => e['id']).toList(),
          ['circle', 'rounded', 'square']);
      expect(ProfileCardSettings.avatarBorders.map((e) => e['id']).toList(),
          ['none', 'thin', 'thick']);
      expect(ProfileCardSettings.bgAligns.map((e) => e['id']).toList(),
          ['center', 'top', 'bottom']);
    });
  });

  // ─────────────────────────────────────────────────────────
  // 老数据兼容(用户是升级上来的,库里全是老串)
  // ─────────────────────────────────────────────────────────
  group('旧数据兼容', () {
    test('只有 v2.9 六个 key 的老串:新字段全部走默认,老字段一个不丢', () {
      // 这就是 v2.9 的 _encode 会写出来的格式
      final old = 'avatar_text=${Uri.encodeComponent('樱')}'
          '&background=moss'
          '&signature=${Uri.encodeComponent('每天 20 分钟')}'
          '&nickname=${Uri.encodeComponent('小樱')}';
      final s = ProfileCardSettings.fromEncodedString(old);
      // 老字段原样保留
      expect(s.avatarText, '樱');
      expect(s.backgroundId, 'moss');
      expect(s.signature, '每天 20 分钟');
      expect(s.nickname, '小樱');
      // 新字段回落默认
      expect(s.avatarSize, 64.0);
      expect(s.avatarShape, 'circle');
      expect(s.avatarBorder, 'none');
      expect(s.bgScale, 1.0);
      expect(s.bgAlign, 'center');
      expect(s.bgDim, 0.45);
      expect(s.bgBlur, 0.0);
      // 换算出来的渲染参数也必须是"老样子"
      expect(s.avatarDiameter, 64.0);
      expect(s.avatarRadius, 32.0, reason: '圆形 = 半边长');
      expect(s.avatarBorderWidth, 0.0, reason: '无边框 = 真的不画');
      expect(s.backgroundAlignment, Alignment.center);
    });

    test('空串 / 只有背景 id 的极老串也能读', () {
      expect(ProfileCardSettings.fromEncodedString('').avatarSize, 64.0);
      final s = ProfileCardSettings.fromEncodedString('background=iris');
      expect(s.backgroundId, 'iris');
      expect(s.avatarShape, 'circle');
    });

    test('整条串坏掉/类型不对:回落默认而不是抛异常', () {
      expect(ProfileCardSettings.fromJson(null).nickname, '');
      expect(ProfileCardSettings.fromJson('我是一个字符串').avatarSize, 64.0);
      expect(ProfileCardSettings.fromJson(12345).bgAlign, 'center');
      expect(ProfileCardSettings.fromJson(<String, Object?>{}).bgDim, 0.45);
    });

    test('半个百分号(串被写坏)只丢那一段,不整体回默认', () {
      final s = ProfileCardSettings.fromEncodedString(
          'nickname=abc%&background=ink&avatar_size=84');
      expect(s.backgroundId, 'ink', reason: '坏的那段不影响其它字段');
      expect(s.avatarSize, 84.0);
    });
  });

  // ─────────────────────────────────────────────────────────
  // 脏数据 / 越界 / NaN
  // ─────────────────────────────────────────────────────────
  group('脏数据容错', () {
    test('非数字、越界、NaN、无穷:统统回落或夹到合法区间', () {
      expect(ProfileCardSettings.normalizeAvatarSize('abc'), 64.0);
      expect(ProfileCardSettings.normalizeAvatarSize(null), 64.0);
      expect(ProfileCardSettings.normalizeAvatarSize(-5), 40.0);
      expect(ProfileCardSettings.normalizeAvatarSize(9999), 96.0);
      expect(ProfileCardSettings.normalizeAvatarSize(double.nan), 64.0);
      expect(ProfileCardSettings.normalizeAvatarSize(double.infinity), 64.0);
      expect(ProfileCardSettings.normalizeBgScale('NaN'), 1.0);
      expect(ProfileCardSettings.normalizeBgScale(0.1), 0.8);
      expect(ProfileCardSettings.normalizeBgScale(5), 2.0);
      expect(ProfileCardSettings.normalizeBgDim(-1), 0.0);
      expect(ProfileCardSettings.normalizeBgDim('x'), 0.45);
      expect(ProfileCardSettings.normalizeBgDim(99), 0.8);
      expect(ProfileCardSettings.normalizeBgBlur(-3), 0.0);
      expect(ProfileCardSettings.normalizeBgBlur(999), 12.0);
    });

    test('乱填的形状名/位置名回归默认(不能出现"第四种形状")', () {
      expect(ProfileCardSettings.normalizeAvatarShape('triangle'), 'circle');
      expect(ProfileCardSettings.normalizeAvatarShape(null), 'circle');
      expect(ProfileCardSettings.normalizeAvatarShape('SQUARE'), 'square',
          reason: '大小写不敏感,免得老串里写了大写就失效');
      expect(ProfileCardSettings.normalizeAvatarBorder(42), 'none');
      expect(ProfileCardSettings.normalizeAvatarBorder('thick'), 'thick');
      expect(ProfileCardSettings.normalizeBgAlign('middle'), 'center');
      expect(ProfileCardSettings.normalizeBgAlign('top'), 'top');
    });

    test('一串全是脏数据:逐字段回落,不互相牵连', () {
      final s = ProfileCardSettings.fromJson(<String, Object?>{
        'background': 'not-a-bg',
        'avatar_size': 'abc',
        'avatar_shape': 'triangle',
        'avatar_border': 42,
        'bg_scale': 'NaN',
        'bg_align': 'middle',
        'bg_dim': 'Infinity',
        'bg_blur': 999,
      });
      expect(s.backgroundId, 'dawn');
      expect(s.avatarSize, 64.0);
      expect(s.avatarShape, 'circle');
      expect(s.avatarBorder, 'none');
      expect(s.bgScale, 1.0);
      expect(s.bgAlign, 'center');
      expect(s.bgDim, 0.45);
      expect(s.bgBlur, 12.0);
    });
  });

  // ─────────────────────────────────────────────────────────
  // 往返(存进去 → 读出来,一个字段都不能错)
  // ─────────────────────────────────────────────────────────
  group('往返', () {
    test('toEncodedString → fromEncodedString:含 & = 换行 emoji 的昵称也不串味', () {
      final s = ProfileCardSettings(
        nickname: 'A&B=测试🦊',
        signature: '第一行\n第二行',
        avatarText: '読',
        backgroundId: 'iris',
        avatarSize: 84,
        avatarShape: 'rounded',
        avatarBorder: 'thick',
        bgScale: 1.4,
        bgAlign: 'top',
        bgDim: 0.6,
        bgBlur: 5,
      );
      final back = ProfileCardSettings.fromEncodedString(s.toEncodedString());
      expect(back.nickname, 'A&B=测试🦊');
      expect(back.signature, '第一行\n第二行');
      expect(back.avatarText, '読');
      expect(back.backgroundId, 'iris');
      expect(back.avatarSize, 84.0);
      expect(back.avatarShape, 'rounded');
      expect(back.avatarBorder, 'thick');
      expect(back.bgScale, 1.4);
      expect(back.bgAlign, 'top');
      expect(back.bgDim, 0.6);
      expect(back.bgBlur, 5.0);
      // 往返两遍必须完全一样(免得第一次读就悄悄改了值)
      final again = ProfileCardSettings.fromEncodedString(back.toEncodedString());
      expect(again.toEncodedString(), back.toEncodedString());
    });

    test('图片路径往返,空路径回落成 null', () {
      final s = ProfileCardSettings(
        avatarPath: r'C:\data\avatar.jpg',
        backgroundPath: r'C:\data\card_bg.png',
      );
      final back = ProfileCardSettings.fromEncodedString(s.toEncodedString());
      expect(back.avatarPath, r'C:\data\avatar.jpg');
      expect(back.backgroundPath, r'C:\data\card_bg.png');
      expect(
        ProfileCardSettings.fromEncodedString(
                const ProfileCardSettings(avatarPath: '').toEncodedString())
            .avatarPath,
        isNull,
      );
    });

    test('save()/load():真的落到 Hive 里,再读回来一模一样', () async {
      final s = ProfileCardSettings(
        nickname: '小樱',
        avatarSize: 84,
        avatarShape: 'square',
        backgroundPath: r'C:\data\card_bg.png',
        bgScale: 1.8,
        bgAlign: 'bottom',
        bgDim: 0.7,
        bgBlur: 9,
      );
      await s.save();
      final back = ProfileCardSettings.load();
      expect(back.nickname, '小樱');
      expect(back.avatarSize, 84.0);
      expect(back.avatarShape, 'square');
      expect(back.backgroundPath, r'C:\data\card_bg.png');
      expect(back.bgScale, 1.8);
      expect(back.bgAlign, 'bottom');
      expect(back.bgDim, 0.7);
      expect(back.bgBlur, 9.0);
    });

    test('load():库里是 v2.9 的老串(手工写入)→ 新字段默认,老字段还在', () async {
      await Hive.box(AppConstants.hiveBoxSettings).put(
        AppConstants.keyProfileCard,
        'nickname=${Uri.encodeComponent('老用户')}&background=clay&avatar_text=${Uri.encodeComponent('🦊')}',
      );
      final s = ProfileCardSettings.load();
      expect(s.nickname, '老用户');
      expect(s.backgroundId, 'clay');
      expect(s.avatarText, '🦊');
      expect(s.avatarSize, 64.0);
      expect(s.bgDim, 0.45);
    });

    test('load():库里是 Map(v2.8 更早的写法)也能读', () async {
      await Hive.box(AppConstants.hiveBoxSettings)
          .put(AppConstants.keyProfileCard, <String, Object?>{
        'nickname': 'Map用户',
        'background': 'rose',
        'avatar_size': 48,
      });
      final s = ProfileCardSettings.load();
      expect(s.nickname, 'Map用户');
      expect(s.backgroundId, 'rose');
      expect(s.avatarSize, 48.0);
    });
  });

  // ─────────────────────────────────────────────────────────
  // 渲染换算:形状 / 边框 / 位置 / 压暗
  // ─────────────────────────────────────────────────────────
  group('渲染换算', () {
    test('三种形状的圆角:圆形=半边、圆角=22%、方形=0', () {
      expect(
        const ProfileCardSettings(avatarSize: 64, avatarShape: 'circle')
            .avatarRadius,
        32.0,
      );
      expect(
        const ProfileCardSettings(avatarSize: 64, avatarShape: 'rounded')
            .avatarRadius,
        closeTo(14.08, 0.001),
      );
      expect(
        const ProfileCardSettings(avatarSize: 84, avatarShape: 'square')
            .avatarRadius,
        0.0,
      );
    });

    test('三种边框宽度:无=0(不画)、细=1.5、粗=3', () {
      expect(const ProfileCardSettings(avatarBorder: 'none').avatarBorderWidth,
          0.0);
      expect(const ProfileCardSettings(avatarBorder: 'thin').avatarBorderWidth,
          1.5);
      expect(
          const ProfileCardSettings(avatarBorder: 'thick').avatarBorderWidth, 3.0);
    });

    test('三种取景位置 → Alignment', () {
      expect(const ProfileCardSettings(bgAlign: 'center').backgroundAlignment,
          Alignment.center);
      expect(const ProfileCardSettings(bgAlign: 'top').backgroundAlignment,
          Alignment.topCenter);
      expect(const ProfileCardSettings(bgAlign: 'bottom').backgroundAlignment,
          Alignment.bottomCenter);
    });

    test('压暗 alpha:0.45 → 115;只对自选图生效(渐变那条路不读它)', () {
      expect(const ProfileCardSettings().backgroundDimAlpha, 115);
      expect(const ProfileCardSettings(bgDim: 0).backgroundDimAlpha, 0);
      expect(const ProfileCardSettings(bgDim: 0.8).backgroundDimAlpha, 204);
    });

    test('copyWith:能单独改一个新字段,其余保持不变', () {
      const s = ProfileCardSettings(nickname: '樱', avatarSize: 48);
      final t = s.copyWith(avatarShape: 'rounded');
      expect(t.avatarShape, 'rounded');
      expect(t.nickname, '樱');
      expect(t.avatarSize, 48.0);
    });
  });

  // ─────────────────────────────────────────────────────────
  // 界面:入口与"选中即预览"
  //
  // v2.11 精简后的界面合同(用户 10/5 第 3 条):
  // - 入口是**右上角的小铅笔**(宽按钮与那句说明文案都按要求删了);
  // - 弹层还在,大小/形状/边框仍是三组 chip,但排在一行标题下(约 1 屏);
  // - "选中即预览"必须成立(改了立刻在弹层顶部预览里看到)。
  // ─────────────────────────────────────────────────────────
  group('界面', () {
    Widget host(Widget child) => MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ListView(
              padding: Insets.page,
              children: [child],
            ),
          ),
        );

    /// 卡片本体上的头像。
    ///
    /// 为什么不能直接 `find.byType(ProfileCardAvatar)`:弹层是 `PopupRoute`
    /// (半透明遮罩),它下面的「我的」页**仍然在树上**,所以弹层打开时全树有 3 个头像
    /// (卡片 + 弹层预览 + 弹层头像区)。这里用祖先限定,免得断言断到别人身上。
    Finder cardAvatar() => find.descendant(
          of: find.byType(ProfileNameCard),
          matching: find.byType(ProfileCardAvatar),
        );

    /// 弹层里的头像(第一个 = 顶部实时预览,第二个 = 头像区的实物预览)
    Finder sheetAvatars() => find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(ProfileCardAvatar),
        );

    /// 卡上右上角那个小铅笔(v2.11:用户 10/5 第 3 条"编辑名片保留个小铅笔",
    /// 同时要求去掉那句多余的说明文字和宽按钮)。
    /// 用 Semantics 标签找:文字没了以后,这是**唯一**一个"能说出名字"的入口,
    /// 也顺带把无障碍标签一起钉住。
    Finder pencil() => find.bySemanticsLabel('编辑名片');

    testWidgets('卡上有个小铅笔;点它 → 弹层出现(入口可用)', (tester) async {
      await tester.pumpWidget(host(const ProfileNameCard(vocabCount: 12)));
      await settle(tester);

      expect(pencil(), findsOneWidget, reason: '入口必须在卡上看得见(小铅笔)');
      // v2.11:用户要求去掉圈起来的那两样 —— 说明文案与宽按钮
      expect(find.textContaining('点这里改名字'), findsNothing);
      expect(find.text('编辑名片'), findsNothing, reason: '宽按钮已按用户要求删掉,只留铅笔');

      await tester.tap(pencil());
      await settle(tester);

      expect(find.text('保存名片'), findsOneWidget, reason: '弹层打开了');
      // v2.11 精简:三组 chip 合并到一行标题下(大小/形状/边框);分组标题也简化了
      expect(find.text('大小 · 形状 · 边框'), findsOneWidget);
      expect(find.text('名字 · 签名'), findsOneWidget);
    });

    testWidgets('点卡片空白处(不是按钮)也能打开弹层', (tester) async {
      await tester.pumpWidget(host(const ProfileNameCard(vocabCount: 12)));
      await settle(tester);
      // 点卡片**自己的留白**(左内边距那条缝),验证整卡可点。
      // 为什么不用 find.text('我'):卡上头像占位与昵称各有一个"我",
      // 文字 finder 会命中两个(旧写法就是因此报 ambiguous 而失败的)——
      // 而且这里本来要测的就是"空白处",不是某个具体文字。
      final rect = tester.getRect(find.byType(ProfileNameCard));
      await tester.tapAt(Offset(rect.left + 4, rect.center.dy));
      await settle(tester);
      expect(find.text('保存名片'), findsOneWidget);
    });

    testWidgets('选「大 84」→ 预览立刻变大;保存后卡片与库里都是 84', (tester) async {
      await tester.pumpWidget(host(const ProfileNameCard(vocabCount: 12)));
      await settle(tester);
      expect(tester.getSize(cardAvatar()), const Size(64, 64));

      await tester.tap(pencil());
      await settle(tester);
      // 弹层里:预览(卡) + 头像区各一个头像
      expect(sheetAvatars(), findsNWidgets(2));

      // 选大号 —— "选中即预览"是这次的硬要求
      await tester.ensureVisible(find.text('大 84'));
      await settle(tester);
      await tester.tap(find.text('大 84'));
      await settle(tester);
      expect(
        tester.getSize(sheetAvatars().first),
        const Size(84, 84),
        reason: '弹层顶部的实时预览必须立刻变成 84',
      );

      // 换形状与边框也一样要立刻反映
      await tester.ensureVisible(find.text('圆角'));
      await settle(tester);
      await tester.tap(find.text('圆角'));
      await settle(tester);
      final previewAvatar = tester.widget<ProfileCardAvatar>(
        sheetAvatars().first,
      );
      expect(previewAvatar.settings.avatarShape, 'rounded');
      expect(previewAvatar.settings.avatarRadius, closeTo(18.48, 0.01));

      await tester.ensureVisible(find.text('粗边框'));
      await settle(tester);
      await tester.tap(find.text('粗边框'));
      await settle(tester);
      expect(
        tester
            .widget<ProfileCardAvatar>(sheetAvatars().first)
            .settings
            .avatarBorder,
        'thick',
      );

      // 保存 → 卡片本体与 Hive 都要更新
      await tester.tap(find.text('保存名片'));
      await settle(tester);
      expect(find.text('保存名片'), findsNothing, reason: '弹层关了');
      expect(tester.getSize(cardAvatar()), const Size(84, 84));
      final stored = ProfileCardSettings.load();
      expect(stored.avatarSize, 84.0);
      expect(stored.avatarShape, 'rounded');
      expect(stored.avatarBorder, 'thick');
      expect(find.text('名片已更新'), findsOneWidget);

      // 把 SnackBar 的定时器放掉,免得测试结束时还挂着
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
    });

    testWidgets('下滑关闭弹层 = 什么都不改', (tester) async {
      await tester.pumpWidget(host(const ProfileNameCard()));
      await settle(tester);
      await tester.tap(pencil());
      await settle(tester);
      await tester.ensureVisible(find.text('大 84'));
      await settle(tester);
      await tester.tap(find.text('大 84'));
      await settle(tester);
      expect(tester.getSize(sheetAvatars().first), const Size(84, 84));

      // 直接关掉弹层(等价于下滑/点遮罩)
      Navigator.of(tester.element(find.text('保存名片'))).pop();
      await settle(tester);
      expect(tester.getSize(cardAvatar()), const Size(64, 64),
          reason: '没点保存就不该有任何变化');
      expect(ProfileCardSettings.load().avatarSize, 64.0);
    });

    testWidgets('各种形状/边框/尺寸组合都能渲染出来(不崩、尺寸对)', (tester) async {
      for (final shape in ['circle', 'rounded', 'square']) {
        for (final border in ['none', 'thin', 'thick']) {
          for (final size in [48.0, 64.0, 84.0]) {
            await tester.pumpWidget(host(ProfileCardView(
              settings: ProfileCardSettings(
                nickname: '樱',
                signature: '每天 20 分钟',
                avatarShape: shape,
                avatarBorder: border,
                avatarSize: size,
              ),
              vocabCount: 3,
              baselineText: 'CET-4',
              dailyMinutes: 20,
            )));
            await tester.pump();
            expect(tester.takeException(), isNull,
                reason: '$shape/$border/$size 这组渲染出错');
            expect(
              tester.getSize(find.byType(ProfileCardAvatar)),
              Size(size, size),
            );
          }
        }
      }
    });
  });
}
