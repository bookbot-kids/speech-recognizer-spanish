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

import com.bookbot.audio.MicrophoneRecorder
import com.k2fsa.sherpa.onnx.SherpaSpeechRecognizer
import java.io.InputStream

interface SpeechCallback {
    fun onSpeechResult(result: String, wasEndpoint: Boolean, resetEndPos: Boolean, isVoiceActive: Boolean, isNoSpeech: Boolean)
    fun onSpeechError(error: Throwable, isEngineError: Boolean, isBusy: Boolean = false)
}

interface SpeechService {
    var microphoneRecorder: MicrophoneRecorder?
    val isRunning:Boolean
    fun initSpeech(onResult: SpeechCallback)
    fun start(grammar:String?)
    fun stop(shouldPause: Boolean = true)
    fun destroy()
    fun destroyRecognizer()
    fun restart(time: Long, grammar:String?)
    fun pause()
    fun resume()
    fun speechRecognizer(): SherpaSpeechRecognizer?
    fun reset()
    fun stopSearch()

    fun setContextBiasing(hotWords: String?)
    fun recordMicBuffer(buffer: ShortArray, readSize: Int)
    fun recordASRBuffer(buffer: ShortArray)
    fun restartRecorder(type: String)
    fun recognizeAudio(inputStream: InputStream)

    var wordMode: Boolean
}

interface RecognitionListener {
    fun onData(data:ShortArray, readSize: Int)
    fun onResult(result: String?, wasEndpoint: Boolean, resetEndPos: Boolean, isVoiceActive: Boolean, isNoSpeech: Boolean)
    fun onError(ex: Exception?)
}
