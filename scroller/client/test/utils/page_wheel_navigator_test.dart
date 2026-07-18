import 'package:bible_scroller/utils/page_wheel_navigator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PageWheelNavigator', () {
    test('returns next when scroll delta is positive', () {
      final navigator = PageWheelNavigator(
        clock: () => DateTime.utc(2026, 1, 1),
      );

      expect(
        navigator.resolve(120, canGoNext: true, canGoPrevious: true),
        PageWheelAction.next,
      );
    });

    test('returns previous when scroll delta is negative', () {
      final navigator = PageWheelNavigator(
        clock: () => DateTime.utc(2026, 1, 1),
      );

      expect(
        navigator.resolve(-120, canGoNext: true, canGoPrevious: true),
        PageWheelAction.previous,
      );
    });

    test('returns null when scroll delta is zero', () {
      final navigator = PageWheelNavigator(
        clock: () => DateTime.utc(2026, 1, 1),
      );

      expect(
        navigator.resolve(0, canGoNext: true, canGoPrevious: true),
        isNull,
      );
    });

    test('returns next for a small positive notch delta', () {
      final navigator = PageWheelNavigator(
        clock: () => DateTime.utc(2026, 1, 1),
      );

      expect(
        navigator.resolve(1, canGoNext: true, canGoPrevious: true),
        PageWheelAction.next,
      );
    });

    test('returns null when next is requested but cannot go next', () {
      final navigator = PageWheelNavigator(
        clock: () => DateTime.utc(2026, 1, 1),
      );

      expect(
        navigator.resolve(120, canGoNext: false, canGoPrevious: true),
        isNull,
      );
    });

    test('returns null when previous is requested but cannot go previous', () {
      final navigator = PageWheelNavigator(
        clock: () => DateTime.utc(2026, 1, 1),
      );

      expect(
        navigator.resolve(-120, canGoNext: true, canGoPrevious: false),
        isNull,
      );
    });

    test('returns null when another scroll arrives during cooldown', () {
      var now = DateTime.utc(2026, 1, 1);
      final navigator = PageWheelNavigator(
        cooldown: const Duration(milliseconds: 400),
        clock: () => now,
      );

      expect(
        navigator.resolve(120, canGoNext: true, canGoPrevious: true),
        PageWheelAction.next,
      );

      now = now.add(const Duration(milliseconds: 100));
      expect(
        navigator.resolve(120, canGoNext: true, canGoPrevious: true),
        isNull,
      );
    });

    test('returns next again when cooldown has elapsed', () {
      var now = DateTime.utc(2026, 1, 1);
      final navigator = PageWheelNavigator(
        cooldown: const Duration(milliseconds: 400),
        clock: () => now,
      );

      expect(
        navigator.resolve(120, canGoNext: true, canGoPrevious: true),
        PageWheelAction.next,
      );

      now = now.add(const Duration(milliseconds: 400));
      expect(
        navigator.resolve(120, canGoNext: true, canGoPrevious: true),
        PageWheelAction.next,
      );
    });
  });
}
