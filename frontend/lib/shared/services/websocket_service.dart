import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/app_constants.dart';
import 'api_service.dart';
import 'local_storage_service.dart';

final websocketServiceProvider = Provider<WebSocketService>((ref) {
  return WebSocketService(ref.read(localStorageServiceProvider));
});

enum WsConnectionState { disconnected, connecting, connected, reconnecting }

class WebSocketService {
  final LocalStorageService _storage;
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;
  String? _currentUserId;
  WsConnectionState _state = WsConnectionState.disconnected;
  // Token age: refresh proactively instead of relying on 403-reconnect loops.
  DateTime _lastTokenRefresh = DateTime.now();
  static const _tokenMaxAge = Duration(minutes: 25); // tokens expire in 30

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<WsConnectionState>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<WsConnectionState> get connectionState => _stateController.stream;
  WsConnectionState get state => _state;

  WebSocketService(this._storage);

  Future<void> connect(String userId) async {
    _currentUserId = userId;

    _setState(WsConnectionState.connecting);

    try {
      // Proactive refresh: if the access token is near/past expiry, get a
      // fresh one BEFORE connecting, so the first attempt succeeds.
      if (DateTime.now().difference(_lastTokenRefresh) >= _tokenMaxAge) {
        final refreshed = await ApiService.refreshTokenOnce(_storage);
        if (!refreshed) {
          _setState(WsConnectionState.disconnected);
          return;
        }
      }
      _lastTokenRefresh = DateTime.now();
      final token = await _storage.getAccessToken();
      if (token == null) return;

      final uri = Uri.parse('${AppConstants.wsBaseUrl}/$userId?token=$token');
      _channel = WebSocketChannel.connect(uri);

      _reconnectAttempts = 0;
      _setState(WsConnectionState.connected);

      _startPingTimer();

      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(decoded);
            _setState(WsConnectionState.connected);
          } catch (_) {}
        },
        onDone: () => _handleDisconnect(),
        onError: (e) => _handleDisconnect(),
        cancelOnError: false,
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _channel = null;
    _pingTimer?.cancel();
    _setState(WsConnectionState.reconnecting);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_currentUserId == null) return;
    final delay = Duration(seconds: _getReconnectDelay());
    _reconnectTimer = Timer(delay, () async {
      _reconnectAttempts++;
      // The access token may have expired while disconnected (the app can sit
      // in the background for hours). Refresh via the SHARED single-flight
      // routine — a parallel refresh from the HTTP interceptor rotates the
      // refresh token, and reusing the dead one here would 401 and wipe the
      // session (this used to cause a 403 reconnect storm + rate-limit 429s).
      try {
        final refreshed = await ApiService.refreshTokenOnce(_storage);
        if (!refreshed) return; // session truly dead; stop reconnecting
      } catch (_) {
        // Network hiccup — still attempt the socket with the current token.
      }
      await connect(_currentUserId!);
    });
  }

  int _getReconnectDelay() {
    final delays = [1, 2, 5, 10, 30, 60];
    final index = _reconnectAttempts.clamp(0, delays.length - 1);
    return delays[index];
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      sendEvent('ping', {});
    });
  }

  void sendEvent(String event, Map<String, dynamic> data) {
    if (_channel == null || _state != WsConnectionState.connected) return;
    try {
      _channel!.sink.add(jsonEncode({'event': event, 'data': data}));
    } catch (_) {}
  }

  void joinConversation(String conversationId) {
    sendEvent('join_conversation', {'conversation_id': conversationId});
  }

  void leaveConversation(String conversationId) {
    sendEvent('leave_conversation', {'conversation_id': conversationId});
  }

  void sendTyping(String conversationId, bool isTyping, String userName) {
    sendEvent('typing', {
      'conversation_id': conversationId,
      'is_typing': isTyping,
      'user_name': userName,
    });
  }

  void sendReadReceipt(String messageId, String senderId) {
    sendEvent('read_receipt', {'message_id': messageId, 'sender_id': senderId});
  }

  void sendCallSignal(Map<String, dynamic> signalData) {
    sendEvent('call_signal', signalData);
  }

  void _setState(WsConnectionState state) {
    _state = state;
    _stateController.add(state);
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _currentUserId = null;
    await _channel?.sink.close();
    _channel = null;
    _setState(WsConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}
