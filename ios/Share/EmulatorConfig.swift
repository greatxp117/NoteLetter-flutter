import Foundation
import FirebaseAuth

/// Where the share extension's Auth and `fn_*` traffic goes (F-122).
///
/// The extension cannot be launched with dart-defines or an environment: the
/// system starts it from another app's share sheet. So a DEBUG Flutter app
/// that is running against the emulator (`--dart-define=USE_EMULATOR=true`,
/// tool/dev.sh) writes its emulator address into the App Group's defaults
/// (`AppDelegate`, channel `xp.noteletter/share_config`), and a DEBUG
/// extension reads it here. A RELEASE extension never reads it — the emulator
/// path must not be reachable in anything shipped.
///
/// And a DEBUG extension with no emulator address REFUSES, as a debug app
/// does (`lib/main.dart`): umbrella law 1. A debug extension that quietly
/// filed into the real library while the app beside it pointed at the
/// emulator would be the worst of both.
enum EmulatorConfig {
    static let appGroup = "group.xp.NoteLetter.Flutter"
    static let key = "nl.share.emulator"

    private static var stored: [String: Any]? {
        #if DEBUG
        return UserDefaults(suiteName: appGroup)?.dictionary(forKey: key)
        #else
        return nil
        #endif
    }

    /// The emulator was asked for, by the app that shares this group.
    static var isEnabled: Bool { stored != nil }

    /// DEBUG and no emulator address: this build must not reach prod.
    static var refusesProd: Bool {
        #if DEBUG
        return !isEnabled
        #else
        return false
        #endif
    }

    static var routesToEmulator: Bool { isEnabled }

    static var host: String { (stored?["host"] as? String) ?? "localhost" }
    static var authPort: Int { (stored?["authPort"] as? Int) ?? 9599 }
    static var functionsPort: Int { (stored?["functionsPort"] as? Int) ?? 5599 }
    static var usesFunctionsShim: Bool { (stored?["shim"] as? Bool) ?? true }

    /// The `fn_*` shim (`functions/dev_server.py`) serves `/fn_name` flat; the
    /// real Functions emulator's path carries the project and region.
    static var functionsBase: String {
        let root = "http://\(host):\(functionsPort)"
        return usesFunctionsShim ? root : "\(root)/noteletter-7a111/us-central1"
    }

    /// Auth to the emulator. Call once, right after `FirebaseApp.configure()`
    /// and before anything reads `Auth.auth()`.
    static func activateAuthAndFunctions() {
        guard routesToEmulator else { return }
        Auth.auth().useEmulator(withHost: host, port: authPort)
        print("⚠️ EMULATOR MODE (share) — auth \(host):\(authPort), functions \(functionsBase)")
    }
}
