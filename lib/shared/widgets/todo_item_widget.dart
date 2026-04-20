import 'package:flutter/material.dart';

/// Todo 1개 행.
///
/// - 왼쪽: 목표 입력 [TextField] (한글 기준 최대 20자)
/// - 가운데: 달성 체크 버튼 (양방향 토글 — 체크 후 해제 가능)
/// - 오른쪽: 삭제 버튼 (오늘 날짜 + 미달성 상태에서만 노출)
///
/// [isEditable]
/// - `true`  → 오늘 날짜: TextField 활성 + 달성 버튼 토글 가능 + 삭제 가능 (미달성에 한해)
/// - `false` → 과거 날짜: TextField `enabled: false` + 달성 버튼/삭제 모두 비활성
class TodoItemWidget extends StatefulWidget {
  const TodoItemWidget({
    super.key,
    required this.text,
    required this.isCompleted,
    required this.isEditable,
    this.onChanged,
    this.onToggle,
    this.onDelete,
  });

  /// 목표 텍스트 (초기값 / 외부 동기화 값).
  final String text;

  /// 달성 여부.
  final bool isCompleted;

  /// 수정 가능 여부 (오늘 날짜 = true, 과거 날짜 = false).
  final bool isEditable;

  /// 텍스트 변경 콜백.
  final ValueChanged<String>? onChanged;

  /// 달성 버튼 토글 콜백 (양방향).
  final VoidCallback? onToggle;

  /// 목표 삭제 콜백. 오늘 날짜이고 아직 달성되지 않은 경우에만 호출 가능.
  final VoidCallback? onDelete;

  @override
  State<TodoItemWidget> createState() => _TodoItemWidgetState();
}

class _TodoItemWidgetState extends State<TodoItemWidget> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(covariant TodoItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 외부에서 text가 바뀐 경우(예: 다른 날짜로 전환)에만 컨트롤러 재설정.
    if (widget.text != oldWidget.text && widget.text != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 오늘 날짜이면 체크/해제 양방향 토글 가능, 과거 날짜이면 비활성.
    final bool canToggle = widget.isEditable;
    // 미달성 상태의 오늘 목표만 삭제 가능. 달성된 목표 / 과거 날짜는 삭제 불가.
    final bool canDelete = widget.isEditable && !widget.isCompleted;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 목표 입력
          Expanded(
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFBDBDBD)),
              ),
              alignment: Alignment.center,
              child: TextField(
                enabled: widget.isEditable,
                controller: _controller,
                maxLength: 20,
                textAlign: TextAlign.center,
                onChanged: widget.onChanged,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF512DA8),
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  counterText: '',
                  hintText: '목표를 입력해주세요',
                  hintStyle: TextStyle(
                    color: Color(0xFF9E9E9E),
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 달성 체크 버튼
          _CheckButton(
            isCompleted: widget.isCompleted,
            enabled: canToggle,
            onTap: widget.onToggle,
          ),
          const SizedBox(width: 8),
          // 삭제 버튼 (canDelete가 false인 경우 자리만 유지하고 숨김)
          SizedBox(
            width: 32,
            height: 56,
            child: Visibility(
              visible: canDelete,
              maintainSize: true,
              maintainState: true,
              maintainAnimation: true,
              child: _DeleteButton(onTap: widget.onDelete),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: const SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            Icons.close,
            size: 22,
            color: Color(0xFF9E9E9E),
            semanticLabel: '목표 삭제',
          ),
        ),
      ),
    );
  }
}

class _CheckButton extends StatelessWidget {
  const _CheckButton({
    required this.isCompleted,
    required this.enabled,
    required this.onTap,
  });

  final bool isCompleted;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const Color borderColor = Color(0xFFBDBDBD);
    final Color background =
        isCompleted ? const Color(0xFFE8F5E9) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          alignment: Alignment.center,
          child: isCompleted
              ? const Icon(
                  Icons.check,
                  color: Color(0xFF13D62D),
                  size: 28,
                )
              : null,
        ),
      ),
    );
  }
}
