import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/app_constants.dart';
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

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _stateController = StreamController<WsConnectionState>.broadcast();

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<WsConnectionState> get connectionState => _stateController.stream;
  WsConnectionState get state => _state;

  WebSocketService(this._storage);

  Future<void> connect(String userId) async {
    _currentUserId = userId;
    final token = await _storage.getAccessToken();
    if (token == null) return;

    _setState(WsConnectionState.connecting);

    try {
      final uri = Uri.parse('${AppConstants.wsBaseUrl}/$userId?token=$token');
      _channel = WebSocketChannel.connect(uri);

      _setState(WsConnectionState.connected);
      _reconnectAttempts = 0;

      _startPingTimer();

      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _messageController.add(decoded);
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
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      connect(_currentUserId!);
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
