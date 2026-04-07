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

- 파라미터: `text`, `isCompleted`, `isEditable`, `onChanged`, `onToggle`
- 오늘 날짜(`isEditable: true`): `TextField` 활성 + 달성 버튼 활성
- 과거 날짜(`isEditable: false`): `TextField(enabled: false)` + 달성 버튼 비활성
- 달성 버튼: 단방향 체크 (체크 후 해제 불가), `InkWell + Icon`
- `TextField`: `maxLength: 20`, `hintText: "목표를 입력해주세요"`

## v1.0.0 결정사항

- 달성 시 목록 숨김 없음 (달성해도 계속 표시) ※ 와이어프레임(todo-02)에서는 숨김처리로 표시되나, v1.0.0에서 보류됨 — 스펙 우선
- 목표 추가 버튼: 총 10개 미만일 때만 활성
