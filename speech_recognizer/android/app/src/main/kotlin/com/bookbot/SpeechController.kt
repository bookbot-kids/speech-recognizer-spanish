@file:Suppress("DEPRECATION")

package com.bookbot

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleObserver
import androidx.lifecycle.LifecycleOwner
import com.bookbot.audio.MicrophoneRecorder
import com.bookbot.service.SpeechCallback
import com.bookbot.service.SpeechService
import com.bookbot.service.SpeechServiceImpl
import com.bookbot.utils.MethodResultWrapper
import com.google.android.exoplayer2.ExoPlayer
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber

@Suppress("DEPRECATION")
class SpeechController(context: Activity, private val lifecycle: Lifecycle): FlutterPlugin, MethodChannel.MethodCallHandler,
        PluginRegistry.RequestPermissionsResultListener, LifecycleObserver, SpeechCallback, ActivityAware, DefaultLifecycleObserver {
    
    private val methodChannel = "com.bookbot/control"
    
    private val eventChannelName = "com.bookbot/event"
    private var eventSink: EventChannel.EventSink? = null
    
    private val permissionRequestCode = 1

    private val recognizerRunningChannelName = "com.bookbot/recognizer"
    private var recognizerRunningEventSink : EventChannel.EventSink? = null
    
    private val levelsChannelName = "com.bookbot/levels"
    private var levelsEventSink : EventChannel.EventSink? = null

    private val measureChannelName = "com.bookbot/measure"
    private var measureEventSink : EventChannel.EventSink? = null
    private lateinit var measureChannel: EventChannel
    
    private var _listen = false

    private var authorizeMethodResult: MethodChannel.Result? = null
    
    private var speechRecognitionService: SpeechService? = null
    private var speechRecognitionLanguage : String? = null
    private lateinit var channel : MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var recognizerRunningChannel: EventChannel
    private lateinit var levelsChannel: EventChannel
    private var currentActivity: Activity? = context
    private val mainHandler = Handler(Looper.getMainLooper())
    private var wasListening = false
    private var profileId:String? = null
    private var lock = Object()
    private var endedSpeech = false
    @Volatile var isPlayingBuffer = false

    private var currentLanguage = "es"

    private fun createExoplayer(context: Activity): ExoPlayer {
        return ExoPlayer.Builder(context).build()
    }

    // 
    /// The recorder that will be used to write the transcript and microphone data to local files,
    /// then encode once stopListening/unmute is called.
    /// This is only created when initSpeech is called with a profileId that is non-null, 
    /// so you will need to check that this actually exists before invoking any methods here.
    ///
    private var recorder: MicrophoneRecorder? = null

    ///
    /// The grammar passed to the recognizer. Usually a superset of [expectedSpeech].
    ///
    private var grammar:String? = null

    @Volatile private var soundNodeIsPlaying = false
    @Volatile private var soundNode2IsPlaying = false
    @Volatile private var voiceNodeIsPlaying = false
//    @Volatile private var loopNodeIsPlaying = false

    private val isPlayingAudio: Boolean
        get() = soundNodeIsPlaying || soundNode2IsPlaying || voiceNodeIsPlaying || isPlayingBuffer

    fun pauseOrResume(isPaused: Boolean) {
        if(isPaused) {
            speechRecognitionService?.pause()
        } else {
            speechRecognitionService?.resume()
        }
    }

    private var listen: Boolean
        get() = _listen
        set(value) {
            _listen = value
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, methodChannel)
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, eventChannelName)
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {}
        })

        recognizerRunningChannel = EventChannel(binding.binaryMessenger, recognizerRunningChannelName)
        recognizerRunningChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                recognizerRunningEventSink = events
            }

            override fun onCancel(arguments: Any?) {

            }
        })

        levelsChannel = EventChannel(binding.binaryMessenger, levelsChannelName)
        levelsChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                levelsEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                levelsEventSink = null
            }
        })

        measureChannel = EventChannel(binding.binaryMessenger, measureChannelName)
        measureChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                measureEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                measureEventSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        levelsEventSink = null
        recognizerRunningEventSink = null
        eventSink = null
        measureEventSink = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if(requestCode == permissionRequestCode) {
            if(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                authorizeMethodResult?.success("authorized")
            } else {
                authorizeMethodResult?.success("denied")
            }

            authorizeMethodResult = null
        }

        return false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        currentActivity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        currentActivity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        currentActivity = null
    }

    @Suppress("UNCHECKED_CAST")
    override fun onMethodCall(call: MethodCall, methodResult: MethodChannel.Result) {
        Timber.i("call method ${call.method} with argument ${call.arguments}")
        val result = MethodResultWrapper(methodResult)
        when (call.method) {
            "audioPermission" -> audioPermission(result)
            "authorize" -> authorize(result)
            "initSpeech" -> initSpeech(call.arguments as List<String?>, result)
            "destroyRecognizer" -> {
                speechRecognitionService?.destroyRecognizer()
                result.success(null)
            }
            "listen" -> {
                listen = true
                endedSpeech = false
                startSpeech()
                result.success(null)
            }
            "stopListening" -> {
                listen = false
                stopSpeech()
                result.success(null)
            }
            "mute" -> {
                listen = false
                stopSpeech()
                result.success(null)
            }
            "unmute" -> {
                listen = true
                startSpeech()
                result.success(null)
            }
            "flushSpeech" -> {
                endedSpeech = false
                // when flushSpeech is called, a String is passed containing the text of what we expect to hear from the user next
                val args = call.arguments as ArrayList<Any?>
                val transcript = args[0] as String?
                val grammarParam = args[1] as String?
                grammar = grammarParam
                Timber.d("flushSpeech with transcript $transcript grammar $grammar")
                flushSpeech(transcript ?: "")
                result.success(null)
            }
            "endSpeech" -> endSpeech(result)
            "resetSpeech" -> resetSpeech(result)
            "setContextBiasing" -> {
                val args = call.arguments as String
                grammar = args
                setContextBiasing(grammar, result)
            }
            "recognizeAudio" -> {
                val path = call.arguments as String
                recognizeAudio(path, result)
            }
            else -> result.notImplemented()
        }
    }

    private fun recognizeAudio(path: String, result: MethodChannel.Result){
        CoroutineScope(Dispatchers.IO).launch {
            val loader = FlutterInjector.instance().flutterLoader()
            val stream = currentActivity?.assets?.open(loader.getLookupKeyForAsset(path))
            if(stream != null) {
                Timber.d("recognizeAudio read asset $path, stream")
                speechRecognitionService?.recognizeAudio(stream)
            }
            withContext(Dispatchers.Main) {
                result.success(null)
            }
        }
    }

    private fun setContextBiasing(hotWords: String?, result: MethodChannel.Result) {
        speechRecognitionService?.setContextBiasing(hotWords)
        result.success(null)
    }

    private fun resetSpeech(result: MethodChannel.Result) {
        speechRecognitionService?.reset()
        result.success(null)
    }

    /// 
    /// Synchronously stops speech recognition (and the microphone recorder), then asynchronously starts speech recognition half a second later.
    /// This effectively resets the Vosk speech recognition buffer, so should be used whenever you expect an utterance to have completed, and want to decode a new utterance.
    /// IMPORTANT - this is not synchronized, and may cause concurrency issues when interleaved with calls to [startSpeech].
    /// TODO - there needs to be some app-side mechanism to ensure that flushSpeech is not called prior to [startSpeech] completing (see [startSpeech])
    ///
    private fun flushSpeech(newTranscript: String) {
        if(speechRecognitionService == null) {
            Timber.d("speechRecognitionService is null, ignoring call to flushSpeech");
            return
        }

        if(speechRecognitionService?.isRunning != true) {
            Timber.d("speechRecognitionService is not running")
        }

        stopSpeech()
        Thread {
            Timber.d("flushSpeech stopSpeech")
            checkToRunFlushRecorder(newTranscript)
        }.start()
    }

    private fun checkToRunFlushRecorder(newTranscript: String) {
        while(isPlayingAudio) {
//            Timber.d("checkToRunFlushRecorder begin")
            Thread.sleep(100)
            if(endedSpeech) {
//                Timber.d("checkToRunFlushRecorder end")
                break
            }
        }

        if(!endedSpeech) {
            startSpeech()
        }

        recorder?.flushSpeech(newTranscript)
    }

    private fun audioPermission(result: MethodChannel.Result) {
        currentActivity?.let {
            if(ContextCompat.checkSelfPermission(it, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                result.success("undetermined")
            } else {
                result.success("authorized")
            }
        } ?: run {
            result.success("undetermined")
        }
    }

    private fun authorize(result: MethodChannel.Result) {
        if(authorizeMethodResult != null) return
        currentActivity?.let {
            authorizeMethodResult = result
            ActivityCompat.requestPermissions(it, arrayOf(Manifest.permission.RECORD_AUDIO), permissionRequestCode)
        }
    }

    /// 
    /// Unpacks/loads the acoustic/language model into the Kaldi service and, if a profile ID is specified, creates a recorder to store/encode audio from the microphone.
    /// This does not actually start speech recognition - [startSpeech] must be called before doing so.
    /// Invoked on a background thread as moving the files around can take some time.
    ///
    private fun initSpeech(args: List<String?>, result: MethodChannel.Result?) {
        Thread {
            currentActivity?.let { activity ->
                synchronized(lock) {
                    endedSpeech = false
                    val asrLanguage = args[0] ?: ""
                    val profileId: String? = args[1]
                    val wordMode : Boolean = args[2] == "true"
                    currentLanguage = asrLanguage

                    if(speechRecognitionService == null || profileId != this.profileId || asrLanguage != this.speechRecognitionLanguage) {
                        Timber.d("Recreating speechRecognitionService for profileId $profileId, wordMode $wordMode and language $asrLanguage")
                        this.profileId = profileId;
                        // If a profile ID is provided, we pass exposeAudio as true when creating the SpeechServiceImpl and pass its buffer to a MicrophoneRecorder instance
                        speechRecognitionService?.destroy()
                        speechRecognitionService = SpeechServiceImpl(activity, asrLanguage, { recognizerRunning:Boolean ->
                            mainHandler.post {
                                recognizerRunningEventSink?.success(recognizerRunning)
                            }
                        }, {
                            // Timber.d("audio status: $listen, $soundNodeIsPlaying, $voiceNodeIsPlaying, $isPlayingBuffer")
                            return@SpeechServiceImpl isPlayingAudio || !listen
                        }, { level:Double ->
                            mainHandler.post {
                                levelsEventSink?.success(level)
                            }
                        })
                        speechRecognitionService?.wordMode = wordMode
                        speechRecognitionLanguage = asrLanguage
                        speechRecognitionService?.initSpeech(this)

                    } else {
                        speechRecognitionService?.wordMode = wordMode
                        speechRecognitionLanguage = asrLanguage
                        speechRecognitionService?.initSpeech(this)
                        Timber.d("SpeechRecognitionService already exists for this language and profile ID, skipping re-creation")
                    }

                    if (profileId != null) {
                        val saveDir = activity.filesDir.path
                        if(recorder == null || recorder?.recordingId != profileId || recorder?.saveDir != saveDir) {
                            Timber.d("Creating recorder for profileId $profileId, ${recorder?.recordingId} and saveDir $saveDir ${recorder?.saveDir}")
                            recorder = MicrophoneRecorder(profileId, saveDir, activity.cacheDir)
                        }
                    } else {
                        recorder = null
                    }

                    speechRecognitionService?.microphoneRecorder = recorder
                    Timber.d("Speech recognition initialization complete.")
                }
            }

            mainHandler.post {
                result?.success(null)
            }
        }.start()
    }

    /// 
    /// (Asynchronously) starts speech recognition, meaning this will return prior to the Recognizer (and the audio recording thread on which it runs) becoming ready.
    /// If you need to ensure that these have been started, listen for an event sent via [recognizerRunningEventSink] (see recognizerRunning in initSpeech above).
    ///
    private fun startSpeech() {
        if(speechRecognitionService == null) {
            Timber.i("speechRecognitionService is null, startSpeech is a no-op")
        }
        synchronized(lock) {
            speechRecognitionService?.start(grammar)
        }
    }

    /// 
    /// (Synchronously) stops speech recognition. 
    ///
    private fun stopSpeech() {
        if(speechRecognitionService == null) {
            Timber.i("speechRecognitionService is null, stopSpeech is a no-op")
        }
        speechRecognitionService?.stop(true)
    }

    /// 
    /// (Synchronously) stops speech recognition and tears down the underlying service (i.e. unloads the model from memory).
    ///
    private fun endSpeech(result: MethodChannel.Result) {
        Timber.d("endSpeech")
        endedSpeech = true
        // TODO don't release the speech service to avoid crash atm
//        speechRecognitionService?.destroy()
//        speechRecognitionService = null
        recorder?.stop()
        result.success(null)
    }

    override fun onDestroy(owner: LifecycleOwner) {
        super.onDestroy(owner)
        Timber.d("onDestroy")
        speechRecognitionService?.destroy()
    }

    override fun onPause(owner: LifecycleOwner) {
        super.onPause(owner)
        Timber.d("onPause")
        if(listen) {
            wasListening = true
        }
        speechRecognitionService?.stop(false)
    }

    override fun onResume(owner: LifecycleOwner) {
        super.onResume(owner)
        Timber.d("onResume")
        if(wasListening) {
            wasListening = false
            listen = true
        }
    }

    override fun onStop(owner: LifecycleOwner) {
        super.onStop(owner)
        Timber.d("onStop")
        if(listen) {
            wasListening = true
        }
        speechRecognitionService?.stop(false)
        listen = false
    }

    override fun onSpeechResult(result: String, wasEndpoint: Boolean, resetEndPos: Boolean, isVoiceActive: Boolean, isNoSpeech: Boolean) {
        eventSink?.success(hashMapOf("transcript" to result, "wasEndpoint" to wasEndpoint,
            "resetEndPos" to resetEndPos, "isVoiceActive" to isVoiceActive, "isNoSpeech" to isNoSpeech))
    }

    override fun onSpeechError(error: Throwable, isEngineError: Boolean, isBusy: Boolean) {
        speechRecognitionService?.restart(if (isBusy) 500 else 0, grammar ?: "")
        if(error.message?.contains("Microphone might be already in use") == true) {
            eventSink?.error("microphone_in_use", "Microphone might be already in use", null)
        } else {
            eventSink?.error("asr_error", error.message, null)
        }
    }
}
