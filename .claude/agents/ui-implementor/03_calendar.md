# 03. 캘린더 화면

**파일**: `lib/features/calendar/view/calendar_screen.dart`

## 레이아웃

```
Scaffold (bg: #dee0df)
└─ SafeArea
   └─ Stack
      ├─ Column
      │  ├─ 월 네비게이션 헤더
      │  │  ├─ Text (YYYY, centered)
      │  │  └─ Row (◀ Text(MMMM) ▶)
      │  ├─ 달성률 범례 바 (Row: ● N ● N ● N ● N)
      │  ├─ 요일 헤더 (Row: SUN MON ... SAT)
      │  ├─ CalendarGrid (커스텀)
      │  └─ BottomNavigationBar
      └─ Positioned(top, right) → ? 버튼
```

## 위젯 상세

### CalendarGrid (`lib/shared/widgets/calendar_grid.dart`)

- 7열 GridView, 해당 월 날짜 배치 (1일 요일 오프셋 계산)
- 각 날짜 셀:
  ```
  Stack
   ├─ Container(circle, #512DA8)  ← 오늘 날짜만
   ├─ Text(날짜 숫자)
   └─ Positioned(bottom) Container(circle, 스티커색)  ← 달성률 > 0인 날만
  ```
- 날짜 탭: 인터랙션 없음 (GestureDetector 불필요)

### AchievementSticker (`lib/shared/widgets/achievement_sticker.dart`)

- 파라미터: `rate` (double)
- 달성률에 따라 원형 컨테이너 색상 결정

## 월 네비게이션 규칙

- 최소 월: `DateTime(2026, 4)` → 좌측 버튼 `onPressed: null`
- 우측 버튼: 항상 활성

## ? 버튼 팝업

- 탭 시 `showDialog(AlertDialog)` 표시
- 팝업 배경: 보라색 계열
- 내용:
  ```
  없음  달성률 0%
  ● (빨강)  달성률 0% 초과 ~ 30% 미만
  ● (노랑)  달성률 30% 이상 ~ 60% 미만
  ● (초록)  달성률 60% 이상 ~ 100% 미만
  ● (파랑)  달성률 100%
  ```
