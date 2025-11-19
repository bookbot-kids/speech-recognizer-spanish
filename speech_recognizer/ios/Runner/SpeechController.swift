#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

import Foundation
import AVFoundation
typealias VoidCallback = () -> Void

/// The SpeechController class is a plugin designed to perform the following tasks:
/// - Recognize and convert speech input from the microphone into phonemes or word text.
/// - Play audio files stored in assets.
/// - Convert and play text-to-speech.
class SpeechController: NSObject, FlutterStreamHandler, FlutterPlugin {
    static let shared: SpeechController = SpeechController()
    public var eventSink: FlutterEventSink?
    
    /// Audio engine
    var engine = AVAudioEngine()

    //
    // Audio playback nodes
    //
    let mixer = AVAudioMixerNode()

    var sound: AVAudioPCMBuffer?
    var soundChannels: UInt32 = 1
    var isPlayingSpeech = false
    var recordingPath = ""
    var profileId: String?
    var appDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    var currentAudioFile: AVAudioFile?
    var currentTranscript: String?
    var hasRecognized = false
    var skipNoiseCheck = false
    var expectedSpeech: String?
    var grammar: String?
        
    var logdir: String?
  
    /// Recognition Queue with highest priority to process ASR buffer
    var recognitionQueue: DispatchQueue! = DispatchQueue(label: "recognizerQueue", qos: DispatchQoS.userInteractive)
    
    /// Recording audio queue
    var audioEngineQueue: DispatchQueue! = DispatchQueue(label: "engineQueue", qos: DispatchQoS.background)
    
    /// Exporting audio queue
    var audioFileQueue: DispatchQueue! = DispatchQueue(label: "audioFileQueue", qos: DispatchQoS.background)
    
    /// Volume level calculation queue
    var levelQueue: DispatchQueue! = DispatchQueue(label: "levelQueue", qos: DispatchQoS.userInitiated)
    
    var recognizer : OpaquePointer?
    var _lastReadResult: String?
    
    /// The buffer duration for ASR, it's 100ms. Buffer needs to be 100ms for good latency
    let kBufferDuration = 0.1
    let kBus = 0
    let kEnableKaldiInputSaving = false
    
    /// Phoneme asr recognizer per language
    var phonemeRecognizers: [String: ModelHandler] = [:]
    
    /// Word asr recognizer per language
    var wordRecognizers: [String: ModelHandler] = [:]
    var currentKaldiInputAudioFile: AVAudioFile?
    var currentLanguage = "en"
    var wordMode = false
    var microphoneEnabled = true
    let vadPatience = 6
    var vadPatienceCounter = 0
    // vadRule1ResetPatience * 100ms audio buffers of silence (no speech since start)
    let vadRule1ResetPatience = 6
    // vadRule2ResetPatience * 100ms audio buffers of silence (after speech)
    let vadRule2ResetPatience = 6
    var vadResetPatienceCounter = -1
    let kVadWindowSize = 512
    var audioEngineInputInitialized = false
    let audioSampleRate: Double = 32000.0
    
    /// VAD recognizer
    var vadWrapper: SherpaOnnxVoiceActivityDetectorWrapper? = nil

    //
    // If true, audio buffers will be sent to the recogniser.
    // If false, no audio will be sent to the recognizer, however it may still be sent elsewhere (e.g. background noise measurements).
    // The naming of the property is therefore slightly misleading and should be changed.
    //
    var listen = true;
    // a timer to reset the speech recognizer if a certain amount of time has elapsed and this has not been automatically reinstated
    var timer:Timer? = nil

    var inputFormat:AVAudioFormat? = nil
    var kaldiFormat:AVAudioFormat? = nil
    var audioFormat:AVAudioFormat? = nil
    var kaldiConverter: AVAudioConverter? = nil
    var audioConveter: AVAudioConverter? = nil
    var sampleRateRatio:Double = 0

    var registrar: FlutterPluginRegistrar? = nil
  
//    var noiseDetector: OpaquePointer?
    var isPluginDetached = false
  
    public var levelsEventSink:FlutterEventSink? = nil
    public var noisyEventSink:FlutterEventSink? = nil
    public var recognizerRunningSink:FlutterEventSink? = nil
    var appInBackground = false
    var resettingSpeech = false
    
    var exportRecordingPath: String?
    
    /// Initialize class plugin
    override init() {
        super.init()
        setupAudioEngine()
        setupAudioSession()
        startEngine()
        
        print("SpeechController initialization complete")
      
    }
    
    /// Setup audio engine with audio nodes (audio, loop, tts)
    func setupAudioEngine () {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
    }
    
    /// Flutter detach callback. After this method we can't use plugin normally
    public func detachFromEngineForRegistrar(registrar: FlutterPluginRegistrar) {
        print("SpeechController detachFromEngineForRegistrar")
        isPluginDetached = true
        stopEngine()
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Register flutter plugin
    public static func register(with registrar: FlutterPluginRegistrar) {
        #if os(iOS)
        let messenger = registrar.messenger()
        #elseif os(macOS)
        let messenger = registrar.messenger
        #endif

        let channel = FlutterMethodChannel(
         name: "com.bookbot/control",
            binaryMessenger: messenger)


        let instance = SpeechController.shared
        instance.registrar = registrar
        registrar.addMethodCallDelegate(instance, channel: channel)
        instance.isPluginDetached = false
        instance.appInBackground = false
        
        // event channel to notify asr result into dart side
        let eventChannel = FlutterEventChannel(name: "com.bookbot/event", binaryMessenger: messenger)
        eventChannel.setStreamHandler(instance)
        
        // register notification to listen background/foreground events
        NotificationCenter.default.addObserver(instance, selector: #selector(handleAudioInterruption), name: AVAudioSession.interruptionNotification, object: nil)
    }
    
    /// Handle flutter methods with args from here
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("call method \(call.method) args \(String(describing: call.arguments))")
      // Handle incoming messages from Flutter
      switch call.method {
       // ask audio permission
        case "audioPermission":
          self.audioPermission(flutterResult: result)
       // ask recording permission
        case "authorize":
          self.authorize(flutterResult: result)
        // Needed for speech, after authorization or start of book
        case "initSpeech":
          _lastReadResult = nil
            let arguments = call.arguments as! [String?]
            let profileId = arguments[1]
            let language = arguments[0]!
            let path = arguments[1]!
            wordMode = arguments[2] == "true"
            currentLanguage = language
          guard let resourcePath = Bundle.main.resourcePath else {
              return
          }
          
          self.initSpeech(profileId: profileId, language:language, modelUrl: resourcePath, path: path, flutterResult: result)
        // The start of a book when it starts listening
        case "listen":
          self.startListening()
          result(nil)
        // The closing of a book and goiong back to the library
        case "stopListening":
          self.stopListening()
          result(nil)
        // Mute microphone. Will be muted and unmuted from other actions
        case "mute":
          self.listen = false
          result(nil)
        // Unmute the microphone
        case "unmute":
          self.listen = true
          result(nil)
          // Check is noisy, but we don't use this now. Will remove
        case "isNoisy":
          result(false)
         // skip noise service check
        case "setSkipNoiseCheck":
            self.skipNoiseCheck = call.arguments as! Bool
            result(nil)
        // release recognizer
        case "destroyRecognizer":
          self.recognitionQueue.async {
            self.stopListening()
            result(nil)
          }
        // reset noise service, but we don't use this now. Will remove
        case "resetNoiseDetector":
          result(nil)
        // Final process of speech - for when page is turned or text line is touched
        case "flushSpeech":
          _lastReadResult = nil
          let args = call.arguments as! Array<Any?>
          self.logdir = args[2] as? String
          let grammar = args[1] as? String
          self.flushSpeech(toRead: args[0] as? String ?? "", grammar: grammar)
          result(nil)
        // set context biasing words to read
      case "setContextBiasing":
          if let grammar = call.arguments as? String {
              print("setContextBiasing \(grammar)")
              setContextBiasing(grammar: grammar)
          }
         
          result(nil)
         // reset asr speech
      case "resetSpeech":
          resetSpeech()
          result(nil)
         // stop search in word mode
      case "stopSearch":
          stopSearch()
          result(nil)
        // enable mic for asr
      case "enableMicrophone":
          microphoneEnabled = call.arguments as! Bool
          setVoiceProcessing()
          result(nil)
      case "currentRecordingPath":
          result(exportRecordingPath ?? "")
      case "recognizeAudio":
                 let path = call.arguments as! String
                 recognizeAudio(audioPath: path, flutterResult: result)
        default:
          result(FlutterMethodNotImplemented)
      }
    }
    
    private func recognizeAudio(
            audioPath: String, flutterResult: @escaping FlutterResult
        ) {
            print("recognizeAudio")

            stopEngine()
            print("stopped engine")

            // detech nodes
            engine.detach(mixer)

            engine = AVAudioEngine()
            mixer.volume = 0
            mixer.outputVolume = 0

            // init node again
            setupAudioEngine()

            // reset model
            self.getHandler()?.recognizer.reset()

            let key = self.registrar!.lookupKey(forAsset: audioPath)
            guard let path = Bundle.main.path(forResource: key, ofType: nil)
            else {
                flutterResult(
                    FlutterError(
                        code: "asset_not_found",
                        message: "Could not locate asset.", details: audioPath))
                return
            }

            // read audio file
            guard
                let audioUrl = URL.init(
                    string: path.replacingOccurrences(of: "%", with: "%25"))
            else {
                flutterResult(
                    FlutterError(
                        code: "asset_not_found",
                        message: "Could not locate asset.", details: path))
                return
            }


            // Guard to see if audio file can be loaded
            guard let audioFile = try? AVAudioFile(forReading: audioUrl) else {
                flutterResult(false)
                return
            }

            let node = AVAudioPlayerNode()

            engine.attach(node)
            engine.connect(node, to: mixer, format: audioFile.processingFormat)

            let bus = 0  // Typically, bus 0 is used
            let kBufferDuration: TimeInterval = 0.1  // Buffer duration in seconds (e.g., 0.1 for 100ms)

            // setup format
            // Input format is the format of the audio bus, which is not necessarily PCM16
            inputFormat = audioFile.processingFormat
            initConverters()

            node.installTap(
                onBus: bus,
                bufferSize: UInt32(inputFormat!.sampleRate * kBufferDuration),
                format: inputFormat!
            ) { buffer, _ in
                self.recognizeWithoutVAD(buffer: buffer)
            }

            startEngine()

            node.scheduleFile(
                audioFile, at: nil,
                completionCallbackType: AVAudioPlayerNodeCompletionCallbackType
                    .dataConsumed,
                completionHandler: {
                    (type: AVAudioPlayerNodeCompletionCallbackType) -> Void in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        node.removeTap(onBus: bus)
                        self.engine.detach(node)
                        guard node.engine != nil else {
                            flutterResult(true)
                            return
                        }
                        
                        flutterResult(true)
                    }
                })

            node.volume = 1.0
//            node.pan = -1.0
            node.play()
            if !engine.isRunning {
                print("engine still not running")
            }
        }
    
    /// Setup audio converters to convert for model and recording
        private func initConverters() {
            // but we also need an AVAudioFormat instance for audio passed to Kaldi
            kaldiFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000, channels: 1,
                interleaved: false)!
            guard let inputFormat = inputFormat, let kaldiFormat = kaldiFormat
            else { return }
            kaldiConverter = AVAudioConverter(from: inputFormat, to: kaldiFormat)!
            //        kaldiConverter?.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal
            //        kaldiConverter?.sampleRateConverterQuality = .max

            // ..and also for the audio conversion/saving
            audioFormat = AVAudioFormat.init(
                commonFormat: AVAudioCommonFormat.pcmFormatInt16,
                sampleRate: audioSampleRate, channels: 1, interleaved: false)!

            // setup audio converter
            audioConveter = AVAudioConverter(from: inputFormat, to: audioFormat!)!
            audioConveter?.sampleRateConverterAlgorithm =
                AVSampleRateConverterAlgorithm_Normal
            audioConveter?.sampleRateConverterQuality = .max
        }
    
    
    /// This is the TEST method for Automatic Speech Recognition (ASR).
        /// This function reads the buffer from the microphone and check for speech presence.
        /// If speech is detected, the buffer is sent to the ASR for processing.
        /// Simultaneously, the buffer is also saved into the recording.
        private func recognizeWithoutVAD(buffer: AVAudioPCMBuffer) {
            guard listen, !isPlayingSpeech, !isPluginDetached else {
                return
            }

            self.recognitionQueue.async { [weak self] in
                // condition checking
                guard let weakSelf = self, !weakSelf.isPluginDetached,
                    weakSelf.listen, !weakSelf.isPlayingSpeech
                else {
                    return
                }

                // convert buffer into ASR model (sample rate 16k)
                //                    let capacity = buffer.frameLength * AVAudioFrameCount(weakSelf.kaldiFormat!.sampleRate)
                //                              / AVAudioFrameCount(buffer.format.sampleRate)
                guard
                    let convertedBuffer = self?.convert(
                        buffer: buffer,
                        destinationConverter: weakSelf.kaldiConverter!)
                else {
                    return
                }

                //                    printLog("run buffer \(convertedBuffer.frameLength)")
                let array = convertedBuffer.array()

                guard let handler = weakSelf.getHandler()
                else {
                    return
                }

                let recognizer = handler.recognizer

                // with VAD, we need info when the person stops speaking ONLY after they spoke something
                // [no speech][speech][no speech] -> detect cases like these
                // [no speech][no speech][no speech] -> keep ignore until they say something

                if !array.isEmpty {
                    // This is just to queue the audio into the ASR buffer, but it won’t get transcribed because we don’t call asr.decode() yet,
                    // and if it’s silent/noise it’ll not be transcribed by the ASR because the VAD says its not speech.
                   recognizer.acceptWaveform(samples: array)

                    while recognizer.isReady() == true {
                        recognizer.decode()
                    }

                    // decode result from model.
                    // If it is word model, just get word text
                    // For phoneme model, get phoneme tokens
                    var resultString: String
                    if weakSelf.wordMode {
                        resultString = recognizer.getResult().text
                    } else {
                        let tokens = recognizer.getResult().tokens
                        resultString = tokens.joined(separator: " ")
                    }
                    print("resultString \(resultString)")

                    // prevent to notify ui the same result
                    if weakSelf._lastReadResult != resultString {
                        weakSelf._lastReadResult = resultString
                        DispatchQueue.main.async {
                            // [resultString, endOfSpeech, isResetting]
                            // NOTE: we mark as endOfSpeech based on VAD
                            weakSelf.eventSink?([
                                "transcript": resultString,
                                "wasEndpoint": false,
                                "resetEndPos": false,
                                "isVoiceActive": true,
                                "isNoSpeech": false,
                            ])
                        }
                    }

                    weakSelf.hasRecognized = true

                }
            }
        }

    
    /// Ask for audio permission
    public func audioPermission(flutterResult: @escaping FlutterResult) {
        #if os(iOS)
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
          flutterResult("authorized")
        case .denied:
          flutterResult("denied")
        case .undetermined:
          flutterResult("undetermined")
        default:
          flutterResult(FlutterError(code: "audioPermissionError", message: "Unknown Audio Error", details: ""))
        }
        #elseif os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
          isAudioRecordingGranted = true
          flutterResult("authorized")
        case .denied:
          flutterResult("denied")
        case .notDetermined:
          flutterResult("undetermined")
        case .restricted:
          flutterResult(FlutterError(code: "audioPermissionError", message: "Restricted Audio Error", details: ""))
        default:
          flutterResult(FlutterError(code: "audioPermissionError", message: "Unknown Audio Error", details: ""))
        }
        #endif
    }
    
    /// Ask for speech recording permission
    public func authorize(flutterResult: @escaping FlutterResult) {
        #if os(iOS)
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          //OperationQueue.main.addOperation {
            flutterResult(granted)
          //}
        }
        #elseif os(macOS)
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          //OperationQueue.main.addOperation {
            flutterResult(granted)
          //}
        }
        #endif
    }
    
    /// Get ASR model handler
    private func getHandler()-> ModelHandler? {
        return wordMode ? wordRecognizers[currentLanguage]: phonemeRecognizers[currentLanguage]
    }
  
    /// Initialize ASR & VADmodels and cache recognizer  in memory
    /// Each language has 2 models: phonemes and word.
    private func loadModel(language:String, modelUrl:String) {
    self.recognitionQueue.async {
        /// init vad model
        if(self.vadWrapper == nil) {
            let sileroVadConfig = getVadModelConfig(threshold: 0.3, minSpeechDuration: 0.15, windowSize: self.kVadWindowSize)
            var vadModelConfig = sherpaOnnxVadModelConfig(sileroVad: sileroVadConfig)
            self.vadWrapper = SherpaOnnxVoiceActivityDetectorWrapper(
                config: &vadModelConfig, buffer_size_in_seconds: 100)
        }
        
        let featConfig = sherpaOnnxFeatureConfig(
            sampleRate: 16000,
            featureDim: 80)
        if self.wordMode && !self.wordRecognizers.keys.contains(language) {
            let modelConfig = getMultilingualModelConfig(language: language, wordMode: true)
            var config = sherpaOnnxOnlineRecognizerConfig(
                featConfig: featConfig,
                modelConfig: modelConfig,
                enableEndpoint: true,
                rule1MinTrailingSilence: 2.4,
                rule2MinTrailingSilence: 1.5,
                rule3MinUtteranceLength: 600,
                decodingMethod: "modified_beam_search",
                maxActivePaths: 4,
                hotwordsScore: 1.5
            )
             
            self.wordRecognizers[language] = ModelHandler(language: language, recognizer: SherpaOnnxRecognizer(config: &config))
        } else if !self.phonemeRecognizers.keys.contains(language) {
            let modelConfig = getMultilingualModelConfig(language: language, wordMode: false)
            var config = sherpaOnnxOnlineRecognizerConfig(
                featConfig: featConfig,
                modelConfig: modelConfig,
                enableEndpoint: true,
                rule1MinTrailingSilence: 600,
                rule2MinTrailingSilence: 0.8,
                rule3MinUtteranceLength: 600,
                decodingMethod: "modified_beam_search",
                maxActivePaths: 4,
                hotwordsScore: 1.5
            )
            
            self.phonemeRecognizers[language] = ModelHandler(language: language, recognizer: SherpaOnnxRecognizer(config: &config))
        }
    }
  }
    
    /// Stop& reset  word recognizer for search
    private func stopSearch() {
        guard !wordRecognizers.isEmpty else {
            return
        }
        
        self.recognitionQueue.async { [weak self] in
            guard let weakSelf = self, !weakSelf.isPluginDetached else {
                return
            }
            
            weakSelf.resettingSpeech = true
            weakSelf.wordRecognizers.forEach { (key: String, value: ModelHandler) in
                value.recognizer.reset()
                value.recognizer.inputFinished()
            }
            
            weakSelf.vadWrapper?.reset()
            weakSelf.resettingSpeech = false
            weakSelf.wordRecognizers.removeAll()
            weakSelf.wordMode = false
        }
    }
    
    /// Save model audio recording, just for TESTING
    private func saveKaldiInputAudio(buffer: AVAudioPCMBuffer) {
            guard self.kEnableKaldiInputSaving, self.hasSignedIn(), self.listen, !self.isPlayingSpeech, !self.isPluginDetached else {
            return
          }

          self.audioFileQueue.async { [weak self] in
            guard let weakSelf = self, weakSelf.listen, !weakSelf.isPlayingSpeech else {
                return
            }

            try? weakSelf.currentKaldiInputAudioFile?.write(from: buffer)
          }
    }
    
    /// Record buffer audio to file. It should be called inside VAD
    private func saveAudio(buffer:AVAudioPCMBuffer) {
      self.audioFileQueue.async { [weak self] in
        guard let weakSelf = self else {
           return
        }
        
          // Convert mic buffer to correct format
          guard let audioBuffer = weakSelf.convert(buffer: buffer, destinationConverter: weakSelf.audioConveter!) else {
              print("Can not convert audio data")
              return
          }
          
        // save to file
        try? weakSelf.currentAudioFile?.write(from: audioBuffer)
      }
    }
    
    
    /// calculate level meter and show into UI
    private func updateLevel(buffer:AVAudioPCMBuffer) {
            guard listen, !isPlayingSpeech, !isPluginDetached else {
                return
            }
        
            self.levelQueue.async { [weak self] in
                guard let weakSelf = self, !weakSelf.isPluginDetached, !weakSelf.appInBackground, weakSelf.listen else {
                    return
                }
                
                var avg = 0.0
                for i in 0...Int(buffer.frameLength) - 1 {
                    let pcmValue:Float = buffer.floatChannelData![0][i]
                  // abs will overflow for Int16.min, so we just ignore
                    if(pcmValue != Float.leastNonzeroMagnitude) {
                    avg += Double(abs(pcmValue)) / 32768.0
                  }
                }
                
                DispatchQueue.main.async {
                    weakSelf.levelsEventSink?(avg / Double(buffer.frameLength))
                }
            }
    }
    
    /// Convert input audio buffer into output PCM buffer from dest format and converter
    private func convert(buffer: AVAudioPCMBuffer, destinationConverter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let formatIn = buffer.format
        
        // calculate frame capacity
        let ratio = buffer.format.sampleRate / destinationConverter.outputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) / ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: destinationConverter.outputFormat, frameCapacity: outputCapacity) else {
            print("Failed to create output buffer.")
            return nil
        }
        
        // prevent the same data is sent to the converter more than once
        var newBufferAvailable = true
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if newBufferAvailable {
                outStatus.pointee = .haveData
                newBufferAvailable = false
                return buffer
            } else {
                outStatus.pointee = .noDataNow
                return nil
            }
        }
        
        var error: NSError?
        let status = destinationConverter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        
        if status == .error {
            print("Format conversion failed: \(error?.localizedDescription ?? "Unknown error")")
            return nil
        }
        
        return outputBuffer
    }
    
    /// Reset asr & vad speech
    private func resetSpeech() {
        self.recognitionQueue.async { [weak self] in
            guard let weakSelf = self, !weakSelf.isPluginDetached, weakSelf.listen, !weakSelf.isPlayingSpeech else {
                return
            }
            
            weakSelf.resettingSpeech = true
            weakSelf.getHandler()?.recognizer.reset()
            weakSelf.vadWrapper?.reset()
            weakSelf.resettingSpeech = false
        }
        
    }
    
    /// Set context biasing by calling reset with grammar text
    private func setContextBiasing(grammar: String) {
        guard listen, !isPlayingSpeech, !isPluginDetached else {
            return
        }
        
        self.recognitionQueue.async { [weak self] in
            // condition checking
            guard let weakSelf = self, !weakSelf.isPluginDetached, weakSelf.listen, !weakSelf.isPlayingSpeech else {
                return
            }
            
            weakSelf.getHandler()?.recognizer.reset(hotwords: grammar)
            weakSelf.vadWrapper?.reset()
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
    private func recognize(buffer:AVAudioPCMBuffer) {
            guard listen, !isPlayingSpeech, !isPluginDetached else {
                return
            }
        
            self.recognitionQueue.async { [weak self] in
                // condition checking
                guard let weakSelf = self, !weakSelf.isPluginDetached, weakSelf.listen, !weakSelf.isPlayingSpeech else {
                    return
                }
                
                // convert buffer into ASR model (sample rate 16k)
                let capacity = buffer.frameLength * AVAudioFrameCount(weakSelf.kaldiFormat!.sampleRate)
                          / AVAudioFrameCount(buffer.format.sampleRate)
                guard let convertedBuffer = weakSelf.convert(buffer: buffer, destinationConverter: weakSelf.kaldiConverter!) else {
                    return
                }
                
                let array = convertedBuffer.array()
                
                // save kaldi buffer for TESTING only (enable the flag)
                if weakSelf.kEnableKaldiInputSaving {
                    weakSelf.saveKaldiInputAudio(buffer: convertedBuffer)
                }

                
                guard let handler = weakSelf.getHandler(), let vad = weakSelf.vadWrapper else {
                    return
                }
                
                let windowSize = weakSelf.kVadWindowSize
                let recognizer = handler.recognizer
                
                // with VAD, we need info when the person stops speaking ONLY after they spoke something
                // [no speech][speech][no speech] -> detect cases like these
                // [no speech][no speech][no speech] -> keep ignore until they say something
                
                if !array.isEmpty {
                    // This is just to queue the audio into the ASR buffer, but it won’t get transcribed because we don’t call asr.decode() yet,
                    // and if it’s silent/noise it’ll not be transcribed by the ASR because the VAD says its not speech.
                    recognizer.acceptWaveform(samples: array)

                    // The VAD model has a very small “window size” that its trained on.
                    // Originally it’s trained to recognize speech/no speech with a buffer size of about 20-30ms (windowSize / sample rate = 400frames / 16000frames/s = 0.025s = 25ms).
                    // So the for-loop chunks the input audio mic buffer (currently we use 100ms) and then ask the VAD to take in every 25ms of audio and finally predict if speech/no speech.
                    // This is just how Silero’s VAD model is trained
                    for offset in stride(from: 0, to: array.count, by: windowSize) {
                        let end = min(offset + windowSize, array.count)
                        vad.acceptWaveform(samples: [Float](array[offset..<end]))
                    }

                    // NOTE: sometimes VAD falsely detects no speech after speech
                    // so after speech was detected, reset count back to maximum patience
                    // similar do so for resetting speech
                    let hasSpeech = vad.isSpeechDetected()
                    if hasSpeech {
                        weakSelf.vadPatienceCounter = weakSelf.vadPatience
                        weakSelf.vadResetPatienceCounter = weakSelf.vadRule2ResetPatience
                    }
                    // if speech detected or is within the maximum patience
                    if (hasSpeech || weakSelf.vadPatienceCounter > 0) {
                        // this case vad detected speech, set patience count to vadRule2ResetPatience, e.g. 6
                        // then run ASR
                     
                        
                        // reset counter
                        if (!hasSpeech) {
                            weakSelf.vadPatienceCounter -= 1
                        }

                        while (recognizer.isReady() == true){
                            recognizer.decode()
                        }
                        
                        // decode result from model.
                        // If it is word model, just get word text
                        // For phoneme model, get phoneme tokens
                        var resultString: String
                        if weakSelf.wordMode {
                            resultString = recognizer.getResult().text
                        } else {
                            let tokens = recognizer.getResult().tokens
                            resultString = tokens.joined(separator: " ")
                        }
                        print("resultString \(resultString)")
                        
                        // prevent to notify ui the same result
                        if weakSelf._lastReadResult != resultString {
                            weakSelf._lastReadResult = resultString
                            DispatchQueue.main.async {
                                // [resultString, endOfSpeech, isResetting]
                                // NOTE: we mark as endOfSpeech based on VAD
                                weakSelf.eventSink?([
                                    "transcript": resultString,
                                    "wasEndpoint": false,
                                    "resetEndPos": false,
                                    "isVoiceActive": true,
                                ])
                            }
                        }
                        
                        weakSelf.hasRecognized = true
                    } else if (weakSelf.vadResetPatienceCounter >= 0) {
                        // this case once vad says there is no more speech, reduce vadRule2ResetPatience
                        // so from 6, 5, 4, ...., 0
                        // if counter is finally 0, add tail padding and finally reset ASR
                                                
                        // create 160ms float of zeros
                        // sometimes the model struggles with very soft sounds near the end of the buffer. So the trick that sherpa suggests is to add a chunk of silence at the end, so something like
                        // [audio buffer][silence/tail padding buffer]
                        // Then ask the ASR model to infer/predict all as if they are from the input mic
                        // we only want to do this once the person stops speaking (VAD finally detects no speech)
                        var tailPadding: [Float] = []
                        for _ in 0..<Int(weakSelf.kaldiFormat!.sampleRate * 0.16) {
                            tailPadding.append(0.0)
                        }
                        
                        // reset ASR if VAD reset patience is hit
                        if (weakSelf.vadResetPatienceCounter == 0) {
                            // decode tail padding for phoneme mode
                            if !weakSelf.wordMode {
                                recognizer.acceptWaveform(samples: tailPadding)
                            }
                            while (recognizer.isReady() == true){
                                recognizer.decode()
                            }
                            
                            // If it is word model, just get word text
                            // For phoneme model, get phoneme tokens
                            var resultString: String
                            if weakSelf.wordMode {
                                resultString = recognizer.getResult().text
                            } else {
                                let tokens = recognizer.getResult().tokens
                                resultString = tokens.joined(separator: " ")
                            }
                            
                            // prevent to notify ui the same result
                            if weakSelf._lastReadResult != resultString {
                                weakSelf._lastReadResult = resultString
                            }

                            print("resultString \(resultString)")
                            DispatchQueue.main.async {
                                // [resultString, endOfSpeech, isResetting]
                                // NOTE: we mark as endOfSpeech based on VAD
                                weakSelf.eventSink?([
                                    "transcript": resultString,
                                    "wasEndpoint": true,
                                    "resetEndPos": true,
                                    "isVoiceActive": false,
                                    "isNoSpeech": !hasSpeech
                                ])
                            }

                            // pop VAD buffer to empty
                            while (!vad.isEmpty()) {
                                vad.pop()
                            }
                            
                            // then reset asr
                            weakSelf.resettingSpeech = true
                            recognizer.reset()
                            weakSelf.resettingSpeech = false
                        }
                        
                        weakSelf.vadResetPatienceCounter -= 1
                    } else {
                        print("vad not detect speech")
                        // GOAL: handle case of long silence buffers, which should be ignored after several seconds,
                        // in order not to "jam" the ASR with useless buffers during inference

                        // NOTE: in this else-clause, vadResetPatienceCounter is < 0 (negative)
                        // we keep reducing the patience counter until it hits -N counts (e.g. -8)
                        // and then we reset/flush the ASR buffer and reset vadResetPatienceCounter back to -1
                        // NOTE: this is like rule1 in Kaldi/K2, while the else-if-clause is like rule2

                        DispatchQueue.main.async {
                            // [resultString, endOfSpeech, isResetting]
                            // NOTE: we mark as endOfSpeech based on VAD
                            weakSelf.eventSink?([
                                "transcript": "",
                                "wasEndpoint": false,
                                "resetEndPos": false,
                                "isVoiceActive": false,
                            ])
                        }
                        if (weakSelf.vadResetPatienceCounter == -weakSelf.vadRule1ResetPatience) {
                            // decode silence streams as to not overload it
                            // but ignore the result, i.e. don't pass to matcher
                            while (recognizer.isReady() == true){
                                recognizer.decode()
                            }

                            while (!vad.isEmpty()) {
                                vad.pop()
                            }

                            weakSelf.resettingSpeech = true
                            recognizer.reset()
                            weakSelf.resettingSpeech = false
                            weakSelf.vadResetPatienceCounter = -1
                        } else {
                            weakSelf.vadResetPatienceCounter -= 1
                        }
                    }
                }
            }
        }
  
  /// Helper function to check if AVAudioEngine is running, and if not, attempts to restart it.
  /// This is called whenever we believe that the engine should already be running. If the restart fails, that indicates some serious error that we don't know how to handle.
  /// This should almost never occur, which is why this function will currently call exit (if you want to recover more gracefully, you will need to add a proper error/callback handling mechanism, otherwise the rest of the app
  /// will blithely assume that speech recognition/audio playback/etc is functioning when it isn't.
    private func checkEngine(forcedStart: Bool = false) {
        if(!engine.isRunning || forcedStart) {
            print("Attempting to restart audio engine")
            
            do {
              engine.prepare()
              try engine.start()
              if(!engine.isRunning) {
                print("Fatal - AVAudioEngine could not be restarted.")
                  let error = NSError(domain: "AVAudioEngine could not be restarted", code: 0, userInfo: [NSLocalizedDescriptionKey : "AVAudioEngine could not be restarted."])
                  print("error \(error.localizedDescription)")
                  throw error
              }
            } catch {
                do {
                    // reinit engine on error
                    reinitEngine()
                    try engine.start()
                } catch {
                    print("error \(error.localizedDescription)")
                }
                
                print("Fatal - AVAudioEngine could not be restarted.")
            }
        }
    }
    
    /// Set audio category for recording
    private func setupAudioSession(withRetry retryCount: Int = 10) {
        guard !appInBackground else {
            print("setupAudioSession in background")
            return
        }
        
        var mode: AVAudioSession.Mode = .voiceChat
        if #available(iOS 13.0, *) {
          mode = .default
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        var currentRetry = 0
        
        func attemptActivation() {
                do {
                    try  audioSession.setCategory(AVAudioSession.Category.playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetooth, .interruptSpokenAudioAndMixWithOthers])
                    try  audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                    print("Audio Session activated successfully.")
                } catch {
                    if currentRetry < retryCount {
                        currentRetry += 1
                        print("Attempt \(currentRetry) failed to activate audio session: \(error). Retrying in 300ms...")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            attemptActivation()
                        }
                    } else {
                        print("Failed to activate audio session after \(retryCount) attempts.")
                    }
                }
            }
            
        attemptActivation()
    }
    
    /// Initialize audio engine
    private func initializeAudioInputEngine() throws {
      try audioEngineQueue.sync {

        if(audioEngineInputInitialized) {
          checkEngine()
          return
        }
        
        print("initializeAudioInputEngine")
      
        guard !appInBackground else {
            print("initializeAudioInputEngine in background")
            return
        }
        

        engine.stop()
        print("stopped engine")
          
        // Set voice processing for engine
        setVoiceProcessing()
        
        // Input format is the format of the audio bus, which is not necessarily PCM16
        inputFormat = engine.inputNode.outputFormat(forBus: kBus)
        // but we also need an AVAudioFormat instance for audio passed to Kaldi
        kaldiFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000, channels: 1,
            interleaved: false)!
        kaldiConverter = AVAudioConverter(from: inputFormat!, to: kaldiFormat!)!
          
        // ..and also for the audio conversion/saving
        audioFormat = AVAudioFormat.init(commonFormat: AVAudioCommonFormat.pcmFormatInt16, sampleRate: 32000, channels: 1, interleaved: false)!
          
        // setup audio converter
        audioConveter = AVAudioConverter(from: inputFormat!, to: audioFormat!)!
        audioConveter?.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal
        audioConveter?.sampleRateConverterQuality = .max
        
        // reset engine if mic isn't available
        if let format = inputFormat, format.channelCount == 0 || format.sampleRate == 0 {
            self.reinitEngine()
        }
          
        self.prepareAudio()
        engine.inputNode.removeTap(onBus: kBus)
        // buffer needs to be 100ms for good latency
        engine.inputNode.installTap(onBus: kBus, bufferSize: UInt32(inputFormat!.sampleRate * kBufferDuration), format: inputFormat!) { buffer, _ in
            guard self.microphoneEnabled, !self.appInBackground else {
                print("not recognize in background")
                return
          }
            
            guard !self.resettingSpeech else {
                print("is resetting, ignore buffer")
                return
            }
          
          
          self.recognize(buffer:buffer)
            // save recording
            self.saveAudio(buffer: buffer)
          // send buffer to level queue
          self.updateLevel(buffer: buffer)
        }
        
        engine.prepare()
          
        try engine.start()
        
        print("started engine")
        
        if(!engine.isRunning) {
            print("engine still not running")
        }
        audioEngineInputInitialized = true
      }

    }
    
    /// Set voice processing for better ASR quality and separate tts from user's speech in recording
    private func setVoiceProcessing() {
        do {
            // then set category and active session
            self.setupAudioSession()

            // set voice processing
            if #available(iOS 13.0, *) {
              if !microphoneEnabled {
                  try engine.inputNode.setVoiceProcessingEnabled(false)
                  try engine.outputNode.setVoiceProcessingEnabled(false)
                  return
              }
              
              try engine.inputNode.setVoiceProcessingEnabled(true)
              try engine.outputNode.setVoiceProcessingEnabled(true)
              print("set setVoiceProcessing ")
            }
        } catch {
            print("Set voiceProcessing error \(error.localizedDescription)")
        }
    }

    /// Speech initialiser
    public func initSpeech(profileId:String?, language:String, modelUrl: String, path: String, flutterResult: @escaping FlutterResult) {
        guard !appInBackground else {
            flutterResult(nil)
            print("do not init speech on background")
            return
        }
      // set profile id for recording
      self.profileId = profileId
      recordingPath = path
      
      do {
        
        // load the speech recognition model if not yet loaded
        self.loadModel(language: language, modelUrl:modelUrl)
          
        // set up the audio input if we haven't already done so
        try self.initializeAudioInputEngine()
        flutterResult(nil)
      } catch {
          flutterResult(FlutterError(code: "speechError", message: "initSpeech error", details: error.localizedDescription))
      }
    }
    
    /// The condition check to whether it should record or not
    /// Usually if there is profile id then it isn't signed in (guest)
    private func hasSignedIn() -> Bool {
        return profileId != nil
    }

    
    /// start listening speech
    public func startListening() {
        self.listen = true
    }
    
    // Prepare audio file for writing
    private func prepareAudio() {
        if(hasSignedIn()) {
          currentAudioFile = temporaryAudioFile(audioFormat: audioFormat!)
          if kEnableKaldiInputSaving {
            currentKaldiInputAudioFile = temporaryAudioFile(audioFormat: kaldiFormat!, defaultDir: FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0])
            print("write kaldi input file \(String(describing: currentKaldiInputAudioFile?.url))")
          }
        }
    }
    
    /// Generate temp audio file
    public func temporaryAudioFile( audioFormat: AVAudioFormat, defaultDir: URL? = nil) -> AVAudioFile? {
        let temporaryDirectoryURL = defaultDir ?? FileManager.default.temporaryDirectory
                let temporaryFilename = ProcessInfo().globallyUniqueString + ".caf"
                let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)
       return try? AVAudioFile(forWriting: temporaryFileURL, settings: audioFormat.settings, commonFormat: audioFormat.commonFormat, interleaved: false)
    }
    
    /// Stop listening speech
    public func stopListening() {
        self.listen = false
        DispatchQueue.main.async {
          self.timer?.invalidate()
        }
    }
    
    /// Recording export path with format dirPath/profileId_timestamp.m4a
    private func recordingExportPath() -> String?{
        guard let id = self.profileId, !recordingPath.isEmpty, let rootDir = appDir else {
            return nil
        }
        
        // create recording dir if not exist
        let recordingDir = rootDir.appendingPathComponent("recordings").appendingPathComponent(recordingPath)
        
        if !FileManager.default.fileExists(atPath: recordingDir.path) {
            do {
                try FileManager.default.createDirectory(atPath: recordingDir.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print(error.localizedDescription)
            }
        }
        
        let fileName = "\(id)_\(Int64(Date().timeIntervalSince1970 * 1000)).m4a"
        return recordingDir.appendingPathComponent(fileName).path
    }
  
  
    ///
    /// The [expectedSpeech] is distinct from [grammar] because the former should be used as the audio clip recording transcript, whereas the latter needs to be for the speech recognition model.
    /// For example, if we expect the word "cat", then [expectedSpeech] is set to "cat" but [grammar] needs to be set to [cat, mat, sat] etc.
    /// Otherwise, the recognizer will only ever return the word "cat", no matter what was said.
    /// [grammar] should be a list of strings where each entry represents a phrase that could be decoded:
    /// e.g. ["one two three", "four five six"]
    ///
    public func flushSpeech(toRead: String, grammar:String?) {
        self.expectedSpeech = toRead
        
        // will immediately stop pushing audio into the recognizer
        self.stopListening()
      
        self.grammar = grammar;

      // we have to submit a task to the queue to destroy/recreate the recognizer
        // otherwise this will not be thread-safe and one thread may try to destroy the recognizer while another thread is mid-way through processing an audio segment
        self.recognitionQueue.async {
            self.stopListening()
            
            // start listening before the new recognizer is created so that microphone data is actually available to to the noise detector
            self.startListening()
            
            // create the recognizer
            // note we don't fire the recognizerRunning callback here as audio may be discarded even though the recognizer has been created (e.g. if we are still collecting noise data)
            // see flushSpeech for this callback
            //self._instantiateRecognizer()
            self.currentTranscript = toRead
        }
    }
    
    /// eventSink is where to send events back to Flutter
    public func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }

    /// Cleanup when plugin detach
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
    
    /// App went to background. At this time we need to stop audio engine, stop playing any audios
    @objc func appDidEnterBackground() {
        appInBackground = true
        stopEngine()
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    /// App goes to forground, init audio engine & setup again
    @objc func applicationWillEnterForeground() {
        appInBackground = false
        audioEngineQueue = DispatchQueue(label: "engineQueue", qos: DispatchQoS.background)
        do {
            reinitEngine()
            if audioEngineInputInitialized {
                audioEngineInputInitialized = false
                try initializeAudioInputEngine()
            }
        } catch {
            print("error \(error.localizedDescription)")
        }
    }
    
    /// Handle intterruption when user leaves the app
    @objc func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            stopEngine()
            try? AVAudioSession.sharedInstance().setActive(false)
        case .ended:
            startEngine()
            try? AVAudioSession.sharedInstance().setActive(true)
        default:
            break
        }
    }
    
    /// Reinit audio engine and re-setup audio session
    func reinitEngine(){
        engine = AVAudioEngine()
        setupAudioEngine()
        setupAudioSession()
    }
    
    /// Stop audio engine
    func stopEngine() {
        if engine.isRunning {
            // then stop engine
            engine.stop()
        }
    }
    
    /// Start audio engine
    func startEngine() {
        checkEngine(forcedStart: true)
    }
}


/// Buffer data extension
extension Data {
    init(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        self.init(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize))
    }
    
    /// Create pcm buffer from format
    func makePCMBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let streamDesc = format.streamDescription.pointee
        let frameCapacity = UInt32(count) / streamDesc.mBytesPerFrame
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }

        buffer.frameLength = buffer.frameCapacity
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers

        withUnsafeBytes { (bufferPointer) in
            guard let addr = bufferPointer.baseAddress else { return }
            audioBuffer.mData?.copyMemory(from: addr, byteCount: Int(audioBuffer.mDataByteSize))
        }

        return buffer
    }
}

extension AudioBuffer {
    /// convert audio buffer to float array
    func array() -> [Float] {
        return Array(UnsafeBufferPointer(self))
    }
}

extension AVAudioPCMBuffer {
    /// Convert pcm buffer tofloat  array
    func array() -> [Float] {
        return self.audioBufferList.pointee.mBuffers.array()
    }
}

extension Collection {
    /// Returns the element at the specified index if it is within bounds, otherwise nil.
    subscript (safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

//func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
//    #if DEBUG
//    Swift.print(items, separator: separator, terminator: terminator)
//    #endif
//}
