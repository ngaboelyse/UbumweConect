import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import 'api_service.dart';

/// Top-level handler required for background push messages.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background pushes are displayed by the OS (notification payload);
  // nothing to do here beyond avoiding a crash on cold start.
}

final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});

class PushNotificationService {
  final Ref _ref;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  final _messageStream = StreamController<RemoteMessage>.broadcast();

  PushNotificationService(this._ref);

  /// Stream of foreground push messages (for in-app banners / routing).
  Stream<RemoteMessage> get messageStream => _messageStream.stream;

  Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;

    // 1. Request permission (iOS / Android 13+)
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Local notifications for foreground display (FCM does not show
    //    notifications while the app is in the foreground).
    const androidChannel = AndroidNotificationChannel(
      'ubumwe_messages',
      'Ubumwe Messages',
      description: 'Message and call notifications',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(initSettings);

    // 3. Wire up listeners
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedApp);

    // App opened from a terminated state via notification tap
    final initial = await messaging.getInitialMessage();
    if (initial != null) _routeMessage(initial);

    // 4. Register the device token with the backend
    messaging.onTokenRefresh.listen(_registerToken);
    await _registerToken(await messaging.getToken());
  }

  Future<void> _registerToken(String? token) async {
    if (token == null || token.isEmpty) return;
    final auth = _ref.read(currentUserProvider);
    if (auth == null) return; // Not logged in yet; will register on token refresh
    try {
      await _ref
          .read(apiServiceProvider)
          .post('/users/push-token', data: {'token': token});
    } catch (_) {
      // Best-effort; retried on next token refresh
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    _messageStream.add(message);

    final notification = message.notification;
    if (notification == null) return;
    _localNotifications.show(
      notification.hashCode,
      notification.title ?? 'Ubumwe Connect',
      notification.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ubumwe_messages',
          'Ubumwe Messages',
          channelDescription: 'Message and call notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: message.data.toString(),
    );
  }

  void _handleOpenedApp(RemoteMessage message) {
    _messageStream.add(message);
    _routeMessage(message);
  }

  /// Route the user to the right screen based on the push payload.
  void _routeMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'];

    switch (type) {
      case 'new_message':
        final conversationId = data['conversation_id'];
        if (conversationId != null) {
          _ref.read(navigationServiceProvider).goToConversation(conversationId);
        }
        break;
      case 'incoming_call':
        // Call routing is handled by the WebSocket incoming_call event;
        // the push is the wake-up mechanism when the app is killed.
        final callId = data['call_id'];
        if (callId != null) {
          _ref.read(navigationServiceProvider).goToIncomingCall(callId);
        }
        break;
    }
  }
}

/// Thin indirection over GoRouter so the push service doesn't import the
/// router directly (avoids circular dependencies).
class NavigationService {
  void Function(String route)? _goTo;

  void attach(void Function(String route) goTo) => _goTo = goTo;

  void goToConversation(String conversationId) =>
      _goTo?.call('/chat/$conversationId');

  void goToIncomingCall(String callId) => _goTo?.call('/call/voice/$callId');
}

final navigationServiceProvider = Provider<NavigationService>((ref) {
  return NavigationService();
});
