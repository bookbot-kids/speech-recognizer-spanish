package com.bookbot.speech_recognizer

import android.os.Bundle
import com.bookbot.SpeechController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import timber.log.Timber

class MainActivity : FlutterActivity() {
    private lateinit var speechController: SpeechController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val debugTree = object: Timber.DebugTree() {
            override fun log(
                priority: Int, tag: String?, message: String, t: Throwable?
            ) {
                super.log(priority, "Bookbot_$tag", message, t)
            }
        }
        Timber.plant(debugTree)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Timber.d("called configureFlutterEngine")
        speechController = SpeechController(this, lifecycle)
        lifecycle.addObserver(speechController)
        flutterEngine.plugins.add(speechController)
    }
}
