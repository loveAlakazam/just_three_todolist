import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../repository/auth_repository.dart';

/// 인증 상태를 관리하는 ViewModel.
///
/// - `AsyncValue<User?>`: null이면 비로그인, User가 있으면 로그인 상태.
/// - `authStateChanges` stream을 구독하여 로그인/로그아웃 시 자동 갱신.
/// - router의 `redirect`에서 이 상태를 읽어 인증 가드(CR-1)를 구현한다.
final authViewModelProvider =
    AsyncNotifierProvider<AuthViewModel, User?>(() => AuthViewModel());

class AuthViewModel extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    final repo = ref.watch(authRepositoryProvider);

    // authStateChanges 구독 → state 업데이트.
    final sub = repo.authStateChanges.listen((authState) {
      state = AsyncData(authState.session?.user);
    });

    // OAuth 취소 시 로딩 상태 해제:
    // 브라우저에서 로그인을 취소하고 앱으로 돌아오면
    // authStateChanges가 발행되지 않아 AsyncLoading이 영구 고착된다.
    // 앱이 포그라운드로 복귀할 때 로딩 상태이면 현재 세션으로 리셋한다.
    final lifecycleListener = AppLifecycleListener(
      onResume: () {
        if (state.isLoading) {
          state = AsyncData(repo.currentSession?.user);
        }
      },
    );

    ref.onDispose(() {
      sub.cancel();
      lifecycleListener.dispose();
    });

    return repo.currentSession?.user;
  }

  /// Google OAuth 로그인.
  ///
  /// 성공 시 authStateChanges가 세션을 발행 → state 자동 갱신.
  /// 실패 시 AsyncError로 전이 → View에서 SnackBar로 표시.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading<User?>();
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.signInWithGoogle();
      // OAuth 흐름은 브라우저를 거치므로 여기서 바로 완료되지 않는다.
      // 브라우저에서 돌아온 뒤 authStateChanges가 세션을 발행하면
      // build()의 listen에서 state가 갱신된다.
      // 사용자가 브라우저에서 취소한 경우, AppLifecycleListener.onResume이
      // 로딩 상태를 해제한다.
    } on AuthFailure catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// 로그아웃.
  ///
  /// signOut 후 authStateChanges가 SIGNED_OUT을 발행
  /// → state = AsyncData(null) → router redirect가 /login으로 이동.
  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
  }
}
