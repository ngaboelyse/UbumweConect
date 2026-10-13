// Web implementation backed by the browser's own <audio> element — the most
// reliable path on web.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'audio_playback_interface.dart';

class WebAudio implements AudioPlayback {
  web.HTMLAudioElement? _element;

  @override
  Future<void> play(String url, void Function() onEnded) async {
    final a = _element ?? web.HTMLAudioElement();
    if (_element != a) {
      a.src = url;
      a.addEventListener(
          'ended',
          ((JSAny _) {
            onEnded();
          }).toJS);
      _element = a;
    }
    await a.play().toDart;
  }

  @override
  void pause() => _element?.pause();

  @override
  void dispose() => _element?.pause();
}
