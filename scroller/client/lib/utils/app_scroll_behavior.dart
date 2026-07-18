import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Allows mouse/trackpad drags to drive vertical PageView on web/desktop.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}
