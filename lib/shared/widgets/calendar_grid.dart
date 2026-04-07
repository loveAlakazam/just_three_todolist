import 'package:flutter/material.dart';

import 'achievement_sticker.dart';

/// 7열 × 최대 6행 형태의 월별 날짜 그리드.
///
/// - [displayMonth]가 가리키는 달의 1일이 위치하는 요일에 맞춰 빈 셀을 채워 넣는다.
/// - 각 날짜 셀은 다음 레이어로 구성된다:
///   ```
///   Stack
///    ├─ Container(circle, #512DA8)  ← 오늘 날짜만
///    ├─ Text(날짜 숫자)
///    └─ Positioned(bottom) AchievementSticker  ← 달성률 > 0인 날만
///   ```
/// - 날짜 탭 인터랙션은 v1.0.0 스펙상 없음.
class CalendarGrid extends StatelessWidget {
  const CalendarGrid({
    super.key,
    required this.displayMonth,
    required this.today,
    required this.achievementRates,
  });

  /// 표시할 달 (해당 월의 임의의 날짜를 받아 year/month만 사용).
  final DateTime displayMonth;

  /// 오늘 날짜 (현재 날짜 강조용).
  final DateTime today;

  /// 일자(`day`)별 달성률 (0.0 ~ 1.0).
  final Map<int, double> achievementRates;

  static const Color _primary = Color(0xFF512DA8);

  @override
  Widget build(BuildContext context) {
    final int year = displayMonth.year;
    final int month = displayMonth.month;

    // 해당 월의 1일이 어느 요일에 위치하는지 (DateTime.weekday: 월=1 ~ 일=7).
    // 캘린더는 SUN ~ SAT 순이므로 일요일을 0으로 환산.
    final int firstWeekday = DateTime(year, month, 1).weekday % 7;
    final int daysInMonth = DateTime(year, month + 1, 0).day;
    final int totalCells = firstWeekday + daysInMonth;
    // 7의 배수로 올림 (마지막 행이 비어도 동일한 셀 크기를 유지하기 위해).
    final int rowCount = (totalCells / 7).ceil();
    final int gridCount = rowCount * 7;

    // 가용 높이를 행 수로 나눠 셀 높이를 결정 → 그리드가 항상 부모 영역을 꽉 채운다.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double cellHeight = constraints.maxHeight / rowCount;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: cellHeight,
          ),
          itemCount: gridCount,
          itemBuilder: (BuildContext context, int index) {
            final int day = index - firstWeekday + 1;
            if (day < 1 || day > daysInMonth) {
              return _emptyCell();
            }
            final bool isToday = year == today.year &&
                month == today.month &&
                day == today.day;
            final double rate = achievementRates[day] ?? 0;
            return _dayCell(day: day, isToday: isToday, rate: rate);
          },
        );
      },
    );
  }

  Widget _emptyCell() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD8D5C8), width: 0.5),
      ),
    );
  }

  Widget _dayCell({
    required int day,
    required bool isToday,
    required double rate,
  }) {
    // 날짜 숫자: 세로 상단 + 가로 중앙 정렬.
    // 오늘 강조 원은 숫자를 감싸는 형태로 상단에 함께 배치.
    // 스티커는 셀 하단 중앙.
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD8D5C8), width: 0.5),
      ),
      child: Stack(
        children: <Widget>[
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isToday ? _primary : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$day',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isToday
                        ? Colors.white
                        : const Color(0xFF333333),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AchievementSticker(rate: rate, size: 8),
            ),
          ),
        ],
      ),
    );
  }
}
