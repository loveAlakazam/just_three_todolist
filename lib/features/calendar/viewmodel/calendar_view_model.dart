import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repository/calendar_repository.dart';

/// 캘린더 ViewModel 의 family 키.
///
/// `DateTime` 을 그대로 family 키로 쓰면 `_displayMonth` 가 동일 월이어도
/// 시/분/초까지 포함된 인스턴스 차이로 Riverpod 이 다른 provider 로 인식해
/// 재요청이 발생할 수 있다. year/month 만으로 구성된 record 로 정규화.
typedef CalendarMonth = ({int year, int month});

/// 월별 달성률 ViewModel.
///
/// - 상태: `AsyncValue<Map<int, double>>` (key = day, value = 0.0~1.0)
/// - family 키: `CalendarMonth` (year / month)
/// - 같은 월을 재진입하면 Riverpod 캐시가 재요청을 방지한다.
///
/// 월이 바뀔 때마다 View 가 새 family 키로 watch 하면 새 ViewModel 인스턴스가
/// 생성되어 자동으로 fetch 가 트리거된다.
final calendarViewModelProvider = AsyncNotifierProvider.family<
    CalendarViewModel, Map<int, double>, CalendarMonth>(CalendarViewModel.new);

class CalendarViewModel extends AsyncNotifier<Map<int, double>> {
  CalendarViewModel(this.month);

  /// 이 ViewModel 인스턴스가 다루는 (year, month).
  final CalendarMonth month;

  @override
  Future<Map<int, double>> build() async {
    final CalendarRepository repo = ref.watch(calendarRepositoryProvider);
    return repo.getMonthlyAchievement(year: month.year, month: month.month);
  }
}
