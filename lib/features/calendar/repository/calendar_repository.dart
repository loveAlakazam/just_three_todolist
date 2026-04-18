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

/// Supabase RPC `get_monthly_achievement(p_year, p_month)` 를 호출해
/// 서버에서 집계된 일자별 달성률을 가져온다.
///
/// RPC 는 `todos` 를 DB 레벨에서 GROUP BY + 반올림까지 수행해
/// `[{day: 1, rate: 0.67}, ...]` 형태로 반환한다. 클라이언트에서는
/// `Map<int, double>` 로 매핑만 수행. 자세한 SQL 정의는
/// `supabase/migrations/20260418000004_add_get_monthly_achievement_rpc.sql` 참조.
class SupabaseCalendarRepository implements CalendarRepository {
  SupabaseClient get _client => SupabaseService.client;

  @override
  Future<Map<int, double>> getMonthlyAchievement({
    required int year,
    required int month,
  }) async {
    try {
      final List<dynamic> rows = await _client.rpc(
        'get_monthly_achievement',
        params: <String, dynamic>{'p_year': year, 'p_month': month},
      ) as List<dynamic>;

      final Map<int, double> result = <int, double>{};
      for (final dynamic raw in rows) {
        final Map<String, dynamic> row = raw as Map<String, dynamic>;
        final int day = (row['day'] as num).toInt();
        // Postgres numeric 은 json 직렬화 시 문자열로 내려올 수 있어 안전하게 parse.
        final dynamic rateValue = row['rate'];
        final double rate = rateValue is num
            ? rateValue.toDouble()
            : double.parse(rateValue as String);
        result[day] = rate;
      }
      return result;
    } catch (e) {
      debugPrint('[CalendarRepository] getMonthlyAchievement 실패: $e');
      rethrow;
    }
  }
}

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  return SupabaseCalendarRepository();
});
