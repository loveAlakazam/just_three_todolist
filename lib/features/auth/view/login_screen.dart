import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_button/sign_in_button.dart';

import '../repository/auth_repository.dart';
import '../viewmodel/auth_view_model.dart';

/// 로그인 화면.
///
/// 레이아웃:
/// Scaffold → SafeArea → Column
///   ├─ Expanded (로고)
///   ├─ SignInButtonBuilder (Google 스타일, 전체 가로폭)
///   └─ SizedBox (하단 여백)
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 에러 구독 → SnackBar 표시.
    ref.listen<AsyncValue<dynamic>>(authViewModelProvider, (prev, next) {
      if (next is AsyncError) {
        final error = next.error;
        // OAuth 취소는 조용히 무시.
        if (error is AuthFailure && error.message.contains('취소')) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('로그인에 실패했습니다. 다시 시도해주세요.'),
          ),
        );
      }
    });

    final authState = ref.watch(authViewModelProvider);
    final isLoading = authState.isLoading;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4EB),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Image.asset(
                  'assets/images/just-three-logo.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            // Google 로그인 버튼: 좌우 10px 여백, 높이 64.
            //
            // `SignInButton(Buttons.google, ...)`은 내부적으로 height: 36,
            // maxWidth: 220이 하드코딩되어 크기 변경이 불가능하므로,
            // 같은 패키지의 [SignInButtonBuilder]를 직접 사용해 Google 스타일을
            // 재현하면서 로고 / 텍스트 / 버튼 높이를 키움.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: SignInButtonBuilder(
                  text: 'Google로 로그인',
                  textColor: const Color(0xFF1F1F1F),
                  backgroundColor: Colors.white,
                  fontSize: 20,
                  height: 64,
                  width: double.infinity,
                  onPressed: isLoading
                      ? () {}
                      : () => ref
                            .read(authViewModelProvider.notifier)
                            .signInWithGoogle(),
                  image: Container(
                    margin: const EdgeInsets.only(right: 14),
                    child: isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: const Image(
                              image: AssetImage(
                                'assets/logos/google_light.png',
                                package: 'sign_in_button',
                              ),
                              height: 44,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
