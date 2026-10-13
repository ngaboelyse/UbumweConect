/// Plays the remote peer's audio stream during a call.
///
/// On web the remote stream must be attached to an <audio> element for sound
/// to be heard; on native platforms flutter_webrtc plays remote audio itself,
/// so the stub is a no-op.
library;

import 'package:flutter_webrtc/flutter_webrtc.dart';

abstract class RemoteAudioPlayer {
  Future<void> setStream(MediaStream? stream);
  void dispose();
}
