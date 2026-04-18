import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';

/// 캘린더 데이터 접근 레이어.
///
/// `todos` 테이블을 원본 데이터로 사용한다. RLS 가 소유자 검증을 강제하므로
/// 클라이언트는 `user_id` 를 직접 전달하지 않는다.
abstract class CalendarRepository {
  /// `year` / `month` 의 일자별 달성률.
  ///
  /// - key: 해당 월의 day (1~31)
  /// - value: 0.0 ~ 1.0 (둘째 자리까지 정규화)
  ///
  /// 해당 day 에 todo 가 0개면 key 를 만들지 않는다
  /// (View 는 `rates[day] ?? 0` 로 처리).
  Future<Map<int, double>> getMonthlyAchievement({
    required int year,
    required int month,
  });
}

class SupabaseCalendarRepository implements CalendarRepository {
  SupabaseClient get _client => SupabaseService.client;

  /// 현재 로그인 user id (RLS 와 별개로 명시적 필터에도 사용).
  /// ViewModel 은 로그인 상태를 가정하므로 non-null 전제.
  String get _uid {
    final String? uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('CalendarRepository 는 로그인 상태에서만 사용할 수 있습니다.');
    }
    return uid;
  }

  @override
  Future<Map<int, double>> getMonthlyAchievement({
    required int year,
    required int month,
  }) async {
    try {
      final String from = _formatDate(DateTime(year, month, 1));
      // 다음 달 1일 전날 = 이번 달 말일.
      final String toExclusive = _formatDate(DateTime(year, month + 1, 1));

      final List<Map<String, dynamic>> rows = await _client
          .from('todos')
          .select('date, is_completed')
          .eq('user_id', _uid)
          .gte('date', from)
          .lt('date', toExclusive);

      final Map<int, _DayCount> byDay = <int, _DayCount>{};
      for (final Map<String, dynamic> row in rows) {
        final int day = DateTime.parse(row['date'] as String).day;
        final _DayCount entry = byDay[day] ?? const _DayCount();
        byDay[day] = entry.increment(
          done: (row['is_completed'] as bool?) ?? false,
        );
      }

      return byDay.map((int day, _DayCount c) {
        final double raw = c.total == 0 ? 0.0 : c.done / c.total;
        // 셋째 자리 반올림 → 둘째 자리 유지.
        final double normalized = (raw * 100).round() / 100;
        return MapEntry<int, double>(day, normalized);
      });
    } catch (e) {
      debugPrint('[CalendarRepository] getMonthlyAchievement 실패: $e');
      rethrow;
    }
  }

  static String _formatDate(DateTime date) {
    final String yyyy = date.year.toString().padLeft(4, '0');
    final String mm = date.month.toString().padLeft(2, '0');
    final String dd = date.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }
}

class _DayCount {
  const _DayCount({this.total = 0, this.done = 0});

  final int total;
  final int done;

  _DayCount increment({required bool done}) {
    return _DayCount(
      total: total + 1,
      done: this.done + (done ? 1 : 0),
    );
  }
}

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return SupabaseCalendarRepository();
});
