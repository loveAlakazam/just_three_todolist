import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../../shared/models/profile.dart';

/// 프로필 데이터 접근 레이어.
///
/// Supabase `profiles` 테이블에 대한 CRUD 를 추상화한다.
/// ViewModel 은 이 인터페이스만 의존하고, 구체 구현(Supabase)은 DI로 교체 가능하다.
abstract class ProfileRepository {
  /// 현재 로그인 유저의 프로필을 가져온다.
  /// 프로필이 없으면 null 반환.
  Future<Profile?> fetchProfile(String userId);

  /// 프로필 이름/아바타를 업데이트한다.
  Future<Profile> updateProfile({
    required String userId,
    String? name,
    String? Function()? avatarUrl,
  });

  /// 회원탈퇴 처리.
  /// 프로필 삭제 + Supabase Auth 계정 삭제를 수행한다.
  Future<void> deleteAccount();
}

class SupabaseProfileRepository implements ProfileRepository {
  final SupabaseClient _client = SupabaseService.client;

  @override
  Future<Profile?> fetchProfile(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) return null;
      return Profile.fromMap(response);
    } catch (e) {
      debugPrint('[ProfileRepository] fetchProfile 실패: $e');
      rethrow;
    }
  }

  @override
  Future<Profile> updateProfile({
    required String userId,
    String? name,
    String? Function()? avatarUrl,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (name != null) updates['name'] = name;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl();

    try {
      final response = await _client
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select()
          .single();

      return Profile.fromMap(response);
    } catch (e) {
      debugPrint('[ProfileRepository] updateProfile 실패: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteAccount() async {
    // TODO(profile-logic): Edge Function 또는 서비스 역할 키를 통한 계정 삭제 구현.
    // Supabase client SDK 에서는 admin 권한 없이 auth.admin.deleteUser 를 호출할 수 없으므로,
    // Edge Function 경유가 필요하다. 현재는 placeholder.
    throw UnimplementedError('deleteAccount 는 Edge Function 연동 후 구현 예정');
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return SupabaseProfileRepository();
});
