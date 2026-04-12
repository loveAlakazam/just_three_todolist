import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase_client.dart';

/// 인증 실패 예외.
class AuthFailure implements Exception {
  final String message;
  final Object? cause;
  const AuthFailure(this.message, [this.cause]);

  @override
  String toString() => 'AuthFailure: $message';
}

/// 인증 관련 데이터 접근 레이어.
///
/// Supabase Auth API를 추상화하여 ViewModel에 제공한다.
abstract class AuthRepository {
  /// 현재 세션이 있는지 여부 (앱 시작 시 사용).
  Session? get currentSession;

  /// 인증 상태 변화 stream. router redirect에서 구독.
  Stream<AuthState> get authStateChanges;

  /// Google OAuth 로그인. 성공 시 세션은 SDK가 자동 저장.
  /// 실패 시 [AuthFailure] throw.
  Future<void> signInWithGoogle();

  /// 로그아웃.
  Future<void> signOut();

  /// 첫 로그인 시 profiles row 생성 (있으면 no-op).
  /// DB trigger(`handle_new_user`)를 사용한다면 이 메서드 호출을 생략할 수 있다.
  Future<void> ensureProfileExists();
}

class SupabaseAuthRepository implements AuthRepository {
  final SupabaseClient _client = SupabaseService.client;

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Future<void> signInWithGoogle() async {
    try {
      final bool success = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.justthree://login-callback',
      );
      if (!success) {
        throw const AuthFailure('Google 로그인이 취소되었습니다.');
      }
    } on AuthException catch (e) {
      throw AuthFailure('로그인에 실패했습니다.', e);
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  @override
  Future<void> ensureProfileExists() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    try {
      final existing = await _client
          .from('profiles')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (existing != null) return;

      final name = user.userMetadata?['full_name'] as String? ??
          user.email?.split('@').first ??
          '사용자';

      await _client.from('profiles').insert({
        'id': user.id,
        'name': name,
      });
    } catch (e) {
      // profiles 생성 실패는 치명적이지 않음.
      // DB trigger가 이미 생성했을 수 있으므로 silent fail.
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository();
});
