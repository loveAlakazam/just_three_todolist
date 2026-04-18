import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/models/todo.dart';
import '../../../shared/widgets/segmented_progress_bar.dart';
import '../../../shared/widgets/todo_item_widget.dart';
import '../viewmodel/todo_view_model.dart';

/// Todo 화면 (메인).
///
/// 레이아웃:
/// Scaffold → SafeArea → Column
///   ├─ Text (날짜 YYYY.MM.DD)
///   ├─ SegmentedProgressBar
///   ├─ Expanded → SingleChildScrollView → Column(TodoItemWidget × N)
///   ├─ ElevatedButton ("목표 추가하기")
///   └─ BottomNavigationBar
///
/// - 상태는 `todoViewModelProvider(date)` (AsyncNotifier.family) 로 관리.
/// - CR-1: 인증 가드는 `core/router.dart` redirect 가 책임 (여기서 비로그인 분기 없음).
/// - CR-2: `StatefulShellRoute` IndexedStack 안에서 유지.
/// - CR-3: `build()` 에서 오늘 날짜 기준으로 fetch → 앱 재시작 시 자연스럽게 복구.
class TodoScreen extends ConsumerStatefulWidget {
  const TodoScreen({super.key});

  @override
  ConsumerState<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends ConsumerState<TodoScreen> {
  /// 화면이 표현하는 날짜 (오늘, KST 기준 시/분/초 0).
  final DateTime _date = _todayKey();

  /// 현재 선택된 BottomNavigation 인덱스 (0: Calendar, 1: To Do, 2: My)
  static const int _tabIndex = 1;

  static DateTime _todayKey() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  void _onTabTapped(int index) {
    if (index == _tabIndex) return;
    StatefulNavigationShell.of(context).goBranch(index);
  }

  bool get _isToday {
    final DateTime today = _todayKey();
    return today == _date;
  }

  String _formatDate(DateTime date) {
    final String yyyy = date.year.toString().padLeft(4, '0');
    final String mm = date.month.toString().padLeft(2, '0');
    final String dd = date.day.toString().padLeft(2, '0');
    return '$yyyy.$mm.$dd';
  }

  void _showError(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Todo>> todosAsync =
        ref.watch(todoViewModelProvider(_date));
    final TodoViewModel notifier =
        ref.read(todoViewModelProvider(_date).notifier);

    // 에러 상태로 "처음 전환될 때만" SnackBar 표시.
    // (build 안에서 addPostFrameCallback 을 쓰면 리빌드마다 등록되어 중복 표시됨)
    ref.listen<AsyncValue<List<Todo>>>(
      todoViewModelProvider(_date),
      (prev, next) {
        if (next is AsyncError && prev is! AsyncError) {
          _showError('목표를 불러오지 못했어요.');
        }
      },
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4EB),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 날짜
              Text(
                _formatDate(_date),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF512DA8),
                ),
              ),
              const SizedBox(height: 20),

              // 달성 게이지바 + 리스트 (로딩/에러/데이터 분기)
              Expanded(
                child: todosAsync.when(
                  loading: () => _buildLoading(),
                  error: (err, _) => _buildError(err),
                  data: (todos) => _buildContent(todos, notifier),
                ),
              ),

              const SizedBox(height: 12),

              // 목표 추가하기
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_isToday && notifier.canAddMore)
                      ? () async {
                          try {
                            await notifier.addTodo();
                          } catch (_) {
                            _showError('목표를 추가하지 못했어요. 잠시 후 다시 시도해주세요.');
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF512DA8),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFBDB0DC),
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('목표 추가하기'),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildLoading() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: const [
        LinearProgressIndicator(
          minHeight: 6,
          color: Color(0xFF512DA8),
          backgroundColor: Color(0xFFE0E0E0),
        ),
        Expanded(child: SizedBox.shrink()),
      ],
    );
  }

  Widget _buildError(Object err) {
    // SnackBar 알림은 build() 안의 ref.listen 이 담당.
    // 여기서는 화면 중앙 안내 문구만 렌더링.
    return const Center(
      child: Text(
        '목표를 불러오지 못했어요.',
        style: TextStyle(color: Color(0xFF9E9E9E)),
      ),
    );
  }

  Widget _buildContent(List<Todo> todos, TodoViewModel notifier) {
    final int completedCount = todos.where((t) => t.isCompleted).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedProgressBar(
          totalCount: todos.length,
          completedCount: completedCount,
        ),
        const SizedBox(height: 24),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: todos
                  .map(
                    (todo) => TodoItemWidget(
                      key: ValueKey<String>(todo.id),
                      text: todo.text,
                      isCompleted: todo.isCompleted,
                      isEditable: _isToday,
                      onChanged: (String v) => notifier.updateText(todo.id, v),
                      onToggle: () async {
                        try {
                          await notifier.toggleComplete(todo.id);
                        } catch (_) {
                          _showError('달성 상태를 저장하지 못했어요.');
                        }
                      },
                      onDelete: () async {
                        try {
                          await notifier.deleteTodo(todo.id);
                        } catch (_) {
                          _showError('목표를 삭제하지 못했어요.');
                        }
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _tabIndex,
      onTap: _onTabTapped,
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFF512DA8),
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
