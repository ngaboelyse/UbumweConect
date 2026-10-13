// Real-time voice translation during calls (Gemini Live, backend).
//
// Flow:
//  1. The receiver picks a voice and sends `voice_translation_start` naming the
//     SPEAKER (the peer) plus the direction of translation.
//  2. The speaker's app receives `voice_translation_stream_start` (carrying
//     source/target languages) and starts streaming mic PCM (16-bit mono
//     16 kHz, base64) as `voice_translation_audio` events.
//  3. The backend pipes the audio through a Gemini Live session and pushes
//     translated audio back to the receiver as `voice_translation` events.
//  4. The receiver decodes the 24 kHz PCM frames and plays them with
//     AudioPlayer (audioplayers). Speech ends on `voice_translation_status`.
//
// Voice selection: the receiver picks any of the backend's GEMINI_VOICES —
// the ORIGINAL speaker voice is never cloned; Gemini renders the translation
// in the chosen synthetic voice, in the receiver's language.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import 'websocket_service.dart';

const List<String> kGeminiVoices = [
  'Zephyr', 'Puck', 'Charon', 'Kore', 'Fenrir', 'Aoede',
  'Leda', 'Orus', 'Fenix', 'Nova', 'Angus', 'Alume',
];
const String kDefaultGeminiVoice = 'Kore';

class VoiceTranslationService {
  VoiceTranslationService(this._ws);

  final WebSocketService _ws;

  // ── Speaker side (streaming mic) ─────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  String? _streamingCallId;

  // ── Receiver side (playback) ─────────────────────────────────────────────
  AudioPlayer? _player;
  bool _playbackBusy = false;
  // Set once Gemini signals turnComplete; exposed for the call UI.
  bool get utteranceEnded => _utteranceEnded;
  // True once Gemini signals turnComplete (end of the current utterance).
  bool _utteranceEnded = false;
  final List<Uint8List> _pcmQueue = [];

  final _statusController = StreamController<VoiceTranslationStatus>.broadcast();
  Stream<VoiceTranslationStatus> get status => _statusController.stream;

  bool get isStreamingMic => _streamingCallId != null;

  // ── Receiver: start listening to the peer's translated voice ────────────
  void startListening({
    required String callId,
    required String speakerId,
    required String sourceLanguage,
    required String targetLanguage,
    String voice = kDefaultGeminiVoice,
  }) {
    _ensurePlayer();
    _utteranceEnded = false;
    _ws.sendEvent('voice_translation_start', {
      'call_id': callId,
      'speaker_id': speakerId,
      'source_language': sourceLanguage,
      'target_language': targetLanguage,
      'voice': voice,
    });
  }

  void stopListening({required String callId, required String speakerId}) {
    _ws.sendEvent('voice_translation_stop', {
      'call_id': callId,
      'speaker_id': speakerId,
    });
    _stopPlayer();
  }

  // ── Speaker: begin streaming mic PCM to the backend ─────────────────────
  Future<void> startStreamingMic({
    required String callId,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    if (_streamingCallId != null) return;
    try {
      if (!await _recorder.hasPermission()) {
        _statusController.add(const VoiceTranslationStatus.error('Mic permission denied'));
        return;
      }
      _streamingCallId = callId;
      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        sampleRate: 16000,
      ));
      _micSub = stream.listen((chunk) {
        if (_streamingCallId == null || chunk.isEmpty) return;
        _ws.sendEvent('voice_translation_audio', {
          'call_id': _streamingCallId,
          'audio': base64Encode(chunk),
        });
      });
      debugPrint('voice translation: streaming mic for call $callId');
    } catch (e) {
      _streamingCallId = null;
      _statusController.add(VoiceTranslationStatus.error('Mic stream failed: $e'));
    }
  }

  Future<void> stopStreamingMic() async {
    _streamingCallId = null;
    try {
      await _micSub?.cancel();
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    _micSub = null;
    debugPrint('voice translation: mic streaming stopped');
  }

  // ── Backend → client events (called from the call controller) ───────────

  /// Speaker's app was asked to stream mic audio.
  Future<void> handleStreamStart(Map<String, dynamic> data) async {
    final callId = data['call_id']?.toString() ?? '';
    if (callId.isEmpty) return;
    await startStreamingMic(
      callId: callId,
      sourceLanguage: data['source_language']?.toString() ?? 'kinyarwanda',
      targetLanguage: data['target_language']?.toString() ?? 'english',
    );
  }

  /// Translated PCM frame (base64, 16-bit mono 24 kHz) from the backend.
  void handleTranslatedAudio(Map<String, dynamic> data) {
    final audio = data['audio']?.toString();
    if (audio == null || audio.isEmpty) return;
    try {
      _pcmQueue.add(base64Decode(audio));
      _drainPcm();
    } catch (e) {
      debugPrint('voice translation: bad audio frame: $e');
    }
  }

  /// Transcript / interruption / end-of-utterance signal.
  void handleStatus(Map<String, dynamic> data) {
    final text = data['text'];
    if (text is String && text.isNotEmpty) {
      _statusController.add(VoiceTranslationStatus.transcript(text));
      _utteranceEnded = false;
    } else if (text is String && text.isEmpty) {
      // Interrupted — flush pending audio.
      _pcmQueue.clear();
      _utteranceEnded = false;
    } else {
      // turnComplete
      _utteranceEnded = true;
    }
  }

  // ── Playback plumbing (PCM 16-bit mono 24 kHz → WAV bytes) ──────────────

  void _ensurePlayer() {
    _player ??= AudioPlayer();
    _player!.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> _drainPcm() async {
    if (_playbackBusy) return;
    _playbackBusy = true;
    try {
      while (_pcmQueue.isNotEmpty) {
        final chunk = _pcmQueue.removeAt(0);
        final wav = _pcmToWav(chunk, sampleRate: 24000, numChannels: 1);
        _ensurePlayer();
        // audioplayers on web/mobile: feed bytes via BytesSource.
        await _player!.play(BytesSource(wav));
      }
    } catch (e) {
      debugPrint('voice translation playback error: $e');
    } finally {
      _playbackBusy = false;
    }
  }

  void _stopPlayer() {
    _pcmQueue.clear();
    try {
      _player?.stop();
      _player?.release();
    } catch (_) {}
  }

  void dispose() {
    stopStreamingMic();
    _stopPlayer();
    _player?.dispose();
    _player = null;
    _statusController.close();
  }

  /// Wrap raw 16-bit PCM data in a minimal WAV container so audioplayers can
  /// decode it uniformly across platforms.
  static Uint8List _pcmToWav(Uint8List pcm, {required int sampleRate, required int numChannels}) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final header = BytesBuilder();
    void u16(int v) => header.add([v & 0xFF, (v >> 8) & 0xFF]);
    void u32(int v) => header.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    header.add('RIFF'.codeUnits);
    u32(36 + pcm.length);
    header.add('WAVE'.codeUnits);
    header.add('fmt '.codeUnits);
    u32(16);
    u16(1); // PCM
    u16(numChannels);
    u32(sampleRate);
    u32(byteRate);
    u16(blockAlign);
    u16(bitsPerSample);
    header.add('data'.codeUnits);
    u32(pcm.length);
    final out = BytesBuilder();
    out.add(header.takeBytes());
    out.add(pcm);
    return out.takeBytes();
  }
}

class VoiceTranslationStatus {
  final String? transcript;
  final String? error;
  const VoiceTranslationStatus.transcript(this.transcript)
      : error = null;
  const VoiceTranslationStatus.error(this.error) : transcript = null;
}

/// Route a voice-translation WebSocket event to the service.
void routeVoiceTranslationEvent(
  VoiceTranslationService service,
  String event,
  Map<String, dynamic> data,
) {
  switch (event) {
    case 'voice_translation_stream_start':
      service.handleStreamStart(data);
      break;
    case 'voice_translation':
      service.handleTranslatedAudio(data);
      break;
    case 'voice_translation_status':
      service.handleStatus(data);
      break;
  }
}

final voiceTranslationServiceProvider = Provider<VoiceTranslationService>((ref) {
  return VoiceTranslationService(ref.read(websocketServiceProvider));
});
