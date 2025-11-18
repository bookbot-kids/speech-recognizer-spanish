package com.k2fsa.sherpa.onnx

import android.content.res.AssetManager

/// An adapter class to connect to sherpa framework
class SherpaSpeechRecognizer(private val windowSize: Int) {
    private lateinit var recognizer: OnlineRecognizer
    private lateinit var vad: Vad
    private var stream: OnlineStream? = null

    fun initModel(assetManager: AssetManager, modelDir: String, vadPath: String) {
        recognizer = OnlineRecognizer(assetManager, buildModelConfig(modelDir))
        vad = Vad(assetManager, buildVADModelConfig(vadPath))
    }

    val text: String
         get() = stream?.let { recognizer.getResult(it).text } ?: ""

    val tokens: Array<String>
        get() = stream?.let { recognizer.getResult(it).tokens } ?: arrayOf()

    fun acceptWaveform(samples: FloatArray, sampleRate: Int) {
        stream?.acceptWaveform(samples, sampleRate)
    }

    fun reset(hotwords: String = "", recreate: Boolean = false){
        if(recreate || stream == null) {
//            release()
            inputFinished()
            stream = recognizer.createStream(hotwords)
        } else {
            stream?.let {
                recognizer.reset(it)
            }
        }
    }

    fun inputFinished() {
        stream?.inputFinished()
    }

    fun isReady(): Boolean = stream?.let { recognizer.isReady(it) } ?: false

    fun decode() {
        stream?.let {
            recognizer.decode(it)
        }
    }

    private fun release(){
        stream?.release()
        stream = null
    }

    fun vadReset() {
        vad.reset()
    }

    fun vadAcceptWaveForm(samples: FloatArray) {
        vad.acceptWaveform(samples)
    }

    fun vadIsSpeechDetected(): Boolean {
        return vad.isSpeechDetected()
    }

    fun vadEmpty(): Boolean {
        return vad.empty()
    }

    fun vadPop() {
        vad.pop()
    }

    private fun buildVADModelConfig(modalPath: String): VadModelConfig {
        return VadModelConfig(
            sileroVadModelConfig = SileroVadModelConfig(
                model = modalPath,
                threshold = 0.25F,
                minSilenceDuration = 0.20F,
                minSpeechDuration = 0.15F,
                windowSize = windowSize,
            ),
            sampleRate = 16000,
            numThreads = 1,
            provider = "cpu")
    }

    private fun buildModelConfig(modelDir: String): OnlineRecognizerConfig {
        val featConfig = FeatureConfig(
            sampleRate = 16000,
            featureDim = 80
        )
        val lmConfig = OnlineLMConfig()
        val endpointConfig = EndpointConfig(
            rule1 = EndpointRule(false, 600.0f, 0.0f),
            rule2 = EndpointRule(true, 0.8f, 0.0f),
            rule3 = EndpointRule(false, 0.0f, 600.0f)
        )

        val modelConfig = OnlineModelConfig(
            transducer = OnlineTransducerModelConfig(
                encoder = "$modelDir/encoder.int8.ort",
                decoder = "$modelDir/decoder.int8.ort",
                joiner = "$modelDir/joiner.int8.ort",
            ),
            tokens = "$modelDir/tokens.txt",
            modelType = "zipformer2",
            provider = "cpu",
            numThreads = 2,
        )

        return OnlineRecognizerConfig(
            featConfig = featConfig,
            modelConfig = modelConfig,
            lmConfig = lmConfig,
            endpointConfig = endpointConfig,
            enableEndpoint = true,
            decodingMethod = "modified_beam_search",
            maxActivePaths = 4,
            hotwordsScore = 1.5f,
            tokenizeHotwords = false
        )
    }
}