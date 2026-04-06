# Todo 화면 UI 분석

## 화면 개요
하루 목표를 관리하는 메인 화면. 기본 3개 제공, 최대 10개까지 추가 가능.

## v1.0.0 스펙 결정사항

| 항목 | v1.0.0 동작 |
|------|------------|
| 달성 체크 방향 | 단방향 (체크 후 해제 불가) |
| 달성 시 숨김 처리 | **보류** — 달성해도 목록에 계속 표시 |
| 과거 날짜 목표 | 다음날 0시 이후 읽기 전용 (수정 불가) |
| 달성 게이지바 색상 | 달성률에 따라 동적 변경 (아래 색상표 참고) |

> **고도화 예정**: 달성 목표 숨김/숨김해제는 마이페이지 설정에서 ON/OFF 토글로 추가 예정 (`.claude/plans/고도화계획.md` 참고)

---

## 레이아웃 구조
- 상단: 현재 날짜 텍스트 (YYYY.MM.DD)
- 중단: 달성 게이지바 (세그먼트형)
- 중단: Todo 리스트 (스크롤 가능)
- 하단: 목표 추가하기 버튼
- 최하단: BottomNavigationBar

---

## 필요한 위젯

### 레이아웃 위젯
| 위젯 | 용도 |
|------|------|
| `Scaffold` | 화면 기본 구조, `backgroundColor: Color(0xFFDEE0DF)` |
| `SafeArea` | 노치/홈바 안전 영역 처리 |
| `Column` | 전체 수직 레이아웃 |
| `Expanded` + `SingleChildScrollView` | Todo 리스트 스크롤 영역 |

### UI 컴포넌트
| 위젯 | 용도 |
|------|------|
| `Text` | 날짜 표시 (YYYY.MM.DD), 폰트 `#512DA8` |
| 커스텀 `SegmentedProgressBar` | 달성 게이지바 |
| 커스텀 `TodoItemWidget` | 목표 1개 행 (목표 텍스트 + 달성 버튼) |
| `TextField` | 목표 텍스트 입력 (최대 20자) |
| `InkWell` + `Icon` | 달성 체크 버튼 (단방향, 체크 후 해제 불가) |
| `ElevatedButton` | 목표 추가하기 버튼 (`#512DA8`) |
| `BottomNavigationBar` | 탭 네비게이션 (Calendar / To Do / My) |

### 달성 게이지바 (SegmentedProgressBar)
- 목표 개수 N개 → 세그먼트 N개, 구분선 N-1개
- 달성률에 따른 채워진 색상 (project-overview.md 기준):

| 달성률 | 색상 | Hex |
|--------|------|-----|
| 0% | 색상 없음 (빈 바) | - |
| 0% 초과 ~ 30% 미만 | 빨강 | `#e32910` |
| 30% 이상 ~ 60% 미만 | 노랑 | `#FFC943` |
| 60% 이상 ~ 100% 미만 | 초록 | `#13d62d` |
| 100% | 파랑 | `#46C8FF` |

- 달성 체크가 단방향이므로 게이지바 색상은 단조 증가 → 사이드이펙트 없음
- 구현: `CustomPainter` 또는 `Row` + `Flexible` 조합

### BottomNavigationBar
| 탭 | 활성 상태 | 비활성 상태 |
|----|----------|------------|
| Calendar | - | 기본 텍스트 |
| To Do | `#512DA8` 배경 + 흰 텍스트 | 기본 텍스트 |
| My | - | 기본 텍스트 |

---

## 구현 계획

### 파일 위치
- `lib/features/todo/view/todo_screen.dart`
- `lib/shared/widgets/segmented_progress_bar.dart`
- `lib/shared/widgets/todo_item_widget.dart`

### 구현 단계
1. `Scaffold` + 배경색 + `BottomNavigationBar` 기본 틀 구성
2. 날짜 `Text` 위젯 (`DateTime.now()` → `YYYY.MM.DD` 포맷)
3. `SegmentedProgressBar` 구현
   - 달성률 계산 → 색상 결정 → 채워진 비율 렌더링
4. `TodoItemWidget` 구현
   - 오늘 날짜: `TextField` 입력 가능 + 달성 체크 버튼 활성
   - 과거 날짜: `enabled: false` 읽기 전용 + 체크 버튼 비활성
5. `ListView.builder`로 todo 목록 렌더링
6. 목표 추가하기 버튼: 목표 수 < 10일 때만 활성화 (10개 달성 시 버튼 숨김 또는 비활성)
7. `TodoViewModel` (Riverpod Provider)과 상태 연결

### 주요 로직
```
// 날짜 비교 (수정 가능 여부)
isEditable = today == todo.date  // 0시 기준

// 달성률 계산
rate = completedCount / totalCount
// 소수점 셋째자리에서 반올림 → 둘째자리까지 표기

// 게이지바 색상 결정
if rate == 0    → 색상 없음
if rate < 0.30  → #e32910
if rate < 0.60  → #FFC943
if rate < 1.00  → #13d62d
if rate == 1.00 → #46C8FF
```

### 입력 제한
- `TextField`: `maxLength: 20` (한글 기준 20자)
- 목표 추가: 총 개수 10개 초과 불가
