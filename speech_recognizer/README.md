# Speech Recognizer

An Spanish children's speech recognizer Flutter app for Android/iOS/MacOS. It will read buffer from microphone and recognize speaking words.

## Installation / Setup

- Install [Flutter SDK](https://docs.flutter.dev/get-started/install).
- Install [Visual Studio Code](https://code.visualstudio.com/).
- Open the project in Visual Studio Code, navigate to `lib/main.dart`.
- Launch an Android emulator or iOS simulator. Optionaly, you can also connect to a real device.
- Run the demo on Android/iOS/MacOS by going to the top navigation bar of VSCode, hit **Run**, then **Start Debugging**.

### Android

On Android, you will need to allow microphone permission in `AndroidManifest.xml` like so:

```xml
<uses-feature android:name="android.hardware.microphone" android:required="false"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

### iOS

Similarly on iOS/MacOS:

- Open Xcode
- Navigate to `Info.plist`
- Add microphone permission `NSMicrophoneUsageDescription`. You can follow this [guide](https://stackoverflow.com/a/38498347/719212).

### UI Automation Testing
- Follow [Installation / Setup](#installation--setup) guide
- Launch an Android emulator or iOS simulator
- Run `flutter test integration_test/app_test.dart`  

https://github.com/user-attachments/assets/46476c73-cfbb-442d-8e81-3199fe0f704d


## Architecture

This library uses **Flutter Platform Channels** to enable communication between Dart (Flutter) and native code (Android/iOS). The architecture follows a three-layer design:

### 1. Flutter Layer (Dart)

The Flutter layer provides a high-level API through the `SpeechController` class, which communicates with native platforms using:

- **Method Channel** (`com.bookbot/control`): For sending commands to native code
- **Event Channel** (`com.bookbot/event`): For receiving continuous speech recognition results

```dart
// Example: Flutter sends command to native platform
await methodChannel.invokeMethod('initSpeech', [language, profileId, wordMode]);

// Example: Flutter receives events from native platform
eventChannel.receiveBroadcastStream().listen((event) {
  final transcript = event['transcript'];
  final wasEndpoint = event['wasEndpoint'];
  // Process recognition results
});
```

### 2. Platform Channel Bridge

Platform channels act as a bridge between Flutter and native code:

| Channel Name | Type | Purpose |
|-------------|------|---------|
| `com.bookbot/control` | MethodChannel | Send commands (init, listen, stop, etc.) |
| `com.bookbot/event` | EventChannel | Receive recognition results continuously |
| `com.bookbot/levels` | EventChannel | Receive audio level updates |
| `com.bookbot/recognizer` | EventChannel | Receive recognizer running status |

### 3. Native Layer (Android/iOS)

#### Android Implementation (Kotlin)

The Android native code in `SpeechController.kt` handles:

1. **Microphone Permission Management**: Requests and checks `RECORD_AUDIO` permission
2. **Speech Recognition Service**: Integrates with Sherpa-ONNX ASR engine
3. **Audio Processing**: Captures audio from microphone using Android's audio APIs
4. **Real-time Recognition**: Processes audio buffers and sends results back to Flutter

```kotlin
// Android: Registering the plugin
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        speechController = SpeechController(this, lifecycle)
        flutterEngine.plugins.add(speechController)
    }
}

// Android: Handling method calls from Flutter
override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
        "initSpeech" -> initSpeech(call.arguments as List<String?>, result)
        "listen" -> startSpeech()
        "stopListening" -> stopSpeech()
        // ... other methods
    }
}

// Android: Sending results back to Flutter
override fun onSpeechResult(result: String, wasEndpoint: Boolean, ...) {
    eventSink?.success(hashMapOf(
        "transcript" to result,
        "wasEndpoint" to wasEndpoint,
        "isVoiceActive" to isVoiceActive
    ))
}
```

#### iOS Implementation (Swift)

The iOS native code in `SpeechController.swift` handles:

1. **Audio Session Management**: Configures `AVAudioSession` for recording
2. **Audio Engine**: Uses `AVAudioEngine` to capture microphone input
3. **Voice Activity Detection (VAD)**: Detects speech vs silence using Sherpa-ONNX VAD
4. **Speech Recognition**: Processes audio with Sherpa-ONNX ASR model

```swift
// iOS: Registering the plugin
public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
        name: "com.bookbot/control",
        binaryMessenger: messenger
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
    
    let eventChannel = FlutterEventChannel(
        name: "com.bookbot/event",
        binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(instance)
}

// iOS: Handling method calls from Flutter
public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initSpeech":
        initSpeech(profileId: profileId, language: language, ...)
    case "listen":
        startListening()
    case "stopListening":
        stopListening()
    // ... other methods
    }
}

// iOS: Processing audio buffers
engine.inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, _ in
    self.recognize(buffer: buffer)
}
```

### Speech Recognition Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter App (Dart)                        │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │          SpeechController.shared.listen()                 │  │
│  └───────────────────────┬───────────────────────────────────┘  │
└────────────────────────────┼─────────────────────────────────────┘
                             │ Method Channel
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Native Platform (Android/iOS)                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  1. Request Microphone Permission                         │  │
│  │  2. Initialize AVAudioEngine/AudioRecord                  │  │
│  │  3. Load Sherpa-ONNX ASR Model                           │  │
│  │  4. Start Capturing Audio (100ms buffers)                │  │
│  └───────────────────────┬───────────────────────────────────┘  │
│                          │                                       │
│  ┌───────────────────────▼───────────────────────────────────┐  │
│  │  Audio Buffer Processing:                                 │  │
│  │  • Convert to 16kHz PCM Float32                          │  │
│  │  • Run Voice Activity Detection (VAD)                    │  │
│  │  • Feed to Sherpa-ONNX Recognizer                        │  │
│  │  • Decode Speech → Text                                  │  │
│  └───────────────────────┬───────────────────────────────────┘  │
│                          │ Event Channel                        │
└────────────────────────────┼─────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Flutter App (Dart)                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Receive Results: { transcript, wasEndpoint, ... }        │  │
│  │  Update UI with recognized text                           │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Technical Details

1. **Audio Processing**:
   - Microphone captures raw audio at native sample rate (typically 48kHz)
   - Audio is resampled to 16kHz for ASR model compatibility
   - Buffer duration: 100ms for optimal latency

2. **Voice Activity Detection (VAD)**:
   - Uses Silero VAD model with 25ms window size
   - Detects speech/silence patterns: `[silence][speech][silence]`
   - Patience counters prevent false endpoint detection

3. **Recognition Modes**:
   - **Phoneme Mode**: Returns phonetic tokens for pronunciation analysis
   - **Word Mode**: Returns complete words for text transcription

4. **Thread Safety**:
   - Android: Uses coroutines and synchronized blocks
   - iOS: Uses dedicated DispatchQueues for recognition, audio, and level processing