import UIKit
import Flutter
import WatchConnectivity

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

    private var channel: FlutterMethodChannel?
    private var watchSession: WatchSessionManager?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller = window?.rootViewController as! FlutterViewController
        channel = FlutterMethodChannel(
            name: "fall_guardian/watch",
            binaryMessenger: controller.binaryMessenger
        )

        // Start WatchConnectivity
        watchSession = WatchSessionManager(channel: channel!)
        watchSession?.startSession()

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
