import 'package:flutter/material.dart';

import '../../calendar/view/calendar_screen.dart';
import '../../todo/view/todo_screen.dart';
import 'edit_profile_screen.dart';

/// My 탭(마이페이지) 초기화면.
///
/// 레이아웃:
/// Scaffold → SafeArea → Column
///   ├─ Row (CircleAvatar + "{이름} 님")
///   ├─ ElevatedButton ("프로필 편집", primary)
///   ├─ ElevatedButton ("회원탈퇴", gray)
///   └─ BottomNavigationBar (My 활성)
///
/// MVP UI 단계 — 사용자 데이터는 임시 값으로 표시한다.
/// ViewModel / Repository / 회원탈퇴 처리 연결은 후속 작업에서 진행.
class MyScreen extends StatefulWidget {
  const MyScreen({super.key});

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  static const Color _primary = Color(0xFF512DA8);
  static const Color _bg = Color(0xFFF3F4EB);
  static const Color _grayButton = Color(0xFFBDBDBD);

  /// 임시 사용자 이름. ViewModel 연결 전까지 사용.
  static const String _userName = '사용자';

  /// 임시 프로필 이미지 URL.
  /// MVP UI 단계에서는 항상 null이며 기본 아이콘이 표시된다.
  /// ViewModel 연결 시 Supabase Storage URL로 대체.
  // TODO(profile): ViewModel에서 받아오도록 교체.
  String? get _profileImageUrl => null;

  /// 현재 선택된 BottomNavigation 인덱스 (0: Calendar, 1: To Do, 2: My)
  static const int _tabIndex = 2;

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
      case 1:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const TodoScreen()),
        );
    }
  }

  /// 프로필 편집 화면으로 이동.
  ///
  /// go_router 도입 후 `context.push('/profile/edit')`로 교체 예정.
  void _goToEditProfile() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditProfileScreen()),
    );
  }

  /// 회원탈퇴 확인 팝업 표시.
  ///
  /// 확인 시 `ProfileViewModel.deleteAccount()` 호출 → 로그인 화면으로 이동.
  /// MVP UI 단계: 확인 콜백은 자리만 둔다.
  Future<void> _showWithdrawDialog() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
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
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(foregroundColor: _primary),
              child: const Text(
                '취소',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                // TODO(profile): ProfileViewModel.deleteAccount() 호출 후
                // 로그인 화면으로 이동.
              },
              style: TextButton.styleFrom(foregroundColor: _primary),
              child: const Text(
                '확인',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildProfileHeader(),
              const SizedBox(height: 32),
              _buildEditProfileButton(),
              const SizedBox(height: 12),
              _buildWithdrawButton(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ────────────────────── 프로필 헤더 ──────────────────────
  Widget _buildProfileHeader() {
    final String? url = _profileImageUrl;
    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 44,
          backgroundColor: const Color(0xFFD9D9D9),
          backgroundImage: url != null ? NetworkImage(url) : null,
          child: url == null
              ? const Icon(Icons.person, size: 48, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Text(
            '$_userName 님',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _primary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
