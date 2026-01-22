import 'package:flutter_test/flutter_test.dart';
import 'package:foo/main.dart' as app;

void main() {
  test('debug_main', () async {
    await app.main();
  }, timeout: Timeout.none);
}
