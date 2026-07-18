import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import 'auth_sheet.dart';

Future<bool> ensureLoggedIn(BuildContext context) async {
  final auth = context.read<AuthController>();
  if (auth.isLoggedIn) {
    return true;
  }
  return AuthSheet.show(context);
}
