/// Compile-time configuration. Override via:
///   flutter run --dart-define=TRUTHRELAY_API_URL=http://10.0.2.2:8080
class Env {
  static const String apiUrl = String.fromEnvironment(
    'TRUTHRELAY_API_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );
}
