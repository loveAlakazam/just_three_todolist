import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/viewmodel/auth_view_model.dart';
import '../../../shared/models/profile.dart';
import '../repository/profile_repository.dart';

/// 프로필 상태를 관리하는 ViewModel.
///
/// - `AsyncValue<Profile?>`: null 이면 프로필 미존재, Profile 이 있으면 정상.
/// - `authViewModelProvider` 를 watch 하여 로그인 유저가 바뀌면 자동으로 프로필을 다시 fetch.
/// - MyScreen / EditProfileScreen 에서 이 상태를 구독하여 사용자 정보를 표시한다.
final profileViewModelProvider =
    AsyncNotifierProvider<ProfileViewModel, Profile?>(
        () => ProfileViewModel());

class ProfileViewModel extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final authState = ref.watch(authViewModelProvider);
    final User? user = authState.value;

    if (user == null) return null;

    final repo = ref.watch(profileRepositoryProvider);
    return repo.fetchProfile(user.id);
  }

  /// 프로필 이름/아바타를 업데이트한다.
  ///
  /// [imageFile]: 갤러리에서 선택된 새 이미지. non-null 이면 Storage 업로드.
  /// [removeImage]: true 이면 기존 이미지 삭제 + avatar_url null.
  /// 둘 다 해당 없으면 이미지 변경 없음 (keep).
  ///
  /// 성공 시 state 를 갱신하여 MyScreen / EditProfileScreen 이 자동 반영.
  Future<void> updateProfile({
    String? name,
    XFile? imageFile,
    bool removeImage = false,
  }) async {
    final authState = ref.read(authViewModelProvider);
    final User? user = authState.value;
    if (user == null) return;

    final repo = ref.read(profileRepositoryProvider);
    final updated = await repo.updateProfile(
      userId: user.id,
      name: name,
      imageFile: imageFile,
      removeImage: removeImage,
    );

    state = AsyncData(updated);
  }

  /// 회원탈퇴 처리.
  ///
  /// 스펙: `.claude/agents/logic-implementor/04_profile.md` §7.
  ///
  /// 1) Repository 의 `deleteAccount` 호출 (Storage 정리 → profiles 삭제 →
  ///    Edge Function `delete-account` 호출 → auth.users cascade 삭제).
  /// 2) 성공 시 `AuthViewModel.signOut()` 로 로컬 세션도 제거한다.
  ///    `authStateChanges` 가 `SIGNED_OUT` 을 발행 → router redirect 가
  ///    자동으로 `/login` 으로 이동시키므로, View 는 다이얼로그 pop 만 하면 된다.
  /// 3) 실패 시 예외를 그대로 rethrow — View 가 catch 해서 SnackBar 안내.
  ///    이 때 세션은 살아있고 profiles / storage 는 일부 삭제된 상태일 수 있으나,
  ///    Repository 의 1·2 단계는 idempotent 하므로 재시도 시 안전하게 완결된다.
  Future<void> deleteAccount() async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.deleteAccount();
    // 탈퇴 성공: 세션 제거. router redirect 가 /login 으로 이동시킴.
    await ref.read(authViewModelProvider.notifier).signOut();
  }
}
