import Foundation

func getResource(_ forResource: String, _ ofType: String, subDir: String) -> String {
    let path = Bundle.main.path(forResource: forResource, ofType: ofType, inDirectory: subDir.isEmpty ? "asr/" : "asr/\(subDir)")
  precondition(
    path != nil,
    "\(forResource).\(ofType) does not exist!\n" + "Remember to change \n"
      + "  Build Phases -> Copy Bundle Resources\n" + "to add it!"
  )
  return path!
}
/// Please refer to
/// https://k2-fsa.github.io/sherpa/ncnn/pretrained_models/index.html
/// to download pre-trained models
func getMultilingualModelConfig(language: String, wordMode: Bool) -> SherpaOnnxOnlineModelConfig {
    let subDir = wordMode ? "\(language)/word" : language
    let encoder = getResource("encoder.int8", "ort", subDir: subDir)
    let decoder = getResource("decoder.int8", "ort", subDir: subDir)
    let joiner = getResource("joiner.int8", "ort", subDir: subDir)
    let tokens = getResource("tokens", "txt", subDir: subDir)

    return sherpaOnnxOnlineModelConfig(
      tokens: tokens,
      transducer: sherpaOnnxOnlineTransducerModelConfig(
        encoder: encoder,
        decoder: decoder,
        joiner: joiner),
      numThreads: 2,
      modelType: "zipformer2"
    )
}

func getVadModelConfig(threshold: Float = 0.5,
                                   minSilenceDuration: Float = 0.25,
                                   minSpeechDuration: Float = 0.5,
                                   windowSize: Int = 512) -> SherpaOnnxSileroVadModelConfig {
    let modelPath = getResource("silero_vad", "ort", subDir: "")
    return sherpaOnnxSileroVadModelConfig(
        model: modelPath,
        threshold: threshold,
        minSilenceDuration: minSilenceDuration,
        minSpeechDuration: minSpeechDuration,
        windowSize: windowSize
    )
}

class ModelHandler {
    let language: String
    let recognizer: SherpaOnnxRecognizer
    
    required init(language: String, recognizer: SherpaOnnxRecognizer) {
        self.language = language
        self.recognizer = recognizer
    }
}
