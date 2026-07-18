import 'package:bible_scroller/utils/app_scroll_behavior.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('includes mouse and trackpad when resolving drag devices', () {
    final devices = AppScrollBehavior().dragDevices;

    expect(
      devices.containsAll({
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.touch,
      }),
      isTrue,
    );
  });
}
