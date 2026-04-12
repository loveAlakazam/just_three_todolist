import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 환경 변수 단일 진입점.
///
/// 앱 시작 전 [Env.load]를 반드시 호출해야 한다.
class Env {
  Env._();

  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get supabaseUrl => _required('SUPABASE_URL');
  static String get supabaseAnonKey => _required('SUPABASE_ANON_KEY');

  static String _required(String key) {
    final v = dotenv.env[key];
    if (v == null || v.isEmpty) {
      throw StateError('Missing env var: $key');
    }
    return v;
  }
}
