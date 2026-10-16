import Flutter
import UIKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, CLLocationManagerDelegate, FlutterStreamHandler {
  private var locationManager: CLLocationManager?
  private var eventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let eventChannel = FlutterEventChannel(name: "hu.uni.miskolc.mfkGeomeasure/native_location", binaryMessenger: controller.binaryMessenger)
    eventChannel.setStreamHandler(self)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    locationManager = CLLocationManager()
    locationManager?.delegate = self
    locationManager?.desiredAccuracy = kCLLocationAccuracyBest
    locationManager?.requestWhenInUseAuthorization()
    locationManager?.startUpdatingLocation()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    locationManager?.stopUpdatingLocation()
    locationManager = nil
    eventSink = nil
    return nil
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last, let sink = eventSink else { return }

    var dict: [String: Any] = [
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "altitude": location.altitude, // this is MSL/Orthometric on iOS
      "horizontalAccuracy": location.horizontalAccuracy,
      "verticalAccuracy": location.verticalAccuracy,
      "timestamp": location.timestamp.timeIntervalSince1970 * 1000
    ]

    if #available(iOS 15.0, *) {
      // Add ellipsoidal altitude if available and valid
      if location.verticalAccuracy > 0.0 {
        dict["ellipsoidalAltitude"] = location.ellipsoidalAltitude
      }
    }

    sink(dict)
  }
}
