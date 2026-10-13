import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'remote_stream_interface.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/router.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/voice_translation_service.dart';
import '../../../shared/services/websocket_service.dart';

// ─── Call state model ───────────────────────────────────────────────────────

enum CallType { voice, video }

enum CallPhase { idle, outgoing, incoming, active, ended }

enum CallRole { caller, callee }

class CallSession {
  final String callId;
  final String conversationId;
  final String peerId;
  final String peerName;
  final String? peerAvatar;
  final CallType type;
  final CallPhase phase;
  final CallRole role;
  final String? error;

  const CallSession({
    required this.callId,
    required this.conversationId,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
    required this.type,
    required this.phase,
    required this.role,
    this.error,
  });

  CallSession copyWith({
    String? callId,
    String? conversationId,
    String? peerId,
    String? peerName,
    String? peerAvatar,
    CallType? type,
    CallPhase? phase,
    CallRole? role,
    String? error,
  }) =>
      CallSession(
        callId: callId ?? this.callId,
        conversationId: conversationId ?? this.conversationId,
        peerId: peerId ?? this.peerId,
        peerName: peerName ?? this.peerName,
        peerAvatar: peerAvatar ?? this.peerAvatar,
        type: type ?? this.type,
        phase: phase ?? this.phase,
        role: role ?? this.role,
        error: error,
      );
}

// ─── Controller ─────────────────────────────────────────────────────────────

class CallController extends StateNotifier<CallSession?> {
  final Ref _ref;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  Timer? _ringTimeout;

  // WebRTC objects
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Pending offer received before the callee pressed "Accept".
  Map<String, dynamic>? _pendingOffer;

  // ICE candidates that arrived before we had a peer connection with a remote
  // description set. They must be replayed in order or the connection fails
  // (classic "call connects but no audio" bug).
  final List<Map<String, dynamic>> _pendingCandidates = [];

  final _remoteStreamNotifier = ValueNotifier<MediaStream?>(null);
  final _localStreamNotifier = ValueNotifier<MediaStream?>(null);

  ValueListenable<MediaStream?> get remoteStream => _remoteStreamNotifier;
  ValueListenable<MediaStream?> get localStream => _localStreamNotifier;

  CallController(this._ref) : super(null);

  bool get _isVideo => state?.type == CallType.video;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Subscribes the controller to WebSocket call events and the router.
  /// Call once (from app startup) after login.
  void attach(WebSocketService ws) {
    _wsSub?.cancel();
    _wsSub = ws.messages.listen(_handleWsEvent);
  }

  void detach() {
    _wsSub?.cancel();
    _wsSub = null;
  }

  // ── Outgoing call ────────────────────────────────────────────────────────

  /// Creates the call server-side and moves into the "outgoing" phase.
  /// Returns the call id, or null when the call could not be created.
  Future<String?> createCall({
    required String conversationId,
    required String peerId,
    required String peerName,
    String? peerAvatar,
    required CallType type,
  }) async {
    if (state != null && state!.phase != CallPhase.ended) return null; // busy

    try {
      final res = await _ref.read(apiServiceProvider).post('/calls', data: {
        'conversation_id': conversationId,
        'call_type': type == CallType.video ? 'video' : 'voice',
      });
      final callId = res['id']?.toString() ?? res['call_id']?.toString();
      if (callId == null || callId.isEmpty) return null;

      state = CallSession(
        callId: callId,
        conversationId: conversationId,
        peerId: peerId,
        peerName: peerName,
        peerAvatar: peerAvatar,
        type: type,
        phase: CallPhase.outgoing,
        role: CallRole.caller,
      );

      await _prepareMediaAndPeer();
      return callId;
    } catch (e) {
      debugPrint('createCall failed: $e');
      _cleanup(routing: false);
      return null;
    }
  }

  // ── Incoming call ────────────────────────────────────────────────────────

  void _handleIncomingCall(Map<String, dynamic> data) {
    // Ignore if we are already in a call.
    if (state != null && state!.phase != CallPhase.ended) return;

    final callType = data['call_type'] == 'video' ? CallType.video : CallType.voice;
    state = CallSession(
      callId: data['call_id']?.toString() ?? '',
      conversationId: data['conversation_id']?.toString() ?? '',
      peerId: data['caller_id']?.toString() ?? '',
      peerName: data['caller_name']?.toString() ?? 'Unknown',
      peerAvatar: data['caller_avatar']?.toString(),
      type: callType,
      phase: CallPhase.incoming,
      role: CallRole.callee,
    );

    // Auto-decline after 45 s of ringing.
    _ringTimeout?.cancel();
    _ringTimeout = Timer(const Duration(seconds: 45), () => rejectIncoming());

    final router = _readRouter();
    router?.push(
      '/incoming-call?call_id=${state!.callId}'
      '&call_type=${callType == CallType.video ? 'video' : 'voice'}'
      '&caller_name=${Uri.encodeComponent(state!.peerName)}'
      '&caller_avatar=${Uri.encodeComponent(state!.peerAvatar ?? '')}',
    );
  }

  Future<void> acceptIncoming() async {
    final s = state;
    if (s == null || s.phase != CallPhase.incoming) return;
    _ringTimeout?.cancel();

    try {
      await _ref.read(apiServiceProvider).put('/calls/${s.callId}/accept');
    } catch (e) {
      debugPrint('accept failed: $e');
      // The call may already be gone; bail out to a safe state.
      _cleanup(routing: true);
      return;
    }

    state = s.copyWith(phase: CallPhase.active);
    await _prepareMediaAndPeer();

    final route = s.type == CallType.video ? '/call/video' : '/call/voice';
    _readRouter()?.pushReplacement('$route/${s.callId}');

    // The caller may have already sent the offer while we were ringing.
    final offer = _pendingOffer;
    if (offer != null) {
      _pendingOffer = null;
      await _handleSignal(offer);
    }
  }

  Future<void> rejectIncoming() async {
    final s = state;
    if (s == null || s.phase != CallPhase.incoming) return;
    _ringTimeout?.cancel();
    try {
      await _ref.read(apiServiceProvider).put('/calls/${s.callId}/reject');
    } catch (_) {}
    _cleanup(routing: true);
  }

  // ── Ending ───────────────────────────────────────────────────────────────

  Future<void> endCall() async {
    final s = state;
    if (s == null || s.phase == CallPhase.ended) return;
    try {
      await _ref.read(apiServiceProvider).put('/calls/${s.callId}/end');
    } catch (_) {}
    // The server notifies the other side; we tear down locally right away.
    _cleanup(routing: true);
  }

  // ── Media controls (called from call screens) ────────────────────────────

  void toggleMute() {
    final tracks = _localStream?.getAudioTracks();
    if (tracks == null || tracks.isEmpty) return;
    final enabled = tracks.first.enabled;
    tracks.first.enabled = !enabled;
  }

  void toggleCamera() {
    final tracks = _localStream?.getVideoTracks();
    if (tracks == null || tracks.isEmpty) return;
    final enabled = tracks.first.enabled;
    tracks.first.enabled = !enabled;
  }

  bool _speakerOn = false;

  void toggleSpeaker() {
    _speakerOn = !_speakerOn;
    Helper.setSpeakerphoneOn(_speakerOn);
  }

  Future<void> switchCamera() async {
    try {
      final track = _localStream?.getVideoTracks().first;
      if (track != null) await Helper.switchCamera(track);
    } catch (_) {}
  }

  // ── WebSocket event routing ──────────────────────────────────────────────

  void _handleWsEvent(Map<String, dynamic> event) {
    final type = event['event'] as String?;
    final data = event['data'] as Map<String, dynamic>? ?? {};
    switch (type) {
      case 'incoming_call':
        _handleIncomingCall(data);
        break;
      case 'call_accepted':
        _handleCallAccepted(data);
        break;
      case 'call_rejected':
        if (state?.callId == data['call_id']?.toString()) {
          _cleanup(routing: true, reason: 'Call declined');
        }
        break;
      case 'call_ended':
        if (state?.callId == data['call_id']?.toString()) {
          _cleanup(routing: true, reason: 'Call ended');
        }
        break;
      case 'call_signal':
        _handleSignal(data);
        break;
      case 'voice_translation_stream_start':
      case 'voice_translation':
      case 'voice_translation_status':
        routeVoiceTranslationEvent(
            _ref.read(voiceTranslationServiceProvider), type!, data);
        break;
      case 'voice_translation_stream_stop':
        _ref.read(voiceTranslationServiceProvider).stopStreamingMic();
        break;
    }
  }

  Future<void> _handleCallAccepted(Map<String, dynamic> data) async {
    final s = state;
    if (s == null || s.role != CallRole.caller) return;
    if (s.phase == CallPhase.active) return;

    state = s.copyWith(phase: CallPhase.active, peerId: data['user_id']?.toString() ?? s.peerId);
    await _prepareMediaAndPeer();
    await _createAndSendOffer();
  }

  // ── WebRTC ───────────────────────────────────────────────────────────────

  Future<void> _prepareMediaAndPeer() async {
    if (_pc != null) return;
    final s = state;
    if (s == null) return;

    try {
      await _ensurePermissions();
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': _isVideo
            ? {'facingMode': 'user', 'width': 1280, 'height': 720}
            : false,
      });
      _localStreamNotifier.value = _localStream;

      // On Android, audio-only calls default to the earpiece and the
      // loudspeaker is only auto-enabled for video calls — which makes voice
      // calls sound silent unless the speaker is forced on. Default to
      // loudspeaker (users can still toggle it off in the call screen).
      _speakerOn = true;
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}

      final pc = await _createPeerConnection();
      _pc = pc;

      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
      }

      pc.onTrack = (event) async {
        debugPrint('onTrack: kind=${event.track.kind} streams=${event.streams.length}');
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams.first;
        } else if (_remoteStream == null) {
          // Web audio-only transceivers can deliver a track with no associated
          // stream — build one so the remote side still gets audio.
          _remoteStream = await createEmptyMediaStream(
              'remote_${DateTime.now().millisecondsSinceEpoch}');
        }
        // Track may arrive after the stream was created for a previous event.
        if (!_remoteStream!.getTracks().contains(event.track)) {
          _remoteStream!.addTrack(event.track);
        }
        _remoteStreamNotifier.value = _remoteStream;
      };

      pc.onIceCandidate = (candidate) {
        if (candidate.candidate == null) return;
        _sendSignal('candidate', candidate: {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      };

      pc.onConnectionState = (connectionState) {
        debugPrint('ICE connection state: $connectionState');
        if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          debugPrint('peer connection CONNECTED');
        } else if (connectionState == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          // Surface the failure instead of a silent "Connected" screen.
          state = state?.copyWith(error: 'Connection failed — check your network');
        }
      };
    } catch (e) {
      debugPrint('Media/peer setup failed: $e');
      state = state?.copyWith(error: 'Could not access microphone/camera');
      _cleanup(routing: true, reason: 'Media error');
    }
  }

  Future<RTCPeerConnection> _createPeerConnection() async {
    final config = {'iceServers': await _iceServers(), 'sdpSemantics': 'unified-plan'};
    return createPeerConnection(config);
  }

  Future<List<Map<String, dynamic>>> _iceServers() async {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
    try {
      final creds = await _ref.read(apiServiceProvider).get('/calls/turn-credentials');
      final urls = (creds['urls'] as List<dynamic>? ?? [])
          .map((u) => u.toString())
          .where((u) => u.isNotEmpty && !u.startsWith('stun:stun.l.google'))
          .toList();
      if (urls.isNotEmpty) {
        servers.add({
          'urls': urls,
          'username': creds['username'],
          'credential': creds['credential'],
        });
      }
    } catch (_) {
      // STUN-only fallback.
    }
    return servers;
  }

  Future<void> _ensurePermissions() async {
    await [Permission.microphone, if (_isVideo) Permission.camera].request();
  }

  // WebRTC peer-connection state surfaced to the call screen.
  final ValueNotifier<String> connectionState = ValueNotifier('new');

  Future<void> _createAndSendOffer() async {
    final pc = _pc;
    if (pc == null) return;
    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    _sendSignal('offer', sdp: {
      'type': offer.type,
      'sdp': offer.sdp,
    });
  }

  Future<void> _createAndSendAnswer() async {
    final pc = _pc;
    if (pc == null) return;
    final answer = await pc.createAnswer({});
    await pc.setLocalDescription(answer);
    _sendSignal('answer', sdp: {
      'type': answer.type,
      'sdp': answer.sdp,
    });
  }

  Future<void> _handleSignal(Map<String, dynamic> data) async {
    final s = state;
    if (s == null || s.callId != data['call_id']?.toString()) {
      // Signal for a call we have not accepted yet (callee, still ringing).
      if (data['signal_type'] == 'offer' && s?.phase == CallPhase.incoming) {
        _pendingOffer = data;
      }
      return;
    }

    final pc = _pc;
    if (pc == null) {
      // Peer connection not ready yet — buffer so nothing is lost.
      if (data['signal_type'] == 'offer') {
        _pendingOffer = data;
      } else if (data['signal_type'] == 'candidate') {
        _pendingCandidates.add(data);
      }
      return;
    }

    switch (data['signal_type']) {
      case 'offer':
        final sdp = data['sdp'] as Map<String, dynamic>?;
        if (sdp == null) return;
        await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'], sdp['type']));
        await _flushPendingCandidates(pc);
        await _createAndSendAnswer();
        break;
      case 'answer':
        final sdp = data['sdp'] as Map<String, dynamic>?;
        if (sdp == null) return;
        await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'], sdp['type']));
        await _flushPendingCandidates(pc);
        break;
      case 'candidate':
        final cand = data['candidate'] as Map<String, dynamic>?;
        if (cand == null) return;
        // Adding a candidate before the remote description is set throws on
        // some platforms; buffer and replay after the answer arrives.
        final remote = await pc.getRemoteDescription();
        if (remote == null) {
          _pendingCandidates.add(data);
          return;
        }
        await pc.addCandidate(RTCIceCandidate(
          cand['candidate'],
          cand['sdpMid'],
          cand['sdpMLineIndex'],
        ));
        break;
    }
  }

  Future<void> _flushPendingCandidates(RTCPeerConnection pc) async {
    if (_pendingCandidates.isEmpty) return;
    final buffered = List<Map<String, dynamic>>.from(_pendingCandidates);
    _pendingCandidates.clear();
    for (final data in buffered) {
      final cand = data['candidate'] as Map<String, dynamic>?;
      if (cand == null) continue;
      try {
        await pc.addCandidate(RTCIceCandidate(
          cand['candidate'],
          cand['sdpMid'],
          cand['sdpMLineIndex'],
        ));
      } catch (e) {
        debugPrint('replay ICE candidate failed: $e');
      }
    }
  }

  void _sendSignal(String signalType, {Map<String, dynamic>? sdp, Map<String, dynamic>? candidate}) {
    final s = state;
    if (s == null) return;
    _ref.read(websocketServiceProvider).sendCallSignal({
      'to_user_id': s.peerId,
      'call_id': s.callId,
      'signal_type': signalType,
      if (sdp != null) 'sdp': sdp,
      if (candidate != null) 'candidate': candidate,
    });
  }

  // ── Voice translation (Gemini Live) ─────────────────────────────────

  /// Receiver: start hearing the peer's speech translated (synthetic voice).
  Future<void> startVoiceTranslation({String voice = kDefaultGeminiVoice}) async {
    final s = state;
    if (s == null || s.callId.isEmpty) return;
    // Figure out the languages: peer speaks THEIR language, we hear OURS.
    String myLang = 'english';
    String peerLang = 'kinyarwanda';
    try {
      final me = await _ref.read(apiServiceProvider).get('/users/profile');
      myLang = me['preferred_language']?.toString() ?? 'english';
      final peer = await _ref.read(apiServiceProvider).get('/users/${s.peerId}');
      peerLang = peer['preferred_language']?.toString() ?? 'kinyarwanda';
    } catch (_) {}
    _ref.read(voiceTranslationServiceProvider).startListening(
          callId: s.callId,
          speakerId: s.peerId,
          sourceLanguage: peerLang,
          targetLanguage: myLang,
          voice: voice,
        );
  }

  /// Receiver: stop translated playback.
  void stopVoiceTranslation() {
    final s = state;
    if (s == null) return;
    _ref.read(voiceTranslationServiceProvider).stopListening(
          callId: s.callId,
          speakerId: s.peerId,
        );
  }

  // ── Teardown ─────────────────────────────────────────────────────────────

  void _cleanup({required bool routing, String? reason}) {
    _ringTimeout?.cancel();
    // End any active voice-translation streaming/playback for this call.
    final vt = _ref.read(voiceTranslationServiceProvider);
    vt.stopStreamingMic();
    vt.stopListening(callId: state?.callId ?? '', speakerId: state?.peerId ?? '');
    _pendingOffer = null;
    _pendingCandidates.clear();
    _pc?.close();
    _pc = null;
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    _remoteStream = null;
    _localStreamNotifier.value = null;
    _remoteStreamNotifier.value = null;

    final s = state;
    // Fully reset so a new call can start immediately afterwards.
    state = null;

    if (routing) {
      // Leave the call screens; go back to where the user was.
      final router = _readRouter();
      final location = router?.routerDelegate.currentConfiguration.last.matchedLocation ?? '';
      if (location.startsWith('/call') || location == '/incoming-call') {
        if (router?.canPop() ?? false) {
          router!.pop();
        } else {
          router?.go('/home');
        }
      }
    } else if (s != null) {
      debugPrint('Call ${s.callId} ended: ${reason ?? 'hangup'}');
    }
  }

  GoRouter? _readRouter() {
    try {
      return _ref.read(routerProvider);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _ringTimeout?.cancel();
    _wsSub?.cancel();
    _pc?.close();
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStreamNotifier.dispose();
    _remoteStreamNotifier.dispose();
    super.dispose();
  }
}

final callControllerProvider =
    StateNotifierProvider<CallController, CallSession?>((ref) => CallController(ref));
