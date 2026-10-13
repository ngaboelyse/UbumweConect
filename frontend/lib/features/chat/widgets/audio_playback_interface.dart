/// Platform-agnostic audio playback used by [MessageBubble] for voice notes.
///
/// The web implementation lives in `audio_playback_web.dart`, the native
/// no-op stub in `audio_playback_stub.dart`; `audio_playback.dart` picks the
/// right one via a conditional export so the app compiles for every target.
abstract class AudioPlayback {
  /// Starts playing [url]; calls [onEnded] when playback finishes.
  Future<void> play(String url, void Function() onEnded);

  /// Pauses playback if playing.
  void pause();

  /// Releases any underlying resources.
  void dispose();
}
