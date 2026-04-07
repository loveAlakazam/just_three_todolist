import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../calendar/view/calendar_screen.dart';
import '../../todo/view/todo_screen.dart';

/// 프로필 편집 화면.
///
/// 레이아웃:
/// Scaffold → SafeArea → Column
///   ├─ Stack
///   │  ├─ CircleAvatar (프로필 이미지)
///   │  └─ Positioned(bottom-right) → GestureDetector → showModalBottomSheet
///   ├─ Row (Text "이름" + TextField)
///   ├─ ElevatedButton ("수정하기", primary)
///   └─ BottomNavigationBar (My 활성 유지)
///
/// 이미지 업로드 / 제거는 [수정하기] 버튼 탭 시점까지 임시 상태로만 보존된다.
/// 화면 이탈 시 변경 사항은 저장되지 않는다.
///
/// MVP UI 단계 — 실제 image_picker / Supabase Storage 연동은 후속 작업에서 진행.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const Color _primary = Color(0xFF512DA8);
  static const Color _bg = Color(0xFFF3F4EB);

  /// 임시 사용자 이름 (My 화면에서 prefill 되어야 하는 값).
  static const String _initialName = '사용자';

  late final TextEditingController _nameController = TextEditingController(
    text: _initialName,
  );

  /// 갤러리에서 사용자가 선택한 임시 이미지.
  /// - null = 기본 이미지(아이콘) 상태 (초기 또는 "이미지 제거" 후)
  /// - 그 외 = 갤러리에서 선택된 로컬 파일 (수정하기 전까지 임시 보존)
  XFile? _pickedImage;

  /// `image_picker` 인스턴스. 시스템 사진첩 권한 요청은 첫 호출 시
  /// iOS/Android OS가 1번 표시한 뒤 사용자 선택을 캐시한다.
  final ImagePicker _imagePicker = ImagePicker();

  /// 현재 선택된 BottomNavigation 인덱스 (0: Calendar, 1: To Do, 2: My)
  /// 프로필 편집 화면도 My 탭의 하위 화면이므로 활성 인덱스는 2를 유지한다.
  static const int _tabIndex = 2;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// BottomNavigationBar 탭 핸들러.
  ///
  /// 스펙(`.claude/agents/ui-implementor.md` `공유 위젯: BottomNavigationBar` 절):
  /// - 동일 탭 재선택은 no-op (My 탭).
  /// - 다른 탭은 백 스택을 쌓지 않도록 `pushReplacement`로 화면 전환.
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

  /// 카메라 버튼 탭 → 이미지 업로드 / 이미지 제거 BottomSheet 표시.
  Future<void> _showImageOptionSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library, color: _primary),
                title: const Text(
                  '이미지 업로드',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _primary,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _onPickImage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: _primary),
                title: const Text(
                  '이미지 제거',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _primary,
                  ),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _onRemoveImage();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 이미지 업로드 처리.
  ///
  /// `image_picker.pickImage(source: gallery)`를 호출한다.
  /// - iOS: 첫 호출 시 OS가 사진첩 접근 권한 다이얼로그를 1번만 표시한다.
  ///   (`Info.plist`의 `NSPhotoLibraryUsageDescription` 필요)
  /// - Android 13+: 시스템 Photo Picker를 사용하므로 별도 권한 불필요.
  /// - 권한이 거부되거나 picker가 실패하면 SnackBar로 안내한다.
  /// - 사용자가 picker를 취소(`null` 반환)하면 상태를 변경하지 않는다.
  ///
  /// 선택된 파일은 `_pickedImage`에 임시 저장되며, [수정하기] 버튼을 누르기
  /// 전까지 Supabase 등 원격 저장소에 반영되지 않는다.
  Future<void> _onPickImage() async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _pickedImage = picked;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '사진첩에 접근할 수 없습니다. ${e.message ?? '설정에서 권한을 확인해주세요.'}',
          ),
        ),
      );
    }
  }

  /// 이미지 제거 처리. 기본 이미지(아이콘)로 임시 상태 변경.
  void _onRemoveImage() {
    setState(() {
      _pickedImage = null;
    });
  }

  /// 수정하기 버튼 탭 핸들러.
  ///
  /// TODO(profile): ProfileViewModel.updateProfile()에 이름 / 이미지 변경
  /// 사항을 전달하고, Supabase Storage 업로드 / profiles 테이블 업데이트 후
  /// My 화면으로 pop 한다.
  void _onSubmit() {
    Navigator.of(context).pop();
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
              Center(child: _buildAvatarWithCameraButton()),
              const SizedBox(height: 32),
              _buildNameRow(),
              const SizedBox(height: 24),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ────────────────────── 프로필 이미지 + 카메라 버튼 ──────────────────────
  Widget _buildAvatarWithCameraButton() {
    final XFile? picked = _pickedImage;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        CircleAvatar(
          radius: 56,
          backgroundColor: const Color(0xFFD9D9D9),
          backgroundImage: picked != null ? FileImage(File(picked.path)) : null,
          child: picked == null
              ? const Icon(Icons.person, size: 64, color: Colors.white)
              : null,
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: GestureDetector(
            onTap: _showImageOptionSheet,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────── 이름 입력 Row ──────────────────────
  Widget _buildNameRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        const SizedBox(
          width: 64,
          child: Text(
            '이름',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _nameController,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF333333),
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFBDBDBD)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFBDBDBD)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ────────────────────── 수정하기 버튼 ──────────────────────
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _onSubmit,
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
        child: const Text('수정하기'),
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
