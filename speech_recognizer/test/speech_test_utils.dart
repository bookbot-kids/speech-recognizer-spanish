import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async => '/tmp/speech-recognizer-test';
}

class SpeechChannelHarness {
  static const controlChannel = MethodChannel('com.bookbot/control');
  static const eventChannelName = 'com.bookbot/event';
  static const eventCodec = StandardMethodCodec();

  final controlCalls = <MethodCall>[];
  final eventCalls = <MethodCall>[];
  String audioPermission = 'authorized';
  Object? authorizeError;

  void install() {
    PathProviderPlatform.instance = FakePathProviderPlatform();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, (methodCall) async {
          controlCalls.add(methodCall);

          if (methodCall.method == 'authorize' && authorizeError != null) {
            final error = authorizeError!;
            if (error is PlatformException) {
              throw error;
            }
            throw PlatformException(code: 'authorize_error', message: '$error');
          }

          if (methodCall.method == 'audioPermission') {
            return audioPermission;
          }

          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannelName, (message) async {
          final methodCall = eventCodec.decodeMethodCall(message);
          eventCalls.add(methodCall);
          return eventCodec.encodeSuccessEnvelope(null);
        });
  }

  Future<void> emitRecognizerEvent({
    required String transcript,
    bool wasEndpoint = false,
    bool resetEndPos = false,
    bool isVoiceActive = true,
    bool isNoSpeech = false,
  }) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          eventChannelName,
          eventCodec.encodeSuccessEnvelope({
            'transcript': transcript,
            'wasEndpoint': wasEndpoint,
            'resetEndPos': resetEndPos,
            'isVoiceActive': isVoiceActive,
            'isNoSpeech': isNoSpeech,
          }),
          (_) {},
        );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(controlChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(eventChannelName, null);
  }

  List<MethodCall> callsFor(String method) =>
      controlCalls.where((call) => call.method == method).toList();
}
