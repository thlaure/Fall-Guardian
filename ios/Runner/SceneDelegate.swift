// Flutter is imported here because SceneDelegate subclasses FlutterSceneDelegate,
// which is defined in the Flutter SDK — not in UIKit.
import Flutter

// UIKit provides UIScene, the base type used in the method override below.
import UIKit

// MARK: - What is UIScene lifecycle?
//
// Older iOS apps had a single "window" managed entirely by AppDelegate.
// iOS 13 introduced UIScene: the operating system can now create multiple independent
// "scenes" (windows) for the same app — useful for iPad split-screen and, more
// importantly for us, required by iOS 26.
//
// With UIScene lifecycle, each scene gets its own delegate (SceneDelegate). iOS
// instantiates SceneDelegate when a new scene connects, and destroys it when the
// scene is closed. AppDelegate still exists but it is only responsible for app-level
// (not window-level) events.
//
// Why do we need this for Fall Guardian?
// Flutter 3.43 on iOS 26 requires UIScene lifecycle. The old single-window model
// (everything in AppDelegate) causes a black screen on iOS 26 because the window
// is now owned by the scene, not the app delegate.

// MARK: - SceneDelegate

// FlutterSceneDelegate (provided by the Flutter SDK) does the heavy lifting:
//   - Creates the UIWindow that hosts the Flutter view.
//   - Instantiates and attaches the FlutterViewController.
//   - Connects the scene to the Flutter engine.
//
// We subclass it here so that iOS's Info.plist scene configuration points to OUR
// class name ("SceneDelegate"), while still getting all of Flutter's behaviour for
// free. If we didn't subclass, we would have to register "FlutterSceneDelegate"
// directly in Info.plist — which is fragile and not recommended.
//
// The class is intentionally almost empty: all the real work is in FlutterSceneDelegate
// and in AppDelegate.didInitializeImplicitFlutterEngine(_:).
class SceneDelegate: FlutterSceneDelegate {

    // MARK: - State Restoration Override

    // What is state restoration?
    // iOS can save and restore the UI state of an app between launches (e.g. which
    // screen was open, what the user was typing). It does this by asking each scene
    // for an NSUserActivity snapshot to persist.
    //
    // Why do we disable it here?
    // On iOS 26 simulators, returning a non-nil NSUserActivity from this method
    // causes a runtime exception (UAUserActivity throws an internal assertion).
    // Since Fall Guardian does not use state restoration at all, returning nil is
    // both safe and correct — it simply tells iOS "don't save anything for this scene".
    override func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? { nil }
}
