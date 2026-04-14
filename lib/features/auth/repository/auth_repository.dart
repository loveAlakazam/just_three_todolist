import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/env.dart';
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
/// 네이티브 Google Sign-In SDK → idToken → Supabase `signInWithIdToken`
/// 흐름을 추상화하여 ViewModel에 제공한다.
abstract class AuthRepository {
  /// 현재 세션이 있는지 여부 (앱 시작 시 사용).
  Session? get currentSession;

  /// 인증 상태 변화 stream. router redirect에서 구독.
  Stream<AuthState> get authStateChanges;

  /// 네이티브 Google Sign-In → Supabase `signInWithIdToken`.
  /// 성공 시 세션은 supabase_flutter가 자동 저장.
  /// 사용자 취소 / idToken 누락 / Supabase 검증 실패 시 [AuthFailure] throw.
  Future<void> signInWithGoogle();

  /// Supabase + Google 네이티브 세션 모두 로그아웃.
  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository()
      : _googleSignIn = GoogleSignIn(
          clientId: Env.googleOAuthIosClientId,
          serverClientId: Env.googleOAuthWebClientId,
        );

  final SupabaseClient _client = SupabaseService.client;
  final GoogleSignIn _googleSignIn;

  @override
  Session? get currentSession => _client.auth.currentSession;

  @override
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  @override
  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // 사용자가 네이티브 시트에서 취소.
        throw const AuthFailure('Google 로그인이 취소되었습니다.');
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      if (idToken == null) {
        // serverClientId 미설정 등 설정 오류.
        throw const AuthFailure('로그인 토큰을 가져오지 못했습니다.');
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
    } on AuthFailure {
      rethrow;
    } on AuthException catch (e) {
      throw AuthFailure('로그인에 실패했습니다.', e);
    } catch (e) {
      throw AuthFailure('로그인에 실패했습니다.', e);
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
    // 네이티브 Google 세션(캐시된 계정 선택 상태)도 함께 정리.
    // 누락 시 다음 로그인에서 계정 선택 없이 기존 계정으로 자동 재로그인됨.
    await _googleSignIn.signOut();
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository();
});
