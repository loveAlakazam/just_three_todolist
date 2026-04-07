import 'package:flutter/material.dart';

import '../../../shared/widgets/calendar_grid.dart';

/// 캘린더 화면.
///
/// 레이아웃:
/// Scaffold → SafeArea → Stack
///   ├─ Column
///   │  ├─ 월 네비게이션 헤더 (YYYY / ◀ MMMM ▶)
///   │  ├─ 달성률 범례 바 (● N × 4)
///   │  ├─ 요일 헤더 (SUN ~ SAT)
///   │  └─ Expanded → CalendarGrid
///   └─ Positioned(top, right) → ? 버튼 (스티커 안내 팝업)
///
/// 월 이동 규칙:
/// - 최소 월: 2026년 4월 → 좌측 화살표 비활성
/// - 우측 화살표: 항상 활성
///
/// MVP UI 단계 — 달성률 데이터는 빈 Map으로 초기화한다.
/// ViewModel / Repository 연결은 후속 작업에서 진행.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  static const Color _primary = Color(0xFF512DA8);
  static const Color _bg = Color(0xFFF3F4EB);
  static final DateTime _minMonth = DateTime(2026, 4);

  static const List<String> _monthNames = <String>[
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  static const List<String> _weekdayLabels = <String>[
    'SUN',
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
  ];

  /// 현재 화면이 표시하는 달 (해당 월의 1일).
  DateTime _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);

  /// 오늘 날짜.
  final DateTime _today = DateTime.now();

  /// 일자(`day`)별 달성률. ViewModel 연결 전까지 빈 Map.
  final Map<int, double> _achievementRates = <int, double>{};

  /// 현재 선택된 BottomNavigation 인덱스 (0: Calendar, 1: To Do, 2: My)
  int _currentTabIndex = 0;

  bool get _canGoPrev => _displayMonth.isAfter(_minMonth);

  void _goPrev() {
    if (!_canGoPrev) return;
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month - 1);
    });
  }

  void _goNext() {
    setState(() {
      _displayMonth = DateTime(_displayMonth.year, _displayMonth.month + 1);
    });
  }

  /// 색상별 스티커가 붙은 날짜 수 집계.
  ({int red, int yellow, int green, int blue}) _countByColor() {
    int red = 0;
    int yellow = 0;
    int green = 0;
    int blue = 0;
    final int daysInMonth =
        DateTime(_displayMonth.year, _displayMonth.month + 1, 0).day;
    for (int day = 1; day <= daysInMonth; day++) {
      final double rate = _achievementRates[day] ?? 0;
      if (rate <= 0) continue;
      if (rate < 0.30) {
        red++;
      } else if (rate < 0.60) {
        yellow++;
      } else if (rate < 1.00) {
        green++;
      } else {
        blue++;
      }
    }
    return (red: red, yellow: yellow, green: green, blue: blue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildMonthHeader(),
                  const SizedBox(height: 16),
                  _buildLegendBar(),
                  const SizedBox(height: 20),
                  _buildWeekdayHeader(),
                  const SizedBox(height: 4),
                  Expanded(
                    child: CalendarGrid(
                      displayMonth: _displayMonth,
                      today: _today,
                      achievementRates: _achievementRates,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 16,
              child: _buildHelpButton(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ────────────────────── 월 네비게이션 헤더 ──────────────────────
  Widget _buildMonthHeader() {
    return Column(
      children: <Widget>[
        Text(
          '${_displayMonth.year}',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _primary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            IconButton(
              onPressed: _canGoPrev ? _goPrev : null,
              icon: const Icon(Icons.arrow_left),
              iconSize: 36,
              color: _primary,
              disabledColor: const Color(0xFFBDB0DC),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 160,
              child: Text(
                _monthNames[_displayMonth.month - 1],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              onPressed: _goNext,
              icon: const Icon(Icons.arrow_right),
              iconSize: 36,
              color: _primary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ],
    );
  }

  // ────────────────────── 달성률 범례 바 ──────────────────────
  Widget _buildLegendBar() {
    final ({int red, int yellow, int green, int blue}) counts = _countByColor();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _legendItem(const Color(0xFFE32910), counts.red),
        _legendItem(const Color(0xFFFFC943), counts.yellow),
        _legendItem(const Color(0xFF13D62D), counts.green),
        _legendItem(const Color(0xFF46C8FF), counts.blue),
      ],
    );
  }

  Widget _legendItem(Color color, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF333333),
          ),
        ),
      ],
    );
  }

  // ────────────────────── 요일 헤더 ──────────────────────
  Widget _buildWeekdayHeader() {
    return Row(
      children: _weekdayLabels
          .map(
            (String label) => Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _primary,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  // ────────────────────── ? 버튼 + 안내 팝업 ──────────────────────
  Widget _buildHelpButton() {
    return GestureDetector(
      onTap: _showStickerGuide,
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFFE0DFD3),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Text(
          '?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF555555),
          ),
        ),
      ),
    );
  }

  void _showStickerGuide() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFFEDE3FF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const <Widget>[
              _GuideRow(color: null, label: '없음', description: '달성률 0%'),
              SizedBox(height: 10),
              _GuideRow(
                color: Color(0xFFE32910),
                label: null,
                description: '달성률 0% 초과 ~ 30% 미만',
              ),
              SizedBox(height: 10),
              _GuideRow(
                color: Color(0xFFFFC943),
                label: null,
                description: '달성률 30% 이상 ~ 60% 미만',
              ),
              SizedBox(height: 10),
              _GuideRow(
                color: Color(0xFF13D62D),
                label: null,
                description: '달성률 60% 이상 ~ 100% 미만',
              ),
              SizedBox(height: 10),
              _GuideRow(
                color: Color(0xFF46C8FF),
                label: null,
                description: '달성률 100%',
              ),
            ],
          ),
        );
      },
    );
  }

  // ────────────────────── BottomNavigationBar ──────────────────────
  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _currentTabIndex,
      onTap: (int idx) => setState(() => _currentTabIndex = idx),
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: _primary,
      unselectedItemColor: const Color(0xFF9E9E9E),
      selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today_outlined),
          activeIcon: Icon(Icons.calendar_today),
          label: 'Calendar',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.check_box_outlined),
          activeIcon: Icon(Icons.check_box),
          label: 'To Do',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'My',
        ),
      ],
    );
  }
}

/// 안내 팝업 행: 스티커(또는 "없음" 라벨) + 설명 텍스트.
class _GuideRow extends StatelessWidget {
  const _GuideRow({
    required this.color,
    required this.label,
    required this.description,
  });

  final Color? color;
  final String? label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 36,
          child: color != null
              ? Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                )
              : Text(
                  label ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            description,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF333333),
            ),
          ),
        ),
      ],
    );
  }
}
