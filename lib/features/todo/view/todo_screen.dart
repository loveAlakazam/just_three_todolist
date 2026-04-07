import 'package:flutter/material.dart';

import '../../../shared/widgets/segmented_progress_bar.dart';
import '../../../shared/widgets/todo_item_widget.dart';
import '../../calendar/view/calendar_screen.dart';
import '../../profile/view/my_screen.dart';

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
/// MVP UI 단계 — 상태는 로컬에서만 관리한다.
/// ViewModel / Repository 연결은 후속 작업에서 진행.
class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  static const int _maxTodoCount = 10;
  static const int _initialTodoCount = 3;

  /// 화면이 표현하는 날짜. 기본값은 오늘.
  final DateTime _date = DateTime.now();

  /// 로컬 todo 상태. ViewModel 연결 전까지 임시로 사용.
  late final List<_TodoDraft> _todos = List<_TodoDraft>.generate(
    _initialTodoCount,
    (_) => _TodoDraft(),
  );

  /// 현재 선택된 BottomNavigation 인덱스 (0: Calendar, 1: To Do, 2: My)
  static const int _tabIndex = 1;

  /// BottomNavigationBar 탭 핸들러.
  ///
  /// 스펙(`.claude/agents/ui-implementor.md` `공유 위젯: BottomNavigationBar` 절):
  /// - 동일 탭 재선택은 no-op.
  /// - 다른 탭은 백 스택을 쌓지 않도록 `pushReplacement`로 화면 전환.
  /// - go_router 도입 후 `context.go(...)`로 교체 예정.
  void _onTabTapped(int index) {
    if (index == _tabIndex) return;
    switch (index) {
      case 0:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const CalendarScreen()),
        );
      case 2:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const MyScreen()),
        );
    }
  }

  bool get _isToday {
    final DateTime now = DateTime.now();
    return now.year == _date.year &&
        now.month == _date.month &&
        now.day == _date.day;
  }

  int get _completedCount => _todos.where((t) => t.isCompleted).length;

  bool get _canAddMore => _todos.length < _maxTodoCount;

  void _addTodo() {
    if (!_canAddMore) return;
    setState(() => _todos.add(_TodoDraft()));
  }

  void _toggleComplete(int index) {
    // 오늘 날짜 목표는 체크/해제 양방향 토글 가능.
    // 과거 날짜는 [_isToday]가 false이므로 위젯 단에서 onTap이 차단된다.
    setState(() {
      final _TodoDraft todo = _todos[index];
      todo.isCompleted = !todo.isCompleted;
    });
  }

  void _deleteTodo(int index) {
    // 미달성 상태의 오늘 목표만 삭제 허용. 위젯 단에서 onTap이 이미 막혀 있지만
    // 안전하게 한 번 더 검사한다.
    if (!_isToday) return;
    if (_todos[index].isCompleted) return;
    setState(() => _todos.removeAt(index));
  }

  void _updateText(int index, String value) {
    _todos[index].text = value;
  }

  String _formatDate(DateTime date) {
    final String yyyy = date.year.toString().padLeft(4, '0');
    final String mm = date.month.toString().padLeft(2, '0');
    final String dd = date.day.toString().padLeft(2, '0');
    return '$yyyy.$mm.$dd';
  }

  @override
  Widget build(BuildContext context) {
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

              // 달성 게이지바
              SegmentedProgressBar(
                totalCount: _todos.length,
                completedCount: _completedCount,
              ),
              const SizedBox(height: 24),

              // Todo 목록
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: List<Widget>.generate(_todos.length, (int i) {
                      final _TodoDraft todo = _todos[i];
                      return TodoItemWidget(
                        key: ValueKey<int>(todo.id),
                        text: todo.text,
                        isCompleted: todo.isCompleted,
                        isEditable: _isToday,
                        onChanged: (String v) => _updateText(i, v),
                        onToggle: () => _toggleComplete(i),
                        onDelete: () => _deleteTodo(i),
                      );
                    }),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 목표 추가하기
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _canAddMore ? _addTodo : null,
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

/// 화면 내부 임시 상태. ViewModel 도입 시 제거 예정.
class _TodoDraft {
  _TodoDraft() : id = _nextId++;

  static int _nextId = 0;

  final int id;
  String text = '';
  bool isCompleted = false;
}
