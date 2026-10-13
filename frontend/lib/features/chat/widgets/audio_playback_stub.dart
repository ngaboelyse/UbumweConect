// Stub for non-web platforms. MessageBubble only constructs this class on
// the web (kIsWeb guard), so the methods are intentionally no-ops.
import 'audio_playback_interface.dart';

class WebAudio implements AudioPlayback {
  @override
  Future<void> play(String url, void Function() onEnded) async {}

  @override
  void pause() {}

  @override
  void dispose() {}
}
