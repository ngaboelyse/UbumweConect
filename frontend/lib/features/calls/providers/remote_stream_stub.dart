import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Non-web implementation: creating a detached MediaStream isn't needed on
/// mobile because `onTrack` events always carry an associated stream there.
/// If it's somehow hit, fall back to an empty local stream via the factory.
Future<MediaStream> createEmptyMediaStream(String id) async {
  throw UnsupportedError('createEmptyMediaStream is web-only');
}
