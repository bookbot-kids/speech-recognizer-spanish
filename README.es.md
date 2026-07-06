🌐 [English](README.md) • **Español**

# Inicio

## Reconocedor Fonémico de Habla en Español

<p align="center">
    <a href="https://github.com/bookbot-kids/speech-recognizer-spanish/blob/main/LICENSE.md">
        <img alt="GitHub" src="https://img.shields.io/github/license/bookbot-kids/speech-recognizer-spanish.svg?color=blue">
    </a>
    <a href="https://bookbot-kids.github.io/speech-recognizer-spanish/">
        <img alt="Documentation" src="https://img.shields.io/website/http/bookbot-kids.github.io/speech-recognizer-spanish.svg?down_color=red&down_message=offline&up_message=online">
    </a>
    <a href="https://github.com/bookbot-kids/speech-recognizer-spanish/blob/main/CODE_OF_CONDUCT.md">
        <img alt="Contributor Covenant" src="https://img.shields.io/badge/Contributor%20Covenant-v2.0%20adopted-ff69b4.svg">
    </a>
    <a href="https://discord.gg/gqwTPyPxa6">
        <img alt="chat on Discord" src="https://img.shields.io/discord/1001447685645148169?logo=discord">
    </a>
    <a href="https://github.com/bookbot-kids/speech-recognizer-spanish/blob/main/CONTRIBUTING.md">
        <img alt="contributing guidelines" src="https://img.shields.io/badge/contributing-guidelines-brightgreen">
    </a>
</p>

Una biblioteca multiplataforma (Android/iOS/MacOS) de reconocimiento fonémico de habla en español, escrita en Flutter y que aprovecha el framework Kaldi. La biblioteca de reconocimiento de habla lee un búfer desde un micrófono y convierte las palabras habladas en fonemas con un tiempo de inferencia casi instantáneo y alta precisión. ¡Esta biblioteca también es extensible a tu propio modelo personalizado de reconocimiento de habla!

## Características

- Reconocimiento de voz a texto en español mediante un modelo de reconocimiento automático de habla (ASR) basado en Kaldi.
- Integra el modelo de habla a fonema con aplicaciones móviles y de escritorio.

## Instalación / Configuración

- Instala el [SDK de Flutter](https://docs.flutter.dev/get-started/install).
- Instala [Visual Studio Code](https://code.visualstudio.com/).
- Abre el proyecto en Visual Studio Code y navega a `lib/main.dart`.
- Inicia un emulador de Android o un simulador de iOS. Opcionalmente, también puedes conectar un dispositivo real.
- Ejecuta la demo en Android/iOS/MacOS yendo a la barra de navegación superior de VSCode, presiona **Run** y luego **Start Debugging**.

### Android

En Android, deberás permitir el permiso del micrófono en `AndroidManifest.xml` de la siguiente manera:

```xml
<uses-feature android:name="android.hardware.microphone" android:required="false"/>
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
```

### iOS

De forma similar en iOS/MacOS:

- Abre Xcode
- Navega a `Info.plist`
- Agrega el permiso del micrófono `NSMicrophoneUsageDescription`. Puedes seguir esta [guía](https://stackoverflow.com/a/38498347/719212).

## Cómo Usar

### Aplicación de Ejemplo en Flutter

- Después de la configuración, ejecuta la aplicación presionando el botón `Load model` y luego `Start listening`.
- Habla al micrófono y el texto de salida correspondiente se mostrará en el campo de texto.
- Presiona `Stop listening` para que la aplicación deje de escuchar.

```dart title="main.dart"
import 'package:speech_recognizer/speech_recognizer.dart';

class _MyHomePageState implements SpeechListener { // (1)
  final recognizer = SpeechController.shared;

  void _load() async {
    // ask for permission
    final permissions = await SpeechController.shared.permissions(); // (2)
    if (permissions == AudioSpeechPermission.undetermined) {
      await SpeechController.shared.authorize();
    }

    if (await SpeechController.shared.permissions() !=
        AudioSpeechPermission.authorized) {
      return;
    }

    if (!_isInitialized) {
      await SpeechController.shared.initSpeech('id'); // (3)
      setState(() {
        _isInitialized = true;
      });

      SpeechController.shared.addListener(this); // (4)
    }
  }

  /// listen to speech events and print result in UI
  void onResult(
    String transcript, bool wasEndpoint, bool resetEndPos,
    bool isVoiceActive, bool isNoSpeech) {
    if (transcript.isEmpty) {
      return;
    }
    
    print(transcript);
    setState(() {
      _decoded.insert(0, transcript);
    });
  }
}
```

1. Configura el listener implementando `SpeechListener` en tu clase.
2. Solicita el permiso de grabación.
3. Inicializa el modelo de reconocimiento en español.
4. Registra el listener en esta clase.
5. Listener de texto de salida mientras se habla.
6. Resultado normalizado.

<!-- TODO: add other platforms -->

## Arquitectura

Esta biblioteca usa **Flutter Platform Channels** para permitir la comunicación entre Dart (Flutter) y el código nativo (Android/iOS). La arquitectura sigue un diseño de tres capas:

### 1. Capa de Flutter (Dart)

La capa de Flutter proporciona una API de alto nivel a través de la clase `SpeechController`, que se comunica con las plataformas nativas usando:

- **Method Channel** (`com.bookbot/control`): Para enviar comandos al código nativo.
- **Event Channel** (`com.bookbot/event`): Para recibir resultados continuos del reconocimiento de habla.

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

### 2. Puente de Platform Channel

Los platform channels actúan como un puente entre Flutter y el código nativo:

| Nombre del Canal | Tipo | Propósito |
|-------------|------|---------|
| `com.bookbot/control` | MethodChannel | Enviar comandos (init, listen, stop, etc.) |
| `com.bookbot/event` | EventChannel | Recibir resultados de reconocimiento continuamente |
| `com.bookbot/levels` | EventChannel | Recibir actualizaciones del nivel de audio |
| `com.bookbot/recognizer` | EventChannel | Recibir el estado de ejecución del reconocedor |

### 3. Capa Nativa (Android/iOS)

#### Implementación en Android (Kotlin)

El código nativo de Android en `SpeechController.kt` gestiona:

1. **Gestión de Permisos del Micrófono**: Solicita y verifica el permiso `RECORD_AUDIO`.
2. **Servicio de Reconocimiento de Habla**: Se integra con el motor ASR Sherpa-ONNX.
3. **Procesamiento de Audio**: Captura audio del micrófono usando las APIs de audio de Android.
4. **Reconocimiento en Tiempo Real**: Procesa búferes de audio y envía los resultados de vuelta a Flutter.

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

#### Implementación en iOS (Swift)

El código nativo de iOS en `SpeechController.swift` gestiona:

1. **Gestión de la Sesión de Audio**: Configura `AVAudioSession` para la grabación.
2. **Motor de Audio**: Usa `AVAudioEngine` para capturar la entrada del micrófono.
3. **Detección de Actividad de Voz (VAD)**: Detecta habla frente a silencio usando el VAD de Sherpa-ONNX.
4. **Reconocimiento de Habla**: Procesa el audio con el modelo ASR de Sherpa-ONNX.

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

### Flujo de Reconocimiento de Habla

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
│  │  2. Initialise AVAudioEngine/AudioRecord                  │  │
│  │  3. Load Sherpa-ONNX ASR Model                           │  │
│  │  4. Start Capturing Audio (100ms buffers)                │  │
│  └───────────────────────┬───────────────────────────────────┘  │
│                          │                                       │
│  ┌───────────────────────▼───────────────────────────────────┐  │
│  │  Audio Buffer Processing:                                 │  │
│  │  • Convert to 16kHz PCM Float32                          │  │
│  │  • Run Voice Activity Detection (VAD)                    │  │
│  │  • Feed to Sherpa-ONNX Recogniser                        │  │
│  │  • Decode Speech → Text                                  │  │
│  └───────────────────────┬───────────────────────────────────┘  │
│                          │ Event Channel                        │
└────────────────────────────┼─────────────────────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Flutter App (Dart)                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Receive Results: { transcript, wasEndpoint, ... }        │  │
│  │  Update UI with recognised text                           │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Detalles Técnicos Clave

1. **Procesamiento de Audio**:
   - El micrófono captura audio sin procesar a la frecuencia de muestreo nativa (típicamente 48kHz).
   - El audio se remuestrea a 16kHz para compatibilidad con el modelo ASR.
   - Duración del búfer: 100ms para una latencia óptima.

2. **Detección de Actividad de Voz (VAD)**:
   - Usa el modelo Silero VAD con un tamaño de ventana de 25ms.
   - Detecta patrones de habla/silencio: `[silencio][habla][silencio]`.
   - Los contadores de paciencia evitan la detección falsa de endpoints.

3. **Modos de Reconocimiento**:
   - **Modo Fonema**: Devuelve tokens fonéticos para el análisis de la pronunciación.
   - **Modo Palabra**: Devuelve palabras completas para la transcripción de texto.

4. **Seguridad de Hilos**:
   - Android: Usa corrutinas y bloques sincronizados.
   - iOS: Usa `DispatchQueue` dedicadas para el reconocimiento, el audio y el procesamiento de niveles.

## Estructura de Archivos

| Plataforma    | Código                                                                                                                                                                                                 | Función                                                                                                                                                       |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Flutter       | [`speech_recognizer.dart`](https://github.com/bookbot-kids/speech-recognizer-spanish/blob/main/speech_recognizer/lib/speech_recognizer.dart)                                                 | API de interfaz para comunicarse con la plataforma nativa (Android/iOS/Mac). Hay muchos métodos del reconocedor de habla; revisa `lib/main.dart` para saber cómo usarlos. |
| Todas las Plataformas | [`asr/es`](https://github.com/bookbot-kids/speech-recognizer-spanish/tree/main/speech_recognizer/android/app/src/main/assets/asr/es)                                            | Modelo de habla compartido para todas las plataformas. 
| iOS/MacOS     | [`SpeechController.swift`](https://github.com/bookbot-kids/speech-recognizer-spanish/blob/main/speech_recognizer/ios/Runner/SpeechController.swift)                                               | Platform channel nativo para el reconocedor de habla en iOS/MacOS. Usa [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) con un modelo personalizado.                           |
| Android       | [`SpeechController.kt`](https://github.com/bookbot-kids/speech-recognizer-spanish/blob/main/speech_recognizer/android/app/src/main/kotlin/com/bookbot/SpeechController.kt) | Platform channel nativo para el reconocedor de habla en Android. Usa [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) con un modelo personalizado.                             |

## Pruebas de Automatización de UI
- Sigue la guía de [Instalación / Configuración](#instalación--configuración)
- Inicia un emulador de Android o un simulador de iOS
- Ejecuta `flutter test integration_test/app_test.dart`  

https://github.com/user-attachments/assets/46476c73-cfbb-442d-8e81-3199fe0f704d

## Enlaces y Recursos Útiles

- [Documentación para desarrolladores de Flutter](https://docs.flutter.dev/)
- [Documentación para desarrolladores de Android](https://developer.android.com/docs)
- [Documentación para desarrolladores de iOS/MacOS](https://developer.apple.com/documentation/)

## Contribuidores

<a href="https://github.com/bookbot-kids/speech-recognizer-spanish/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=bookbot-kids/speech-recognizer-spanish" />
</a>

## Créditos

[Sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)
[Onnxruntime](https://github.com/microsoft/onnxruntime)
</content>
</invoke>
