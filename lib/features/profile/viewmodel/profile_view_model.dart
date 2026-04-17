import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  /// 성공 시 state 를 갱신하여 MyScreen / EditProfileScreen 이 자동 반영.
  Future<void> updateProfile({
    String? name,
    String? Function()? avatarUrl,
  }) async {
    final authState = ref.read(authViewModelProvider);
    final User? user = authState.value;
    if (user == null) return;

    final repo = ref.read(profileRepositoryProvider);
    final updated = await repo.updateProfile(
      userId: user.id,
      name: name,
      avatarUrl: avatarUrl,
    );

    state = AsyncData(updated);
  }

  /// 회원탈퇴 처리.
  ///
  /// 성공 시 auth state 가 null 이 되어 router redirect 가 /login 으로 이동한다.
  /// 실패 시 예외를 throw — View 에서 catch 하여 SnackBar 안내.
  Future<void> deleteAccount() async {
    final repo = ref.read(profileRepositoryProvider);
    await repo.deleteAccount();
  }
}
