import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Centers a phone-width frame on web; passes through on mobile.
class WebShell extends StatelessWidget {
  const WebShell({super.key, required this.child});

  static const double phoneMaxWidth = 430;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return child;
    }

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: phoneMaxWidth),
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: child,
          ),
        ),
      ),
    );
  }
}
