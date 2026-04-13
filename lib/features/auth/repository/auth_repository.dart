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
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository();
});
