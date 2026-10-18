// F-125 S4. Ported from the retired Swift app's
// `NoteLetter/NoteLetter/CameraSweep/SweepBackgroundTask.swift` (NoteLetter
// 910864a): the same BGProcessingTask, asked for on the same terms (network,
// external power, an hour out), re-queued first thing on every run. Port
// changes, each marked PORT below:
//   1. Flutter's OWN identifier, never the Swift app's
//      `xp.NoteLetter.camerasweep.refresh`.
//   2. The task is COMPLETED WHEN THE PASS ENDS. Swift's handler awaited
//      `startIfEnabled()`, which only STARTS a pass, so it reported the task
//      done at once and the system was free to suspend the app mid-pass.
//   3. The pass is the Dart side's (lib/state/camera_sweep_host.dart), over
//      the method channel `xp.noteletter/camera_sweep/background`: the same
//      service, ledger and tray as the foreground, in the one Flutter engine.
//      A task that arrives before Dart is listening waits for it ("attach").
//   4. Scheduled while the sweep is ON (the Dart side says so), not on every
//      launch whatever the setting.
//   5. On expiry the Dart side is told and given a moment to reach a safe
//      point — never between a capture session and its upload's hand-off —
//      and the task is completed (unsuccessfully) either way.
import BackgroundTasks
import Flutter
import Foundation
import UIKit

/// Background wiring for the camera-roll sweep.
///
/// **iOS gives no wake-on-new-photo.** The honest ceiling is a
/// `BGProcessingTask` — opportunistic, charging/idle, no guaranteed cadence —
/// plus a pass whenever the app comes to the foreground. The setup copy says
/// so (screens/settings.md, Mode).
///
/// `BGTaskScheduler.register` must run before launch finishes, so it is the
/// AppDelegate's first act.
enum SweepBackgroundTask {
    /// PORT 1. Listed in Info.plist's `BGTaskSchedulerPermittedIdentifiers`
    /// (registering an identifier that is not listed is a crash).
    static let identifier = "xp.NoteLetter.Flutter.camerasweep.refresh"

    static let channelName = "xp.noteletter/camera_sweep/background"

    /// The Dart side's own bound is 2 s (`CameraSweepService.expiryGrace`);
    /// this is the backstop if it never answers.
    static let expiryGrace: TimeInterval = 3

    /// A task that arrives with no Dart side listening (the engine never
    /// started in this background launch) is given up on after this.
    static let attachDeadline: TimeInterval = 60

    private static var channel: FlutterMethodChannel?
    private static var attached = false
    private static var current: SweepTask?
    private static var waitingForDart = false

    /// What happened, in order, for the device test (and a debugger).
    private static var trail: [[String: Any]] = []

    // MARK: - Launch

    static func register() {
        let ok = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            handle(task)
        }
        // false (not a crash) when Info.plist does not permit the identifier.
        note("registered", ["ok": ok])
    }

    static func connect(_ messenger: FlutterBinaryMessenger) {
        let c = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        c.setMethodCallHandler { call, result in handleCall(call, result) }
        channel = c
    }

    // MARK: - Scheduling (PORT 4)

    @discardableResult
    static func schedule() -> [String: Any] {
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresNetworkConnectivity = true
        // Recognition over a few hundred thumbnails is real work; asking for
        // external power keeps a sweep off the user's battery.
        request.requiresExternalPower = true
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            note("scheduled")
            return ["scheduled": true]
        } catch {
            // Said, not swallowed (Swift's was `try?`): the simulator answers
            // `unavailable`, and a phone with Background App Refresh off
            // answers `notPermitted` — either way no background pass will run.
            let why = "\(error.localizedDescription) (\((error as NSError).code))"
            NSLog("NoteLetter: camera sweep background task not scheduled — %@", why)
            note("notScheduled", ["error": why])
            return ["scheduled": false, "error": why]
        }
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        note("cancelled")
    }

    // MARK: - A run

    private static func handle(_ task: SweepTask) {
        schedule()   // always queue the next one first (Swift)
        current = task
        note("launched", ["appState": UIApplication.shared.applicationState.rawValue])
        task.expirationHandler = {
            DispatchQueue.main.async { expire(task) }
        }
        if attached {
            run(task)
        } else {
            waitingForDart = true
            note("waitingForDart")
            DispatchQueue.main.asyncAfter(deadline: .now() + attachDeadline) {
                guard waitingForDart, current === task else { return }
                note("noDart")
                finish(task, success: false)
            }
        }
    }

    /// PORT 2: completed when the Dart side's pass has ended, not when it began.
    private static func run(_ task: SweepTask) {
        waitingForDart = false
        note("run")
        channel?.invokeMethod("run", arguments: nil) { reply in
            let failed = reply is FlutterError || (reply as AnyObject?) === FlutterMethodNotImplemented
            note("ran", ["reply": String(describing: reply ?? "nil")])
            finish(task, success: !failed)
        }
    }

    /// PORT 5.
    private static func expire(_ task: SweepTask) {
        guard current === task else { return }
        note("expired")
        if waitingForDart {
            return finish(task, success: false)
        }
        channel?.invokeMethod("expire", arguments: nil) { _ in
            note("expireAcknowledged")
            finish(task, success: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + expiryGrace) {
            finish(task, success: false)
        }
    }

    private static func finish(_ task: SweepTask, success: Bool) {
        guard current === task else { return }
        current = nil
        waitingForDart = false
        task.setTaskCompleted(success: success)
        note("completed", ["success": success])
    }

    // MARK: - The Dart side's calls

    private static func handleCall(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "attach":
            attached = true
            note("attached")
            result(nil)
            if waitingForDart, let task = current { run(task) }

        case "setScheduled":
            if args["on"] as? Bool == true {
                result(schedule())
            } else {
                cancel()
                result(["scheduled": false])
            }

        #if DEBUG
        // What Apple's "Starting and Terminating Tasks During Development"
        // has typed into the debugger, sent from the app itself so a device
        // test can drive it. Debug builds only: a release build carries none
        // of this.
        case "debugSimulateLaunch":
            // iOS's own simulation needs the request iOS accepted. The
            // simulator accepts none (`submit` answers BGTaskSchedulerErrorDomain
            // 1, unavailable), and its `_simulateLaunch…` then finds nothing to
            // run — so there the same handler is driven with a stand-in task.
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                DispatchQueue.main.async {
                    if requests.contains(where: { $0.identifier == identifier }) {
                        note("simulateLaunch", ["via": "BGTaskScheduler"])
                        BGTaskScheduler.shared.perform(
                            NSSelectorFromString("_simulateLaunchForTaskWithIdentifier:"), with: identifier)
                    } else {
                        note("simulateLaunch", ["via": "standIn"])
                        handle(StandInTask())
                    }
                    result(nil)
                }
            }

        case "debugSimulateExpiration":
            if let standIn = current as? StandInTask {
                note("simulateExpiration", ["via": "standIn"])
                standIn.expire()
            } else {
                note("simulateExpiration", ["via": "BGTaskScheduler"])
                BGTaskScheduler.shared.perform(
                    NSSelectorFromString("_simulateExpirationForTaskWithIdentifier:"), with: identifier)
            }
            result(nil)

        case "debugPending":
            BGTaskScheduler.shared.getPendingTaskRequests { requests in
                let ids = requests.map { $0.identifier }
                DispatchQueue.main.async { result(ids) }
            }

        case "debugTrail":
            result(trail)

        case "debugUploads":
            let u = CameraSweepUploader.shared
            result(["wakes": u.wakes, "eventsDelivered": u.eventsDelivered])
        #endif

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func note(_ event: String, _ detail: [String: Any] = [:]) {
        var e = detail
        e["event"] = event
        e["atMs"] = CameraSweepUploader.nowMs()
        trail.append(e)
        if trail.count > 200 { trail.removeFirst(trail.count - 200) }
    }
}

/// What the handler needs of a task: the system's `BGTask`, or (debug
/// builds, the simulator) a stand-in for one.
protocol SweepTask: AnyObject {
    var expirationHandler: (() -> Void)? { get set }
    func setTaskCompleted(success: Bool)
}

extension BGTask: SweepTask {}

#if DEBUG
/// The simulator's BGTask: what the system would do to one, done by the
/// device test — launched, expired, completed. It proves the handler; that
/// iOS accepts the request and launches the task is a phone's to prove.
final class StandInTask: SweepTask {
    var expirationHandler: (() -> Void)?
    private(set) var completed: Bool?

    func expire() { expirationHandler?() }

    func setTaskCompleted(success: Bool) { completed = success }
}
#endif
