import 'dart:io';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:image_picker/image_picker.dart';

import '../config/design_tokens.dart';
import 'brief_kit.dart';
import '../models/learner_model.dart';
import '../services/learner_model_store.dart';
import '../services/profile_card.dart';

/// 「我的」顶部个性化名片(v2.8 初版,v2.9 按用户反馈重做,v2.10 补"大小与形状")。
///
/// v2.9 用户反馈原话:"**'我的'的用户名片没法编辑调整背景图,头像也是。
/// 没法自定义用户名字。个性卡片整体的 ui 风要再精美优化一些。**"
///
/// v2.10 用户反馈(第 6 条,**第二次**提名片):"'我的'界面的个人名片无法编辑呀,
/// 用户导入的头像、背景,**全都无法编辑大小和形状**。"
/// 这一版的根因与修法:
/// 1. **"无法编辑"** —— 入口本身是通的(整卡 + 右下角「编辑名片」都能点开弹层,
///    `test/profile_card_test.dart` 里有用例钉住),但两处让用户**以为**点不动:
///    ① 水波纹画在背景图**下面**(Material 的 ink 默认在 child 之下),点了毫无反馈;
///    ② 提示文案只说"改名字 / 头像 / 背景",没提"大小形状"。
///    现在:波纹挪到背景之上(外层 Stack + 内层透明 Material)、
///    按钮改成真有水波纹的 `InkWell`、文案写明"头像大小形状"。
/// 2. **大小与形状** —— v2.9 只解决"能不能换进来",没解决"换进来之后能不能调"。
///    现在头像有尺寸(小 48 / 中 64 / 大 84)、形状(圆形 / 圆角 / 方形)、
///    边框(无 / 细 / 粗);自选背景图有缩放(0.8×~2.0×)、取景位置(居中 / 偏上 / 偏下)、
///    压暗(0~80%)、模糊(0~12)。
/// 3. **弹层里的预览必须和卡片本体是同一份代码** —— 否则"预览好看、保存后不一样"。
///    于是把展示层抽成 [ProfileCardView],弹层顶部固定一块实时预览(不随表单滚走,
///    调滑条时它一直在视野里)。
class ProfileNameCard extends StatefulWidget {
  final int? vocabCount;

  /// **仅用于测试/渲染**:直接指定名片设置,跳过 Hive 读取
  /// (有背景图/无背景图两态对照必须能确定性复现,不能依赖本机磁盘状态)
  final ProfileCardSettings? settingsOverride;

  const ProfileNameCard({super.key, this.vocabCount, this.settingsOverride});

  @override
  State<ProfileNameCard> createState() => _ProfileNameCardState();
}

class _ProfileNameCardState extends State<ProfileNameCard> {
  ProfileCardSettings _card = ProfileCardSettings.defaults;
  LearnerModel _model = LearnerModel();

  @override
  void initState() {
    super.initState();
    _card = widget.settingsOverride ?? ProfileCardSettings.load();
    _model = LearnerModelStore.load();
  }

  Future<void> _edit() async {
    final edited = await showModalBottomSheet<ProfileCardSettings>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _CardEditSheet(initial: _card),
    );
    // 取消/下滑关闭 = null,此时卡片必须原样不动(用户没点保存就不该有任何变化)
    if (edited == null || !mounted) return;
    setState(() => _card = edited);
    // 先给反馈、再落库:写盘是本地 KV,但等它返回会让"已更新"慢半拍;
    // 落库本身失败也只影响下次启动(ProfileCardSettings.save 内部已兜底)
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('名片已更新'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _card.save();
  }

  /// 卡上「水平」一栏只有约 90px 宽:这里只放短文案,
  /// 完整依据放在「词汇量测试」入口里讲(390 宽下不允许出现半截字)。
  String _shortBaseline() {
    final int estimate = _model.vocabEstimate?.value ?? 0;
    if (estimate <= 0) return '未测 · 去测';
    final String cefr = (_model.cefr?.value ?? '').trim();
    return cefr.isEmpty ? '约 $estimate 词' : '约 $estimate 词 · $cefr';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.xs),
      child: ProfileCardView(
        settings: _card,
        vocabCount: widget.vocabCount,
        baselineText: _shortBaseline(),
        dailyMinutes: _model.dailyMinutes?.value ?? 0,
        // 整卡可点 + 卡上按钮都指向同一个编辑弹层(用户两次说"无法编辑")
        onEdit: _edit,
      ),
    );
  }
}

/// 名片的**纯展示层**:给一份设置就画出来,不读库、不写库。
///
/// 为什么要抽出来:编辑弹层里的"实时预览"必须是**同一份渲染代码** ——
/// v2.9 的预览是另写的一段简化布局,于是"预览里看到的"和"保存后卡片上的"不是一回事。
/// 现在两边都用 [ProfileCardView],预览就是最终卡片的样子(只少了数据行)。
class ProfileCardView extends StatelessWidget {
  final ProfileCardSettings settings;
  final int? vocabCount;

  /// 学习水平(没有就显示 "—")
  final String baselineText;

  /// 每天学习分钟数(0 = 未设置)
  final int dailyMinutes;

  /// 是否显示底部数据行(弹层预览里不需要)
  final bool showStats;

  /// 点「编辑名片」;为 null 时按钮只作为外观展示(预览态)
  final VoidCallback? onEdit;

  const ProfileCardView({
    super.key,
    required this.settings,
    this.vocabCount,
    this.baselineText = '',
    this.dailyMinutes = 0,
    this.showStats = true,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final BriefTheme t = BriefTheme.of(context);
    final String bgPath = settings.backgroundPath ?? '';
    final bool hasPhoto = bgPath.isNotEmpty && File(bgPath).existsSync();
    // B 卡形态(2026-11-07):暖纸白 + 1px 细边 + 26 圆角 + 暖柔影,
    // 与 brief_kit / 「我的」首页同一套局部令牌。旧版是整块深色背景 + 白字,
    // 在每日简报的纸面语言里像"另一个 App 的卡片"。
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: t.line, width: 0.9),
        boxShadow: t.shadow,
      ),
      child: Stack(
        children: [
          // 用户自选的背景图保留,但按"照片 → 磨砂纸"处理(用户第 7 条真机反馈:
          // 背景图直接铺上去,文字与标签看不清):
          // ① 轻模糊 6px —— 把照片细节打散,避免文字压在杂乱纹理上;
          // ② 纸面渐变 scrim(上 92% → 中 84% → 下 94% 纸色) —— 照片仍看得出来,
          //    但墨字/标签/三栏数据都有足够对比度(无图时完全不出现这两层)。
          if (hasPhoto) ...[
            // 2026-11-08 用户反馈"背景始终是模糊的"：卡片上不再额外加模糊，
            // 照片保持清晰；文字可读性交给下面的渐变 scrim（上淡下重）。
            Positioned.fill(
              child: IgnorePointer(child: _CardBackdrop(settings: settings)),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const <double>[0, 0.42, 1],
                      colors: <Color>[
                        // 顶部只压一层薄雾：用户自己选的照片要看得见；
                        // 中部最透（照片主体露出来）；底部数据区再压重一点保可读。
                        t.surface.withValues(alpha: 0.52),
                        t.surface.withValues(alpha: 0.22),
                        t.surface.withValues(alpha: 0.86),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          // 身份条:设置里选的渐变/背景图收成顶部 3px —— 还看得见,但不再压住文字
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: IgnorePointer(child: _identityRule(t, hasPhoto, bgPath)),
          ),
          // ② 内容 + 点击反馈。
          //    Material 的 ink 特性默认画在 child **下面**,所以上一版
          //    `Material(透明) > InkWell > 背景图` 的结构里,水波纹被背景图整块盖住 ——
          //    用户点卡片没有任何视觉反馈,自然会觉得"这张卡不能编辑"。
          //    把 Material 放在背景之上(内容之下),波纹就看得见了。
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onEdit,
              splashColor: t.accent.withValues(alpha: 0.06),
              highlightColor: t.accent.withValues(alpha: 0.04),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.all(showStats ? Gap.md : Gap.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // B 语言:首行是眉标 + 右上编辑键(旧版铅笔在卡片右下角)
                      Row(
                        children: <Widget>[
                          Text(
                            'PROFILE · 我的名片',
                            style: AppFont.tagStyle.copyWith(
                              fontSize: 9.5,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w800,
                              color: t.accent,
                            ),
                          ),
                          const Spacer(),
                          _editPencil(t),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 暖纸卡上不再用"白字白描边"的头像(会白底白字),
                          // 改成跟随主题的墨色(文字头像与无图兜底都清楚)
                          ProfileCardAvatar(
                            settings: settings,
                            onBackdrop: false,
                          ),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  settings.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFont.titleStyle.copyWith(
                                    color: t.ink,
                                    fontSize: 20,
                                    height: 1.2,
                                    letterSpacing: -0.3,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                // v2.11(用户 10/5 第 3 条):"个性签名的字体颜色需和名字 id
                                // 的颜色有区分度"。
                                // 旧实现:名字 `Colors.white`(纯白)、签名
                                // `Colors.white.withAlpha(228)` —— **都是白色**,只差透明度,
                                // 在浅色/花哨的背景图上几乎分不出来。
                                // 现在签名走一条**冷青灰**并把透明度降到 0.82:
                                // 色相上与纯白名字拉开距离(名字是"亮",签名是"偏冷" ),
                                // 亮度上仍保证在压暗过的背景上可读(压暗层由 _CardBackdrop 保证)。
                                Text(
                                  settings.signature.trim().isEmpty
                                      ? '点一下,写下你的名字'
                                      : settings.signature.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppFont.metaStyle.copyWith(
                                    color: t.inkSoft,
                                    fontSize: 11.5,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (showStats) ...[
                        const SizedBox(height: Gap.sm),
                        // 三栏数据:一条 hairline + 两条竖线(B 的纸面表格感);
                        // 旧版是白色半透明胶囊 + 白字,只在深色大背景上成立
                        Container(height: 1, color: t.line),
                        const SizedBox(height: Gap.xs),
                        Row(
                          children: <Widget>[
                            Expanded(child: _stat(t, '生词', '${vocabCount ?? 0}')),
                            _statDivider(t),
                            Expanded(child: _stat(t, '水平', baselineText)),
                            _statDivider(t),
                            Expanded(
                              child: _stat(t, '每天',
                                  dailyMinutes > 0 ? '$dailyMinutes 分' : '—'),
                            ),
                          ],
                        ),
                        const SizedBox(height: Gap.xxs),
                      ],
                      // 编辑入口已上移到卡首行(与眉标同一行),这里不再重复
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 卡上的编辑入口:右上角**一个小铅笔**(用户 10/5 第 3 条:"编辑名片保留个小铅笔")。
  ///
  /// 设计取舍:
  /// - 保留 `InkWell` 而不是画一个容器 —— 没有水波纹的"假按钮"正是 v2.10 用户
  ///   以为"名片无法编辑"的原因之一(那时铅笔是纯装饰、点了没反应);
  /// - 面积做成 40×40 的可点区(视觉上只有 16px 图标,但触控目标够大,
  ///   免得用户"点了没点准"又以为坏了);
  /// - 只有图标没有文字:卡面要"精美简洁",文字说明交给弹层自己。
  /// B 卡顶部身份条:用户在设置里选的渐变 / 背景图收成 3px 一条。
  ///
  /// 为什么不是"去掉背景选择":用户两次要求自定义名片(头像/背景/签名),
  /// 功能不能丢;但整块深色背景会让这张卡脱离暖纸白页(每日简报是黑字纸面)。
  /// 所以:背景"还在"(看得见、还能换),只是从"压住文字的底色"变成"卡的身份条"。
  Widget _identityRule(BriefTheme t, bool hasPhoto, String bgPath) {
    final dynamic bg = ProfileCardSettings.backgroundOf(settings.backgroundId);
    final List<Color> colors = <Color>[
      Color((bg['colors'] as List)[0] as int),
      Color((bg['colors'] as List)[1] as int),
    ];
    // 没主动挑过背景(id 仍是默认 'dawn' 的蓝)时,身份条走简报的砖红系 ——
    // 否则"默认用户"会看到一张暖纸卡顶上顶一条蓝色条,像没改干净;
    // 主动挑过其它渐变的用户,仍显示他自己选的颜色(否则"换了背景没变化")。
    final bool untouched = settings.backgroundId.isEmpty ||
        settings.backgroundId == 'dawn';
    final List<Color> ruleColors = untouched
        ? const <Color>[Color(0xFFC4562E), Color(0xFF9A572F)]
        : colors;
    return SizedBox(
      height: 3,
      child: hasPhoto
          ? Image.file(
              File(bgPath),
              fit: BoxFit.cover,
              alignment: settings.backgroundAlignment,
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: ruleColors,
                ),
              ),
            ),
    );
  }

  /// 卡上的编辑入口:**砖红小铅笔**(旧版是白色半透明铅笔,只在深色卡上成立)。
  ///
  /// 设计取舍:
  /// - 保留 `InkWell` 而不是画一个容器 —— 没有水波纹的"假按钮"正是 v2.10 用户
  ///   以为"名片无法编辑"的原因之一(那时铅笔是纯装饰、点了没反应);
  /// - 面积做成 34×34 的可点区(视觉上只有 15px 图标,但触控目标够大);
  /// - 只有图标没有文字:卡面要"精美简洁",文字说明交给弹层自己。
  Widget _editPencil(BriefTheme t) {
    return Semantics(
      // 无障碍标签 + 测试用的稳定入口(文字按钮删掉后,这里必须还有"能说出名字"的入口)
      label: '编辑名片',
      button: true,
      child: Material(
        color: t.tint(t.accent, alpha: 0.10),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onEdit,
          splashColor: t.accent.withValues(alpha: 0.12),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(Icons.edit_outlined, size: 15, color: t.accent),
          ),
        ),
      ),
    );
  }

  /// (v2.11 删除)旧版卡上那个带文字的「编辑名片」按钮。
  /// 用户 10/5 的原话是"去掉我图中圈起来的现在这些多余的描述,个性名片要精美、简洁",
  /// 圈里的正是"说明文案 + 这个宽按钮"。删掉而不是留着 —— 死代码会误导下一个人
  /// 以为卡上还有两个入口。要去旧实现看 `git log -p`(搜索"编辑名片"即可)。

  Widget _statDivider(BriefTheme t) => Container(
        width: 1,
        height: 24,
        color: t.line,
      );

  Widget _stat(BriefTheme t, String label, String value) {
    return Column(
      children: <Widget>[
        // 三栏各约 90px 宽：用 FittedBox 等比缩小而不是截断，
        // 否则「约 4250 词」会被截成「约 425…」（真机 2026-11-07 反馈）。
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value.isEmpty ? '—' : value,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: AppFont.bodyStyle.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.ink,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppFont.tagStyle.copyWith(fontSize: 10, color: t.inkFaint),
        ),
      ],
    );
  }
}

/// 名片头像:按设置渲染**尺寸 / 形状 / 边框**,图片缺失或损坏时回落到文字头像。
///
/// 公开出来是为了能在测试里量到它的真实直径(见 `test/profile_card_test.dart`)——
/// "选中即预览"这件事必须可验证,而不是靠肉眼看。
class ProfileCardAvatar extends StatelessWidget {
  final ProfileCardSettings settings;

  /// 是否显示在名片背景上(true = 白字 + 白描边;false = 跟随主题色,
  /// 用于编辑弹层那种浅/深色表单底 —— v2.9 在弹层里也用白字,
  /// 浅色主题下就是"白底白字,头像看不见")
  final bool onBackdrop;

  /// 描边颜色;不传则按 [onBackdrop] 取
  final Color? borderColor;

  const ProfileCardAvatar({
    super.key,
    required this.settings,
    this.onBackdrop = true,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = settings.avatarDiameter;
    final radius = settings.avatarRadius;
    final borderWidth = settings.avatarBorderWidth;
    final line = borderColor ??
        (onBackdrop ? Colors.white : theme.colorScheme.outline);
    final fill = onBackdrop
        ? Colors.white.withAlpha(52)
        : theme.colorScheme.surfaceContainerHighest;
    final textColor =
        onBackdrop ? Colors.white : theme.colorScheme.onSurface;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        // 边框宽度由设置决定;none 时**不画**(宽度 0 的 Border 仍会占位并留下描边),
        // 所以这里必须是 null 而不是 Border.all(width: 0)
        border: borderWidth > 0
            ? Border.all(color: line.withAlpha(190), width: borderWidth)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(28),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: _content(context, size, textColor),
    );
  }

  Widget _content(BuildContext context, double size, Color textColor) {
    final path = settings.avatarPath ?? '';
    final hasImg = path.isNotEmpty && File(path).existsSync();
    final text = settings.avatarText.isNotEmpty
        ? settings.avatarText
        : (settings.nickname.isNotEmpty
            ? settings.nickname.characters.first
            : '我');
    final fallback = Text(
      text,
      style: TextStyle(
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
    );
    if (!hasImg) return fallback;
    return Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      // 文件在但解码失败(拷到一半/不是图片)时不能崩:
      // 回落到文字头像,总比卡片上出现一块红色报错块好
      errorBuilder: (_, _, _) => fallback,
    );
  }
}

/// 名片背景:自选图(缩放 / 取景 / 压暗 / 模糊)→ 6 套渐变的回落顺序。
///
/// 只负责**画背景**,内容与点击反馈由 [ProfileCardView] 叠在上面。
class _CardBackdrop extends StatelessWidget {
  final ProfileCardSettings settings;

  const _CardBackdrop({required this.settings});

  @override
  Widget build(BuildContext context) {
    final bgPath = settings.backgroundPath ?? '';
    final hasImg = bgPath.isNotEmpty && File(bgPath).existsSync();
    final bg = ProfileCardSettings.backgroundOf(settings.backgroundId);
    final colors = [
      Color((bg['colors'] as List)[0] as int),
      Color((bg['colors'] as List)[1] as int),
    ];
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasImg) _imageLayer(bgPath, colors) else _gradient(colors),
        // 图上的压暗层:满屏照片直接铺白字会看不清(这正是 v2.9 只给渐变的原因)。
        // 只对**自选图**生效:6 套渐变是挑过的,本来就保证白字可读,
        // 再压一层等于把老用户的名片偷偷变暗(向后兼容)。
        if (hasImg)
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(settings.backgroundDimAlpha),
            ),
          ),
      ],
    );
  }

  Widget _gradient(List<Color> colors) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
        ),
      );

  /// 自选图:缩放 + 取景位置 + 模糊。
  ///
  /// 缩放为什么要走"更大的虚拟画布再缩回"这一手:
  /// 直接把图 `Transform.scale(0.8)` 会在卡片边缘露出一圈底色(图变小了、框没变);
  /// 而先按 `1/scale` 铺满一个更大的画布、再整体缩回可视区,缩小时**依然是铺满的**,
  /// 只是能看到更多画面 —— 这才是用户想要的"缩小"。
  Widget _imageLayer(String path, List<Color> fallbackColors) {
    final align = settings.backgroundAlignment;
    final scale = ProfileCardSettings.normalizeBgScale(settings.bgScale);
    // 2026-11-08 用户反馈"背景始终是模糊的"：卡片展示时把模糊封顶在 2px
    // （编辑弹层里仍按用户设置预览，但名片本身上照片要保持可辨认）。
    final blur =
        ProfileCardSettings.normalizeBgBlur(settings.bgBlur).clamp(0, 2).toDouble();
    return LayoutBuilder(
      builder: (context, c) {
        // 兜底尺寸只为"约束意外无界"时不崩(正常一定是有界的)
        final w = c.maxWidth.isFinite ? c.maxWidth : 360.0;
        final h = c.maxHeight.isFinite ? c.maxHeight : 160.0;
        Widget layer = SizedBox(
          width: w / scale,
          height: h / scale,
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            alignment: align,
            errorBuilder: (_, _, _) => _gradient(fallbackColors),
          ),
        );
        // Align:把虚拟画布按取景位置摆好(它允许溢出,不裁)
        layer = Align(alignment: align, child: layer);
        // Transform:整体缩回可视区(锚点与取景位置一致,于是"偏上/偏下"是真的偏上/偏下)
        layer = Transform.scale(scale: scale, alignment: align, child: layer);
        if (blur > 0) {
          // TileMode.clamp:模糊采样越界时用边缘像素补,否则四边会出现一圈半透明虚边
          layer = ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: blur,
              sigmaY: blur,
              tileMode: TileMode.clamp,
            ),
            child: layer,
          );
        }
        // ClipRect:缩放/模糊都可能画到卡片外,先裁掉(外层 ClipRRect 也裁,
        // 但这里裁一层更省,且能避免溢出层被反复合成)
        return ClipRect(child: layer);
      },
    );
  }
}

/// 编辑名片的底部弹层(v2.10:预览固定在上方,表单在中部滚动,保存固定在底部)。
class _CardEditSheet extends StatefulWidget {
  final ProfileCardSettings initial;

  const _CardEditSheet({required this.initial});

  @override
  State<_CardEditSheet> createState() => _CardEditSheetState();
}

class _CardEditSheetState extends State<_CardEditSheet> {
  late ProfileCardSettings _draft = widget.initial;
  late final TextEditingController _name =
      TextEditingController(text: widget.initial.nickname);
  late final TextEditingController _sign =
      TextEditingController(text: widget.initial.signature);
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _name.dispose();
    _sign.dispose();
    super.dispose();
  }

  void _apply(ProfileCardSettings s) => setState(() => _draft = s);

  /// 选图:头像与背景图只差参数(尺寸上限/压缩率/落盘前缀),
  /// 所以共用一条路径,避免两处逻辑各写一份、各漏一处
  Future<void> _pick({required bool avatar}) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: avatar ? 600 : 1600,
        imageQuality: avatar ? 90 : 88,
      );
      if (picked == null) return;
      final path = await ProfileCardSettings.persistImage(
        File(picked.path),
        prefix: avatar ? 'avatar' : 'card_bg',
      );
      if (path == null || !mounted) return;
      _apply(avatar
          ? _draft.copyWith(avatarPath: path)
          : _draft.copyWith(backgroundPath: path));
    } catch (e) {
      debugPrint('选图失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hasBgImage = (_draft.backgroundPath ?? '').isNotEmpty;

    return SafeArea(
      top: false,
      child: Padding(
        // 键盘弹起时把内容顶上去:底部弹层不会自己躲键盘
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 固定的实时预览 ──
            // 为什么不放进滚动区:调背景缩放/明暗时,预览一旦滚出屏幕,
            // "改一点看一眼"就变成了"改完再滚上去看"
            //
            // v2.11(用户 10/5:"编辑界面太冗杂了…约 1 屏就好"):预览留,
            // 但下面那行「实时预览 · 改任何一项,这里立刻变」删掉了 ——
            // 预览就贴在表单上面,改动立刻可见是**看得见的事实**,不需要一句解释。
            // 同时把这块的上下边距收紧(12 → 8),省下的高度给表单。
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.xs),
              child: ProfileCardView(settings: _draft, showStats: false),
            ),
            // ── 表单(可滚) ──
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 名字与签名(约 1 屏:v2.11 精简)──
                    // 三处改动:① `maxLength` 去掉 —— Flutter 会在框下多渲染一行
                    // "3/12" 计数器,两个输入框就白占掉约 40px;限长改用
                    // inputFormatters(功能一样,界面干净);
                    // ② 签名从 2 行高度压到 1 行;③ 标题从「名字与签名」缩成「名字·签名」。
                    _section('名字 · 签名'),
                    TextField(
                      controller: _name,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(12),
                      ],
                      decoration: const InputDecoration(
                        labelText: '你的名字 / 昵称',
                        hintText: '如:小樱、Aki',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          _apply(_draft.copyWith(nickname: v)),
                    ),
                    const SizedBox(height: Gap.xs),
                    TextField(
                      controller: _sign,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(40),
                      ],
                      decoration: const InputDecoration(
                        labelText: '个性签名',
                        hintText: '如:每天 20 分钟,读原著',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) =>
                          _apply(_draft.copyWith(signature: v)),
                    ),
                    const SizedBox(height: Gap.sm),

                    // ── 头像 ──
                    _section('头像'),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ProfileCardAvatar(settings: _draft, onBackdrop: false),
                        const SizedBox(width: Gap.sm),
                        Expanded(
                          child: Wrap(
                            spacing: Gap.xs,
                            runSpacing: Gap.xs,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _pick(avatar: true),
                                icon: const Icon(Icons.photo_library_outlined,
                                    size: 16),
                                label: const Text('从相册选'),
                              ),
                              if ((_draft.avatarPath ?? '').isNotEmpty)
                                TextButton(
                                  onPressed: () => _apply(
                                      _draft.copyWith(avatarPath: null)),
                                  child: const Text('用文字头像'),
                                ),
                              // v2.11:文字头像预设从"单独一行"挪到这里 ——
                              // 它本来就和"从相册选"是同一件事的两个选项
                              //(选图 or 用文字),分两行只是白占 40px。
                              for (final t in ProfileCardSettings.avatarTexts)
                                _chip(
                                  label: t,
                                  selected: (_draft.avatarPath ?? '').isEmpty &&
                                      _draft.avatarText == t,
                                  onTap: () => _apply(_draft.copyWith(
                                      avatarPath: null, avatarText: t)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.xs),
                    // v2.11:大小 / 形状 / 边框 三个标签合并成一行标题,
                    // 三组 chip 依次排在下面(以前各占一行标题 = 白占 54px)
                    _label('大小 · 形状 · 边框', muted),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final s in ProfileCardSettings.avatarSizes)
                          _chip(
                            label:
                                '${s['label']} ${(s['size'] as double).round()}',
                            selected: _draft.avatarDiameter == s['size'],
                            onTap: () => _apply(_draft
                                .copyWith(avatarSize: s['size'] as double)),
                          ),
                        for (final s in ProfileCardSettings.avatarShapes)
                          _chip(
                            label: s['label']!,
                            selected: _draft.avatarShape == s['id'],
                            onTap: () => _apply(
                                _draft.copyWith(avatarShape: s['id'])),
                          ),
                        for (final b in ProfileCardSettings.avatarBorders)
                          _chip(
                            label: b['label']!,
                            selected: _draft.avatarBorder == b['id'],
                            onTap: () => _apply(
                                _draft.copyWith(avatarBorder: b['id'])),
                          ),
                      ],
                    ),
                    const SizedBox(height: Gap.sm),

                    // ── 背景 ──
                    _section('名片背景',
                        hint: hasBgImage ? '正在用你自己的图,下面四项都是调它' : null),
                    Wrap(
                      spacing: Gap.xs,
                      runSpacing: Gap.xs,
                      children: [
                        for (final b in ProfileCardSettings.backgrounds)
                          InkWell(
                            borderRadius: Radii.controlRadius,
                            onTap: () => _apply(_draft.copyWith(
                                backgroundId: '${b['id']}',
                                backgroundPath: null)),
                            child: Container(
                              width: 62,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Color((b['colors'] as List)[0] as int),
                                    Color((b['colors'] as List)[1] as int),
                                  ],
                                ),
                                borderRadius: Radii.controlRadius,
                                border: Border.all(
                                  color: (_draft.backgroundPath ?? '').isEmpty &&
                                          _draft.backgroundId == b['id']
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text('${b['label']}',
                                  style: const TextStyle(
                                      fontSize: 10.5, color: Colors.white)),
                            ),
                          ),
                        InkWell(
                          borderRadius: Radii.controlRadius,
                          onTap: () => _pick(avatar: false),
                          child: Container(
                            width: 62,
                            height: 40,
                            decoration: BoxDecoration(
                              color:
                                  theme.colorScheme.surfaceContainerHighest,
                              borderRadius: Radii.controlRadius,
                              border: Border.all(
                                color: hasBgImage
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outlineVariant,
                                width: hasBgImage ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined,
                                    size: 15, color: muted),
                                Text('选图',
                                    style:
                                        TextStyle(fontSize: 9.5, color: muted)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (hasBgImage) ...[
                      const SizedBox(height: Gap.sm),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '自选背景图(压暗是为了白字看得清)',
                              style: TextStyle(fontSize: 11, color: muted),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _apply(_draft.copyWith(
                              backgroundPath: null,
                            )),
                            child: const Text('换回渐变'),
                          ),
                        ],
                      ),
                      _slider(
                        label: '缩放',
                        valueText: '${_draft.bgScale.toStringAsFixed(1)}×',
                        value: _draft.bgScale,
                        min: ProfileCardSettings.minBgScale,
                        max: ProfileCardSettings.maxBgScale,
                        divisions: 12,
                        onChanged: (v) =>
                            _apply(_draft.copyWith(bgScale: v)),
                      ),
                      _label('图片位置(取景)', muted),
                      Wrap(
                        spacing: Gap.xs,
                        runSpacing: Gap.xs,
                        children: [
                          for (final a in ProfileCardSettings.bgAligns)
                            _chip(
                              label: a['label']!,
                              selected: _draft.bgAlign == a['id'],
                              onTap: () =>
                                  _apply(_draft.copyWith(bgAlign: a['id'])),
                            ),
                        ],
                      ),
                      _slider(
                        label: '暗度',
                        valueText: '${(_draft.bgDim * 100).round()}%',
                        value: _draft.bgDim,
                        min: ProfileCardSettings.minBgDim,
                        max: ProfileCardSettings.maxBgDim,
                        divisions: 16,
                        onChanged: (v) => _apply(_draft.copyWith(bgDim: v)),
                      ),
                      _slider(
                        label: '模糊',
                        valueText: _draft.bgBlur <= 0
                            ? '不模糊'
                            : '${_draft.bgBlur.round()}',
                        value: _draft.bgBlur,
                        min: ProfileCardSettings.minBgBlur,
                        max: ProfileCardSettings.maxBgBlur,
                        divisions: 12,
                        onChanged: (v) => _apply(_draft.copyWith(bgBlur: v)),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _apply(_draft.copyWith(
                            bgScale: 1.0,
                            bgAlign: 'center',
                            bgDim: ProfileCardSettings.defaults.bgDim,
                            bgBlur: 0,
                          )),
                          icon: const Icon(Icons.restart_alt, size: 16),
                          label: const Text('还原这四项'),
                        ),
                      ),
                    ] else
                      // v2.11(用户 10/5:"去掉…多余的描述,要精美简洁"):
                      // 这一整段说明文案删掉了 —— 上面就是「选图」格子,
                      // 选完四项滑条自己出现,不需要一句解释。
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ),
            // ── 保存(固定) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, _draft),
                  child: const Text('保存名片'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, {String? hint}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.xs, bottom: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(width: Gap.xs),
            Expanded(
              child: Text(
                hint,
                style: TextStyle(
                  fontSize: 10.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _label(String text, Color muted) => Padding(
        padding: const EdgeInsets.only(top: Gap.xs, bottom: 2),
        child: Text(text, style: TextStyle(fontSize: 12, color: muted)),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
      );

  Widget _slider({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 12, color: muted)),
            ),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: valueText,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
