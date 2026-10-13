// Web implementation: flutter_webrtc does NOT play remote audio automatically
// on web. Attach the remote stream's audio tracks to a dedicated <audio>
// element — the same technique the working video path uses internally.
//
// Reliability rules for this file:
//  1. The element must be in the DOM BEFORE srcObject/play() (detached
//     elements are autoplay-blocked and GC'd in some browsers).
//  2. play() must be retried — the first attempt races with track arrival and
//     autoplay policy. A short watchdog keeps retrying until it plays.
//  3. Never early-return on an identical stream instance: tracks are added to
//     the stream AFTER onTrack fires, so re-force play on every set.
import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web/web.dart' as web;

import 'remote_audio_player_interface.dart';

class RemoteAudioPlayerImpl implements RemoteAudioPlayer {
  web.HTMLAudioElement? _element;
  MediaStream? _current;
  Timer? _watchdog;
  int _attempts = 0;

  @override
  Future<void> setStream(MediaStream? stream) async {
    _current = stream;
    _watchdog?.cancel();

    if (stream == null) {
      _element?.pause();
      return;
    }

    try {
      final a = _element ?? _createElement();
      a.autoplay = true;
      a.muted = false;
      a.volume = 1.0;

      // flutter_webrtc wraps the JS MediaStream; pull the raw object out so
      // the browser accepts it. Works for MediaStreamWeb (web builds only).
      final jsStream = (stream as dynamic).jsStream as web.MediaStream?;
      a.srcObject = jsStream;

      _attempts = 0;
      await _tryPlay(a);
      // Watchdog: retry every 300 ms for up to ~5 s until the element is
      // actually playing. Covers autoplay rejection and late track arrival.
      _watchdog = Timer.periodic(const Duration(milliseconds: 300), (t) async {
        if (t.tick > 16) {
          t.cancel();
          debugPrint('remote audio: giving up after 16 play attempts');
          return;
        }
        if (_element != a) {
          t.cancel();
          return;
        }
        await _tryPlay(a);
      });
      debugPrint('remote audio attached (${stream.getAudioTracks().length} tracks)');
    } catch (e) {
      debugPrint('remote audio attach failed: $e');
    }
  }

  web.HTMLAudioElement _createElement() {
    final a = web.HTMLAudioElement();
    a.autoplay = true;
    a.muted = false;
    // Keep it in the document: some browsers pause detached elements, and
    // Chrome applies stricter autoplay to elements not in the DOM.
    web.document.body?.append(a);
    _element = a;
    return a;
  }

  Future<void> _tryPlay(web.HTMLAudioElement a) async {
    _attempts++;
    try {
      final p = a.play().toDart;
      await p;
      // Success: no more retries needed.
      _watchdog?.cancel();
      debugPrint('remote audio playing (attempt $_attempts)');
    } catch (e) {
      // Autoplay policy or empty srcObject — retry via the watchdog.
      debugPrint('remote audio play() attempt $_attempts failed: $e');
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _element?.pause();
    _element?.srcObject = null;
    _element?.remove();
    _element = null;
    _current = null;
  }
}
