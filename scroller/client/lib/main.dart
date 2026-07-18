import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/reels_feed_screen.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/storage_service.dart';
import 'services/token_storage.dart';
import 'state/auth_controller.dart';
import 'state/reels_controller.dart';
import 'theme/app_theme.dart';
import 'utils/app_scroll_behavior.dart';
import 'utils/startup_timing.dart';
import 'widgets/web_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  StartupTiming.start('main.total');

  final storage = StorageService();
  await StartupTiming.track('main.storageInit', storage.init);

  var deviceId = await StartupTiming.track('main.readDeviceId', storage.readDeviceId);
  if (deviceId == null) {
    deviceId = ApiClient().deviceId;
    await StartupTiming.track('main.saveDeviceId', () => storage.saveDeviceId(deviceId!));
  }

  final api = ApiClient(deviceId: deviceId);
  final authService = AuthService(
    api: ApiAuthClient(apiClient: api),
    storage: SecureTokenStorage(),
    googleSignIn: GoogleSignInAdapter(),
  );
  final authController = AuthController(authService: authService);
  final controller = ReelsController(api: api, storage: storage);

  StartupTiming.end('main.total');
  StartupTiming.summary();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authController),
        ChangeNotifierProvider.value(value: controller),
      ],
      child: const _AppBootstrap(child: BibleScrollerApp()),
    ),
  );
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap({required this.child});

  final Widget child;

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        StartupTiming.track(
          'main.restoreSession',
          () => context.read<AuthController>().restoreSession(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class BibleScrollerApp extends StatelessWidget {
  const BibleScrollerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bible Scroller',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      scrollBehavior: AppScrollBehavior(),
      home: const WebShell(child: ReelsFeedScreen()),
    );
  }
}
