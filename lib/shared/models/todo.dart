/// 하루 목표 1개(todo) 모델.
///
/// `todos` 테이블과 1:1 매핑.
/// - [date]: 해당 todo가 속한 날짜 (KST 기준, 시/분/초 = 0).
/// - [orderIndex]: 같은 날짜 내 정렬 순서 (같은 날짜 기준 오름차순).
class Todo {
  final String id;
  final String userId;
  final DateTime date;
  final String text;
  final bool isCompleted;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Todo({
    required this.id,
    required this.userId,
    required this.date,
    required this.text,
    required this.isCompleted,
    required this.orderIndex,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Todo.fromMap(Map<String, dynamic> map) {
    return Todo(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      date: DateTime.parse(map['date'] as String),
      text: (map['text'] as String?) ?? '',
      isCompleted: (map['is_completed'] as bool?) ?? false,
      orderIndex: map['order_index'] as int,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'date': formatDate(date),
      'text': text,
      'is_completed': isCompleted,
      'order_index': orderIndex,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Todo copyWith({
    String? text,
    bool? isCompleted,
    int? orderIndex,
    DateTime? updatedAt,
  }) {
    return Todo(
      id: id,
      userId: userId,
      date: date,
      text: text ?? this.text,
      isCompleted: isCompleted ?? this.isCompleted,
      orderIndex: orderIndex ?? this.orderIndex,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Supabase `date` 컬럼은 `YYYY-MM-DD` 문자열로 저장된다.
  /// Repository 등 다른 레이어에서도 재사용하도록 public 으로 노출.
  static String formatDate(DateTime date) {
    final String yyyy = date.year.toString().padLeft(4, '0');
    final String mm = date.month.toString().padLeft(2, '0');
    final String dd = date.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }
}
