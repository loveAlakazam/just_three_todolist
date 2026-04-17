import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/viewmodel/auth_view_model.dart';
import '../../../shared/models/profile.dart';
import '../viewmodel/profile_view_model.dart';

/// My 탭(마이페이지) 초기화면.
///
/// 레이아웃:
/// Scaffold → SafeArea → Column
///   ├─ Row (CircleAvatar + "{이름} 님")
///   ├─ Align(right) → TextButton ("로그아웃", gray)
///   ├─ ElevatedButton ("프로필 편집", primary)
///   ├─ ElevatedButton ("회원탈퇴", gray)
///   └─ BottomNavigationBar (My 활성)
///
/// `profileViewModelProvider` 를 구독하여 로그인 유저의 프로필 정보를 표시한다.
class MyScreen extends ConsumerStatefulWidget {
  const MyScreen({super.key});

  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen> {
  static const Color _primary = Color(0xFF512DA8);
  static const Color _bg = Color(0xFFF3F4EB);
  static const Color _grayButton = Color(0xFFBDBDBD);

  /// 현재 선택된 BottomNavigation 인덱스 (0: Calendar, 1: To Do, 2: My)
  static const int _tabIndex = 2;

  /// BottomNavigationBar 탭 핸들러.
  ///
  /// `StatefulNavigationShell.goBranch`로 탭을 전환하여
  /// IndexedStack 안에서 화면 상태가 유지된다 (CR-2).
  void _onTabTapped(int index) {
    if (index == _tabIndex) return;
    StatefulNavigationShell.of(context).goBranch(index);
  }

  /// 로그아웃 처리.
  ///
  /// `AuthViewModel.signOut()` 호출 → `authStateChanges`가 `SIGNED_OUT` 발행
  /// → router redirect가 자동으로 `/login`으로 이동.
  Future<void> _signOut() async {
    try {
      await ref.read(authViewModelProvider.notifier).signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('로그아웃에 실패했습니다. 다시 시도해주세요.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// 프로필 편집 화면으로 이동.
  void _goToEditProfile() {
    context.push('/my/edit');
  }

  /// 회원탈퇴 확인 팝업 표시.
  ///
  /// 다이얼로그 lifecycle 계약 (`.claude/agents/ui-implementor/04_mypage.md`):
  /// 1) `barrierDismissible: false` — 진행 중 외부 탭으로 임의 닫기 차단.
  /// 2) 로딩 중 "확인"/"취소" 비활성, "확인"은 [CircularProgressIndicator]로 교체.
  /// 3) 중복 클릭 가드 — 진행 중 재진입 차단.
  /// 4) 성공/실패 모두 다이얼로그를 [Navigator.pop]으로 닫는다. 라우팅은
  ///    go_router redirect에 위임.
  Future<void> _showWithdrawDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        bool isDeleting = false;

        return StatefulBuilder(
          builder: (BuildContext sbContext, StateSetter setStateDialog) {
            Future<void> onConfirm() async {
              if (isDeleting) return; // 중복 클릭 가드.
              setStateDialog(() => isDeleting = true);

              try {
                await ref
                    .read(profileViewModelProvider.notifier)
                    .deleteAccount();
                // 성공: 다이얼로그만 닫는다. /login 이동은 router redirect.
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } catch (_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('탈퇴에 실패했습니다. 잠시 후 다시 시도해주세요.'),
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              }
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                '탈퇴하시겠습니까?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
              ),
              content: const Text(
                '탈퇴 후 14일 동안은 같은 계정으로 재가입할 수 없습니다.',
                style: TextStyle(fontSize: 14, color: Color(0xFF555555)),
              ),
              actionsAlignment: MainAxisAlignment.spaceEvenly,
              actions: <Widget>[
                TextButton(
                  onPressed:
                      isDeleting ? null : () => Navigator.of(dialogContext).pop(),
                  style: TextButton.styleFrom(foregroundColor: _primary),
                  child: const Text(
                    '취소',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: isDeleting ? null : onConfirm,
                  style: TextButton.styleFrom(foregroundColor: _primary),
                  child: isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(_primary),
                          ),
                        )
                      : const Text(
                          '확인',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileViewModelProvider);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
          child: profileAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _buildContent(null),
            data: (profile) => _buildContent(profile),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildContent(Profile? profile) {
    final String userName = profile?.name ?? '사용자';
    final String? avatarUrl = profile?.avatarUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildProfileHeader(userName, avatarUrl),
        const SizedBox(height: 32),
        _buildEditProfileButton(),
        const SizedBox(height: 12),
        _buildWithdrawButton(),
      ],
    );
  }

  // ────────────────────── 프로필 헤더 ──────────────────────
  Widget _buildProfileHeader(String userName, String? avatarUrl) {
    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 44,
          backgroundColor: const Color(0xFFD9D9D9),
          backgroundImage:
              avatarUrl != null ? NetworkImage(avatarUrl) : null,
          child: avatarUrl == null
              ? const Icon(Icons.person, size: 48, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$userName 님',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: _primary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              _buildLogoutButton(),
            ],
          ),
        ),
      ],
    );
  }

  // ────────────────────── 로그아웃 버튼 ──────────────────────
  Widget _buildLogoutButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: _signOut,
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF9E9E9E),
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          '로그아웃',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  // ────────────────────── 프로필 편집 버튼 ──────────────────────
  Widget _buildEditProfileButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _goToEditProfile,
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: const Text('프로필 편집'),
      ),
    );
  }

  // ────────────────────── 회원탈퇴 버튼 ──────────────────────
  Widget _buildWithdrawButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _showWithdrawDialog,
        style: ElevatedButton.styleFrom(
          backgroundColor: _grayButton,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: const Text('회원탈퇴'),
      ),
    );
  }

  // ────────────────────── BottomNavigationBar ──────────────────────
  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _tabIndex,
      onTap: _onTabTapped,
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: _primary,
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
