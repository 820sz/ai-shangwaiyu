/// 每日学习记录
class LearningRecord {
  final DateTime date;
  final int newWordsCount;
  final int reviewedCount;
  final int exerciseCompleted;
  final int studyMinutes;

  LearningRecord({
    required this.date,
    this.newWordsCount = 0,
    this.reviewedCount = 0,
    this.exerciseCompleted = 0,
    this.studyMinutes = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': dateKey(date),
      'new_words_count': newWordsCount,
      'reviewed_count': reviewedCount,
      'exercise_completed': exerciseCompleted,
      'study_minutes': studyMinutes,
    };
  }

  factory LearningRecord.fromMap(Map<String, dynamic> map) {
    return LearningRecord(
      date: DateTime.parse(map['date'] as String),
      newWordsCount: map['new_words_count'] as int? ?? 0,
      reviewedCount: map['reviewed_count'] as int? ?? 0,
      exerciseCompleted: map['exercise_completed'] as int? ?? 0,
      studyMinutes: map['study_minutes'] as int? ?? 0,
    );
  }

  LearningRecord copyWith({
    DateTime? date,
    int? newWordsCount,
    int? reviewedCount,
    int? exerciseCompleted,
    int? studyMinutes,
  }) {
    return LearningRecord(
      date: date ?? this.date,
      newWordsCount: newWordsCount ?? this.newWordsCount,
      reviewedCount: reviewedCount ?? this.reviewedCount,
      exerciseCompleted: exerciseCompleted ?? this.exerciseCompleted,
      studyMinutes: studyMinutes ?? this.studyMinutes,
    );
  }

  static String dateKey(DateTime dt) {
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// 总活动点数（用于热力图强度计算）
  int get totalActivity => newWordsCount + reviewedCount + exerciseCompleted;
}
