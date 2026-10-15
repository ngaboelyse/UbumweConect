import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/host_discovery.dart';

class AppConstants {
  AppConstants._();

  static const String appName = 'Ubumwe Connect';
  static const String appTagline = 'Bringing People Together Beyond Language';
  static const String appVersion = '1.0.0';

  // Backend endpoint.
  // WEB: the host is auto-detected from the browser URL, so any device on the
  // same Wi-Fi can open the app at http://<PC-IP>:3000 and reach the backend
  // at http://<PC-IP>:8000 with zero configuration.
  // MOBILE (Android/iOS/desktop): the LAN host is auto-discovered by probing
  // the device's subnet for the backend /health endpoint (see HostDiscovery).
  // `defaultHost` is only the last-resort fallback if probing finds nothing.
  // Android emulator: '10.0.2.2:8000'.
  // Override at build/run time: flutter run --dart-define=API_HOST=192.168.1.10 --dart-define=API_PORT=8001
  static const String defaultHost =
      String.fromEnvironment('API_HOST', defaultValue: '10.20.3.125:8000');
  static const bool useTls = bool.fromEnvironment('API_TLS', defaultValue: false); // true = https/wss (tunnel), false = http/ws (local/LAN)

  // The web build is served on :3000 but the backend listens on :8000.
  static const String webPort = '3000';
  static const String apiPort =
      String.fromEnvironment('API_PORT', defaultValue: '8000');

  /// Synchronously usable host. Returns the last discovered host, or falls
  /// back to [defaultHost] before discovery has run. Call [initHost] at app
  /// startup so the discovered value is set before the first API call.
  static String get host {
    if (kIsWeb) {
      final b = Uri.base;
      if (b.host.isEmpty) return defaultHost;
      final port = b.hasPort || b.port > 0 ? '${b.port}' : '';
      // The backend listens on the API port. Only reuse the browser port when
      // the app is served from the API port itself (same-origin deployment);
      // any other port (3000, 8080, ...) is the web server, not the API.
      final api = (port.isEmpty || port == webPort) ? apiPort : (port == apiPort ? port : apiPort);
      return api.isEmpty ? b.host : '${b.host}:$api';
    }
    return HostDiscovery.resolvedHost ?? defaultHost;
  }

  /// Runs LAN discovery once at startup (non-web only). Safe to await or fire
  /// and forget; [host] picks up the result as soon as it completes.
  static Future<void> initHost() async {
    if (kIsWeb) return;
    await HostDiscovery.resolve();
  }

  static String get baseUrl => '${useTls ? 'https' : 'http'}://$host/api/v1';
  static String get wsBaseUrl => '${useTls ? 'wss' : 'ws'}://$host/ws';

  // Supported Languages
  static const List<Map<String, String>> supportedLanguages = [
    {
      'code': 'kinyarwanda',
      'name': 'Kinyarwanda',
      'native': 'Ikinyarwanda',
      'flag': '🇷🇼',
      'iso': 'rw',
    },
    {
      'code': 'english',
      'name': 'English',
      'native': 'English',
      'flag': '🇬🇧',
      'iso': 'en',
    },
    {
      'code': 'french',
      'name': 'French',
      'native': 'Français',
      'flag': '🇫🇷',
      'iso': 'fr',
    },
    {
      'code': 'swahili',
      'name': 'Swahili',
      'native': 'Kiswahili',
      'flag': '🇹🇿',
      'iso': 'sw',
    },
    {
      'code': 'spanish',
      'name': 'Spanish',
      'native': 'Español',
      'flag': '🇪🇸',
      'iso': 'es',
    },
    {
      'code': 'arabic',
      'name': 'Arabic',
      'native': 'العربية',
      'flag': '🇸🇦',
      'iso': 'ar',
    },
    {
      'code': 'portuguese',
      'name': 'Portuguese',
      'native': 'Português',
      'flag': '🇵🇹',
      'iso': 'pt',
    },
    {
      'code': 'german',
      'name': 'German',
      'native': 'Deutsch',
      'flag': '🇩🇪',
      'iso': 'de',
    },
    {
      'code': 'chinese',
      'name': 'Chinese',
      'native': '中文',
      'flag': '🇨🇳',
      'iso': 'zh',
    },
  ];

  /// Preview of a greeting in each supported language (used in language settings).

  // Message types
  static const String msgTypeText = 'text';
  static const String msgTypeVoice = 'voice';
  static const String msgTypeImage = 'image';
  static const String msgTypeFile = 'file';
  static const String msgTypeSystem = 'system';

  // Call types
  static const String callTypeVoice = 'voice';
  static const String callTypeVideo = 'video';

  // Call status
  static const String callStatusRinging = 'ringing';
  static const String callStatusActive = 'active';
  static const String callStatusEnded = 'ended';
  static const String callStatusMissed = 'missed';
  static const String callStatusRejected = 'rejected';

  // Message status
  static const String msgStatusSent = 'sent';
  static const String msgStatusDelivered = 'delivered';
  static const String msgStatusRead = 'read';

  // Pagination
  static const int messagesPerPage = 50;
  static const int usersPerPage = 20;

  // File limits
  static const int maxImageSizeMb = 5;
  static const int maxFileSizeMb = 50;
  static const int maxAudioDurationSeconds = 300;

  // Storage keys
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUser = 'current_user';
  static const String keyLanguage = 'preferred_language';
  static const String keyDarkMode = 'dark_mode';
  static const String keyOnboardingDone = 'onboarding_done';

  // WebSocket events
  static const String wsNewMessage = 'new_message';
  static const String wsTypingIndicator = 'typing_indicator';
  static const String wsMessageStatus = 'message_status';
  static const String wsCallSignal = 'call_signal';
  static const String wsIncomingCall = 'incoming_call';
  static const String wsCallAccepted = 'call_accepted';
  static const String wsCallRejected = 'call_rejected';
  static const String wsCallEnded = 'call_ended';
  static const String wsOnlineStatus = 'online_status';
}
