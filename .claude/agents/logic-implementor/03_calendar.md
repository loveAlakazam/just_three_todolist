# 03. 캘린더 비즈니스 로직

## 작업 브랜치 (git-flow)

- 브랜치: `feature/calendar`
- **`develop`에서 분기**하여 생성한다 (`main`에서 분기 금지):
  ```bash
  git checkout develop && git pull origin develop
  git checkout -b feature/calendar
  ```
- PR base 브랜치는 **`develop`**. 릴리즈는 `/release` 커맨드가 별도로 처리한다.
- 자세한 규칙은 `.claude/rules/git-flow.md` 및 `00_overview.md` §7 참조.

## 대상 View
- `lib/features/calendar/view/calendar_screen.dart`
- (참고만, 변경 금지) `lib/shared/widgets/calendar_grid.dart`, `achievement_sticker.dart`

## 사전 가드 (00_overview.md 핵심 제약)

- **CR-1 (인증 가드)**: `/calendar`는 로그인 회원 전용. 비로그인 차단은 router redirect가 책임지며, View / ViewModel에서 별도 분기 금지.
- **CR-2 (탭 상태 유지)**: 탭 전환 후 돌아왔을 때 사용자가 보고 있던 `_displayMonth`가 그대로 유지되어야 한다. `_displayMonth`는 위젯의 `State`(`ConsumerStatefulWidget`)에 두되, 화면이 `StatefulShellRoute`의 `IndexedStack`에서 dispose되지 않도록 한다. ViewModel(`CalendarViewModel.family`)도 Riverpod 캐시 + `keepAlive`로 유지.
- **CR-3 (세션 영속화)**: 자동 로그인된 사용자가 캘린더 탭을 처음 열었을 때, 현재 월의 달성률이 fetch되어야 한다.

### 현재 상태 (UI 구현 완료, 로직 미연결)
```dart
/// 일자(`day`)별 달성률. ViewModel 연결 전까지 빈 Map.
final Map<int, double> _achievementRates = <int, double>{};

DateTime _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);
static final DateTime _minMonth = DateTime(2026, 4);  // 스펙 최소 월

/// 색상별 스티커가 붙은 날짜 수 집계.
({int red, int yellow, int green, int blue}) _countByColor() { ... }
```
- 월 이동 (`_goPrev`, `_goNext`)은 동작하지만 `_achievementRates`는 항상 빈 Map.
- 월 이동 시 새 데이터 fetch 로직 없음.
- 캘린더 그리드 셀에는 탭 인터랙션이 없다 (스펙 v1.0.0).

---

## 구현해야 할 비즈니스 로직

### 1. 월별 달성률 조회
- 입력: `year`, `month`.
- 출력: `Map<int, double>` (key = day of month, value = 0.0~1.0).
- 데이터 소스: `todos` 테이블.
- 계산:
  ```
  per-day rate = (해당 day의 is_completed = true count) / (해당 day의 total count)
  ```
- 해당 day의 total이 0이면 key 자체를 만들지 않거나 0으로 둔다 (`AchievementSticker`가 0 처리).

### 2. 소수점 처리 (스펙 `project-overview.md`)
- 둘째 자리까지 표기.
- 부동소수점 이슈를 위해 셋째 자리에서 반올림 → 둘째 자리 유지.
- View가 표시용으로만 쓴다면 `(rate * 100).round() / 100` 형태.
- 색상 분기는 0.30, 0.60, 1.00 경계만 보면 되므로 둘째자리 반올림 후 비교.

### 3. 월 이동 시 fetch + 캐시
- ViewModel은 `family<Map<int, double>, ({int year, int month})>` 또는 `family(DateTime)`.
- Riverpod의 자동 캐시 + `keepAlive` 옵션으로 같은 월 재진입 시 재요청 방지.
- 사용자가 빠르게 월을 넘기면 in-flight 요청은 cancel하지 않고 그대로 두되, 마지막 월의 결과만 화면에 반영되도록 `state` 관리.

### 4. 최소 월 제약
- 2026년 4월 이전은 View에서 이미 좌측 화살표 비활성으로 처리.
- Repository는 그래도 모든 월에 대해 동작 가능하게 둔다 (제약은 View에서만).

### 5. 미래 월 / 데이터 없는 날
- 미래 월 진입 → 모든 day의 rate = 0 → 스티커 없음 + 범례 카운트 모두 0.
- 데이터 없는 날은 자연스럽게 `_achievementRates[day] ?? 0`로 처리됨 (View 코드에 이미 반영).

### 6. 달성률 변경 → 캘린더 자동 갱신 (옵션)
- Todo 화면에서 완료 토글한 결과가 캘린더에 즉시 반영되어야 함.
- 방법:
  - **A. 수동 invalidate**: Todo의 `toggleComplete` 성공 후 `ref.invalidate(calendarViewModelProvider(currentMonthKey))`.
  - **B. Realtime**: Supabase Realtime으로 `todos` 변경 구독 → 캘린더 ViewModel에서 자동 갱신.
  - MVP는 A 권장 (단순). B는 고도화에서.

---

## 구현해야 할 파일

### `lib/features/calendar/repository/calendar_repository.dart`
```dart
abstract class CalendarRepository {
  /// year/month 의 일별 달성률을 반환.
  /// key = day of month (1~31), value = 0.0 ~ 1.0 (둘째 자리까지 정규화).
  Future<Map<int, double>> getMonthlyAchievement({
    required int year,
    required int month,
  });
}

class SupabaseCalendarRepository implements CalendarRepository {
  @override
  Future<Map<int, double>> getMonthlyAchievement({...}) async {
    // 옵션 1: select 후 클라이언트 집계
    final from = DateTime(year, month, 1);
    final to = DateTime(year, month + 1, 1).subtract(const Duration(days: 1));

    final rows = await supabase
      .from('todos')
      .select('date, is_completed')
      .gte('date', from.toIso8601String().substring(0, 10))
      .lte('date', to.toIso8601String().substring(0, 10));

    final Map<int, ({int total, int done})> byDay = {};
    for (final row in rows) {
      final day = DateTime.parse(row['date'] as String).day;
      final entry = byDay[day] ?? (total: 0, done: 0);
      byDay[day] = (
        total: entry.total + 1,
        done: entry.done + (row['is_completed'] == true ? 1 : 0),
      );
    }

    return byDay.map((day, c) {
      final raw = c.total == 0 ? 0.0 : c.done / c.total;
      // 셋째자리 반올림 → 둘째자리 유지.
      final normalized = (raw * 100).round() / 100;
      return MapEntry(day, normalized);
    });
  }
}
```

> 데이터 양이 많아지면 SQL view 또는 RPC function으로 위임:
> ```sql
> create or replace function get_monthly_achievement(p_year int, p_month int)
> returns table(day int, rate numeric) ...
> ```
> MVP에서는 클라이언트 집계로 충분.

### `lib/features/calendar/viewmodel/calendar_view_model.dart`
```dart
@riverpod
class CalendarViewModel extends _$CalendarViewModel {
  @override
  Future<Map<int, double>> build({required int year, required int month}) async {
    final repo = ref.watch(calendarRepositoryProvider);
    return repo.getMonthlyAchievement(year: year, month: month);
  }
}
```

- View는 현재 `_displayMonth`만 들고 있으므로, View에서 `(year, month)` 키로 ViewModel을 호출.
- `keepAlive` 또는 캐시 정책은 Riverpod 기본 동작 활용.

### `lib/features/calendar/view/calendar_screen.dart` 수정
- `StatefulWidget` → `ConsumerStatefulWidget`.
- `_achievementRates` 로컬 필드 제거.
- build에서 `ref.watch(calendarViewModelProvider(year: _displayMonth.year, month: _displayMonth.month))`로 `AsyncValue<Map<int, double>>` 구독.
- `loading` → 그리드 영역에 가벼운 indicator 또는 빈 그리드 (UI 추가 필요 시 ui-implementor와 합의).
- `error` → SnackBar.
- `data` → `CalendarGrid(achievementRates: data)`로 전달.
- `_countByColor()` 메서드는 ViewModel state 기반으로 동작하도록 인자/내부 참조만 수정 (로직은 그대로).
- 월 이동 핸들러 (`_goPrev`, `_goNext`)는 `setState`로 `_displayMonth`만 갱신 → ViewModel family가 자동으로 새 월의 데이터를 fetch.
- 위젯 트리, 색상, 헤더 / 범례 / 그리드 / ? 버튼 등 **레이아웃은 일체 변경 금지**.

### Todo와의 연동 (cross-feature)
- `TodoViewModel`의 `addTodo`, `toggleComplete`, `deleteTodo` 성공 시점에:
  ```dart
  ref.invalidate(calendarViewModelProvider(year: date.year, month: date.month));
  ```
- 이렇게 하면 사용자가 캘린더 탭으로 이동했을 때 즉시 새 달성률이 보인다.

---

## Supabase 스키마

> 추가 테이블 없음. `02_todo.md`의 `todos` 테이블만 사용.

### (선택) 성능을 위한 RPC

#### 목적

월별 달성률 집계를 **클라이언트가 아닌 DB 서버에서** 수행하는 Supabase RPC(Remote Procedure Call) 함수다. `CalendarRepository.getMonthlyAchievement()`의 내부 구현을 교체하는 용도다.

#### 왜 필요한가

캘린더 달성률 계산에는 두 가지 방식이 있다:

| | 클라이언트 집계 (현재 MVP 방식) | RPC 함수 (서버 집계) |
|---|---|---|
| 동작 방식 | `todos` 테이블에서 해당 월의 전체 row를 SELECT → 앱(Dart)에서 day별 `done/total` 계산 | DB 서버에서 SQL로 `GROUP BY date` + `SUM/COUNT` 계산 → 결과(day, rate)만 반환 |
| 네트워크 전송량 | 해당 월의 **모든 todo row** (10개/일 × 30일 = 최대 300개) | **집계 결과만** (최대 31개 row) |
| 연산 위치 | 모바일 기기 (Dart) | DB 서버 (PostgreSQL) |
| 장점 | 별도 DB 설정 불필요. 즉시 사용 가능 | 전송량 ~1/10, 서버가 인덱스 활용해 빠르게 집계, 모바일 기기 부하 감소 |
| 단점 | 데이터가 쌓일수록 전송량/처리 시간 증가 | Supabase SQL Editor에서 함수를 직접 생성해야 함 |

**MVP에서는 클라이언트 집계로 충분하다.** 하루 최대 10개 todo × 30일 = 300개 row 정도는 모바일에서도 빠르게 처리된다. 하지만 장기간 사용으로 데이터가 쌓이거나, 네트워크 환경이 느린 경우 RPC로 교체하면 체감 성능이 크게 개선된다.

#### 사용되는 곳

- `CalendarRepository.getMonthlyAchievement()` — 현재 클라이언트 집계 코드를 `supabase.rpc(...)` 한 줄로 교체

#### 동작 흐름

1. 사용자가 캘린더에서 특정 월(예: 2026년 4월)을 보고 있음
2. `CalendarViewModel`이 `CalendarRepository.getMonthlyAchievement(year: 2026, month: 4)` 호출
3. Repository가 `supabase.rpc('get_monthly_achievement', params: {'p_year': 2026, 'p_month': 4})` 실행
4. DB 서버에서 해당 월의 `todos`를 날짜별로 GROUP BY → `done/total` 비율 계산 → 둘째 자리 반올림
5. 결과 `[{day: 1, rate: 0.67}, {day: 2, rate: 1.00}, ...]` 만 클라이언트로 전송
6. Repository가 `Map<int, double>`로 변환 → ViewModel → View에 반영

```sql
create or replace function public.get_monthly_achievement(p_year int, p_month int)
returns table(day int, rate numeric)
language sql security definer set search_path = public as $$
  select
    extract(day from date)::int as day,
    round(
      sum(case when is_completed then 1 else 0 end)::numeric / count(*)::numeric,
      2
    ) as rate
  from todos
  where user_id = auth.uid()
    and date >= make_date(p_year, p_month, 1)
    and date <  (make_date(p_year, p_month, 1) + interval '1 month')
  group by date
  order by date;
$$;
```

```dart
final rows = await supabase.rpc('get_monthly_achievement', params: {
  'p_year': year, 'p_month': month,
});
```

---

## 체크리스트

- [ ] `calendar_repository.dart` 작성 (클라이언트 집계 또는 RPC)
- [ ] `calendar_view_model.dart` 작성 (`AsyncNotifier.family<Map<int, double>, ...>`)
- [ ] `calendar_screen.dart`를 `ConsumerStatefulWidget`으로 변환 + 콜백 연결
- [ ] 둘째자리 반올림 정책 검증
- [ ] Todo의 `toggleComplete` 등에서 `ref.invalidate(calendarViewModelProvider(...))` 호출 추가
- [ ] (선택) Supabase RPC 함수 생성
- [ ] 수동 테스트: 월 이동 / 0% 처리 / 색상 경계값 (29.99% / 30% / 59.99% / 60% / 99.99% / 100%)
