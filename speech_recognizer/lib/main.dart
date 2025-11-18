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

import 'package:flutter/material.dart';
import 'package:speech_recognizer/app.dart';
import 'package:speech_recognizer/speech_recognizer.dart';

void main() {
  runApp(const MyApp());
}

/// The main application
class MyApp extends StatelessWidget {
  final bool isTesting;
  const MyApp({super.key, this.isTesting = false});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Demo speech recognize',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: MyHomePage(title: 'Demo speech recognize', isTesting: isTesting),
    );
  }
}

/// The home page of the application
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title, this.isTesting = false});
  final String title;
  final bool isTesting;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  var _isInitialized = false;
  var _listening = false;
  final _decoded = <String>[];
  static const _audioPath = 'assets/sample.wav';

  /// listen to speech events and print result in UI
  void onResult(
    String transcript,
    bool wasEndpoint,
    bool resetEndPos,
    bool isVoiceActive,
    bool isNoSpeech,
  ) {
    if (transcript.isEmpty) {
      return;
    }
    // ignore: avoid_print
    print(transcript);
    setState(() {
      _decoded.insert(0, transcript);
    });
  }

  /// Loads the speech recognition model
  void _load() async {
    if (!widget.isTesting) {
      // ask for permission
      final permissions = await SpeechController.shared.permissions();
      if (permissions == AudioSpeechPermission.undetermined) {
        await SpeechController.shared.authorize();
      }

      if (await SpeechController.shared.permissions() !=
          AudioSpeechPermission.authorized) {
        return;
      }
    }

    if (!_isInitialized) {
      await SpeechController.shared.initSpeech(language: AppConfigs.language);
      setState(() {
        _isInitialized = true;
      });

      SpeechController.shared.addListener(onResult);
    }
  }

  Future<void> _recognizeAudio() async {
    await SpeechController.shared.recognizeAudio(_audioPath);
  }

  /// Initialize the speech recognizer and start listening
  Future<void> _recognize() async {
    await SpeechController.shared.flushSpeech();
    await SpeechController.shared.listen();
    setState(() {
      _listening = true;
    });
  }

  /// Stop the speech recognizer
  Future<void> _stopRecognize() async {
    if (_isInitialized) {
      await SpeechController.shared.stopListening();

      setState(() {
        _listening = false;
      });
    }
  }

  @override
  void dispose() {
    _stopRecognize();
    SpeechController.shared.removeListener(onResult);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              height: 300,
              width: double.infinity,
              color: Colors.grey.withValues(alpha: 0.2),
              child: _decoded.isEmpty
                  ? Container()
                  : SingleChildScrollView(
                      child: Column(
                        children: _decoded.map((d) => Text(d)).toList(),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              key: const ValueKey('loadModel'),
              onPressed: !_isInitialized ? _load : null,
              child: const Text('Load model'),
            ),
            ElevatedButton(
              onPressed: _isInitialized && !_listening ? _recognize : null,
              child: const Text('Start listening'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _listening ? _stopRecognize : null,
              child: const Text('Stop listening'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              key: const ValueKey('recognizeAudio'),
              onPressed: _isInitialized ? _recognizeAudio : null,
              child: const Text('Recgonize audio file'),
            ),
          ],
        ),
      ),
    );
  }
}
