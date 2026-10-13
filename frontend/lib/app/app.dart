import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/host_discovery.dart';
import '../features/auth/providers/auth_provider.dart';
import '../shared/services/push_notification_service.dart';
import '../shared/services/websocket_service.dart';
import '../features/calls/providers/call_controller.dart';

class UbumweConnectApp extends ConsumerStatefulWidget {
  const UbumweConnectApp({super.key});

  @override
  ConsumerState<UbumweConnectApp> createState() => _UbumweConnectAppState();
}

class _UbumweConnectAppState extends ConsumerState<UbumweConnectApp>
    with WidgetsBindingObserver {
  String? _connectedUserId;

  @override
  void initState() {
    super.initState();
    // Re-establish connectivity when the app comes back from the background
    // (hours later): re-discover the backend host (the PC's IP may have
    // changed) and force-reconnect the WebSocket, which may have silently
    // died while the OS suspended the app.
    WidgetsBinding.instance.addObserver(this);
    _initializePushNotifications();
    // Keep the WebSocket lifecycle in sync with the login state: connect on
    // login, disconnect on logout. Without this the server has no socket to
    // push incoming calls / WebRTC signalling to.
    ref.listenManual(authNotifierProvider, (previous, next) {
      if (next.hasValue && next.valueOrNull != null) {
        _ensureWebSocketConnected(next.valueOrNull!.id);
      } else if (previous?.valueOrNull != null && _connectedUserId != null) {
        _disconnectWebSocket();
      }
    }, fireImmediately: true);
  }

  void _ensureWebSocketConnected(String userId) {
    if (_connectedUserId == userId) return;
    _connectedUserId = userId;
    ref.read(websocketServiceProvider).connect(userId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || kIsWeb) return;
    _handleResume();
  }

  Future<void> _handleResume() async {
    final userId = _connectedUserId;
    if (userId == null) return;
    // The backend host may have changed while we were away (DHCP, new Wi-Fi).
    HostDiscovery.reset();
    try {
      await AppConstants.initHost();
    } catch (_) {}
    // Drop the (possibly dead) socket and reconnect on the fresh host.
    ref.read(websocketServiceProvider).disconnect();
    ref.read(websocketServiceProvider).connect(userId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _disconnectWebSocket() {
    _connectedUserId = null;
    ref.read(websocketServiceProvider).disconnect();
  }

  Future<void> _initializePushNotifications() async {
    try {
      // Give the push service a way to navigate (deferred one frame so the
      // router provider is mounted).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final router = ref.read(routerProvider);
        ref.read(navigationServiceProvider).attach(router.push);
        // Listen for call events (incoming calls, WebRTC signalling).
        ref.read(callControllerProvider.notifier).attach(ref.read(websocketServiceProvider));
      });
      await ref.read(pushNotificationServiceProvider).initialize();
    } catch (e) {
      debugPrint('Push notifications initialization skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Ubumwe Connect',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
