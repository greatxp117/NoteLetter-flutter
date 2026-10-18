import Flutter
import UIKit
import FirebaseCore
import FirebaseAuth

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// The share extension's App Group and keychain group (F-122): this app's
  /// OWN, never the retired Swift app's `group.xp.NoteLetter` /
  /// `xp.NoteLetter.shared` (ruled 2026-10-18: start fresh).
  static let appGroup = "group.xp.NoteLetter.Flutter"
  static let keychainGroup = "3SA8A2JP3T.xp.NoteLetter.Flutter.shared"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // The Firebase session lives in the SHARED keychain group, so the share
    // extension (ios/Share) signs in as whoever signed in here. It has to be
    // set before anything reads `Auth.auth()` — so Firebase is configured here,
    // natively, before FlutterFire's `Firebase.initializeApp` (which finds the
    // default app already up and uses it). Moving the session to a new group
    // signs every existing user out ONCE, on the first launch of this build.
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    do {
      try Auth.auth().useUserAccessGroup(Self.keychainGroup)
    } catch {
      // The extension then sees no session and says "Sign in required";
      // the app itself is unaffected.
      print("NoteLetter: shared keychain group unavailable — \(error)")
    }

    GeneratedPluginRegistrant.register(with: self)

    // DEBUG only: where the share extension should send a debug build's
    // traffic. A debug app on the emulator writes the emulator's address into
    // the App Group; a debug app on prod clears it, and the debug extension
    // then refuses (ios/Share/EmulatorConfig.swift). A release build never
    // writes, and a release extension never reads.
    if let registrar = self.registrar(forPlugin: "NoteLetterShareConfig") {
      let channel = FlutterMethodChannel(
        name: "xp.noteletter/share_config", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        #if DEBUG
        guard call.method == "setEmulator" else { return result(FlutterMethodNotImplemented) }
        let defaults = UserDefaults(suiteName: AppDelegate.appGroup)
        if let config = call.arguments as? [String: Any] {
          defaults?.set(config, forKey: "nl.share.emulator")
        } else {
          defaults?.removeObject(forKey: "nl.share.emulator")
        }
        result(nil)
        #else
        result(nil)
        #endif
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
