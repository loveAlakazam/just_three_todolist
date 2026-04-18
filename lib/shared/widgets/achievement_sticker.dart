import 'package:flutter/material.dart';

/// 달성률을 색상이 있는 원형 도트로 시각화하는 스티커.
///
/// 색상 규칙(`.claude/rules/project-overview.md`):
/// | 달성률 | 색상 |
/// |--------|------|
/// | 0%                  | 표기 안 함 (스티커 없음) |
/// | 0% 초과 ~ 30% 미만  | `#e32910` (빨강)         |
/// | 30% 이상 ~ 60% 미만 | `#FFC943` (노랑)         |
/// | 60% 이상 ~ 100% 미만| `#13d62d` (초록)         |
/// | 100%                | `#46C8FF` (파랑)         |
///
/// 달성률이 0인 경우 [SizedBox.shrink]를 반환한다.
class AchievementSticker extends StatelessWidget {
  const AchievementSticker({super.key, required this.rate, this.size = 18});

  /// 달성률 (0.0 ~ 1.0).
  final double rate;

  /// 도트 지름.
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color? color = resolveColor(rate);
    if (color == null) {
      return const SizedBox.shrink();
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  /// 달성률에 대응하는 스티커 색상. 0%인 경우 `null`을 반환한다.
  static Color? resolveColor(double rate) {
    if (rate <= 0) return null;
    if (rate < 0.30) return const Color(0xFFE32910);
    if (rate < 0.60) return const Color(0xFFFFC943);
    if (rate < 1.00) return const Color(0xFF13D62D);
    return const Color(0xFF46C8FF);
  }
}
