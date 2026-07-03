import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_recognizer/speech_recognizer.dart';

import 'speech_test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpeechChannelHarness harness;

  setUp(() {
    SpeechController.resetSharedForTesting();
    harness = SpeechChannelHarness()..install();
  });

  tearDown(() {
    harness.uninstall();
    SpeechController.resetSharedForTesting();
  });

  group('SpeechController permissions', () {
    test('maps native permission strings to enum values', () async {
      final cases = {
        'undetermined': AudioSpeechPermission.undetermined,
        'denied': AudioSpeechPermission.denied,
        'authorized': AudioSpeechPermission.authorized,
        'unexpected': AudioSpeechPermission.unknown,
      };

      for (final entry in cases.entries) {
        harness.audioPermission = entry.key;

        expect(await SpeechController.shared.permissions(), entry.value);
      }

      expect(harness.callsFor('audioPermission'), hasLength(cases.length));
    });

    test('authorize swallows native errors after logging them', () async {
      harness.authorizeError = PlatformException(
        code: 'denied',
        message: 'Microphone unavailable',
      );

      await expectLater(SpeechController.shared.authorize(), completes);

      expect(harness.callsFor('authorize'), hasLength(1));
    });
  });

  group('SpeechController method channel commands', () {
    test(
      'dispatches listen, stop, reset, recognizeAudio, and initSpeech',
      () async {
        await SpeechController.shared.listen();
        await SpeechController.shared.stopListening();
        await SpeechController.shared.resetSpeech();
        await SpeechController.shared.recognizeAudio('/tmp/sample.wav');
        await SpeechController.shared.initSpeech(
          language: 'es',
          wordMode: true,
        );

        expect(harness.controlCalls.map((call) => call.method), [
          'listen',
          'stopListening',
          'resetSpeech',
          'recognizeAudio',
          'initSpeech',
        ]);
        expect(harness.controlCalls[0].arguments, ['false']);
        expect(harness.controlCalls[3].arguments, '/tmp/sample.wav');
        expect(harness.controlCalls[4].arguments, ['es', 'demo', 'true']);
        expect(harness.eventCalls.single.method, 'listen');
      },
    );

    test(
      'flushSpeech queues work with text, grammar, and temp directory',
      () async {
        await Future.wait([
          SpeechController.shared.flushSpeech(toRead: 'hola', grammar: 'hola'),
          SpeechController.shared.flushSpeech(toRead: 'adios'),
        ]);

        final flushCalls = harness.callsFor('flushSpeech');
        expect(flushCalls, hasLength(2));
        expect(flushCalls[0].arguments, [
          'hola',
          'hola',
          '/tmp/speech-recognizer-test',
        ]);
        expect(flushCalls[1].arguments, [
          'adios',
          null,
          '/tmp/speech-recognizer-test',
        ]);
      },
    );

    test(
      'init performs authorization, permission check, init, and listen',
      () async {
        await SpeechController.shared.init();
        await Future<void>.delayed(Duration.zero);

        expect(harness.controlCalls.map((call) => call.method), [
          'authorize',
          'audioPermission',
          'initSpeech',
          'listen',
        ]);
        expect(harness.controlCalls[2].arguments, ['es', 'demo', 'false']);
        expect(harness.controlCalls[3].arguments, ['false']);
      },
    );
  });

  group('SpeechController listeners', () {
    test('adds each listener once and removes it', () {
      void listener(
        String transcript,
        bool wasEndpoint,
        bool resetEndPos,
        bool isVoiceActive,
        bool isNoSpeech,
      ) {}

      SpeechController.shared.addListener(listener);
      SpeechController.shared.addListener(listener);

      expect(SpeechController.shared.listeners, [listener]);

      SpeechController.shared.removeListener(listener);

      expect(SpeechController.shared.listeners, isEmpty);
    });

    test(
      'delivers event channel results to the latest speech callback',
      () async {
        final received = <Object?>[];

        SpeechController.shared.addListener((
          transcript,
          wasEndpoint,
          resetEndPos,
          isVoiceActive,
          isNoSpeech,
        ) {
          received.addAll([
            transcript,
            wasEndpoint,
            resetEndPos,
            isVoiceActive,
            isNoSpeech,
          ]);
        });
        await SpeechController.shared.initSpeech(language: 'es');

        await harness.emitRecognizerEvent(
          transcript: 'hola',
          wasEndpoint: true,
          resetEndPos: true,
          isVoiceActive: false,
          isNoSpeech: true,
        );

        expect(received, ['hola', true, true, false, true]);
      },
    );
  });
}
