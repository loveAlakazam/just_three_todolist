import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/todo.dart';
import '../../calendar/viewmodel/calendar_view_model.dart';
import '../repository/todo_repository.dart';

/// 하루 최대 todo 개수. 클라이언트 검증용 (DB 제약은 선택사항).
const int kMaxTodoCount = 10;

/// 빈 날짜에 자동 생성되는 default todo 개수.
const int kDefaultTodoCount = 3;

/// 텍스트 자동 저장 debounce.
const Duration _kTextSaveDebounce = Duration(milliseconds: 500);

/// 날짜별 Todo 목록 ViewModel.
///
/// - 상태: `AsyncValue<List<Todo>>` (`order_index` 오름차순)
/// - family 키: 해당 날짜 (KST 기준 시/분/초 = 0)
/// - 낙관적 업데이트: 먼저 state 를 갱신한 뒤 DB 호출, 실패 시 rollback.
///
/// Riverpod 3.x 에서는 family 인자를 생성자로 주입받는다.
final todoViewModelProvider = AsyncNotifierProvider.family<
    TodoViewModel, List<Todo>, DateTime>(TodoViewModel.new);

class TodoViewModel extends AsyncNotifier<List<Todo>> {
  TodoViewModel(this.date);

  /// 이 ViewModel 인스턴스가 다루는 날짜 (family 키).
  final DateTime date;

  Timer? _debounce;
  String? _pendingTodoId;
  String? _pendingText;

  @override
  Future<List<Todo>> build() async {
    final repo = ref.watch(todoRepositoryProvider);

    ref.onDispose(() {
      _debounce?.cancel();
    });

    var list = await repo.getTodosByDate(date);
    if (list.isEmpty) {
      list = await repo.createDefaultTodos(date);
    }
    return list;
  }

  /// 더 추가할 수 있는가. View 에서 버튼 활성/비활성 판단에 사용.
  bool get canAddMore => (state.value?.length ?? 0) < kMaxTodoCount;

  /// 이 ViewModel 이 다루는 날짜의 (year, month) 키. 캘린더 invalidate 용.
  CalendarMonth get _monthKey => (year: date.year, month: date.month);

  /// Todo 변경 직후 해당 월의 캘린더 달성률 캐시를 무효화.
  /// 사용자가 캘린더 탭으로 이동했을 때 즉시 최신 달성률을 보도록 한다.
  void _invalidateCalendar() {
    ref.invalidate(calendarViewModelProvider(_monthKey));
  }

  /// 목록 정렬: 미달성(false) 먼저 → 달성(true) 나중.
  /// 같은 그룹 내에서는 `orderIndex` 오름차순.
  static List<Todo> _sorted(List<Todo> list) {
    final copy = [...list];
    copy.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      return a.orderIndex.compareTo(b.orderIndex);
    });
    return copy;
  }

  /// 빈 todo 추가. 실패 시 state 변경 없음.
  ///
  /// 배치 위치: 새 todo 는 미달성이므로 정렬 규칙(미달성 → 달성)상
  /// **달성된 목표들 중 첫번째 바로 위**, 즉 미달성 그룹의 맨 끝에 놓인다.
  /// `orderIndex` 를 "전체 max + 1" 로 계산하여 미달성 그룹 내에서도 맨 뒤가 되도록 보장.
  Future<void> addTodo() async {
    final current = state.value;
    if (current == null) return;
    if (current.length >= kMaxTodoCount) return;

    final repo = ref.read(todoRepositoryProvider);
    final nextIndex = current.isEmpty
        ? 0
        : current.map((t) => t.orderIndex).reduce((a, b) => a > b ? a : b) + 1;

    final created = await repo.createTodo(date: date, orderIndex: nextIndex);
    state = AsyncData(_sorted([...current, created]));
    _invalidateCalendar();
  }

  /// 완료 토글. 낙관적 업데이트 후 실패 시 rollback.
  /// 토글 후에는 "미달성 → 달성" 순으로 재정렬한다 (달성된 todo 는 목록 맨 아래로).
  Future<void> toggleComplete(String id) async {
    final current = state.value;
    if (current == null) return;

    final int idx = current.indexWhere((t) => t.id == id);
    if (idx < 0) return;

    final Todo original = current[idx];
    final Todo optimistic =
        original.copyWith(isCompleted: !original.isCompleted);

    state = AsyncData(_sorted([
      ...current.sublist(0, idx),
      optimistic,
      ...current.sublist(idx + 1),
    ]));

    final repo = ref.read(todoRepositoryProvider);
    try {
      await repo.updateTodoCompletion(id, optimistic.isCompleted);
      _invalidateCalendar();
    } catch (e) {
      debugPrint('[TodoViewModel] toggleComplete 실패 → rollback: $e');
      final rolled = state.value;
      if (rolled != null) {
        final int rbIdx = rolled.indexWhere((t) => t.id == id);
        if (rbIdx >= 0) {
          state = AsyncData(_sorted([
            ...rolled.sublist(0, rbIdx),
            original,
            ...rolled.sublist(rbIdx + 1),
          ]));
        }
      }
      rethrow;
    }
  }

  /// 삭제. 낙관적 업데이트 후 실패 시 rollback.
  Future<void> deleteTodo(String id) async {
    final current = state.value;
    if (current == null) return;

    final int idx = current.indexWhere((t) => t.id == id);
    if (idx < 0) return;

    // 진행 중인 debounce 가 삭제 대상 todo 를 가리키면 취소.
    if (_pendingTodoId == id) {
      _debounce?.cancel();
      _debounce = null;
      _pendingTodoId = null;
      _pendingText = null;
    }

    final Todo removed = current[idx];
    state = AsyncData([
      ...current.sublist(0, idx),
      ...current.sublist(idx + 1),
    ]);

    final repo = ref.read(todoRepositoryProvider);
    try {
      await repo.deleteTodo(id);
      _invalidateCalendar();
    } catch (e) {
      debugPrint('[TodoViewModel] deleteTodo 실패 → rollback: $e');
      final rolled = state.value ?? const <Todo>[];
      state = AsyncData(_sorted([...rolled, removed]));
      rethrow;
    }
  }

  /// 입력 중 텍스트 갱신. state 는 즉시 갱신, DB 는 debounce 후 저장.
  ///
  /// state 와 DB 는 항상 **raw text** 로 동일하게 유지한다.
  /// (이전에는 DB 쪽만 `trim()` 되어 세션 중 raw text 와 앱 재시작 후 트림된 값이
  /// 달라지는 불일치가 있었음 → 세션 중 커서 이동을 방해하지 않으면서도
  /// 양쪽을 같은 값으로 유지하기 위해 트림 제거. 빈 문자열 같은 표시용 정리는
  /// 필요 시 뷰 레이어에서 수행)
  void updateText(String id, String text) {
    final current = state.value;
    if (current == null) return;

    final int idx = current.indexWhere((t) => t.id == id);
    if (idx < 0) return;

    final Todo next = current[idx].copyWith(text: text);
    state = AsyncData([
      ...current.sublist(0, idx),
      next,
      ...current.sublist(idx + 1),
    ]);

    _pendingTodoId = id;
    _pendingText = text;
    _debounce?.cancel();
    _debounce = Timer(_kTextSaveDebounce, _flushPendingText);
  }

  /// 디바운스 타이머가 만료되면 pending 텍스트를 DB 에 저장한다.
  /// 실패해도 optimistic state 는 유지 (사용자 입력 손실 방지).
  Future<void> _flushPendingText() async {
    final String? id = _pendingTodoId;
    final String? text = _pendingText;
    _pendingTodoId = null;
    _pendingText = null;
    _debounce = null;

    if (id == null || text == null) return;

    final repo = ref.read(todoRepositoryProvider);
    try {
      await repo.updateTodoText(id, text);
    } catch (e) {
      debugPrint('[TodoViewModel] updateTodoText 실패 (state 유지): $e');
    }
  }
}
