import Flutter
import UIKit

// Empty subclass required to opt into UIScene lifecycle on iOS 13+.
// FlutterSceneDelegate handles window and FlutterViewController setup.
class SceneDelegate: FlutterSceneDelegate {
    // Disable state restoration — UAUserActivity throws on iOS 26 simulators
    override func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? { nil }
}
