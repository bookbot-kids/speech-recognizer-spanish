package com.bookbot.service

import android.annotation.SuppressLint
import android.media.AudioRecord
import android.media.MediaRecorder
import com.bookbot.audio.AudioConfig
import com.bookbot.utils.DispatchQueue
import com.k2fsa.sherpa.onnx.SherpaSpeechRecognizer
import timber.log.Timber
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.min

interface RecognizerCallback {
    fun speechRecognizer(): SherpaSpeechRecognizer?

    val isWordMode: Boolean

    fun windowSize(): Int

    fun recordMicBuffer(buffer: ShortArray, readSize: Int)

    fun recordASRBuffer(buffer: ShortArray)

    fun shouldPause(): Boolean

    fun recordTranscript(transcript: String)
}

/**
 * Service for streaming audio from an AudioRecorder (i.e. a microphone) in a dedicated thread, and optionally:
 * - buffering streamed data in a BlockingQueue
 * - passing streamed data to a Recognizer for speech recognition processing, and invoking the respective callbacks on the passed MicrophoneDataHandler if/when available
 * - invoking the onData callback on the passed MicrophoneDataHandler every time the raw microphone buffer is read.
 *
 * The BlockingQueue buffer is intended to be managed by a separate consumer (i.e where a larger buffer may be required than the raw microphone buffer, e.g. for encoding/saving to a file if needed).
 * The onData callback is intended to be used for fire-and-forget events (e.g calculating the point-in-time mic RMS levels).
 */
class BufferedRecognitionService @SuppressLint("MissingPermission") constructor(
    private val recordingSampleRate: Int,
    private val speechSampleRate: Int,
    private val listener: SpeechServiceImpl.MicrophoneDataHandler,
) {
    private var recorder: AudioRecord? = null
    private var vadPatienceCounter = 0
    private var vadResetPatienceCounter = -1

    /**
     * The thread on which the recognizer will actually run.
     */
    private var recognizerThread: RecognizerThread? = null
    private var callbackQueue = ConcurrentLinkedQueue<()-> Unit>()
    private val PAUSE_TIME = 100L

    @SuppressLint("MissingPermission")
    fun initRecorder() {
        val channelConfig = AudioConfig.CHANNEL_CONFIG
        val audioFormat = AudioConfig.AUDIO_FORMAT
        val numBytes = AudioRecord.getMinBufferSize(recordingSampleRate, channelConfig, audioFormat)
        recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC, recordingSampleRate,
            channelConfig,
            audioFormat,
            numBytes * 2
        )
    }

    /**
     * Starts a thread that will stream data from the microphone to a temporary buffer and pass to a Recognizer (if the latter is non-null).
     * Successfully invoking this method does not mean the Recognizer is actually doing anything.
     * The Recognizer itself is responsible for choosing whether or not to process the data stream and for notifying consumers when it is ready/actively consuming data.
     */
    fun startListening(callback: RecognizerCallback?) {
        Timber.d("Start listening")
        if (recognizerThread == null) {
            initRecognizerThread()
        }
        recognizerThread?.setRecognizerCallback(callback)
    }

    fun runOnBuffer(call: ()-> Unit) {
        callbackQueue.add(call)
    }

    fun stop(): Boolean {
        Timber.d("stopping")
        if (null == recognizerThread) return false
        try {
            Timber.d("interryupting")
            recognizerThread?.setPause(true)
            recognizerThread?.interrupt()
            recognizerThread?.join()
            Timber.d("joined")
        } catch (e: InterruptedException) {
            // Restore the interrupted status.
            Thread.currentThread().interrupt()
        } catch (e1: Throwable) {
            Timber.e(e1, "stop error")
        }
        Timber.d("set null")
        callbackQueue.clear()
        recognizerThread = null
        return true
    }

    fun processAudio(inputStream: InputStream) {
        recognizerThread?.processAudio(inputStream)
    }

    /**
     * Shutdown the recognizer and release the recorder
     */
    fun shutdown() {
        recorder?.release()
        stop()
    }

    fun setPause(paused: Boolean) {
        recognizerThread?.setPause(paused)

        if(!paused && recognizerThread?.isRunning != true) {
            initRecognizerThread()
        }
    }

    private fun initRecognizerThread() {
        stop()
        Timber.d("cresting new thread")

        recognizerThread = RecognizerThread()
        recognizerThread!!.start()
    }

    private inner class RecognizerThread :
        Thread() {

        ///
        /// This class is only responsible for passing data from a microphone interface to a Recognizer and/or intermediate buffer.
        /// In other words, it is not responsible for constructing or destroying Recognizer instances.
        /// As such, we need to synchronize on an external lock when passing audio data to a Recognizer. This ensures consistency in we can  while being destroyed.
        ///
        private val lock = Object()

        private var recognizerCallback: RecognizerCallback? = null

        private var lastReadResult = ""

        ///
        /// [paused] is set to true by default because the underlying thread
        /// will generally start running before any recognizer has been created/ready.
        /// This is because a new recognizer is created for every new passage of text.
        ///
        @Volatile
        private var paused = false

        @Volatile
        var isRunning = false

        /**
         * When we are paused, don't process audio by the recognizer and don't emit
         * any listener results
         *
         * @param paused the status of pause
         */
        fun setPause(paused: Boolean) {
            this.paused = paused
            Timber.d("setPause $paused")
        }


        /*
        * Replaces the Recognizer in the running thread.
        */

        fun setRecognizerCallback(callback:RecognizerCallback?) {
            synchronized(lock) {
                this.recognizerCallback = callback
            }
        }

        /// Running thread to start recognizer
        override fun run() {
            try{
                isRunning = true
                lastReadResult = ""
                // init recorder again if it's stopped
                if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
                    recorder?.release()
                    Timber.d("startRecording() called on an uninitialized AudioRecord.")
                    initRecorder()
                }

                if (recorder?.state != AudioRecord.STATE_INITIALIZED) {
                    val ioe = IOException("Audio recorder (${recorder?.state}) still not initialized. Microphone might be already in use")
                    Timber.e(ioe, "Record state is in valid ${recorder?.state}")
                    listener.onError(ioe)
                }

                // start the recording
                recorder?.startRecording()

                // check if there is something wrong that we can't start microphone
                if (recorder?.recordingState == AudioRecord.RECORDSTATE_STOPPED) {
                    recorder?.stop()
                    val ioe = IOException(
                        "Failed to start recording. Microphone might be already in use."
                    )
                    listener.onError(ioe)
                }

                val bufferSize = (AudioConfig.AUDIO_BUFFER_SIZE).toInt()
                while (!interrupted()) {
                    if (paused or (recognizerCallback?.shouldPause() == true)) {
                        sleep(PAUSE_TIME)
                        continue
                    }

                    val buffer = ShortArray(bufferSize)
                    // read mic buffer
                    val readSize = try {
                        recorder?.read(buffer, 0, bufferSize) ?: -1
                    } catch (e: Exception) {
                        Timber.e(e, "Error reading from AudioRecord")
                        -1
                    }
                    if (readSize < 0) {
                        when (readSize) {
                            AudioRecord.ERROR_INVALID_OPERATION -> Timber.e("Invalid read size: ERROR_INVALID_OPERATION")
                            AudioRecord.ERROR_BAD_VALUE -> Timber.e("Invalid read size: ERROR_BAD_VALUE")
                            else -> Timber.e("Invalid read size: Unknown error code: $readSize")
                        }
                        break
                    }

                    // save recording
                    recognizerCallback?.recordMicBuffer(buffer, readSize)

                    // Execute the buffer processing in single highest priority queue
                    DispatchQueue.recognitionQueue.execute {
                        recognize(buffer, readSize)
                    }

                    // Send buffer into level
                    listener.onData(buffer, readSize)
                }
            } catch(th: Throwable) {
                Timber.e(th, "Error in audio processing thread")
            } finally {
                try{
                    recorder?.release()
                } catch (e:Throwable) {
                    Timber.e(e, "Can not release recorder")
                }
                recorder = null
                isRunning = false
            }
        }

        fun processAudio(inputStream: InputStream){
            // reset model
            recognizerCallback?.speechRecognizer()?.let { recognizer ->
                recognizer.reset()
            }

            val bufferSize = AudioConfig.AUDIO_BUFFER_SIZE.toInt()
            val audioSamples = readWavFile(inputStream)
            Timber.d("processAudio ${audioSamples?.size}")
            if (audioSamples != null) {
                for (offset in 0 until audioSamples.size step bufferSize) {
                    val end = minOf(offset + bufferSize, audioSamples.size)
                    var buffer = audioSamples.sliceArray(offset until end)
                    val readSize = buffer.size

                    val isLastChunk = (end == audioSamples.size)
                    if (isLastChunk) {
                        val zeros = ShortArray(speechSampleRate)
                        buffer = buffer.plus(zeros)
                    }

                    // Execute buffer processing
                    Timber.d("send buffer ${buffer.size}, isLastChunk: $isLastChunk")
                    recognizeWithoutVAD(buffer, readSize)
                }
            } else {
                Timber.e("Failed to read WAV data from InputStream")
            }
        }

        /// Recognize audio without VAD
        /// For testing only
        private fun recognizeWithoutVAD(buffer: ShortArray, readSize: Int) {
            while (true) {
                val callback = callbackQueue.poll() ?: break
                callback.invoke()
            }

            val windowSize = AudioConfig.VAD_WINDOWS_SIZE
            val isWordMode = recognizerCallback?.isWordMode == true
            recognizerCallback?.speechRecognizer()?.let { recognizer ->
                val downSample = downSample(buffer, recordingSampleRate, speechSampleRate)
                val bufferArr = downSample.first
                val sampleSize = downSample.second

                val samples = FloatArray(sampleSize) { bufferArr[it] / 32768.0f }
                Timber.d("read buffer sample ${samples.size}")

                if(samples.isNotEmpty()) {
                    // This is just to queue the audio into the ASR buffer, but it won't get transcribed because we don't call asr.decode() yet,
                    // and if it's silent/noise it'll not be transcribed by the ASR because the VAD says its not speech.
                    recognizer.acceptWaveform(samples, speechSampleRate)
                    recognizerCallback?.recordASRBuffer(bufferArr)
                    while (recognizer.isReady()) {
                        recognizer.decode()
                    }
                    val result: String = if (isWordMode) {
                        recognizer.text
                    } else {
                        recognizer.tokens.joinToString(" ")
                    }

                    recognizerCallback?.recordTranscript(result)
                    Timber.d("tag isWordMode $isWordMode, speak [$result]")
                    // prevent to notify ui the same result
                    if(lastReadResult != result) {
                        lastReadResult = result
                        listener.onResult(
                            result = result,
                            wasEndpoint = false,
                            resetEndPos = false,
                            isVoiceActive = true,
                            isNoSpeech = false
                        )
                    }
                }
            }
        }

        /// This is the KEY method for Automatic Speech Recognition (ASR).
        /// This function reads the buffer from the microphone and passes it to the Voice Activity Detection (VAD) to check for speech presence.
        /// If speech is detected, the buffer is sent to the ASR for processing.
        /// Simultaneously, the buffer is also saved into the recording.
        /// The function is designed to detect patterns such as [no speech][speech][no speech]
        /// and ignore sequences like [no speech][no speech][no speech] until speech is detected.
        ///
        /// The flow of the code is as follows:
        ///
        ///     convertedBuffer = convert(buffer)
        ///     samples = convertedBuffer.getSamples()
        ///     if (vad.isSpeechDetected(samples))
        ///       set patience count to vadRule2ResetPatience, e.g. 6
        ///       run ASR
        ///     else if (vadResetPatienceCounter >= 0)
        ///       once vad says there is no more speech, reduce vadRule2ResetPatience
        ///       so from 6, 5, 4, ...., 0
        ///       if counter is finally 0, add tail padding and finally reset ASR
        ///     else
        ///       keep reducing the patience counter until it hits -N counts (e.g. -8)
        ///       and then we reset/flush the ASR buffer and reset vadResetPatienceCounter back to -1
        private fun recognize(buffer: ShortArray, readSize: Int) {
            // Execute all other speech task in here (usually it is model.reset())
            // The reason for that is we need to run ASR model method in the same thread
            // And we need to call it first before process buffer
            while (true) {
                val callback = callbackQueue.poll() ?: break
                callback.invoke()
            }

            if (paused or (recognizerCallback?.shouldPause() == true)) {
                sleep(PAUSE_TIME)
                return
            }

            //val startTime = System.currentTimeMillis()

            val windowSize = recognizerCallback?.windowSize() ?: 0
            val isWordMode = recognizerCallback?.isWordMode == true
            recognizerCallback?.speechRecognizer()?.let { recognizer ->
                val downSample = downSample(buffer, recordingSampleRate, speechSampleRate)
                val downSampleBuffer = downSample.first
                val downSampleSize = downSample.second

                val samples = FloatArray(downSampleSize) { downSampleBuffer[it] / 32768.0f }

                // with VAD, we need info when the person stops speaking ONLY after they spoke something
                // [no speech][speech][no speech] -> detect cases like these
                // [no speech][no speech][no speech] -> keep ignore until they say something
                if(samples.isNotEmpty()) {
                    // This is just to queue the audio into the ASR buffer, but it won’t get transcribed because we don’t call asr.decode() yet,
                    // and if it’s silent/noise it’ll not be transcribed by the ASR because the VAD says its not speech.
                    recognizer.acceptWaveform(samples, speechSampleRate)

                    // The VAD model has a very small “window size” that its trained on.
                    // Originally it’s trained to recognize speech/no speech with a buffer size of about 20-30ms (windowSize / sample rate = 400frames / 16000frames/s = 0.025s = 25ms).
                    // So the for-loop chunks the input audio mic buffer (currently we use 100ms) and then ask the VAD to take in every 25ms of audio and finally predict if speech/no speech.
                    // This is just how Silero’s VAD model is trained
                    for (offset in samples.indices step windowSize) {
                        val end = min(offset + windowSize, samples.size)
                        recognizer.vadAcceptWaveForm(samples = samples.slice(offset until end).toFloatArray())
                    }

                    // NOTE: sometimes VAD falsely detects no speech after speech
                    // so after speech was detected, reset count back to maximum patience
                    val hasSpeech = recognizer.vadIsSpeechDetected()
                    if(hasSpeech) {
                        vadPatienceCounter = AudioConfig.VAD_PATIENCE
                        vadResetPatienceCounter = AudioConfig.vadRule2ResetPatience
                    }

                    recognizerCallback?.recordASRBuffer(downSampleBuffer)

                    // if speech detected or is within the maximum patience
                    if (hasSpeech || vadPatienceCounter > 0) {
                        // this case vad detected speech, set patience count to vadRule2ResetPatience, e.g. 6
                        // then run ASR

                        // reset counter
                        if (!hasSpeech) {
                            vadPatienceCounter -= 1
                        }

                        while (recognizer.isReady()) {
                            recognizer.decode()
                        }

                        // decode result from model.
                        // If it is word model, just get word text
                        // For phoneme model, get phoneme tokens
                        val result: String = if (isWordMode) {
                            recognizer.text
                        } else {
                            recognizer.tokens.joinToString(" ")
                        }

                        recognizerCallback?.recordTranscript(result)
//                        Timber.d("tag ${recognizer.tag} isWordMode $isWordMode, speak [$result]")
                        //Logger.instance.d("process buffer in ${System.currentTimeMillis() - startTime} ms")

                        // prevent to notify ui the same result
                        if(lastReadResult != result) {
                            lastReadResult = result
                            // [resultString, endOfSpeech]
                            // NOTE: we mark as endOfSpeech based on VAD
                            listener.onResult(result = result, wasEndpoint = false,
                                resetEndPos = false,
                                isVoiceActive = true,
                                isNoSpeech = false
                            )
                        }
                    } else if (vadResetPatienceCounter >= 0) {
                        // this case once vad says there is no more speech, reduce vadRule2ResetPatience
                        // so from 6, 5, 4, ...., 0
                        // if counter is finally 0, add tail padding and finally reset ASR

                        // create 160ms float of zeros
                        // sometimes the model struggles with very soft sounds near the end of the buffer. So the trick that sherpa suggests is to add a chunk of silence at the end, so something like
                        // [audio buffer][silence/tail padding buffer]
                        // Then ask the ASR model to infer/predict all as if they are from the input mic
                        // we only want to do this once the person stops speaking (VAD finally detects no speech)
                        val tailPadding = FloatArray((speechSampleRate * 0.16).toInt()) { 0.0f }

                        // reset ASR if VAD reset patience is hit
                        if (vadResetPatienceCounter == 0) {
                            // decode tail padding for phoneme mode
                            if (!isWordMode) {
                                recognizer.acceptWaveform(tailPadding, speechSampleRate)
                            }
                            while (recognizer.isReady()) {
                                recognizer.decode()
                            }

                            // If it is word model, just get word text
                            // For phoneme model, get phoneme tokens
                            val result: String = if (isWordMode) {
                                recognizer.text
                            } else {
                                recognizer.tokens.joinToString(" ")
                            }

                            // prevent to notify ui the same result
                            if (lastReadResult != result) {
                                lastReadResult = result
                            }

                            recognizerCallback?.recordTranscript(result)
                            //Logger.instance.d("process buffer in ${System.currentTimeMillis() - startTime} ms")
                            // [resultString, endOfSpeech]
                            // NOTE: we mark as endOfSpeech based on VAD
                            // then reset asr
                            listener.onResult(result = result, wasEndpoint = true,
                                resetEndPos = true,
                                isVoiceActive = false,
                                isNoSpeech = !hasSpeech
                            )
                            // pop VAD buffer to empty
                            while (!recognizer.vadEmpty()) {
                                recognizer.vadPop()
                            }
//                            Timber.d("reset()")
                            recognizer.reset(recreate = true)
                        }
                        vadResetPatienceCounter -= 1
                    } else {
                        listener.onResult(result= "", wasEndpoint = false,
                            resetEndPos = false,
                            isVoiceActive = false,
                            isNoSpeech = false
                        )
                        // Logger.instance.d("vad does not detect")

                        // GOAL: handle case of long silence buffers, which should be ignored after several seconds,
                        // in order not to "jam" the ASR with useless buffers during inference

                        // NOTE: in this else-clause, vadResetPatienceCounter is < 0 (negative)
                        // we keep reducing the patience counter until it hits -N counts (e.g. -8)
                        // and then we reset/flush the ASR buffer and reset vadResetPatienceCounter back to -1
                        // NOTE: this is like rule1 in Kaldi/K2, while the else-if-clause is like rule2
                        if (vadResetPatienceCounter == -AudioConfig.vadRule1ResetPatience) {
                            // decode silence streams as to not overload it
                            // but ignore the result, i.e. don't pass to matcher
                            while (recognizer.isReady()) {
                                recognizer.decode()
                            }

                            // pop VAD buffer to empty
                            while (!recognizer.vadEmpty()) {
                                recognizer.vadPop()
                            }

//                            Timber.d("reset()")
                            recognizer.reset(recreate = true)
                            vadResetPatienceCounter = -1
                        } else {
                            vadResetPatienceCounter -= 1
                        }
                        // Logger.instance.d("process buffer in ${System.currentTimeMillis() - startTime} ms")
                    }
                } else {
                    // Logger.instance.d("samples buffer is empty")
                    // Logger.instance.d("process buffer in ${System.currentTimeMillis() - startTime} ms")
                }
            }
        }
    }

    /// Init mic recorder and retry if there is any error
    private fun retryInitRecorder(){
        for (i in 0..5) {
            if(recorder?.state != AudioRecord.STATE_UNINITIALIZED) {
                break
            }
            recorder?.release()
            Thread.sleep(1000)
            initRecorder()
            Timber.d("try to init recorder $i, start ${recorder?.state}")
        }
    }

    private fun downSample(
        buffer: ShortArray,
        fromSampleRate: Int,
        toSampleRate: Int
    ): Pair<ShortArray, Int> {
        // Calculate the sampling ratio as a floating-point number
        val ratio = fromSampleRate.toDouble() / toSampleRate.toDouble()
        val newSize = ((buffer.size) / ratio).toInt()
        val resampledBuffer = ShortArray(newSize)

        // Apply an anti-aliasing low-pass filter
        val filteredBuffer = lowPassFilter(buffer, fromSampleRate, toSampleRate)

        // Resample using linear interpolation
        for (i in resampledBuffer.indices) {
            val srcIndex = i * ratio
            val intIndex = srcIndex.toInt()
            val frac = srcIndex - intIndex

            val sample: Double = if (intIndex + 1 < filteredBuffer.size) {
                // Linear interpolation between adjacent samples
                (1 - frac) * filteredBuffer[intIndex] + frac * filteredBuffer[intIndex + 1]
            } else {
                // Use the last sample if at the end of the buffer
                filteredBuffer[intIndex].toDouble()
            }

            // Clamp the sample to the Short range to prevent overflow
            resampledBuffer[i] = sample.coerceIn(Short.MIN_VALUE.toDouble(), Short.MAX_VALUE.toDouble()).toInt().toShort()
        }

        return Pair(resampledBuffer, newSize)
    }


    /// Down sample rate of buffer and convert into float array
    // Return new float samples
    private fun downSampleAndConvertToFloat(
        buffer: ShortArray,
        fromSampleRate: Int,
        toSampleRate: Int
    ): FloatArray {
        // Calculate the sampling ratio as a floating-point number
        val ratio = fromSampleRate.toDouble() / toSampleRate.toDouble()
        val newSize = ((buffer.size) / ratio).toInt()
        val samples = FloatArray(newSize)

        // Apply an anti-aliasing low-pass filter
        val filteredBuffer = lowPassFilter(buffer, fromSampleRate, toSampleRate)

        // Resample using linear interpolation
        for (i in samples.indices) {
            val srcIndex = i * ratio
            val intIndex = srcIndex.toInt()
            val frac = srcIndex - intIndex

            val sample: Double = if (intIndex + 1 < filteredBuffer.size) {
                // Linear interpolation between adjacent samples
                (1 - frac) * filteredBuffer[intIndex] + frac * filteredBuffer[intIndex + 1]
            } else {
                // Use the last sample if at the end of the buffer
                filteredBuffer[intIndex]
            }

            // Clamp the sample to the Short range to prevent overflow
            samples[i] = (sample / 32768.0).toFloat()
        }

        return samples
    }

    private fun lowPassFilter(buffer: ShortArray, fromSampleRate: Int, toSampleRate: Int): DoubleArray {
        val cutoffFreq = toSampleRate / 2.0 // Nyquist frequency of the target sample rate
        val normalizedCutoff = cutoffFreq / (fromSampleRate / 2.0) // Normalize cutoff frequency
        val filterOrder = 101 // Filter order (must be an odd number)
        val filterCoeffs = firLowPassCoefficients(normalizedCutoff, filterOrder)

        val filteredBuffer = DoubleArray(buffer.size)

        // Zero-padding at the beginning and end to handle filter delay
        val paddedBuffer = DoubleArray(buffer.size + filterOrder - 1)
        for (i in buffer.indices) {
            paddedBuffer[i + (filterOrder - 1) / 2] = buffer[i].toDouble()
        }

        // Apply convolution (FIR filtering)
        for (i in filteredBuffer.indices) {
            var acc = 0.0
            for (j in filterCoeffs.indices) {
                acc += paddedBuffer[i + j] * filterCoeffs[j]
            }
            filteredBuffer[i] = acc
        }

        return filteredBuffer
    }

    private fun firLowPassCoefficients(cutoff: Double, filterOrder: Int): DoubleArray {
        val coeffs = DoubleArray(filterOrder)
        val m = filterOrder - 1

        for (i in 0 until filterOrder) {
            val n = i - m / 2.0
            if (n == 0.0) {
                coeffs[i] = 2 * cutoff
            } else {
                coeffs[i] = Math.sin(2 * Math.PI * cutoff * n) / (Math.PI * n)
            }

            // Apply a Hamming window to reduce spectral leakage
            coeffs[i] *= 0.54 - 0.46 * Math.cos(2 * Math.PI * i / m)
        }

        // Normalize the coefficients so that their sum is 1
        val sum = coeffs.sum()
        for (i in coeffs.indices) {
            coeffs[i] /= sum
        }

        return coeffs
    }

    fun readWavFile(inputStream: InputStream): ShortArray? {
        try {
            // Read the header (typically 44 bytes for PCM WAV files)
            val headerSize = 44
            val header = ByteArray(headerSize)
            val bytesRead = inputStream.read(header, 0, headerSize)
            if (bytesRead != headerSize) {
                // Handle error
                inputStream.close()
                return null
            }

            // Optionally, parse the header to get audio format info
            // For simplicity, we'll assume the format matches what we expect

            // Read the rest of the data (audio samples)
            val audioData = inputStream.readBytes()
            // Close the InputStream if you are done with it
            inputStream.close()

            // Convert byte data to short data (assuming 16-bit samples)
            val numSamples = audioData.size / 2
            val audioSamples = ShortArray(numSamples)
            val byteBuffer = ByteBuffer.wrap(audioData)
            byteBuffer.order(ByteOrder.LITTLE_ENDIAN)
            for (i in 0 until numSamples) {
                audioSamples[i] = byteBuffer.short
            }

            return audioSamples
        } catch (e: IOException) {
            e.printStackTrace()
            return null
        }
    }

    /**
     * Creates speech service. Service holds the AudioRecord object, so you
     * need to call [.shutdown] in order to properly finalize it.
     *
     * thrown IOException if audio recorder can not be created for some reason.
     */
    init {
        initRecorder()
        retryInitRecorder()

        if (recorder?.state == AudioRecord.STATE_UNINITIALIZED) {
            Timber.d("Failed to initialize recorder. Microphone might be already in use")
            Timber.e(IOException("Failed to initialize recorder. Microphone might be already in use."))
        }

        initRecognizerThread()
    }
}