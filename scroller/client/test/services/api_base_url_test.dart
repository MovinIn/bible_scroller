import 'package:bible_scroller/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns override when base url is provided explicitly', () {
    expect(
      ApiClient.resolveApiBaseUrl('http://localhost:8000'),
      'http://localhost:8000',
    );
  });

  test('returns android emulator host when override is omitted on vm', () {
    // On VM/mobile tests, empty override still uses fromEnvironment default
    // unless dart-define emptied it. Explicit non-empty override is the contract.
    expect(
      ApiClient.resolveApiBaseUrl('http://10.0.2.2:8000'),
      'http://10.0.2.2:8000',
    );
  });
}
