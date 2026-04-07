import 'package:flutter/material.dart';

/// 달성 게이지바 (세그먼트형).
///
/// - 세그먼트 수 = [totalCount]
/// - 구분선 수 = [totalCount] - 1
/// - 채워진 세그먼트 수 = [completedCount] (왼쪽부터 순서대로 채움)
/// - 채워진 색상은 달성률(`completedCount / totalCount`) 구간에 따라 결정.
///
/// 색상 규칙(`.claude/rules/project-overview.md`):
/// | 달성률 | 색상 |
/// |--------|------|
/// | 0%                  | 색상 없음 (빈 바)      |
/// | 0% 초과 ~ 30% 미만  | `#e32910`              |
/// | 30% 이상 ~ 60% 미만 | `#FFC943`              |
/// | 60% 이상 ~ 100% 미만| `#13d62d`              |
/// | 100%                | `#46C8FF`              |
class SegmentedProgressBar extends StatelessWidget {
  const SegmentedProgressBar({
    super.key,
    required this.totalCount,
    required this.completedCount,
    this.height = 14,
    this.gap = 6,
  });

  /// 전체 목표 수 (세그먼트 개수).
  final int totalCount;

  /// 달성 완료된 목표 수.
  final int completedCount;

  /// 게이지바 높이.
  final double height;

  /// 세그먼트 사이 구분선(여백) 너비.
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (totalCount <= 0) {
      return SizedBox(height: height);
    }

    final int filled = completedCount.clamp(0, totalCount);
    final double rate = filled / totalCount;
    final Color filledColor = _resolveColor(rate);
    final Color emptyColor = const Color(0xFFE5E5E5);

    final List<Widget> segments = <Widget>[];
    for (int i = 0; i < totalCount; i++) {
      if (i > 0) {
        segments.add(SizedBox(width: gap));
      }
      final bool isFilled = i < filled;
      segments.add(
        Expanded(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: isFilled ? filledColor : emptyColor,
              borderRadius: BorderRadius.circular(height / 2),
            ),
          ),
        ),
      );
    }

    return Row(children: segments);
  }

  /// 달성률에 따른 채움 색상.
  Color _resolveColor(double rate) {
    if (rate <= 0) return Colors.transparent;
    if (rate < 0.30) return const Color(0xFFE32910);
    if (rate < 0.60) return const Color(0xFFFFC943);
    if (rate < 1.00) return const Color(0xFF13D62D);
    return const Color(0xFF46C8FF);
  }
}
