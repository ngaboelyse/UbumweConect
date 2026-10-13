import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:dart_webrtc/dart_webrtc.dart' show RTCFactoryWeb;

/// Web implementation: web audio-only transceivers can deliver a track with
/// no associated stream, so we build one so the remote side still gets audio.
Future<MediaStream> createEmptyMediaStream(String id) {
  return RTCFactoryWeb.instance.createLocalMediaStream(id) as Future<MediaStream>;
}
