import UIKit
import Foundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
      GeneratedPluginRegistrant.register(with: self)
      SpeechController.register(with: self.registrar(forPlugin: "BookbotSpeech")!)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
        
    
    override public func applicationDidEnterBackground(_ application: UIApplication) {
        super.applicationDidEnterBackground(application)
        debugPrint("applicationDidEnterBackground")
        SpeechController.shared.appDidEnterBackground()
    }

    override public func applicationWillEnterForeground(_ application: UIApplication) {
        super.applicationWillEnterForeground(application)
        print("applicationWillEnterForeground")
        SpeechController.shared.applicationWillEnterForeground()
    }
}

