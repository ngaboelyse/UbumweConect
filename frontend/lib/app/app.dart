import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';
import '../shared/services/push_notification_service.dart';

class UbumweConnectApp extends ConsumerStatefulWidget {
  const UbumweConnectApp({super.key});

  @override
  ConsumerState<UbumweConnectApp> createState() => _UbumweConnectAppState();
}

class _UbumweConnectAppState extends ConsumerState<UbumweConnectApp> {
  @override
  void initState() {
    super.initState();
    _initializePushNotifications();
  }

  Future<void> _initializePushNotifications() async {
    try {
      // Give the push service a way to navigate (deferred one frame so the
      // router provider is mounted).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final router = ref.read(routerProvider);
        ref.read(navigationServiceProvider).attach(router.push);
      });
      await ref.read(pushNotificationServiceProvider).initialize();
    } catch (e) {
      debugPrint('Push notifications initialization skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Ubumwe Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
