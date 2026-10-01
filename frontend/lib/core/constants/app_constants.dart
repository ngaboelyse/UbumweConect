class AppConstants {
  AppConstants._();

  static const String appName = 'Ubumwe Connect';
  static const String appTagline = 'Bringing People Together Beyond Language';
  static const String appVersion = '1.0.0';

  // API
  static const String baseUrl = 'http://127.0.0.1:8000/api/v1';
  static const String wsBaseUrl = 'ws://127.0.0.1:8000/ws';

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
  ];

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
