import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // iOS needs the Maps key before any map is created. It comes from
    // MAPS_API_KEY in ios/Flutter/Secrets.xcconfig via Info.plist (GMSApiKey).
    // See README "iOS Setup".
    var mapsKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    if mapsKey.isEmpty {
      // The Maps SDK crashes the app on an empty key. A placeholder gives a
      // blank map instead, matching Android when MAPS_API_KEY isn't set.
      NSLog("FrameWalk: MAPS_API_KEY is not set in ios/Flutter/Secrets.xcconfig; maps will be blank.")
      mapsKey = "MAPS_API_KEY_NOT_SET"
    }
    GMSServices.provideAPIKey(mapsKey)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
