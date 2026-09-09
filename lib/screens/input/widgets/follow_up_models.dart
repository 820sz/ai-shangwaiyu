/// 追问对话相关的数据结构。
///
/// 原为 process_chat.dart 的私有类(2026-08-10 拆分重构):
/// 追问消息 + 已保存的追问历史对话。跨文件使用须公开,故去 `_` 前缀。
library;

/// 追问对话消息
class FollowUpMessage {
  final String role; // 'user' | 'ai'
  final String content;
  final String? reasoningText;
  final bool streaming; // AI 是否仍在生成
  /// 生成此消息的模型名(仅 AI 消息有值)。
  /// 头像/标签按消息自身的模型渲染——切槽位不改变历史气泡;
  /// null = 旧版本数据,渲染时回退当前模型。
  final String? model;

  const FollowUpMessage({
    required this.role,
    required this.content,
    this.reasoningText,
    this.streaming = false,
    this.model,
  });

  FollowUpMessage copyWith({
    String? content,
    String? reasoningText,
    bool? streaming,
  }) => FollowUpMessage(
    role: role,
    content: content ?? this.content,
    reasoningText: reasoningText ?? this.reasoningText,
    streaming: streaming ?? this.streaming,
    model: model,
  );
}

/// 保存的追问对话
class FollowUpSavedConversation {
  final String id; // timestamp
  final String title; // 第一个用户问题
  final String dateLabel;
  final List<Map<String, dynamic>>
  messages; // [{role, content, reasoningText?}]

  const FollowUpSavedConversation({
    required this.id,
    required this.title,
    required this.dateLabel,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'dateLabel': dateLabel,
    'messages': messages,
  };

  factory FollowUpSavedConversation.fromJson(Map<String, dynamic> json) =>
      FollowUpSavedConversation(
        id: json['id'] as String,
        title: json['title'] as String,
        dateLabel: json['dateLabel'] as String,
        messages: (json['messages'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
}
