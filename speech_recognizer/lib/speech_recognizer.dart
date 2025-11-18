/*
Copyright 2025 [BOOKBOT](https://bookbotkids.com/)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:queue/queue.dart';
import 'package:speech_recognizer/app_logger.dart';

enum AudioSpeechPermission { undetermined, authorized, denied, unknown }

typedef SpeechListener =
    void Function(
      String transcript,
      bool wasEndpoint,
      bool resetEndPos,
      bool isVoiceActive,
      bool isNoSpeech,
    );

class SpeechController {
  SpeechController._privateConstructor();
  static SpeechController shared = SpeechController._privateConstructor();

  final _NativeSpeechController _controller = _NativeSpeechController();
  final listeners = <SpeechListener>[];

  Future<void> init() async {
    await _controller.authorize();
    await _controller.permissions();
    await _controller.initSpeech();
    AppLogger.info('initialized');
    _controller.listen();
  }

  Future<void> listen() async {
    await _controller.listen();
  }

  Future<void> stopListening() async {
    await _controller.stopListening();
  }

  Future<void> resetSpeech() async {
    await _controller.resetSpeech();
  }

  Future<void> flushSpeech({String toRead = '', String? grammar}) async {
    await _controller.flushSpeech(toRead: toRead, grammar: grammar);
  }

  Future<void> initSpeech({
    String language = 'es',
    bool wordMode = false,
  }) async {
    await _controller.initSpeech(language: language, wordMode: wordMode);
  }

  /// Detect current permission for speech recognition
  Future<AudioSpeechPermission> permissions() async {
    return await _controller.permissions();
  }

  /// Authorize speech recognition
  Future<void> authorize() async {
    await _controller.authorize();
  }

  /// Register listener for speech events while speaking
  void addListener(SpeechListener listener) {
    if (!listeners.contains(listener)) {
      listeners.add(listener);
    }

    _controller.setSpeechCallback(listener);
  }

  /// Remove listener for speech events
  void removeListener(SpeechListener listener) {
    listeners.remove(listener);
  }

  /// Recognize audio from a file
  /// [filePath] is the path to the audio file
  Future<void> recognizeAudio(String filePath) async {
    return await _controller.recognizeAudio(filePath);
  }
}

class _NativeSpeechController {
  final methodChannel = const MethodChannel('com.bookbot/control');

  StreamSubscription? _eventListener;
  final eventChannel = const EventChannel('com.bookbot/event');
  final _flushSpeechqueue = Queue(parallel: 1);
  SpeechListener? speechCallback;

  _NativeSpeechController();

  void setSpeechCallback(SpeechListener callback) {
    speechCallback = callback;
  }

  Future<void> listen({bool wordMode = false}) async {
    debugPrint('start listening');
    await methodChannel.invokeMethod('listen', [wordMode.toString()]);
  }

  Future<void> authorize() async {
    try {
      final result = await methodChannel.invokeMethod('authorize');
      AppLogger.info('Authorize result $result');
    } catch (e, stacktrace) {
      AppLogger.error('Authorize error $e', e, stacktrace);
    }
  }

  Future<void> stopListening() async {
    debugPrint('stop listening');

    await methodChannel.invokeMethod('stopListening');
  }

  Future<void> mute() async {
    await methodChannel.invokeMethod('mute');
  }

  Future<void> unmute() async {
    await methodChannel.invokeMethod('unmute');
  }

  Future<void> cancelListening() async {
    debugPrint('cancel listening');

    await methodChannel.invokeMethod('cancel');
  }

  Future<void> playSound(
    String path, {
    double start = 0.0,
    double end = 0.0,
    bool forceNative = false,
    bool waitToFinish = false,
  }) async {
    await methodChannel.invokeMethod('playSound', [
      path,
      start.toString(),
      end.toString(),
      waitToFinish.toString().toLowerCase(),
    ]);
  }

  // ignore: unused_element
  Future<void> _onSpeechResult(dynamic result) async {
    debugPrint('_onSpeechResult $result');
    speak(result.toLowerCase());
  }

  Future<void> speak(String text) async {}

  Future<AudioSpeechPermission> permissions() async {
    final audioPermission = await methodChannel.invokeMethod('audioPermission');

    if (audioPermission == 'undetermined') {
      return AudioSpeechPermission.undetermined;
    }

    if (audioPermission == 'denied') {
      return AudioSpeechPermission.denied;
    }

    if (audioPermission == 'authorized') {
      return AudioSpeechPermission.authorized;
    }

    return AudioSpeechPermission.unknown;
  }

  Future<void> initSpeech({
    String language = 'es',
    bool wordMode = false,
  }) async {
    AppLogger.info("Init with asrLanguage $language");
    _eventListener ??= eventChannel.receiveBroadcastStream().listen(
      _onRecognizeEvent,
      onError: _onRecognizeError,
    );

    await methodChannel.invokeMethod('initSpeech', [
      language, // ASR language
      'demo', // profile id
      wordMode.toString(), // word mode
    ]);
  }

  Future<void> flushSpeech({String toRead = '', String? grammar}) async {
    return _flushSpeechqueue.add(() async {
      final tempDir = await getTemporaryDirectory();
      await methodChannel.invokeMethod('flushSpeech', [
        toRead,
        grammar,
        tempDir.path,
      ]);
    });
  }

  void _onRecognizeEvent(dynamic event) {
    final args = event as Map;
    final String transcript = args['transcript'];
    final bool wasEndpoint = args['wasEndpoint'];
    final bool resetEndPos = args['resetEndPos'];
    final bool isVoiceActive = args['isVoiceActive'];
    final isNoSpeech = args['isNoSpeech'] == true;
    if (transcript.isNotEmpty) {
      AppLogger.info(
        'speechRecognize isVoiceActive = $isVoiceActive, wasEndpoint = $wasEndpoint, transcript = $transcript',
      );
    }

    speechCallback?.call(
      transcript,
      wasEndpoint,
      resetEndPos,
      isVoiceActive,
      isNoSpeech,
    );
  }

  void _onRecognizeError(Object error) {
    AppLogger.error('Speech error $error');
  }

  Future<void> resetSpeech() async {
    await methodChannel.invokeMethod('resetSpeech');
  }

  Future<void> enableMicrophone(bool value) async {
    if (Platform.isIOS || Platform.isMacOS) {
      await methodChannel.invokeMethod('enableMicrophone', value);
    }
  }

  Future<void> setContextBiasing(String grammar) async {
    await methodChannel.invokeMethod('setContextBiasing', grammar);
  }

  Future<void> endSpeech() async {
    if (Platform.isAndroid) {
      await methodChannel.invokeMethod('endSpeech');
    }

    await _eventListener?.cancel();
    _eventListener = null;
  }

  Future<void> recognizeAudio(String filePath) async {
    return await methodChannel.invokeMethod('recognizeAudio', filePath);
  }
}
