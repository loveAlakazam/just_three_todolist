# 02. Todo 비즈니스 로직

## 작업 브랜치 (git-flow)

- 브랜치: `feature/todo`
- **`develop`에서 분기**하여 생성한다 (`main`에서 분기 금지):
  ```bash
  git checkout develop && git pull origin develop
  git checkout -b feature/todo
  ```
- PR base 브랜치는 **`develop`**. 릴리즈는 `/release` 커맨드가 별도로 처리한다.
- 자세한 규칙은 `.claude/rules/git-flow.md` 및 `00_overview.md` §7 참조.

## 대상 View
- `lib/features/todo/view/todo_screen.dart`

## 사전 가드 (00_overview.md 핵심 제약)

- **CR-1 (인증 가드)**: `/todo`는 로그인 회원 전용. View 자체에 비로그인 분기 처리를 넣지 않는다. 비로그인 상태에서의 접근 차단은 `core/router.dart`의 `redirect`가 단독으로 책임진다. ViewModel `build()`는 항상 `auth.uid()`가 존재한다고 가정해도 된다.
- **CR-2 (탭 상태 유지)**: `/todo` 탭은 `StatefulShellRoute`의 `IndexedStack`에 들어 있어야 한다. 다른 탭으로 이동했다 돌아와도 ViewModel이 dispose되지 않고, 진행 중이던 텍스트 입력 / 스크롤이 그대로 유지되어야 한다. → `keepAlive: true` 또는 shell 안에서 자연스럽게 유지되는 구조 사용.
- **CR-3 (세션 영속화)**: 앱 재시작 시 자동 로그인 → 사용자는 `/todo`로 바로 진입한다. ViewModel은 매번 새로 생성되므로, "오늘 날짜" 기준 데이터를 다시 fetch할 수 있어야 한다.

### 현재 상태 (UI 구현 완료, 로직 미연결)
View 안에서 다음 임시 상태로만 동작한다 (모두 ViewModel로 옮겨야 함):
```dart
class _TodoDraft { final int id; String text = ''; bool isCompleted = false; }

late final List<_TodoDraft> _todos = List.generate(_initialTodoCount, (_) => _TodoDraft());
final DateTime _date = DateTime.now();   // 오늘만 표시
static const int _maxTodoCount = 10;
static const int _initialTodoCount = 3;
```
- 모든 변경(`_addTodo`, `_toggleComplete`, `_deleteTodo`, `_updateText`)이 `setState`로 로컬에서만 유지됨 → 앱 재시작 시 사라짐.
- "캘린더에서 특정 날짜 진입" 케이스는 v1.0.0 스펙상 없음. 지금은 항상 `DateTime.now()` 기준.

---

## 구현해야 할 비즈니스 로직

### 1. 일별 todo 조회 (Read)
- 화면 진입 시점의 KST 날짜로 `todos` 테이블 조회.
- 결과가 비어 있으면 `_initialTodoCount` (=3) 개의 빈 todo를 자동 생성하고 다시 조회한다.
- `order_index` 오름차순.

### 2. todo 추가 (Create)
- 현재 todo 수가 `_maxTodoCount` (=10) 미만일 때만 허용.
- `text = ''`, `is_completed = false`, `order_index = (현재 max order_index) + 1`.
- 추가 직후 새 row의 id를 받아 ViewModel state에 추가.

### 3. todo 텍스트 수정 (Update)
- 입력 중에는 ViewModel state만 갱신 (로컬).
- 저장 시점:
  - 옵션 A: **debounce 500ms** → 자동 저장.
  - 옵션 B: **focus blur** 또는 다른 todo 탭 시 저장.
- DB에 저장할 때 trim된 값으로 update. 빈 문자열도 허용 (사용자가 비울 수 있음).
- 한글 20자 제한은 UI 측 `maxLength: 20`에서 이미 처리됨.

### 4. todo 완료 토글 (양방향 Update)
- `isEditable = true` (오늘 날짜)인 경우만 호출됨.
- `is_completed`를 즉시 toggle → DB update.
- DB 실패 시 이전 상태로 rollback + SnackBar.

### 5. todo 삭제 (Delete)
- 오늘 + 미달성 상태에서만 호출됨 (View 단에서 이미 가드).
- DB delete + state에서 제거.
- 삭제 후 남은 todo의 `order_index`는 재정렬하지 않는다 (gap 허용).

### 6. 자정 갱신 (옵션, MVP 이후)
- 사용자가 화면을 띄워둔 채 자정을 넘기면 새 날짜로 다시 조회해야 한다.
- `WidgetsBindingObserver`로 `didChangeAppLifecycleState`를 구독해 resume 시 날짜 비교.
- 또는 ViewModel 내부 `Timer`로 자정 트리거.
- MVP에서는 미구현 가능. 단, ViewModel 인터페이스가 이를 지원할 수 있도록 `currentDate`를 외부에서 주입 가능하게 설계.

### 7. 캘린더 진입은 현재 스펙상 없음
- 캘린더 그리드의 날짜 셀은 탭 인터랙션이 없다 (`calendar_grid.dart` 주석 참고).
- 따라서 Todo 화면은 항상 "오늘" 기준으로만 동작한다.
- 추후 과거 날짜 read-only 화면이 필요해지면 ViewModel `family(date)`에서 자연스럽게 확장 가능.

---

## 구현해야 할 파일

### `lib/shared/models/todo.dart`
```dart
class Todo {
  final String id;
  final String userId;
  final DateTime date;     // KST 기준 일자 (시/분/초 = 0)
  final String text;
  final bool isCompleted;
  final int orderIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Todo({...});

  factory Todo.fromMap(Map<String, dynamic> map) { ... }
  Map<String, dynamic> toMap() { ... }
  Todo copyWith({...}) { ... }
}
```

### `lib/features/todo/repository/todo_repository.dart`
```dart
abstract class TodoRepository {
  /// 특정 날짜의 todo 목록 조회. order_index 오름차순.
  Future<List<Todo>> getTodosByDate(DateTime date);

  /// 빈 todo 1개 생성. orderIndex는 호출자가 계산해서 전달.
  Future<Todo> createTodo({
    required DateTime date,
    required int orderIndex,
  });

  /// 텍스트 갱신.
  Future<void> updateTodoText(String id, String text);

  /// 완료 여부 갱신.
  Future<void> updateTodoCompletion(String id, bool isCompleted);

  /// 삭제.
  Future<void> deleteTodo(String id);

  /// 일별 todo가 0개일 때 default 3개를 한 번에 생성.
  /// 호출자가 비어 있음을 확인한 뒤 호출해야 한다.
  Future<List<Todo>> createDefaultTodos(DateTime date);
}

class SupabaseTodoRepository implements TodoRepository { ... }
```

> 모든 메서드는 내부에서 `auth.uid()`를 user_id로 사용. 클라이언트는 user_id를 직접 전달하지 않는다 (RLS가 강제).

### `lib/features/todo/viewmodel/todo_view_model.dart`
```dart
@riverpod
class TodoViewModel extends _$TodoViewModel {
  Timer? _debounce;

  @override
  Future<List<Todo>> build(DateTime date) async {
    final repo = ref.watch(todoRepositoryProvider);
    var list = await repo.getTodosByDate(date);
    if (list.isEmpty) {
      list = await repo.createDefaultTodos(date);
    }
    return list;
  }

  bool get canAddMore => (state.valueOrNull?.length ?? 0) < 10;

  Future<void> addTodo() async { ... }
  Future<void> toggleComplete(String id) async { ... }
  Future<void> deleteTodo(String id) async { ... }

  /// 입력 중에는 state만 갱신, debounce 후 저장.
  void updateText(String id, String text) { ... }
}
```

- 상태 타입: `AsyncValue<List<Todo>>`.
- 낙관적 업데이트(optimistic update): `toggleComplete`, `addTodo`는 먼저 state를 갱신한 뒤 DB 호출 → 실패 시 rollback.

### `lib/features/todo/view/todo_screen.dart` 수정
- `StatefulWidget` → `ConsumerStatefulWidget`.
- `_TodoDraft`, `_todos`, `_addTodo`, `_toggleComplete`, `_deleteTodo`, `_updateText`, `_canAddMore` 등 로컬 상태/메서드 제거.
- `_date`는 ViewModel family 키로 사용 (`DateTime(now.year, now.month, now.day)` KST).
- `ref.watch(todoViewModelProvider(date))`로 `AsyncValue<List<Todo>>` 구독:
  - `loading` → 기존 위젯 트리에 가벼운 loading indicator (예: 게이지바 위치에 `LinearProgressIndicator` 또는 빈 상태) — UI 변경이 필요하면 ui-implementor와 합의.
  - `error` → SnackBar 한번 + 빈 상태 표시.
  - `data` → 기존 동일하게 렌더.
- 콜백 연결:
  ```dart
  TodoItemWidget(
    text: todo.text,
    isCompleted: todo.isCompleted,
    isEditable: _isToday,
    onChanged: (v) => ref.read(todoViewModelProvider(date).notifier).updateText(todo.id, v),
    onToggle: () => ref.read(todoViewModelProvider(date).notifier).toggleComplete(todo.id),
    onDelete: () => ref.read(todoViewModelProvider(date).notifier).deleteTodo(todo.id),
  )
  ```
- `목표 추가하기` 버튼: `ref.read(...notifier).addTodo()`.
- 위젯 트리, 색상, 패딩, 네비게이션 구조는 그대로 유지.

---

## Supabase 스키마

### `todos` 테이블
```sql
create table public.todos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  text text not null default '',
  is_completed boolean not null default false,
  order_index integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_todos_user_date on public.todos (user_id, date, order_index);

alter table public.todos enable row level security;

create policy "todos owner select" on public.todos
  for select using (auth.uid() = user_id);
create policy "todos owner insert" on public.todos
  for insert with check (auth.uid() = user_id);
create policy "todos owner update" on public.todos
  for update using (auth.uid() = user_id);
create policy "todos owner delete" on public.todos
  for delete using (auth.uid() = user_id);
```

### updated_at 자동 갱신 trigger
```sql
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger todos_set_updated_at
  before update on public.todos
  for each row execute function public.set_updated_at();
```

### 제약 (선택)
- 한 날짜당 todo 수 제한 (10개)을 DB에서 강제하려면 trigger 또는 partial unique index 활용.
- MVP에서는 클라이언트(`canAddMore`)만으로 충분.

---

## 체크리스트

- [ ] `shared/models/todo.dart` 생성 (Todo 모델 + 직렬화)
- [ ] `todos` 테이블 + RLS + index + updated_at trigger 생성
- [ ] `todo_repository.dart` 작성 (인터페이스 + Supabase 구현)
- [ ] `todo_view_model.dart` 작성 (`AsyncNotifier.family<List<Todo>, DateTime>`)
- [ ] `todo_screen.dart`를 `ConsumerStatefulWidget`으로 변환 + 콜백 연결
- [ ] 낙관적 업데이트 + rollback 패턴 확인
- [ ] 디바운스(500ms) 텍스트 저장 동작 확인
- [ ] 수동 테스트: 추가 / 토글 / 삭제 / 텍스트 저장 / 앱 재시작 시 유지 / 10개 제한
