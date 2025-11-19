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

/// Speech recognition library for Flutter applications.
///
/// This library provides a high-level API for performing speech recognition
/// on mobile platforms (iOS and Android). It supports real-time speech-to-text
/// conversion, permission management, and audio file recognition.
///
/// The main entry point is [SpeechController], which provides a singleton
/// interface for managing speech recognition operations.
///
/// Example:
/// ```dart
/// final controller = SpeechController.shared;
/// await controller.authorize();
/// controller.addListener((transcript, wasEndpoint, resetEndPos, isVoiceActive, isNoSpeech) {
///   print('Recognized: $transcript');
/// });
/// await controller.init();
/// await controller.listen();
/// ```
library speech_recognizer;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:queue/queue.dart';
import 'package:speech_recognizer/app_logger.dart';

/// Enumeration representing the current audio and speech recognition permission status.
///
/// This enum is used to check the permission state for accessing the microphone
/// and performing speech recognition on the device.
enum AudioSpeechPermission {
  /// Permission status has not been determined yet.
  undetermined,

  /// Permission has been granted by the user.
  authorized,

  /// Permission has been denied by the user.
  denied,

  /// Permission status is unknown or could not be determined.
  unknown,
}

/// Callback function type for receiving speech recognition events.
///
/// This callback is invoked whenever the speech recognizer processes audio
/// and provides recognition results or status updates.
///
/// Parameters:
/// - [transcript]: The recognized text transcript from the audio input.
/// - [wasEndpoint]: Whether the current recognition represents an endpoint
///   (e.g., end of a sentence or phrase).
/// - [resetEndPos]: Whether the end position should be reset in the recognition buffer.
/// - [isVoiceActive]: Whether voice activity is currently detected in the audio stream.
/// - [isNoSpeech]: Whether the system detected no speech in the current audio segment.
typedef SpeechListener =
    void Function(
      String transcript,
      bool wasEndpoint,
      bool resetEndPos,
      bool isVoiceActive,
      bool isNoSpeech,
    );

/// Main controller for managing speech recognition functionality.
///
/// This class provides a singleton interface for initializing, controlling,
/// and receiving events from the speech recognition system. It acts as a
/// high-level wrapper around the native platform implementation.
///
/// Example usage:
/// ```dart
/// final controller = SpeechController.shared;
/// await controller.init();
/// controller.addListener((transcript, wasEndpoint, resetEndPos, isVoiceActive, isNoSpeech) {
///   print('Recognized: $transcript');
/// });
/// await controller.listen();
/// ```
class SpeechController {
  SpeechController._privateConstructor();
  static SpeechController shared = SpeechController._privateConstructor();

  final _NativeSpeechController _controller = _NativeSpeechController();
  final listeners = <SpeechListener>[];

  /// Initializes the speech recognition system.
  ///
  /// This method performs the following operations:
  /// 1. Requests authorization for speech recognition
  /// 2. Checks current permissions
  /// 3. Initializes the speech recognition engine with default settings
  /// 4. Starts listening for audio input
  ///
  /// Should be called before using any other speech recognition methods.
  Future<void> init() async {
    await _controller.authorize();
    await _controller.permissions();
    await _controller.initSpeech();
    AppLogger.info('initialized');
    _controller.listen();
  }

  /// Starts listening for speech input from the microphone.
  ///
  /// Begins capturing audio from the device's microphone and processing it
  /// for speech recognition. Recognition results will be delivered through
  /// registered listeners via [addListener].
  Future<void> listen() async {
    await _controller.listen();
  }

  /// Stops listening for speech input.
  ///
  /// Stops capturing audio from the microphone. The recognition engine
  /// remains initialized and can be restarted with [listen].
  Future<void> stopListening() async {
    await _controller.stopListening();
  }

  /// Resets the speech recognition state.
  ///
  /// Clears the current recognition buffer and resets the internal state
  /// of the speech recognizer. Useful when you want to start fresh
  /// without reinitializing the entire system.
  Future<void> resetSpeech() async {
    await _controller.resetSpeech();
  }

  /// Flushes the current speech recognition buffer.
  ///
  /// Processes any pending audio in the recognition buffer and optionally
  /// applies grammar constraints for more accurate recognition.
  ///
  /// Parameters:
  /// - [toRead]: Optional text to read or process during the flush operation.
  /// - [grammar]: Optional grammar constraint to apply for recognition accuracy.
  Future<void> flushSpeech({String toRead = '', String? grammar}) async {
    await _controller.flushSpeech(toRead: toRead, grammar: grammar);
  }

  /// Initializes or reinitializes the speech recognition engine.
  ///
  /// Configures the speech recognizer with the specified language and mode.
  /// This can be called multiple times to change recognition settings.
  ///
  /// Parameters:
  /// - [language]: The language code for speech recognition (default: 'es' for Spanish).
  /// - [wordMode]: Whether to enable word-level recognition mode (default: false).
  Future<void> initSpeech({
    String language = 'es',
    bool wordMode = false,
  }) async {
    await _controller.initSpeech(language: language, wordMode: wordMode);
  }

  /// Detects the current permission status for speech recognition.
  ///
  /// Returns the current [AudioSpeechPermission] status, which indicates
  /// whether the app has been granted permission to access the microphone
  /// and perform speech recognition.
  ///
  /// Returns:
  /// - [AudioSpeechPermission.authorized] if permission has been granted
  /// - [AudioSpeechPermission.denied] if permission has been denied
  /// - [AudioSpeechPermission.undetermined] if permission hasn't been requested yet
  /// - [AudioSpeechPermission.unknown] if the status could not be determined
  Future<AudioSpeechPermission> permissions() async {
    return await _controller.permissions();
  }

  /// Requests authorization for speech recognition.
  ///
  /// This method prompts the user to grant permission for microphone access
  /// and speech recognition. Should be called before attempting to use
  /// speech recognition features.
  ///
  /// Note: On iOS, this will show a system permission dialog if not already granted.
  Future<void> authorize() async {
    await _controller.authorize();
  }

  /// Registers a listener to receive speech recognition events.
  ///
  /// The provided [listener] callback will be invoked whenever the speech
  /// recognizer processes audio and provides recognition results or status updates.
  ///
  /// The same listener will not be added multiple times if it's already registered.
  ///
  /// Parameters:
  /// - [listener]: The callback function to receive speech recognition events.
  void addListener(SpeechListener listener) {
    if (!listeners.contains(listener)) {
      listeners.add(listener);
    }

    _controller.setSpeechCallback(listener);
  }

  /// Removes a previously registered speech recognition listener.
  ///
  /// The [listener] will no longer receive speech recognition events after
  /// being removed.
  ///
  /// Parameters:
  /// - [listener]: The callback function to remove from the listeners list.
  void removeListener(SpeechListener listener) {
    listeners.remove(listener);
  }

  /// Recognizes speech from an audio file.
  ///
  /// Processes a pre-recorded audio file and performs speech recognition on it.
  /// Recognition results will be delivered through registered listeners.
  ///
  /// Parameters:
  /// - [filePath]: The absolute path to the audio file to recognize.
  Future<void> recognizeAudio(String filePath) async {
    return await _controller.recognizeAudio(filePath);
  }
}

/// Internal controller for native platform communication.
///
/// This private class handles all communication with the native platform
/// (iOS/Android) through method channels and event channels. It manages
/// the low-level speech recognition operations and event streaming.
///
/// This class is not intended for direct use by external code. Use
/// [SpeechController] instead for the public API.
class _NativeSpeechController {
  /// Method channel for invoking native platform methods.
  final methodChannel = const MethodChannel('com.bookbot/control');

  /// Stream subscription for receiving recognition events from the native platform.
  StreamSubscription? _eventListener;

  /// Event channel for receiving continuous recognition events.
  final eventChannel = const EventChannel('com.bookbot/event');

  /// Queue for serializing flush speech operations to prevent race conditions.
  final _flushSpeechqueue = Queue(parallel: 1);

  /// Callback function to invoke when speech recognition events occur.
  SpeechListener? speechCallback;

  _NativeSpeechController();

  /// Sets the callback function to receive speech recognition events.
  ///
  /// Parameters:
  /// - [callback]: The function to call when recognition events are received.
  void setSpeechCallback(SpeechListener callback) {
    speechCallback = callback;
  }

  /// Starts listening for speech input on the native platform.
  ///
  /// Parameters:
  /// - [wordMode]: Whether to enable word-level recognition mode (default: false).
  Future<void> listen({bool wordMode = false}) async {
    debugPrint('start listening');
    await methodChannel.invokeMethod('listen', [wordMode.toString()]);
  }

  /// Requests authorization for speech recognition from the native platform.
  ///
  /// This method communicates with the native platform to request microphone
  /// and speech recognition permissions. Errors are logged but not rethrown.
  Future<void> authorize() async {
    try {
      final result = await methodChannel.invokeMethod('authorize');
      AppLogger.info('Authorize result $result');
    } catch (e, stacktrace) {
      AppLogger.error('Authorize error $e', e, stacktrace);
    }
  }

  /// Stops listening for speech input on the native platform.
  ///
  /// Stops the audio capture and recognition process without canceling
  /// the recognition session.
  Future<void> stopListening() async {
    debugPrint('stop listening');

    await methodChannel.invokeMethod('stopListening');
  }

  /// Mutes the microphone input.
  ///
  /// Temporarily disables audio capture while keeping the recognition
  /// session active.
  Future<void> mute() async {
    await methodChannel.invokeMethod('mute');
  }

  /// Unmutes the microphone input.
  ///
  /// Re-enables audio capture after it has been muted.
  Future<void> unmute() async {
    await methodChannel.invokeMethod('unmute');
  }

  /// Cancels the current listening session.
  ///
  /// Completely cancels the recognition session and stops all audio processing.
  Future<void> cancelListening() async {
    debugPrint('cancel listening');

    await methodChannel.invokeMethod('cancel');
  }

  /// Plays a sound file on the native platform.
  ///
  /// Parameters:
  /// - [path]: The path to the audio file to play.
  /// - [start]: The start position in seconds (default: 0.0).
  /// - [end]: The end position in seconds (default: 0.0, plays entire file).
  /// - [forceNative]: Whether to force native playback (currently unused).
  /// - [waitToFinish]: Whether to wait for playback to complete before returning (default: false).
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

  /// Internal handler for speech recognition results.
  ///
  /// This method is called when speech recognition completes and processes
  /// the result. Currently unused but kept for potential future use.
  ///
  /// Parameters:
  /// - [result]: The recognition result from the native platform.
  // ignore: unused_element
  Future<void> _onSpeechResult(dynamic result) async {
    debugPrint('_onSpeechResult $result');
    speak(result.toLowerCase());
  }

  /// Placeholder method for text-to-speech functionality.
  ///
  /// Currently not implemented. Reserved for future text-to-speech features.
  ///
  /// Parameters:
  /// - [text]: The text to speak.
  Future<void> speak(String text) async {}

  /// Retrieves the current audio and speech permission status from the native platform.
  ///
  /// Returns:
  /// The current [AudioSpeechPermission] status as reported by the native platform.
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

  /// Initializes the speech recognition engine on the native platform.
  ///
  /// Sets up the recognition engine with the specified language and mode,
  /// and establishes the event stream for receiving recognition results.
  ///
  /// Parameters:
  /// - [language]: The language code for recognition (default: 'es' for Spanish).
  /// - [wordMode]: Whether to enable word-level recognition mode (default: false).
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

  /// Flushes the speech recognition buffer on the native platform.
  ///
  /// Processes any pending audio in the recognition buffer. This operation
  /// is queued to prevent concurrent flush operations.
  ///
  /// Parameters:
  /// - [toRead]: Optional text parameter for the flush operation.
  /// - [grammar]: Optional grammar constraint to apply during recognition.
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

  /// Handles recognition events received from the native platform.
  ///
  /// This method processes recognition events from the event channel and
  /// invokes the registered callback with the recognition data.
  ///
  /// Parameters:
  /// - [event]: The event data map containing recognition results and status.
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

  /// Handles errors from the recognition event stream.
  ///
  /// Logs recognition errors that occur during event processing.
  ///
  /// Parameters:
  /// - [error]: The error object received from the event channel.
  void _onRecognizeError(Object error) {
    AppLogger.error('Speech error $error');
  }

  /// Resets the speech recognition state on the native platform.
  ///
  /// Clears the recognition buffer and resets internal state without
  /// reinitializing the entire recognition engine.
  Future<void> resetSpeech() async {
    await methodChannel.invokeMethod('resetSpeech');
  }

  /// Enables or disables the microphone on supported platforms.
  ///
  /// This method only works on iOS and macOS platforms.
  ///
  /// Parameters:
  /// - [value]: Whether to enable (true) or disable (false) the microphone.
  Future<void> enableMicrophone(bool value) async {
    if (Platform.isIOS || Platform.isMacOS) {
      await methodChannel.invokeMethod('enableMicrophone', value);
    }
  }

  /// Sets context biasing grammar for improved recognition accuracy.
  ///
  /// Applies a grammar constraint to help the recognizer better understand
  /// expected words or phrases in the current context.
  ///
  /// Parameters:
  /// - [grammar]: The grammar string to apply for context biasing.
  Future<void> setContextBiasing(String grammar) async {
    await methodChannel.invokeMethod('setContextBiasing', grammar);
  }

  /// Ends the speech recognition session and cleans up resources.
  ///
  /// Stops the recognition session on Android and cancels the event stream
  /// subscription. Should be called when speech recognition is no longer needed.
  Future<void> endSpeech() async {
    if (Platform.isAndroid) {
      await methodChannel.invokeMethod('endSpeech');
    }

    await _eventListener?.cancel();
    _eventListener = null;
  }

  /// Recognizes speech from an audio file on the native platform.
  ///
  /// Processes a pre-recorded audio file and performs speech recognition.
  /// Results are delivered through the event channel and callback.
  ///
  /// Parameters:
  /// - [filePath]: The absolute path to the audio file to recognize.
  Future<void> recognizeAudio(String filePath) async {
    return await methodChannel.invokeMethod('recognizeAudio', filePath);
  }
}
