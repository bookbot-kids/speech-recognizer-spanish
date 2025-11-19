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

package com.bookbot.service

import android.content.Context
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import com.bookbot.audio.AudioConfig
import com.bookbot.audio.MicrophoneRecorder
import com.bookbot.utils.DispatchQueue
import com.k2fsa.sherpa.onnx.SherpaSpeechRecognizer
import timber.log.Timber
import java.io.InputStream
import kotlin.math.abs

class SpeechServiceImpl(
    private val context: Context,
    private val language:String,
    private val recognizerRunningCallback:(Boolean)->Unit,
    private val canPauseCallback: () -> Boolean,
    private val levelCallback:(Double)->Unit): SpeechService, RecognizerCallback {

    private lateinit var onResult: SpeechCallback
    private var kaldiSpeechService: BufferedRecognitionService? = null
    override var microphoneRecorder: MicrophoneRecorder? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var phonemeSherpaService: SherpaSpeechRecognizer? = null
    private var wordSherpaService: SherpaSpeechRecognizer? = null

    override fun speechRecognizer(): SherpaSpeechRecognizer? {
        if(wordMode) {
            return wordSherpaService ?: SherpaSpeechRecognizer(windowSize()).also { wordSherpaService = it }
        }

        return phonemeSherpaService ?: SherpaSpeechRecognizer(windowSize()).also { phonemeSherpaService = it }
    }

    ///
    /// Whether or not the model has been loaded and is ready to be started.
    ///
    @Volatile
    private var ready = false


    override var isRunning:Boolean = false

    ///
    /// Whether or not the recognition service has been instructed to stop (this is distinct from whether it has actually stopped).
    ///
    private var stopped = true
    private var handler = Handler(Looper.getMainLooper())
    override var wordMode = false

    override fun windowSize(): Int {
        return AudioConfig.VAD_WINDOWS_SIZE
    }

    override fun initSpeech(onResult: SpeechCallback) {
        Timber.i("vosk initSpeech")
        this.onResult = onResult
        initModel()
    }

    override fun start(grammar:String?) {
        if(!ready) {
            throw IllegalAccessException("SpeechServiceImpl is not ready, did you wait for initModel to complete?")
        }

        kaldiSpeechService?.startListening(this)
        kaldiSpeechService?.setPause(false)
        isRunning = true
        recognizerRunningCallback(true)
        stopped = false

        Timber.i("vosk speech start")
    }

    override fun setContextBiasing(hotWords: String?) {
        hotWords?.let {
            if(kaldiSpeechService != null) {
                kaldiSpeechService?.runOnBuffer {
                    Timber.d("call setContextBiasing $hotWords")
                    speechRecognizer()?.reset(hotWords, recreate = true)
                    speechRecognizer()?.vadReset()
                }
            } else {
                speechRecognizer()?.reset(hotWords, recreate = true)
                speechRecognizer()?.vadReset()
            }
        }
    }

    override fun recordMicBuffer(buffer: ShortArray, readSize: Int) {
        microphoneRecorder?.recordMicBuffer(buffer, readSize)
    }

    override fun recordASRBuffer(buffer: ShortArray) {
        microphoneRecorder?.recordASRBuffer(buffer)
    }

    override fun recordTranscript(transcript: String) {
        microphoneRecorder?.recordTranscript(transcript)
    }

    override fun restartRecorder(type: String) {
        if (type == "voice") {
            AudioConfig.audioSource = MediaRecorder.AudioSource.VOICE_COMMUNICATION
        } else {
            AudioConfig.audioSource = MediaRecorder.AudioSource.MIC
        }

        kaldiSpeechService?.initRecorder()
    }

    override fun recognizeAudio(inputStream: InputStream) {
        kaldiSpeechService?.startListening(this)
        kaldiSpeechService?.processAudio(inputStream)
    }

    override fun shouldPause(): Boolean {
        return canPauseCallback.invoke()
    }

    override fun pause() {
        if(ready) {
            kaldiSpeechService?.setPause(true)
        }
    }

    override fun resume() {
        if(ready) {
            kaldiSpeechService?.setPause(false)
        }
    }

    override fun stop(shouldPause: Boolean) {
        if(!ready) {
            return
        }
        stopped = true
        if(shouldPause)
            kaldiSpeechService?.setPause(true)
        else
            kaldiSpeechService?.stop()
        Timber.i("vosk speech stop")
    }

    override fun destroyRecognizer() {
        kaldiSpeechService?.startListening(null)
    }

    override fun destroy() {
        if(!ready) {
            return
        }

        stop(false)
        microphoneRecorder?.release()
        kaldiSpeechService?.shutdown()
        ready = false
    }

    override fun restart(time: Long, grammar:String?) {
        if(!ready || stopped) {
            return
        }

        isRunning = false
        handler.postDelayed({
            start(grammar)
        }, time)
        Timber.i("vosk speech restart")
    }

    override fun reset() {
        kaldiSpeechService?.runOnBuffer {
            Timber.d("call reset()")
//            pause()
            speechRecognizer()?.reset(recreate = true)
            speechRecognizer()?.vadReset()
//            resume()
        }
    }

    override fun stopSearch() {
        wordMode = false
        kaldiSpeechService?.runOnBuffer {
            pause()
            speechRecognizer()?.reset()
            speechRecognizer()?.inputFinished()
            speechRecognizer()?.vadReset()
            resume()
        }
    }

    override val isWordMode: Boolean
        get() = wordMode

    ///
    /// Model loading by Vosk is asynchronous, but doesn't return a proper Future that we can await.
    /// For now, we just return immediately and assume that start() won't be called before this has completed.
    /// If this causes issues, we will restructure to wait elsewhere.
    ///
    private fun initModel() {
        ready = false
        Timber.i("Initializing model $language")
        speechRecognizer()?.initModel(context.assets, if(wordMode) "asr/$language/word" else "asr/$language", "asr/silero_vad.ort")
        kaldiSpeechService = BufferedRecognitionService(AudioConfig.RECORDING_SAMPLE_RATE, AudioConfig.MODEL_SAMPLE_RATE, MicrophoneDataHandler())
        ready = true
    }

    inner class MicrophoneDataHandler : RecognitionListener {
        private var smoothedVolume = 0.0
        private val alpha = 0.9
        override fun onData(data:ShortArray, readSize: Int) {
            DispatchQueue.levelQueue.execute{
                // Calculate peak amplitude
                var maxAmplitudeSample = 0
                for (i in 0 until readSize) {
                    val sample = abs(data[i].toInt())
                    if (sample > maxAmplitudeSample) {
                        maxAmplitudeSample = sample
                    }
                }

                // Normalize the amplitude to a percentage (0% - 100%)
                val maxAmplitude = 32767.0
                val volumePercentage = (maxAmplitudeSample / maxAmplitude) * 100

                // Ensure volumePercentage is within 0% to 100%
                val volumeLevel = volumePercentage.coerceIn(0.0, 100.0)

                // Apply exponential smoothing
                smoothedVolume = alpha * smoothedVolume + (1 - alpha) * volumeLevel
                levelCallback(if(smoothedVolume < 1.0) 0.0 else smoothedVolume)
            }
        }

        override fun onResult(result: String?, wasEndpoint: Boolean, resetEndPos: Boolean, isVoiceActive: Boolean, isNoSpeech: Boolean) {
            result?.let {
                mainHandler.post {
                    onResult.onSpeechResult(it, wasEndpoint, resetEndPos, isVoiceActive, isNoSpeech)
                }
            }
        }

        override fun onError(ex: Exception?) {
            Timber.d("vosk onError ${ex?.message}")
            ex?.let {
                mainHandler.post {
                    onResult.onSpeechError(it, false)
                }
            }
            isRunning = false
        }
    }
}