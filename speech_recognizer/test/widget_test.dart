import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:speech_recognizer/main.dart';
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

  testWidgets('Demo app renders speech recognizer controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(isTesting: true));

    expect(find.text('Demo speech recognize'), findsOneWidget);
    expect(find.byKey(const ValueKey('loadModel')), findsOneWidget);
    expect(find.byKey(const ValueKey('recognizeAudio')), findsOneWidget);
    expect(find.text('Load model'), findsOneWidget);
    expect(find.text('Start listening'), findsOneWidget);
    expect(find.text('Stop listening'), findsOneWidget);
    expect(find.text('Recgonize audio file'), findsOneWidget);

    final startButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Start listening'),
    );
    final stopButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Stop listening'),
    );
    final recognizeButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Recgonize audio file'),
    );

    expect(startButton.onPressed, isNull);
    expect(stopButton.onPressed, isNull);
    expect(recognizeButton.onPressed, isNull);
  });

  testWidgets('Load model initializes recognizer and updates button states', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(isTesting: true));

    await tester.tap(find.byKey(const ValueKey('loadModel')));
    await tester.pumpAndSettle();

    expect(harness.callsFor('initSpeech'), hasLength(1));
    expect(harness.callsFor('initSpeech').single.arguments, [
      'es',
      'demo',
      'false',
    ]);
    expect(SpeechController.shared.listeners, hasLength(1));

    final loadButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Load model'),
    );
    final startButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Start listening'),
    );
    final stopButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Stop listening'),
    );
    final recognizeButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Recgonize audio file'),
    );

    expect(loadButton.onPressed, isNull);
    expect(recognizeButton.onPressed, isNotNull);
    if (Platform.isIOS || Platform.isMacOS) {
      expect(startButton.onPressed, isNull);
      expect(stopButton.onPressed, isNotNull);
      expect(harness.callsFor('flushSpeech'), hasLength(1));
      expect(harness.callsFor('listen'), hasLength(1));
    } else {
      expect(startButton.onPressed, isNotNull);
      expect(stopButton.onPressed, isNull);
      expect(harness.callsFor('flushSpeech'), isEmpty);
      expect(harness.callsFor('listen'), isEmpty);
    }
  });

  testWidgets('Start and stop listening dispatch native commands', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(isTesting: true));
    await tester.tap(find.byKey(const ValueKey('loadModel')));
    await tester.pumpAndSettle();

    if (!(Platform.isIOS || Platform.isMacOS)) {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Start listening'));
      await tester.pumpAndSettle();
    }

    expect(harness.callsFor('flushSpeech'), hasLength(1));
    expect(harness.callsFor('listen'), hasLength(1));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Stop listening'));
    await tester.pumpAndSettle();

    expect(harness.callsFor('stopListening'), hasLength(1));

    final startButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Start listening'),
    );
    final stopButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Stop listening'),
    );
    expect(startButton.onPressed, isNotNull);
    expect(stopButton.onPressed, isNull);
  });

  testWidgets('Recognize audio button dispatches sample asset path', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(isTesting: true));
    await tester.tap(find.byKey(const ValueKey('loadModel')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('recognizeAudio')));
    await tester.pumpAndSettle();

    expect(harness.callsFor('recognizeAudio'), hasLength(1));
    expect(
      harness.callsFor('recognizeAudio').single.arguments,
      'assets/sample.wav',
    );
  });

  testWidgets('Recognizer events render decoded transcript text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(isTesting: true));
    await tester.tap(find.byKey(const ValueKey('loadModel')));
    await tester.pumpAndSettle();

    await harness.emitRecognizerEvent(transcript: 'hola mundo');
    await tester.pump();

    expect(find.text('hola mundo'), findsOneWidget);
  });
}
