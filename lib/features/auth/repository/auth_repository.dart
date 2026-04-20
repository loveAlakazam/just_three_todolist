import 'dart:convert';

import 'package:flutter/foundation.dart';
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

/// 사용자가 네이티브 로그인 시트에서 취소한 경우.
///
/// View 는 이 타입을 보고 SnackBar 를 **억제**한다 (에러가 아닌 사용자 의도).
class AuthCancelled extends AuthFailure {
  const AuthCancelled() : super('Google 로그인이 취소되었습니다.');
}

/// 탈퇴 후 14일 쿨다운이 아직 끝나지 않은 계정으로 재로그인을 시도한 경우.
///
/// 스펙: `.claude/agents/logic-implementor/04_profile.md` §7 "14일 쿨다운 강제 흐름".
/// `signInWithIdToken` 자체는 성공했더라도 `check_signin_cooldown` RPC 가
/// blocked=true 를 반환하면 Repository 가 즉시 `auth.signOut()` 을 호출해 세션을
/// 제거하고 이 예외를 throw 한다. View 는 [remainingDays] 를 사용해 남은 일수를
/// SnackBar 로 안내한다.
class CooldownException extends AuthFailure {
  final int remainingDays;
  const CooldownException(this.remainingDays)
      : super('탈퇴 후 14일이 지나지 않은 계정입니다.');
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
        throw const AuthCancelled();
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final String? idToken = googleAuth.idToken;
      if (idToken == null) {
        // serverClientId 미설정 등 설정 오류.
        throw const AuthFailure('로그인 토큰을 가져오지 못했습니다.');
      }

      // JWT payload 디코딩 — nonce 존재 여부 확인용 디버그 로그.
      _debugLogIdToken(idToken);

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );

      // 14일 재가입 쿨다운 체크 (04_profile.md §7).
      // 세션이 이미 생긴 직후에 호출해야 auth.jwt() 가 현재 사용자 claim 을 반환한다.
      // 쿨다운 활성이면 세션을 즉시 제거하고 [CooldownException] 을 throw 해
      // ViewModel 이 AsyncError 로 전이시키도록 한다.
      await _enforceSigninCooldown();
    } on AuthFailure {
      rethrow;
    } on AuthException catch (e) {
      debugPrint('[AuthRepository] signInWithIdToken 실패: ${e.message} (statusCode: ${e.statusCode})');
      throw AuthFailure('로그인에 실패했습니다.', e);
    } catch (e) {
      debugPrint('[AuthRepository] 예기치 않은 오류: $e');
      throw AuthFailure('로그인에 실패했습니다.', e);
    }
  }

  /// 로그인 직후 14일 쿨다운 RPC 를 호출해 재가입 차단 여부를 확인한다.
  ///
  /// 스펙: `.claude/agents/logic-implementor/04_profile.md` §7 "14일 쿨다운 강제 흐름".
  /// - blocked=false → 무시하고 진행 (정상 로그인).
  /// - blocked=true  → 즉시 Supabase + Google 세션 제거, [CooldownException] throw.
  /// - RPC 호출 자체가 실패한 경우 (네트워크 등) → fail-open 하지 않고 에러를
  ///   띄워 사용자가 재시도하도록 한다. 쿨다운을 놓치는 것보다 "잠시 후 다시
  ///   시도" 메시지가 안전하다.
  Future<void> _enforceSigninCooldown() async {
    try {
      final dynamic raw = await _client.rpc('check_signin_cooldown');
      // RPC 가 `returns table(...)` 이므로 List<Map> 으로 내려온다. 빈 리스트 방어.
      final List<dynamic> rows = raw is List<dynamic> ? raw : const [];
      if (rows.isEmpty) return;
      final Map<String, dynamic> row = rows.first as Map<String, dynamic>;
      final bool blocked = row['blocked'] == true;
      if (!blocked) return;

      final int remainingDays =
          (row['remaining_days'] as num?)?.toInt() ?? 14;

      // 세션 제거 — 방금 만들어진 Supabase 세션 + 네이티브 Google 캐시 모두.
      await _client.auth.signOut();
      await _googleSignIn.signOut();

      throw CooldownException(remainingDays);
    } on AuthFailure {
      rethrow;
    } catch (e) {
      debugPrint('[AuthRepository] check_signin_cooldown 실패: $e');
      // RPC 호출 실패 — 세션이 이미 만들어진 상태라 안전하게 원복.
      await _client.auth.signOut();
      await _googleSignIn.signOut();
      throw AuthFailure('쿨다운 확인에 실패했습니다. 잠시 후 다시 시도해주세요.', e);
    }
  }

  /// idToken JWT 의 payload 를 디코딩해 nonce 유무를 콘솔에 출력한다.
  void _debugLogIdToken(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length == 3) {
        final payload = utf8.decode(
          base64Url.decode(base64Url.normalize(parts[1])),
        );
        final claims = json.decode(payload) as Map<String, dynamic>;
        debugPrint('[AuthRepository] idToken nonce: ${claims['nonce']}');
        debugPrint('[AuthRepository] idToken iss: ${claims['iss']}');
        debugPrint('[AuthRepository] idToken aud: ${claims['aud']}');
      }
    } catch (e) {
      debugPrint('[AuthRepository] idToken 디코딩 실패: $e');
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
