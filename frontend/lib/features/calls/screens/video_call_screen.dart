import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../app/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../chat/providers/chat_provider.dart';
import '../providers/call_controller.dart';

class VideoCallScreen extends ConsumerStatefulWidget {
  final String callId;
  const VideoCallScreen({super.key, required this.callId});

  @override
  ConsumerState<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends ConsumerState<VideoCallScreen> {
  bool _isMuted = false;
  bool _isCameraOn = true;
  bool _showControls = true;
  String _duration = '00:00';
  Timer? _durationTimer;
  Timer? _controlsTimer;
  int _seconds = 0;

  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  CallController get _call => ref.read(callControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _startTimer();
    _scheduleHideControls();
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    if (!mounted) return;
    setState(() => _renderersReady = true);
    // Attach current streams and keep following future ones.
    _localRenderer.srcObject = _call.localStream.value;
    _remoteRenderer.srcObject = _call.remoteStream.value;
    _call.localStream.addListener(_attachLocal);
    _call.remoteStream.addListener(_attachRemote);
  }

  void _attachLocal() {
    if (mounted) _localRenderer.srcObject = _call.localStream.value;
  }

  void _attachRemote() {
    if (mounted) _remoteRenderer.srcObject = _call.remoteStream.value;
  }

  void _startTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final phase = ref.read(callControllerProvider)?.phase;
      if (phase != CallPhase.active) return;
      _seconds++;
      final m = (_seconds ~/ 60).toString().padLeft(2, '0');
      final s = (_seconds % 60).toString().padLeft(2, '0');
      if (mounted) setState(() => _duration = '$m:$s');
    });
  }

  void _scheduleHideControls() {
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _onTap() {
    setState(() => _showControls = true);
    _controlsTimer?.cancel();
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _controlsTimer?.cancel();
    _call.localStream.removeListener(_attachLocal);
    _call.remoteStream.removeListener(_attachRemote);
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(callControllerProvider);
    // The controller already ended the call and popped the route.
    if (session == null) return const SizedBox.shrink();

    final currentUser = ref.watch(currentUserProvider);
    final conversationsAsync = ref.watch(conversationsProvider);
    String peerName = session.peerName;
    conversationsAsync.whenData((convs) {
      final conv = convs.where((c) => c.id == session.conversationId).firstOrNull;
      if (conv != null) peerName = conv.getDisplayName(currentUser?.id ?? '');
    });

    final hasRemoteVideo = _renderersReady && _remoteRenderer.srcObject != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _onTap,
        child: Stack(
          children: [
            // Remote video (full screen)
            Container(
              width: double.infinity,
              height: double.infinity,
              color: const Color(0xFF1A1A2E),
              child: hasRemoteVideo
                  ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(peerName.isNotEmpty ? peerName[0].toUpperCase() : 'U', style: const TextStyle(fontSize: 48, color: Colors.white, fontFamily: 'Poppins')),
                          const SizedBox(height: 16),
                          Text(peerName, style: const TextStyle(color: Colors.white54, fontSize: 16, fontFamily: 'Poppins')),
                          const SizedBox(height: 8),
                          Text(session.phase == CallPhase.active ? 'Connected' : 'Ringing...', style: const TextStyle(color: Colors.white38, fontSize: 13, fontFamily: 'Poppins')),
                        ],
                      ),
                    ),
            ),

            // Self video (PiP - top right)
            Positioned(
              top: 60,
              right: 16,
              child: Container(
                width: 100,
                height: 140,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D44),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: _isCameraOn && _renderersReady && _localRenderer.srcObject != null
                      ? RTCVideoView(_localRenderer, mirror: true)
                      : const Center(child: Icon(Icons.videocam_off, color: Colors.white38, size: 32)),
                ),
              ),
            ),

            // Top bar
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black54, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(peerName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, fontFamily: 'Poppins')),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.success.withOpacity(0.3), borderRadius: BorderRadius.circular(8)),
                            child: Text(_duration, style: const TextStyle(color: AppColors.success, fontSize: 12, fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
                          ),
                          const Spacer(),
                          const Icon(Icons.signal_cellular_alt, color: Colors.white70, size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom controls
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _VideoCallButton(
                            icon: _isMuted ? Icons.mic_off : Icons.mic,
                            label: _isMuted ? 'Unmute' : 'Mute',
                            onTap: () {
                              _call.toggleMute();
                              setState(() => _isMuted = !_isMuted);
                            },
                            active: _isMuted,
                          ),
                          _VideoCallButton(
                            icon: Icons.flip_camera_ios_outlined,
                            label: 'Flip',
                            onTap: () => _call.switchCamera(),
                          ),
                          GestureDetector(
                            onTap: () => _call.endCall(),
                            child: Container(
                              width: 64, height: 64,
                              decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                              child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                            ),
                          ),
                          _VideoCallButton(
                            icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                            label: 'Camera',
                            onTap: () {
                              _call.toggleCamera();
                              setState(() => _isCameraOn = !_isCameraOn);
                            },
                            active: !_isCameraOn,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  const _VideoCallButton({required this.icon, required this.label, required this.onTap, this.active = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'Poppins')),
        ],
      ),
    );
  }
}
