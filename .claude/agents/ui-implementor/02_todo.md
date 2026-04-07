# 02. Todo 화면

**파일**: `lib/features/todo/view/todo_screen.dart`

## 작업 브랜치

- Todo 화면 UI 구현 및 개발 작업은 **반드시 `feature/todo` 브랜치에서 진행**한다.
- 작업 시작 전 현재 브랜치를 확인하고, 다른 브랜치라면 `feature/todo`로 전환한 후 작업한다.
- `feature/todo` 브랜치가 없다면 `main`에서 분기하여 생성한다.

## 레이아웃

```
Scaffold (bg: #f3f4eb)
└─ SafeArea
   └─ Column
      ├─ Text (날짜: YYYY.MM.DD, color: #512DA8)
      ├─ SegmentedProgressBar (커스텀)
      ├─ Expanded
      │  └─ SingleChildScrollView
      │     └─ Column → TodoItemWidget × N
      ├─ ElevatedButton ("목표 추가하기", #512DA8)
      └─ BottomNavigationBar
```

## 위젯 상세

### SegmentedProgressBar (`lib/shared/widgets/segmented_progress_bar.dart`)

- 파라미터: `totalCount`, `completedCount`
- 세그먼트 수 = `totalCount`, 구분선 수 = `totalCount - 1`
- 달성률 = `completedCount / totalCount` → 색상 결정 (디자인 시스템 색상표 참고)
- 구현: `CustomPainter` 또는 `Row + Flexible`

### TodoItemWidget (`lib/shared/widgets/todo_item_widget.dart`)

- 파라미터: `text`, `isCompleted`, `isEditable`, `onChanged`, `onToggle`, `onDelete`
- 오늘 날짜(`isEditable: true`): `TextField` 활성 + 달성 버튼 활성 (목표명·달성여부 모두 수정 가능)
- 과거 날짜(`isEditable: false`): `TextField(enabled: false)` + 달성 버튼 비활성 (목표명·달성여부 모두 수정 불가)
- 달성 버튼: 양방향 토글 (체크/해제 모두 가능), `InkWell + Icon`
- 달성여부 토글 시 상위 화면의 `SegmentedProgressBar` 상태가 즉시 갱신되도록 콜백 설계
- 삭제 버튼: 행 우측에 `InkWell + Icon(Icons.close)` 배치
  - `isEditable && !isCompleted`인 경우에만 노출 + 탭 가능
  - 그 외 상태에서는 `Visibility(maintainSize: true)`로 자리만 유지하고 숨김 → 행 너비 일정
- `TextField`: `maxLength: 20`, `hintText: "목표를 입력해주세요"`

## v1.0.0 결정사항

- 달성 시 목록 숨김 없음 (달성해도 계속 표시) ※ 와이어프레임(todo-02)에서는 숨김처리로 표시되나, v1.0.0에서 보류됨 — 스펙 우선
- 목표 추가 버튼: 총 10개 미만일 때만 활성
- 달성여부 체크 버튼: **양방향 토글** — 오늘 날짜 목표는 체크/해제 모두 가능, 과거 날짜는 모두 불가
- 토글 시 `SegmentedProgressBar`의 채워진 세그먼트 수와 색상이 즉시 갱신됨
- **목표 삭제 버튼**: 와이어프레임에는 없으나 v1.0.0에서 추가 — 오늘 날짜 + `isCompleted == false`인 경우에만 노출 및 동작 (달성된 목표/과거 날짜는 삭제 불가)
- 삭제 시 `SegmentedProgressBar`의 세그먼트 수가 줄어들고 달성률도 즉시 재계산됨
