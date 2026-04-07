import 'package:flutter/material.dart';
import 'package:sign_in_button/sign_in_button.dart';

/// 로그인 화면.
///
/// 레이아웃:
/// Scaffold → SafeArea → Column
///   ├─ Expanded (로고)
///   ├─ SignInButton (Buttons.google)
///   └─ SizedBox (하단 여백)
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SignInButton(
                Buttons.google,
                text: 'Google로 로그인',
                onPressed: () => _handleGoogleSignIn(context),
              ),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  /// Google 로그인 탭 핸들러.
  ///
  /// TODO: ViewModel 연결 후 실제 로그인 처리로 교체.
  /// 로그인 실패 시 [SnackBar]로 에러 메시지 표시(아래 예시 참고).
  void _handleGoogleSignIn(BuildContext context) {
    // 예시: 실패 처리
    // ScaffoldMessenger.of(context).showSnackBar(
    //   const SnackBar(content: Text('로그인에 실패했습니다. 다시 시도해주세요.')),
    // );
  }
}
