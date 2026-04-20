import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';
import '../../../shared/models/profile.dart';

/// Storage 버킷 이름.
const String _storageBucket = 'just-three-storage';

/// Signed URL 유효 시간 (초). 1시간.
const int _signedUrlExpiry = 3600;

/// 프로필 데이터 접근 레이어.
///
/// Supabase `profiles` 테이블 CRUD + Storage 파일 업로드/삭제를 추상화한다.
abstract class ProfileRepository {
  /// 현재 로그인 유저의 프로필을 가져온다.
  /// 프로필이 없으면 null 반환.
  Future<Profile?> fetchProfile(String userId);

  /// 프로필 이름/아바타를 업데이트한다.
  ///
  /// [imageFile]이 non-null이면 Storage에 업로드 후 경로를 `avatar_url`에 저장.
  /// [removeImage]가 true이면 기존 Storage 파일 삭제 후 `avatar_url`을 null로 설정.
  /// 둘 다 해당 없으면 이미지 변경 없음 (keep).
  Future<Profile> updateProfile({
    required String userId,
    String? name,
    XFile? imageFile,
    bool removeImage = false,
  });

  /// 회원탈퇴 처리.
  Future<void> deleteAccount();
}

class SupabaseProfileRepository implements ProfileRepository {
  final SupabaseClient _client = SupabaseService.client;

  /// Storage 파일 경로. 항상 `<userId>/avatar.jpg`.
  String _avatarPath(String userId) => '$userId/avatar.jpg';

  @override
  Future<Profile?> fetchProfile(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (response == null) return null;

      final profile = Profile.fromMap(response);
      return _resolveAvatarUrl(profile);
    } catch (e) {
      debugPrint('[ProfileRepository] fetchProfile 실패: $e');
      rethrow;
    }
  }

  @override
  Future<Profile> updateProfile({
    required String userId,
    String? name,
    XFile? imageFile,
    bool removeImage = false,
  }) async {
    final String path = _avatarPath(userId);
    String? newAvatarPath;

    // 1) 이미지 교체: 같은 경로에 upsert (기존 파일 자동 덮어쓰기)
    if (imageFile != null) {
      await _client.storage
          .from(_storageBucket)
          .upload(path, File(imageFile.path),
              fileOptions: const FileOptions(upsert: true));
      newAvatarPath = path;
    }
    // 2) 이미지 제거: Storage 파일 삭제 (best-effort)
    else if (removeImage) {
      try {
        await _client.storage.from(_storageBucket).remove([path]);
      } catch (e) {
        debugPrint('[ProfileRepository] Storage 삭제 실패 (무시): $e');
      }
    }

    // 3) profiles 테이블 업데이트
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (name != null) updates['name'] = name;
    if (imageFile != null) updates['avatar_url'] = newAvatarPath;
    if (removeImage) updates['avatar_url'] = null;

    try {
      final response = await _client
          .from('profiles')
          .update(updates)
          .eq('id', userId)
          .select()
          .single();

      final profile = Profile.fromMap(response);
      return _resolveAvatarUrl(profile);
    } catch (e) {
      debugPrint('[ProfileRepository] updateProfile 실패: $e');
      rethrow;
    }
  }

  /// avatar_url 에 Storage 경로가 있으면 signed URL 로 변환한 Profile 을 반환.
  Future<Profile> _resolveAvatarUrl(Profile profile) async {
    if (profile.avatarUrl == null || profile.avatarUrl!.isEmpty) {
      return profile;
    }

    try {
      final signedUrl = await _client.storage
          .from(_storageBucket)
          .createSignedUrl(profile.avatarUrl!, _signedUrlExpiry);
      return profile.copyWith(avatarUrl: () => signedUrl);
    } catch (e) {
      debugPrint('[ProfileRepository] signedUrl 생성 실패 (무시): $e');
      return profile.copyWith(avatarUrl: () => null);
    }
  }

  /// 회원탈퇴.
  ///
  /// 스펙: `.claude/agents/logic-implementor/04_profile.md` §7.
  ///
  /// 1) Storage `<userId>/` 하위 파일 정리 (best-effort — 실패해도 진행)
  /// 2) `profiles` row 삭제 (RLS: 본인 row 만, 이미 없어도 no-op)
  /// 3) Edge Function `delete-account` 호출
  ///    - JWT 검증 → `deleted_accounts` INSERT → `auth.admin.deleteUser`
  ///    - `todos` 는 `auth.users` cascade 로 함께 삭제됨
  ///
  /// signOut 은 여기서 호출하지 않는다 — 호출 측(ViewModel)의 책임.
  /// 3) 단계가 실패하면 사용자 데이터가 부분 삭제된 상태가 되지만, 1·2 는
  /// idempotent 하므로 사용자가 다시 "회원탈퇴" 를 눌렀을 때 안전하게 재시도
  /// 된다.
  @override
  Future<void> deleteAccount() async {
    final User? user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('deleteAccount: 로그인 세션이 없습니다.');
    }
    final String userId = user.id;

    // 1) Storage <userId>/ 하위 파일 best-effort 정리.
    //    list → remove 2-step. 파일이 없거나 조회에 실패해도 조용히 넘긴다.
    try {
      final List<FileObject> files =
          await _client.storage.from(_storageBucket).list(path: userId);
      if (files.isNotEmpty) {
        final List<String> paths =
            files.map((FileObject f) => '$userId/${f.name}').toList();
        await _client.storage.from(_storageBucket).remove(paths);
      }
    } catch (e) {
      debugPrint('[ProfileRepository] storage 정리 실패 (무시): $e');
    }

    // 2) profiles row 삭제. row 가 없어도 delete().eq 는 정상 응답.
    try {
      await _client.from('profiles').delete().eq('id', userId);
    } catch (e) {
      debugPrint('[ProfileRepository] profiles 삭제 실패: $e');
      rethrow;
    }

    // 3) Edge Function 호출. Supabase SDK 가 현재 세션 JWT 를 Authorization
    //    헤더로 자동 주입한다. non-2xx 응답은 예외로 변환해 ViewModel 에서
    //    SnackBar 표시로 이어진다.
    try {
      final FunctionResponse resp =
          await _client.functions.invoke('delete-account');
      final int status = resp.status;
      if (status < 200 || status >= 300) {
        throw StateError(
          'delete-account Edge Function 실패: status=$status, body=${resp.data}',
        );
      }
    } catch (e) {
      debugPrint('[ProfileRepository] delete-account 호출 실패: $e');
      rethrow;
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return SupabaseProfileRepository();
});
