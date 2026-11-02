import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'graphics_core.dart';
import 'graphics_palette.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// 13 个**领域身份图形**(资料分类 / 学习方向 / 推荐卡片)。
/// ═══════════════════════════════════════════════════════════════════════
///
/// 设计原则(用户原话:"精简和高级,实用第一"):
///
/// 1. **一眼能认出来**。每个图形只表达一件具体的事,不是"随便画个几何图案":
///    科技=原子轨道、健康=心电图、新闻=报头分栏、书=书脊封面…… 用户不看文字
///    也应该能猜出个八九不离十;
/// 2. **一张图最多两种色相**。结构线用中性墨,只有"身份笔画"用领域色。
///    13 张图并排放在一起时,靠形不靠色区分,才不会变成调色板;
/// 3. **统一笔触**。所有描边走 [GraphicPainter.strokePaint](圆头圆角 + 同一线宽),
///    圆角只用圆头/统一小圆角,不加投影不叠渐变 —— 这是"高级"而不是"花哨"的
///    分界线;
/// 4. 所有坐标都按 `s`(边长)取比例,所以 72/96/120/160 四档是同一个东西。
///
/// 想加新领域:在 [GraphicDomain] 加枚举 + 在这里加一个 painter + 更新
/// `_painterFor` 的 switch(漏了会有编译错误,不会静默画错)。
class DomainGraphic extends StatelessWidget {
  const DomainGraphic({
    super.key,
    required this.domain,
    this.size = GraphicsPalette.defaultSize,
    this.showPanel = false,
    this.semanticLabel,
  });

  final GraphicDomain domain;

  /// 建议取自 [GraphicsPalette.sizes](72/96/120/160)
  final double size;

  /// 是否铺一层该领域色的极淡渐变面板(hero 位/卡片图标位用)
  final bool showPanel;

  /// 无障碍标签;默认用领域中文名 + "图形"
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final ink = GraphicInk.of(context, accent: domain.colorOf(context));
    final stroke = GraphicsPalette.strokeOf(size);
    return GraphicFrame(
      painter: _painterFor(domain, ink, stroke),
      size: size,
      semanticLabel: semanticLabel ?? '${domain.label}图形',
      panelAccent: showPanel ? ink.accent : null,
    );
  }
}

GraphicPainter _painterFor(
  GraphicDomain domain,
  GraphicInk ink,
  double stroke,
) {
  return switch (domain) {
    GraphicDomain.science => _SciencePainter(ink: ink, stroke: stroke),
    GraphicDomain.business => _BusinessPainter(ink: ink, stroke: stroke),
    GraphicDomain.health => _HealthPainter(ink: ink, stroke: stroke),
    GraphicDomain.culture => _CulturePainter(ink: ink, stroke: stroke),
    GraphicDomain.travel => _TravelPainter(ink: ink, stroke: stroke),
    GraphicDomain.language => _LanguagePainter(ink: ink, stroke: stroke),
    GraphicDomain.exam => _ExamPainter(ink: ink, stroke: stroke),
    GraphicDomain.academic => _AcademicPainter(ink: ink, stroke: stroke),
    GraphicDomain.news => _NewsPainter(ink: ink, stroke: stroke),
    GraphicDomain.book => _BookPainter(ink: ink, stroke: stroke),
    GraphicDomain.audio => _AudioPainter(ink: ink, stroke: stroke),
    GraphicDomain.note => _NotePainter(ink: ink, stroke: stroke),
    GraphicDomain.custom => _CustomPainter(ink: ink, stroke: stroke),
  };
}

/// 高级用法 / 测试入口:直接拿到某个领域的 painter。
///
/// 绝大多数页面用 [DomainGraphic] 就够了;这个函数存在的原因有两个:
/// 1. 需要把领域图形画进**别人的 CustomPaint**(例如和别的图层叠在一起)时,
///    不用再包一层 GraphicFrame;
/// 2. `shouldRepaint` 的行为要能被单测直接验证(私有类没法在 test 里 new)。
///
/// 注意:颜色必须由调用方解析好(见 [GraphicInk.of]) —— painter 不持有 context。
GraphicPainter domainGraphicPainter(
  GraphicDomain domain, {
  required GraphicInk ink,
  required double stroke,
}) =>
    _painterFor(domain, ink, stroke);

// ═══════════════════════════════════════════════════════════════════════
// 各领域画法
// ═══════════════════════════════════════════════════════════════════════

/// 科学与技术:**原子模型** —— 3 条旋转的同心椭圆轨道 + 轨道粒子 + 中心星芒。
///
/// 为什么是原子:科技领域最不容易画错、也最不容易画俗的符号。三条轨道按
/// 60° 均分,视觉上立刻出现"三维球体"的错觉;中心用四角星而不是实心圆,
/// 是因为实心圆在这个尺寸下会变成"一个点",没有"能量"的意思。
class _SciencePainter extends GraphicPainter {
  _SciencePainter({required super.ink, required super.stroke});

  /// 轨道长短半轴(比例)
  static const double _rx = 0.375;
  static const double _ry = 0.155;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = size.center(Offset.zero);
    final orbit = strokePaint(ink.accent.withAlpha(150), width: stroke * 0.85);
    final orbitTone = strokePaint(ink.tone.withAlpha(120), width: stroke * 0.7);

    for (var i = 0; i < 3; i++) {
      drawOrbit(
        canvas,
        c,
        Size(s * _rx * 2, s * _ry * 2),
        orbit,
        rotation: i * math.pi / 3,
      );
    }

    // 3 个粒子:每条轨道上各一个,相位错开 120°,再跟着轨道旋转
    final dot = fillPaint(ink.line);
    for (var i = 0; i < 3; i++) {
      final rot = i * math.pi / 3;
      final angle = rot + i * 2 * math.pi / 3;
      final px = math.cos(angle) * s * _rx;
      final py = math.sin(angle) * s * _ry;
      final rotated = Offset(
        px * math.cos(rot) - py * math.sin(rot),
        px * math.sin(rot) + py * math.cos(rot),
      );
      canvas.drawCircle(c + rotated, stroke * 0.72, dot);
    }

    // 中心:领域色星芒(4 长角) + 中性内星(层次,不用阴影)
    drawStar4(canvas, c, s * 0.135, fillPaint(ink.accent), notch: 0.20);
    drawStar4(canvas, c, s * 0.062, fillPaint(ink.line), notch: 0.30);

    // 一条极淡的辅助轨道:补"转动"的方向感,同时不增加新色相
    drawOrbit(
      canvas,
      c,
      Size(s * (_rx * 2 + 0.06), s * (_ry * 2 + 0.02)),
      orbitTone,
      rotation: math.pi / 6,
    );
  }
}

/// 商业与政治:**增长柱状图** —— 5 根递增竖柱 + 穿过柱顶的上升折线 + 箭头。
///
/// 背后的地球弧是"商业/政治"的全球化含义,压到几乎看不见 —— 它只负责让
/// 这张图不像"随手画的柱状图",不抢主体。
class _BusinessPainter extends GraphicPainter {
  _BusinessPainter({required super.ink, required super.stroke});

  static const List<double> _heights = <double>[0.15, 0.23, 0.32, 0.42, 0.54];

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final left = s * 0.13;
    final right = s * 0.87;
    final baseY = s * 0.80;

    // 背景地球弧:圆心在框外右上,只露一段弧 —— 淡到"看第二眼才发现"
    final globe = strokePaint(ink.tone.withAlpha(110), width: stroke * 0.7);
    final globeCenter = Offset(s * 0.86, s * 0.14);
    canvas.drawArc(
      Rect.fromCircle(center: globeCenter, radius: s * 0.22),
      math.pi * 0.62,
      math.pi * 0.95,
      false,
      globe,
    );

    // 基准线(比柱子淡一档,只做"地面")
    canvas.drawLine(
      Offset(left, baseY),
      Offset(right + s * 0.05, baseY),
      strokePaint(ink.line.withAlpha(110), width: stroke * 0.7),
    );

    final step = (right - left) / _heights.length;
    final barW = step * 0.52;
    final tops = <Offset>[];
    for (var i = 0; i < _heights.length; i++) {
      final h = s * _heights[i];
      final x = left + step * i + (step - barW) / 2;
      // 越靠右越浓:递进感靠"浓度"而不是"再多一个颜色"
      final alpha = 70 + i * 42;
      final rect = Rect.fromLTWH(x, baseY - h, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barW * 0.28)),
        fillPaint(ink.accent.withAlpha(alpha.clamp(0, 255))),
      );
      tops.add(Offset(x + barW / 2, baseY - h));
    }

    // 折线穿过柱顶,并向右上延伸出箭头
    final tip = Offset(right + s * 0.055, baseY - s * 0.62);
    final line = <Offset>[...tops, tip];
    final linePaint = strokePaint(ink.line, width: stroke * 0.95);
    drawPolyline(canvas, line, linePaint);

    // 箭头:沿最后一段方向张 30°
    final dir = (tip - tops.last).direction;
    final len = s * 0.075;
    for (final d in <double>[-0.42, 0.42]) {
      canvas.drawLine(
        tip,
        tip + Offset.fromDirection(dir + math.pi + d, len),
        linePaint,
      );
    }
  }
}

/// 健康与生活:**ECG 脉搏线** + 右上角双圆环。
///
/// 心电图是这个领域唯一"文化上无歧义"的符号(哑铃、苹果、心形都太俗)。
/// 两个心跳尖峰一大一小,让线条有节奏;双圆环是"记录/指标"的暗喻。
class _HealthPainter extends GraphicPainter {
  _HealthPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final baseY = s * 0.56;

    // 双圆环:外环领域色、内环中性 —— 放在尖峰右上方的空白区
    final ringCenter = Offset(s * 0.77, s * 0.27);
    canvas.drawCircle(
      ringCenter,
      s * 0.125,
      strokePaint(ink.accent.withAlpha(190), width: stroke * 0.85),
    );
    canvas.drawCircle(
      ringCenter,
      s * 0.072,
      strokePaint(ink.tone, width: stroke * 0.75),
    );

    // ECG:平段 → 小 P 波 → QRS 尖峰 → 更小的第二个尖峰 → 收尾
    final pts = <Offset>[
      Offset(s * 0.11, baseY),
      Offset(s * 0.24, baseY),
      Offset(s * 0.28, baseY - s * 0.055),
      Offset(s * 0.32, baseY),
      Offset(s * 0.38, baseY),
      Offset(s * 0.41, baseY + s * 0.075),
      Offset(s * 0.46, baseY - s * 0.24),
      Offset(s * 0.51, baseY + s * 0.11),
      Offset(s * 0.55, baseY),
      Offset(s * 0.64, baseY),
      Offset(s * 0.68, baseY - s * 0.09),
      Offset(s * 0.72, baseY),
      Offset(s * 0.86, baseY),
    ];
    drawPolyline(canvas, pts, strokePaint(ink.accent, width: stroke * 1.15));

    // 基线:给波形一个"参考零位",也让图形有地平线一样的稳定感
    canvas.drawLine(
      Offset(s * 0.10, baseY),
      Offset(s * 0.90, baseY),
      strokePaint(ink.tone.withAlpha(70), width: stroke * 0.7),
    );
  }
}

/// 文化与艺术:**三层嵌套拱门** + 拱内太阳 + 底部短柱。
///
/// 拱门是建筑/艺术最简洁的"文化"符号(博物馆、教堂、剧场都是拱),
/// 三层由外到内变淡 = 进深;太阳落在最内层,视觉重心在正中。
class _CulturePainter extends GraphicPainter {
  _CulturePainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final baseY = s * 0.76;

    // 三层拱:宽度 0.62 / 0.44 / 0.26,越内越淡(靠 alpha 做进深,不做渐变)
    const widths = <double>[0.62, 0.44, 0.26];
    const tops = <double>[0.20, 0.32, 0.44];
    const alphas = <int>[235, 170, 115];
    for (var i = 0; i < widths.length; i++) {
      final w = s * widths[i];
      final rect = Rect.fromLTWH(
        (s - w) / 2,
        s * tops[i],
        w,
        baseY - s * tops[i],
      );
      drawArch(canvas, rect, strokePaint(ink.accent.withAlpha(alphas[i]),
          width: stroke * (i == 0 ? 1.0 : 0.85)));
    }

    // 拱内太阳:实心圆,是整张图唯一的"重色块"
    canvas.drawCircle(
      Offset(s * 0.5, baseY - s * 0.16),
      s * 0.058,
      fillPaint(ink.accent),
    );

    // 底部 5 根短柱:像台阶/柱廊,把拱门"落"在地面上
    final columnPaint = strokePaint(ink.line.withAlpha(200), width: stroke * 0.9);
    for (var i = 0; i < 5; i++) {
      final x = s * 0.30 + s * 0.10 * i;
      canvas.drawLine(Offset(x, baseY + s * 0.055), Offset(x, baseY + s * 0.145), columnPaint);
    }
    canvas.drawLine(
      Offset(s * 0.24, baseY + s * 0.155),
      Offset(s * 0.76, baseY + s * 0.155),
      strokePaint(ink.tone.withAlpha(120), width: stroke * 0.7),
    );
  }
}

/// 旅行与体验:**地平线 + 虚线航线 + 纸飞机 + 云**。
///
/// 虚线弧是从左下爬升到右上的"航线",飞机落在弧的末端 —— 视线会自然沿着虚线
/// 走到飞机上,这就是"出发"的叙事。云只用两个圆,多了就卡通。
class _TravelPainter extends GraphicPainter {
  _TravelPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);

    // 云:两个错落的圆 + 一条底线(不是云朵图标,是一笔带过的几何云)
    // 两个圆的**底边对齐**(0.342)再压底线,否则云会像"两个泡泡"
    final cloudPaint = strokePaint(ink.tone, width: stroke * 0.8);
    canvas.drawCircle(Offset(s * 0.24, s * 0.28), s * 0.062, cloudPaint);
    canvas.drawCircle(Offset(s * 0.33, s * 0.30), s * 0.042, cloudPaint);
    canvas.drawLine(
      Offset(s * 0.185, s * 0.342),
      Offset(s * 0.365, s * 0.342),
      cloudPaint,
    );

    // 地平线:一段直线 + 两端极短的收笔,不做起伏(起伏会变插画)
    canvas.drawLine(
      Offset(s * 0.10, s * 0.72),
      Offset(s * 0.90, s * 0.72),
      strokePaint(ink.line.withAlpha(150), width: stroke * 0.85),
    );

    // 虚线航迹:左下山脚 → 右上天空
    final start = Offset(s * 0.19, s * 0.70);
    final control = Offset(s * 0.31, s * 0.30);
    final end = Offset(s * 0.74, s * 0.31);
    final arc = quadraticPoints(start, control, end, segments: 26);
    drawDashedPolyline(
      canvas,
      arc,
      strokePaint(ink.accent.withAlpha(200), width: stroke * 0.85),
      dash: s * 0.048,
      gap: s * 0.036,
    );

    // 纸飞机:两个三角拼出折叠感(上翼实、下翼半透明),机头指向航线终点方向
    final tip = Offset(s * 0.84, s * 0.22);
    final back = Offset(s * 0.60, s * 0.32);
    final tail = Offset(s * 0.66, s * 0.46);
    final fold = Offset(s * 0.655, s * 0.345);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(back.dx, back.dy)
        ..lineTo(fold.dx, fold.dy)
        ..close(),
      fillPaint(ink.accent),
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(fold.dx, fold.dy)
        ..lineTo(tail.dx, tail.dy)
        ..close(),
      fillPaint(ink.accent.withAlpha(150)),
    );
  }
}

/// 语言与学习:**几何字母 A** + 3×3 点阵 + 对话气泡。
///
/// A 是拉丁字母里笔画最少、辨识度最高的一个(三条线);点阵代表"词汇量/练习";
/// 气泡是"语言=交流"。三样东西都只用直线/圆,拼在一起就是"学语言"。
class _LanguagePainter extends GraphicPainter {
  _LanguagePainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);

    // A:顶点 + 两条腿 + 横杠(按顶点/腿的坐标算横杠两端,不要写死)
    final apex = Offset(s * 0.37, s * 0.22);
    final leftFoot = Offset(s * 0.20, s * 0.80);
    final rightFoot = Offset(s * 0.54, s * 0.80);
    final aPaint = strokePaint(ink.accent, width: stroke * 1.1);
    canvas.drawLine(apex, leftFoot, aPaint);
    canvas.drawLine(apex, rightFoot, aPaint);
    final barY = s * 0.575;
    final t = (barY - apex.dy) / (leftFoot.dy - apex.dy);
    canvas.drawLine(
      Offset(apex.dx + (leftFoot.dx - apex.dx) * t, barY),
      Offset(apex.dx + (rightFoot.dx - apex.dx) * t, barY),
      aPaint,
    );

    // 3×3 点阵:词汇/练习的量化感
    drawDotGrid(
      canvas,
      Rect.fromLTRB(s * 0.64, s * 0.24, s * 0.86, s * 0.46),
      fillPaint(ink.line.withAlpha(210)),
      cols: 3,
      rows: 3,
      radius: stroke * 0.5,
    );

    // 对话气泡:圆角矩形 + 小尾巴,放在右下
    final bubble = Rect.fromLTRB(s * 0.55, s * 0.60, s * 0.87, s * 0.79);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bubble, Radius.circular(s * 0.045)),
      strokePaint(ink.tone, width: stroke * 0.85),
    );
    canvas.drawPath(
      Path()
        ..moveTo(bubble.left + s * 0.06, bubble.bottom)
        ..lineTo(bubble.left + s * 0.035, bubble.bottom + s * 0.075)
        ..lineTo(bubble.left + s * 0.14, bubble.bottom),
      strokePaint(ink.tone, width: stroke * 0.85),
    );
  }
}

/// 备考:**考卷格 + 对勾 + 计时圆弧**。
///
/// 备考期间用户最在意的三件事:卷面(还有多少题)、正确率(对勾)、时间(计时环)。
/// 一个图形把三件事都摆上,比一个"学士帽"有用得多。
class _ExamPainter extends GraphicPainter {
  _ExamPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);

    // 考卷:外框 + 三道题横线 + 左侧题号小方块
    final paper = Rect.fromLTRB(s * 0.11, s * 0.21, s * 0.63, s * 0.79);
    canvas.drawRRect(
      RRect.fromRectAndRadius(paper, Radius.circular(s * 0.035)),
      strokePaint(ink.accent.withAlpha(225), width: stroke * 0.95),
    );
    final linePaint = strokePaint(ink.tone, width: stroke * 0.8);
    final boxPaint = strokePaint(ink.tone.withAlpha(200), width: stroke * 0.75);
    for (var i = 0; i < 3; i++) {
      final y = s * (0.38 + 0.135 * i);
      canvas.drawLine(Offset(s * 0.31, y), Offset(s * 0.56, y), linePaint);
      // 题号小方块:尺寸统一(0.10s),和横线共中心线
      final box = Rect.fromCenter(
        center: Offset(s * 0.205, y),
        width: s * 0.085,
        height: s * 0.075,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, Radius.circular(s * 0.014)),
        boxPaint,
      );
    }

    // 对勾:右下角(答案正确)—— 笔画比外框粗一档,是"结论"
    drawCheck(
      canvas,
      Rect.fromLTRB(s * 0.62, s * 0.68, s * 0.90, s * 0.88),
      strokePaint(ink.accent, width: stroke * 1.3),
    );

    // 计时圆弧:右上角 300° 缺口环 + 一根指针
    final timerCenter = Offset(s * 0.79, s * 0.26);
    final timerRadius = s * 0.115;
    canvas.drawArc(
      Rect.fromCircle(center: timerCenter, radius: timerRadius),
      -math.pi / 2,
      math.pi * 5 / 3,
      false,
      strokePaint(ink.line.withAlpha(200), width: stroke * 0.95),
    );
    canvas.drawLine(
      timerCenter,
      timerCenter + Offset.fromDirection(-math.pi / 6, timerRadius * 0.72),
      strokePaint(ink.accent, width: stroke * 0.9),
    );
  }
}

/// 学术论文:**积分符号 + 分数线 + 上下点阵 + 引文括号**。
///
/// 论文的视觉语言是"公式 + 引用",不是"一本书"。积分号用两段三次贝塞尔画,
/// 上下点阵代表"公式的上下文",右下角引号表示"引用"。
class _AcademicPainter extends GraphicPainter {
  _AcademicPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);

    // 积分符号(∫):上钩往右上、下钩往左下 —— 这是它和"S"的区别
    final integral = Path()
      ..moveTo(s * 0.38, s * 0.225)
      ..cubicTo(s * 0.285, s * 0.205, s * 0.305, s * 0.33, s * 0.305, s * 0.44)
      ..lineTo(s * 0.305, s * 0.575)
      ..cubicTo(s * 0.305, s * 0.695, s * 0.322, s * 0.795, s * 0.225, s * 0.775);
    canvas.drawPath(
      integral,
      strokePaint(ink.accent, width: stroke * 1.25),
    );

    // 分数线:公式的骨架
    canvas.drawLine(
      Offset(s * 0.45, s * 0.50),
      Offset(s * 0.86, s * 0.50),
      strokePaint(ink.line, width: stroke * 0.95),
    );

    // 分数线上下各 2×2 点阵(分子/分母)
    final dotPaint = fillPaint(ink.line.withAlpha(200));
    drawDotGrid(
      canvas,
      Rect.fromLTRB(s * 0.51, s * 0.30, s * 0.63, s * 0.40),
      dotPaint,
      cols: 2,
      rows: 2,
      radius: stroke * 0.55,
    );
    drawDotGrid(
      canvas,
      Rect.fromLTRB(s * 0.51, s * 0.61, s * 0.63, s * 0.71),
      dotPaint,
      cols: 2,
      rows: 2,
      radius: stroke * 0.55,
    );

    // 引文括号(引号):右下角一对 —— 圆点 + 上挑的尾巴
    final quoteFill = fillPaint(ink.accent);
    final quoteStroke = strokePaint(ink.accent, width: stroke * 0.8);
    for (var i = 0; i < 2; i++) {
      final center = Offset(s * (0.735 + 0.085 * i), s * 0.705);
      canvas.drawCircle(center, s * 0.026, quoteFill);
      canvas.drawLine(
        center + Offset(s * 0.018, -s * 0.018),
        center + Offset(s * 0.048, -s * 0.060),
        quoteStroke,
      );
    }
  }
}

/// 外刊新闻:**报头粗条 + 三栏竖线 + 头条条 + 日期点**。
///
/// 报纸版式的三个特征:顶部粗报头、多栏排版、头条标题块。认出报纸靠版式,
/// 不靠一个"报纸图标"。
class _NewsPainter extends GraphicPainter {
  _NewsPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);

    // 报头:一条粗实心条(全图最重的元素,压住"这是报纸"的语义)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.13, s * 0.17, s * 0.87, s * 0.255),
        Radius.circular(s * 0.022),
      ),
      fillPaint(ink.accent),
    );

    // 报头下的细分隔线
    canvas.drawLine(
      Offset(s * 0.13, s * 0.305),
      Offset(s * 0.87, s * 0.305),
      strokePaint(ink.tone.withAlpha(170), width: stroke * 0.75),
    );

    // 三栏竖线:版式的"骨架"
    final gutter = strokePaint(ink.tone.withAlpha(150), width: stroke * 0.7);
    canvas.drawLine(Offset(s * 0.385, s * 0.38), Offset(s * 0.385, s * 0.80), gutter);
    canvas.drawLine(Offset(s * 0.635, s * 0.38), Offset(s * 0.635, s * 0.80), gutter);

    // 头条条:第一栏最重,其余两根中性淡一档(层级清楚但不吵)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.15, s * 0.38, s * 0.33, s * 0.44),
        Radius.circular(s * 0.012),
      ),
      fillPaint(ink.accent.withAlpha(215)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.15, s * 0.50, s * 0.31, s * 0.545),
        Radius.circular(s * 0.010),
      ),
      fillPaint(ink.line.withAlpha(120)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.42, s * 0.38, s * 0.60, s * 0.425),
        Radius.circular(s * 0.010),
      ),
      fillPaint(ink.line.withAlpha(165)),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(s * 0.67, s * 0.38, s * 0.85, s * 0.425),
        Radius.circular(s * 0.010),
      ),
      fillPaint(ink.line.withAlpha(165)),
    );

    // 正文行线(极短,只做"有字"的暗示)
    final bodyPaint = strokePaint(ink.tone.withAlpha(120), width: stroke * 0.65);
    for (var i = 0; i < 2; i++) {
      final y = s * (0.585 + 0.075 * i);
      canvas.drawLine(Offset(s * 0.15, y), Offset(s * 0.31, y), bodyPaint);
      canvas.drawLine(Offset(s * 0.42, y), Offset(s * 0.60, y), bodyPaint);
      canvas.drawLine(Offset(s * 0.67, y), Offset(s * 0.85, y), bodyPaint);
    }

    // 日期圆点:右下角(报纸的"出版日"锚点)
    canvas.drawCircle(
      Offset(s * 0.815, s * 0.745),
      s * 0.048,
      fillPaint(ink.accent),
    );
  }
}

/// 公版书:**书脊竖条 + 封面 + 书名条 + 装饰弧线**。
///
/// 立着的书比"摊开的书"更适合这个尺寸:书脊是唯一的"厚度"信号,
/// 右下角的装饰弧线是书籍装帧里的经典元素(不是随手加的)。
class _BookPainter extends GraphicPainter {
  _BookPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);

    final cover = Rect.fromLTRB(s * 0.28, s * 0.16, s * 0.82, s * 0.84);
    final radius = Radius.circular(s * 0.028);
    // 封面:极淡的领域色填充 + 描边(填充让"书"有面,不只是一条线框)
    canvas.drawRRect(
      RRect.fromRectAndCorners(cover, topRight: radius, bottomRight: radius),
      fillPaint(ink.accent.withAlpha(22)),
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(cover, topRight: radius, bottomRight: radius),
      strokePaint(ink.accent, width: stroke * 0.95),
    );

    // 书脊:实心领域色 = 全图最深的一档(这就是"书脊比封面深一档")
    final spine = Rect.fromLTRB(s * 0.20, s * 0.16, s * 0.28, s * 0.84);
    canvas.drawRRect(
      RRect.fromRectAndCorners(spine, topLeft: radius, bottomLeft: radius),
      fillPaint(ink.accent),
    );

    // 书名条:两行(第二行短),中性墨线压在封面上
    canvas.drawLine(
      Offset(s * 0.375, s * 0.335),
      Offset(s * 0.725, s * 0.335),
      strokePaint(ink.line, width: stroke * 1.0),
    );
    canvas.drawLine(
      Offset(s * 0.375, s * 0.435),
      Offset(s * 0.625, s * 0.435),
      strokePaint(ink.line.withAlpha(170), width: stroke * 0.8),
    );

    // 右下角装饰弧线:以封面右下角为心的一段 1/4 弧
    canvas.drawArc(
      Rect.fromCircle(center: cover.bottomRight, radius: s * 0.225),
      math.pi,
      math.pi / 2,
      false,
      strokePaint(ink.tone.withAlpha(190), width: stroke * 0.75),
    );
  }
}

/// 听力/播客:**对称声波柱 + 底部圆弧 + 播放三角**。
///
/// 对称柱是"音频频谱",中间最高 —— 这是所有人都会读的波形语言。
/// 底部那张弧 + 播放键把"这是可以听的东西"说清楚。
class _AudioPainter extends GraphicPainter {
  _AudioPainter({required super.ink, required super.stroke});

  static const List<double> _heights = <double>[
    0.13, 0.22, 0.33, 0.45, 0.33, 0.22, 0.13,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final cy = s * 0.40;
    final step = s * 0.082;
    final startX = s * 0.5 - step * (_heights.length - 1) / 2;

    // 声波柱:中间三根用满领域色,两端渐淡 —— 对称 + 有重心
    for (var i = 0; i < _heights.length; i++) {
      final x = startX + step * i;
      final h = s * _heights[i];
      // 浓度按"离中心几步"递减(中间 255 → 两端 145),不用再引入新颜色
      final alpha = switch (i) {
        3 => 255,
        2 || 4 => 205,
        _ => 145,
      };
      canvas.drawLine(
        Offset(x, cy - h / 2),
        Offset(x, cy + h / 2),
        strokePaint(ink.accent.withAlpha(alpha), width: stroke * 1.3),
      );
    }

    // 底部大弧:声波扩散的"碗"
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s * 0.5, cy), radius: s * 0.36),
      math.pi * 0.22,
      math.pi * 0.56,
      false,
      strokePaint(ink.tone.withAlpha(150), width: stroke * 0.8),
    );

    // 播放三角:底弧正中,朝右
    final tri = Path()
      ..moveTo(s * 0.47, s * 0.685)
      ..lineTo(s * 0.47, s * 0.775)
      ..lineTo(s * 0.56, s * 0.730)
      ..close();
    canvas.drawPath(tri, fillPaint(ink.accent));
  }
}

/// 笔记/碎片:**便签(右上折角) + 手写横线 + 回形针**。
///
/// 折角是便签最硬的识别特征(便利贴永远折一个角);三条略微波动的线代表
/// "手写",直线会显得像表格;左边回形针是"夹在资料里"的暗示。
///
/// 注意:便签"折角"在深色下不能用阴影表达,只能靠**折角三角形的实心填充**,
/// 所以这里填充用的是领域色 90 alpha,两套主题都成立。
class _NotePainter extends GraphicPainter {
  _NotePainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);

    // 便签轮廓:右上角切掉一块(折角),其余是直角 —— 圆头笔触负责柔和
    final paper = Path()
      ..moveTo(s * 0.26, s * 0.17)
      ..lineTo(s * 0.60, s * 0.17)
      ..lineTo(s * 0.81, s * 0.38)
      ..lineTo(s * 0.81, s * 0.83)
      ..lineTo(s * 0.26, s * 0.83)
      ..close();
    canvas.drawPath(paper, fillPaint(ink.accent.withAlpha(16)));
    canvas.drawPath(
      paper,
      strokePaint(ink.accent, width: stroke * 0.95),
    );

    // 折角:三角形 + 两条折线(用实心块表示"背面翻起来",深色下也读得懂)
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.60, s * 0.17)
        ..lineTo(s * 0.60, s * 0.38)
        ..lineTo(s * 0.81, s * 0.38)
        ..close(),
      fillPaint(ink.accent.withAlpha(90)),
    );
    canvas.drawLine(
      Offset(s * 0.60, s * 0.17),
      Offset(s * 0.60, s * 0.38),
      strokePaint(ink.accent, width: stroke * 0.8),
    );
    canvas.drawLine(
      Offset(s * 0.60, s * 0.38),
      Offset(s * 0.81, s * 0.38),
      strokePaint(ink.accent, width: stroke * 0.8),
    );

    // 三条"手写"横线:各自轻微起伏,长度递减(段落感)
    final inkLine = strokePaint(ink.line.withAlpha(195), width: stroke * 0.85);
    const lineYs = <double>[0.50, 0.60, 0.70];
    const lineEnds = <double>[0.70, 0.66, 0.58];
    for (var i = 0; i < lineYs.length; i++) {
      final y = s * lineYs[i];
      final x0 = s * 0.33;
      final x1 = s * lineEnds[i];
      final mid = (x0 + x1) / 2;
      final wave = s * 0.018 * (i.isEven ? 1 : -1);
      canvas.drawPath(
        Path()
          ..moveTo(x0, y)
          ..quadraticBezierTo(mid, y - wave, x1, y),
        inkLine,
      );
    }

    // 回形针:外圈窄圆角框 + 内圈竖线 —— 只画两笔,别画成"回形针图标"
    final clip = Rect.fromLTRB(s * 0.145, s * 0.30, s * 0.235, s * 0.72);
    canvas.drawRRect(
      RRect.fromRectAndRadius(clip, Radius.circular(s * 0.045)),
      strokePaint(ink.tone, width: stroke * 0.8),
    );
    canvas.drawLine(
      Offset(clip.center.dx, s * 0.36),
      Offset(clip.center.dx, s * 0.66),
      strokePaint(ink.tone, width: stroke * 0.8),
    );
  }
}

/// 兜底(未知领域):**四角星罗盘 + 虚线圆 + 两个点**。
///
/// 兜底图形的职责是"安静":不冒充任何一个具体领域,但也不是空槽 ——
/// 罗盘暗示"待分类",虚线圆暗示"临时"。
class _CustomPainter extends GraphicPainter {
  _CustomPainter({required super.ink, required super.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = size.center(Offset.zero);

    // 虚线圆:半径 0.34,像"待定"的边界
    drawDashedArc(
      canvas,
      c,
      s * 0.34,
      0,
      math.pi * 2,
      strokePaint(ink.tone, width: stroke * 0.8),
      dash: s * 0.052,
      gap: s * 0.042,
    );

    // 罗盘星:外层领域色 + 内层中性(和科技图同一套"星"语言,但更安静)
    drawStar4(canvas, c, s * 0.285, fillPaint(ink.accent.withAlpha(215)), notch: 0.24);
    drawStar4(canvas, c, s * 0.115, fillPaint(ink.line), notch: 0.30);

    // 两个点:落在虚线圆的斜对角,补"坐标"意味
    final dotPaint = fillPaint(ink.accent);
    for (final angle in <double>[-3 * math.pi / 4, math.pi / 4 + math.pi / 2]) {
      final p = c + Offset.fromDirection(angle, s * 0.34);
      canvas.drawCircle(p, stroke * 0.85, dotPaint);
    }
  }
}
