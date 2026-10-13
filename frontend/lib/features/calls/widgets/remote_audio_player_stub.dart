// Native platforms: flutter_webrtc renders remote audio itself, nothing to do.
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'remote_audio_player_interface.dart';

class RemoteAudioPlayerImpl implements RemoteAudioPlayer {
  @override
  Future<void> setStream(MediaStream? stream) async {}

  @override
  void dispose() {}
}
