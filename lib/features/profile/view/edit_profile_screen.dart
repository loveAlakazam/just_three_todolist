import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../viewmodel/profile_view_model.dart';

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
/// `profileViewModelProvider` 를 구독하여 현재 프로필 정보를 prefill 한다.
/// 이미지 업로드 / 제거는 [수정하기] 버튼 탭 시점까지 임시 상태로만 보존된다.
/// 화면 이탈 시 변경 사항은 저장되지 않는다.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  static const Color _primary = Color(0xFF512DA8);
  static const Color _bg = Color(0xFFF3F4EB);

  late final TextEditingController _nameController;

  /// 갤러리에서 사용자가 선택한 임시 이미지.
  /// - null = 변경 없음 (기존 이미지 또는 기본 아이콘 유지)
  XFile? _pickedImage;

  /// 이미지 제거가 명시적으로 요청되었는지 여부.
  bool _imageRemoved = false;

  /// 현재 프로필의 원본 아바타 URL (비교용).
  String? _originalAvatarUrl;

  /// `image_picker` 인스턴스.
  final ImagePicker _imagePicker = ImagePicker();

  /// 현재 선택된 BottomNavigation 인덱스 (0: Calendar, 1: To Do, 2: My)
  static const int _tabIndex = 2;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// BottomNavigationBar 탭 핸들러.
  void _onTabTapped(int index) {
    if (index == _tabIndex) return;
    StatefulNavigationShell.of(context).goBranch(index);
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
        _imageRemoved = false;
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
      _imageRemoved = true;
    });
  }

  /// 수정하기 버튼 탭 핸들러.
  ///
  /// ProfileViewModel.updateProfile() 에 이름 / 이미지 변경 사항을 전달하고,
  /// 완료 후 My 화면으로 pop 한다.
  Future<void> _onSubmit() async {
    final String newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    try {
      await ref.read(profileViewModelProvider.notifier).updateProfile(
            name: newName,
            avatarUrl: _imageRemoved ? () => null : null,
          );
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('프로필 수정에 실패했습니다. 다시 시도해주세요.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileViewModelProvider);

    // 프로필 데이터가 로드되면 한 번만 컨트롤러를 초기화.
    final profile = profileAsync.value;
    if (!_initialized && profile != null) {
      _nameController.text = profile.name;
      _originalAvatarUrl = profile.avatarUrl;
      _initialized = true;
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
          child: profileAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => _buildForm(null),
            data: (_) => _buildForm(_originalAvatarUrl),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildForm(String? currentAvatarUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Center(child: _buildAvatarWithCameraButton(currentAvatarUrl)),
        const SizedBox(height: 32),
        _buildNameRow(),
        const SizedBox(height: 24),
        _buildSubmitButton(),
      ],
    );
  }

  // ────────────────────── 프로필 이미지 + 카메라 버튼 ──────────────────────
  Widget _buildAvatarWithCameraButton(String? currentAvatarUrl) {
    final XFile? picked = _pickedImage;

    // 표시할 이미지 결정: 갤러리 선택 > 제거됨 > 기존 URL
    ImageProvider? imageProvider;
    if (picked != null) {
      imageProvider = FileImage(File(picked.path));
    } else if (!_imageRemoved && currentAvatarUrl != null) {
      imageProvider = NetworkImage(currentAvatarUrl);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        CircleAvatar(
          radius: 56,
          backgroundColor: const Color(0xFFD9D9D9),
          backgroundImage: imageProvider,
          child: imageProvider == null
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
