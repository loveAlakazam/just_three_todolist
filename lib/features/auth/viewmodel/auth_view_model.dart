import 'dart:async';

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

    ref.onDispose(sub.cancel);

    return repo.currentSession?.user;
  }

  /// 네이티브 Google Sign-In 로그인.
  ///
  /// - 성공: `signInWithIdToken` 완료와 동시에 `authStateChanges` 가
  ///   새 세션을 발행 → build() 의 listener 에서 `state = AsyncData(user)`.
  /// - 취소/실패: Repository 가 `AuthFailure`(취소 시 `AuthCancelled`) 를 throw
  ///   → 여기서 `state = AsyncError` 로 전이 → View 가 타입으로 분기.
  Future<void> signInWithGoogle() async {
    state = const AsyncLoading<User?>();
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
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
