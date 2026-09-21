/// 写译相关文案的单一来源 —— 对应代码审查 P2-29(术语/状态文案一致)。
///
/// 为什么放在 lib/widgets/ 而不是 AppConstants:本轮 `lib/config/constants.dart`
/// 由其他人负责,先在这里**局部收口**,避免「写译批改」页与「写译记录」页
/// 各写一份字面量、日后慢慢漂移(材料类型标签原先就在两页各写了一遍)。
///
/// ⚠️ 待主 agent 统一(以下文件不在本 agent 负责范围,故只在此留档):
/// 「不认识 / 模糊 / 认识」(动作词,`review_screen.dart` 掌握度按钮)与
/// 「新词 / 学习中 / 已掌握」(状态词,`review_screen.dart:340/439`、
/// `models/vocabulary.dart:194`、`screens/profile/vocab_detail.dart:134`)
/// 是同一个 `masteryLevel` 字段的两套说法。P2-29 要求把它们集中到
/// `AppConstants` 一处、两页共用(建议动作侧保留动作词,状态侧显示对应的
/// 状态词),并把映射写进注释,让用户点完「不认识」回词库能对上「新词」。
library;

/// 材料类型在 DB / Hive 里的原始值。
/// 这两个字符串是历史数据格式,**不要改**(改了老记录会读不出来)。
const String kMaterialTypeHandwritten = 'handwritten';
const String kMaterialTypeElectronic = 'electronic';

/// 材料类型的中文标签:写译批改页的分段按钮与写译记录页的标签共用一份
const String kMaterialTypeHandwrittenLabel = '手写档';
const String kMaterialTypeElectronicLabel = '电子档';

const Map<String, String> kMaterialTypeLabels = {
  kMaterialTypeHandwritten: kMaterialTypeHandwrittenLabel,
  kMaterialTypeElectronic: kMaterialTypeElectronicLabel,
};

/// 未知值兜底成「电子档」——记录页宁可显示一个默认标签,也不要空白
String materialTypeLabel(String type) =>
    kMaterialTypeLabels[type] ?? kMaterialTypeElectronicLabel;
