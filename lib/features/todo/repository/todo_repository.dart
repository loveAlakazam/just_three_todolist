import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../../shared/models/todo.dart';

/// Todo 데이터 접근 레이어.
///
/// 모든 메서드는 내부에서 `auth.uid()` 를 user_id 로 사용한다.
/// (클라이언트는 user_id 를 직접 전달하지 않으며, RLS 가 소유자 검증을 강제한다.)
abstract class TodoRepository {
  /// 특정 날짜의 todo 목록 조회.
  ///
  /// 정렬: 미달성(`is_completed = false`) → 달성(`true`) 순,
  /// 각 그룹 내에서는 `order_index` 오름차순.
  Future<List<Todo>> getTodosByDate(DateTime date);

  /// 빈 todo 1개 생성. [orderIndex] 는 호출자가 계산해서 전달.
  Future<Todo> createTodo({
    required DateTime date,
    required int orderIndex,
  });

  /// 텍스트 갱신. `updated_at` 은 DB trigger 가 갱신.
  Future<void> updateTodoText(String id, String text);

  /// 완료 여부 갱신. `updated_at` 은 DB trigger 가 갱신.
  Future<void> updateTodoCompletion(String id, bool isCompleted);

  /// 삭제. `order_index` 재정렬은 하지 않는다 (gap 허용).
  Future<void> deleteTodo(String id);

  /// 일별 todo 가 0개일 때 default 3개를 한 번에 생성.
  /// 호출자가 비어 있음을 확인한 뒤 호출해야 한다.
  Future<List<Todo>> createDefaultTodos(DateTime date);
}

class SupabaseTodoRepository implements TodoRepository {
  SupabaseClient get _client => SupabaseService.client;

  /// 현재 로그인 user id (RLS 와 별개로, INSERT payload 에 직접 채워야 하므로 필요).
  /// ViewModel `build()` 는 로그인 상태를 가정하므로 여기서도 non-null 전제.
  String get _uid {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('TodoRepository 는 로그인 상태에서만 사용할 수 있습니다.');
    }
    return uid;
  }

  /// `date` 컬럼은 PostgreSQL `date` 타입 (YYYY-MM-DD).
  String _formatDate(DateTime date) {
    final String yyyy = date.year.toString().padLeft(4, '0');
    final String mm = date.month.toString().padLeft(2, '0');
    final String dd = date.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  @override
  Future<List<Todo>> getTodosByDate(DateTime date) async {
    try {
      final rows = await _client
          .from('todos')
          .select()
          .eq('user_id', _uid)
          .eq('date', _formatDate(date))
          .order('is_completed', ascending: true)
          .order('order_index', ascending: true);

      return (rows as List)
          .map((row) => Todo.fromMap(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[TodoRepository] getTodosByDate 실패: $e');
      rethrow;
    }
  }

  @override
  Future<Todo> createTodo({
    required DateTime date,
    required int orderIndex,
  }) async {
    try {
      final row = await _client
          .from('todos')
          .insert({
            'user_id': _uid,
            'date': _formatDate(date),
            'text': '',
            'is_completed': false,
            'order_index': orderIndex,
          })
          .select()
          .single();

      return Todo.fromMap(row);
    } catch (e) {
      debugPrint('[TodoRepository] createTodo 실패: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateTodoText(String id, String text) async {
    try {
      await _client
          .from('todos')
          .update({'text': text})
          .eq('id', id);
    } catch (e) {
      debugPrint('[TodoRepository] updateTodoText 실패: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateTodoCompletion(String id, bool isCompleted) async {
    try {
      await _client
          .from('todos')
          .update({'is_completed': isCompleted})
          .eq('id', id);
    } catch (e) {
      debugPrint('[TodoRepository] updateTodoCompletion 실패: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteTodo(String id) async {
    try {
      await _client.from('todos').delete().eq('id', id);
    } catch (e) {
      debugPrint('[TodoRepository] deleteTodo 실패: $e');
      rethrow;
    }
  }

  @override
  Future<List<Todo>> createDefaultTodos(DateTime date) async {
    try {
      final dateStr = _formatDate(date);
      final payload = List<Map<String, dynamic>>.generate(
        3,
        (i) => {
          'user_id': _uid,
          'date': dateStr,
          'text': '',
          'is_completed': false,
          'order_index': i,
        },
      );

      final rows = await _client.from('todos').insert(payload).select();

      final todos = (rows as List)
          .map((row) => Todo.fromMap(row as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

      return todos;
    } catch (e) {
      debugPrint('[TodoRepository] createDefaultTodos 실패: $e');
      rethrow;
    }
  }
}

final todoRepositoryProvider = Provider<TodoRepository>((ref) {
  return SupabaseTodoRepository();
});
