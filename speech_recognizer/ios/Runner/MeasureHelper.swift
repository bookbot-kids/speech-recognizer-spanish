//
//  MeasureHelper.swift
//  Runner
//
//  Created by ductran on 17/9/24.
//

import Foundation
#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

enum MeasureType: String {
    case lastSpeech = "LastSpeech"
}

class MeasureInfo {
    var start: Int64 = 0
    var end: Int64 = 0
    var list = [Double]()
    
    func count() {
        list.append(Double(end - start))
    }
    
    func reset() {
        start = 0
        end = 0
    }
    
    func export() -> [String: Double] {
        guard !list.isEmpty else {
            return [:]
        }
        let minValue = list.min() ?? 0.0
        let maxValue = list.max() ?? 0.0
        let average = list.reduce(0.0, +) / Double(list.count)
        let last = list.last ?? 0.0
        return ["min": minValue, "max": maxValue, "avg": average, "last": last]
    }
}


class MeasureHelper {
    static private var map = [MeasureType: MeasureInfo]()
    static private var listener: (MeasureType, [String: Double]) -> Void = { _, _ in }
    
    static func start(type: MeasureType) {
        if map[type] == nil {
            map[type] = MeasureInfo()
        }
        map[type]?.start = currentTimeMillis()
    }
    
    static func end(type: MeasureType) {
        if map[type] == nil {
            map[type] = MeasureInfo()
        }
        guard let info = map[type] else { return }
        info.end = currentTimeMillis()
        info.count()
        info.reset()
        listener(type, info.export())
    }
    
    static func setListener(callback: @escaping (MeasureType, [String: Double]) -> Void) {
        listener = callback
    }
    
    static func reset() {
        map.removeAll()
    }
    
    private static func currentTimeMillis() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
}

class MeasureHandler : NSObject, FlutterStreamHandler {
  var controller:SpeechController
  init(controller:SpeechController) {
    self.controller = controller

  }
  public func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    controller.measureEventSink = eventSink
    return nil
  }
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
      return nil
  }
}
