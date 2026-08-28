// TASK-001 probe — throwaway. Reused, deliberately, by TASK-009.
//
// Not product code and not a test fixture. It answered the four open questions at the bottom
// of docs/product/recon/macos-findings.md; TASK-009 then reused it to ask whether §5's
// no-consent-needed result holds against apps other than TextEdit.
//
// TASK-001's header used to say "not a dependency of any later card". TASK-009's card retires
// that line on purpose: the non-goal existed to stop throwaway code becoming product
// infrastructure, and TASK-009 is another throwaway spike rather than the product, so the
// reuse keeps the rule's spirit while breaking its letter.
//
// Safety rules taken verbatim from the task cards, all enforced below:
//   * a hardcoded allow-list, and the probe refuses to address anything outside it;
//   * the pid is re-read at the moment of use and the bundle identifier re-confirmed
//     immediately before every send — never cached across a use boundary (findings §10);
//   * no forced-termination API and no process signals of any kind — the polite Apple Event
//     is the only way this probe ever ends another process;
//   * the quit event is hand-rolled exactly as findings §4 prescribes.
//
// Every Apple Event call runs on a background queue, never on the main thread — that is
// itself part of what question 4 measures.

import AppKit
import Darwin
import Foundation

// MARK: - Allow-list

/// The ONLY bundle identifiers this probe may ever address, and there is no way to pass one
/// in from the command line — widening this list means editing this file and rebuilding.
/// That is the whole value of the guard, and TASK-009's card names a command-line target
/// parameter as grounds for rejection.
///
/// TASK-001 had one entry. TASK-009 widened it to five, chosen by the operator to span the
/// axes its card names: first-party vs third-party, sandboxed vs not, Mac App Store vs
/// directly distributed, document-based vs not, scriptable vs not.
///
/// Which one a run addresses is decided by the state of the machine, not by an argument:
/// exactly one of them must be running. See `findSubject()`.
let allowedBundleIDs: [String] = [
    "com.apple.TextEdit",       // Apple, sandboxed, document-based, scriptable
    "com.apple.calculator",     // Apple, sandboxed, NOT document-based, NOT scriptable
    "org.videolan.vlc",         // third party, NOT sandboxed, document-based, scriptable
    "com.todoist.mac.Todoist",  // third party, sandboxed, Mac App Store
    "md.obsidian"               // third party, Electron — many helper processes (findings §10)
]

// MARK: - Output channel
//
// Launched via `open`, the probe is its own responsible process — which is the entire point,
// see the task report — but LaunchServices gives it no usable stdout. Everything therefore
// goes to a file next to the bundle as well as to stdout, and the file is the channel the
// operator actually reads.

let outputURL: URL = URL(fileURLWithPath: Bundle.main.bundlePath)
    .deletingLastPathComponent()
    .appendingPathComponent("probe-output.txt")

func emit(_ line: String = "") {
    fputs(line + "\n", stdout)
    guard let data = (line + "\n").data(using: .utf8) else { return }
    if let handle = try? FileHandle(forWritingTo: outputURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: outputURL)
    }
}

// MARK: - Reporting helpers

/// Names the OSStatus values this spike can actually produce. Anything outside the table is
/// reported as `unnamed` rather than guessed at — an unnamed status is a finding, not a bug.
func statusName(_ status: OSStatus) -> String {
    switch status {
    case 0: return "noErr"
    case -50: return "paramErr"
    case -600: return "procNotFound"
    case -609: return "connectionInvalid"
    case -1700: return "errAECoercionFail"
    case -1701: return "errAEDescNotFound"
    case -1708: return "errAEEventNotHandled"
    case -1712: return "errAETimeout"
    case -1743: return "errAEEventNotPermitted"
    case -1744: return "errAEEventWouldRequireUserConsent"
    default: return "unnamed"
    }
}

func report(_ label: String, _ status: OSStatus) {
    emit("  \(label): \(status) (\(statusName(status)))")
}

func fourCC(_ code: FourCharCode) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xFF), UInt8((code >> 16) & 0xFF),
        UInt8((code >> 8) & 0xFF), UInt8(code & 0xFF),
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? "????"
}

func seconds(_ duration: ContinuousClock.Duration) -> String {
    let (s, attos) = duration.components
    return String(format: "%.3f s", Double(s) + Double(attos) / 1e18)
}

// MARK: - Subject resolution

/// Every running process whose bundle identifier is on the allow-list, whatever its
/// activation policy. Used to pick the subject, and to explain a refusal.
func allowedRunningApps() -> [NSRunningApplication] {
    NSWorkspace.shared.runningApplications.filter {
        guard let identifier = $0.bundleIdentifier else { return false }
        return allowedBundleIDs.contains(identifier)
    }
}

/// Looks the subject up fresh, every time. Nothing about the target is ever stored between
/// calls — that is the whole point of findings §10.
///
/// With five allow-listed apps and no command-line target parameter, the subject is not
/// chosen: it is *the* allow-listed app that happens to be running. Zero is a refusal, and so
/// is more than one — findings §10 records that several live NSRunningApplication instances
/// can share a bundle identifier, and a probe whose job is to quit things must never pick on
/// the operator's behalf. Ambiguity is resolved by closing the extra app, not by guessing.
func findSubject() -> NSRunningApplication? {
    let running = allowedRunningApps()
    let candidates = running.filter { $0.activationPolicy == .regular }
    guard candidates.count == 1 else {
        emit("  REFUSED: exactly one allow-listed .regular app must be running, found \(candidates.count)")
        if running.isEmpty {
            emit("    (nothing from the allow-list is running)")
        }
        for app in running {
            emit("    \(app.bundleIdentifier ?? "nil") pid=\(app.processIdentifier) "
                + "policy=\(app.activationPolicy.rawValue) isTerminated=\(app.isTerminated)")
        }
        return nil
    }
    return candidates[0]
}

/// Builds an address descriptor for the subject and hands it to `body`, or refuses.
///
/// The identity check happens here, immediately before the descriptor is built, so no caller
/// can hold a pid across a use boundary even by accident.
func withSubjectTarget<T>(_ body: (UnsafePointer<AEAddressDesc>, pid_t) -> T?) -> T? {
    guard let app = findSubject() else {
        // findSubject already emitted what it saw and why it refused.
        return nil
    }
    // Re-confirm identity at the moment of use, then read the pid (findings §10).
    guard let identifier = app.bundleIdentifier,
          allowedBundleIDs.contains(identifier),
          !app.isTerminated else {
        emit("  REFUSED: subject identity changed between lookup and use — nothing was addressed")
        return nil
    }
    var pid = app.processIdentifier
    emit("  subject: \(identifier) pid=\(pid)")

    var desc = AEAddressDesc()
    let created = AECreateDesc(typeKernelProcessID, &pid, MemoryLayout<pid_t>.size, &desc)
    guard created == noErr else {
        report("AECreateDesc", OSStatus(created))
        return nil
    }
    defer { AEDisposeDesc(&desc) }
    return withUnsafePointer(to: &desc) { body($0, pid) }
}

/// Liveness test that does not signal the process. The usual idiom sends signal 0; this card
/// forbids that whole family, so the check goes through sysctl instead.
func pidIsAlive(_ pid: pid_t) -> Bool {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    let result = sysctl(&mib, 4, &info, &size, nil, 0)
    guard result == 0 else { return false }
    return size > 0 && info.kp_proc.p_pid == pid
}

// MARK: - Commands

func printIdentity() {
    emit("== identity ==")
    emit("  bundleIdentifier: \(Bundle.main.bundleIdentifier ?? "nil")")
    emit("  bundlePath: \(Bundle.main.bundlePath)")
    emit("  buildTag: \(buildTag)")
    emit("  activationPolicy: \(NSApp.activationPolicy().rawValue) (0=regular 1=accessory 2=prohibited)")
    let usage = Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription")
    emit("  NSAppleEventsUsageDescription: \(usage == nil ? "ABSENT" : "present")")
}

func printStatus() {
    emit("== subject status ==")
    let all = allowedRunningApps()
    for app in all {
        emit("  \(app.bundleIdentifier ?? "nil"): pid=\(app.processIdentifier) "
            + "policy=\(app.activationPolicy.rawValue) isTerminated=\(app.isTerminated)")
    }
    for identifier in allowedBundleIDs
    where !all.contains(where: { $0.bundleIdentifier == identifier }) {
        emit("  \(identifier): not running")
    }
}

/// Question 1 / 4 workhorse. `ask == false` is also the reset verifier the card demands
/// before every trial: it must return -1744 or the trial is void.
func permission(eventClass: AEEventClass, eventID: AEEventID, ask: Bool) {
    emit("== AEDeterminePermissionToAutomateTarget ==")
    emit("  event: \(fourCC(eventClass))/\(fourCC(eventID)), askUserIfNeeded: \(ask)")
    emit("  thread: \(Thread.isMainThread ? "MAIN" : "background")")
    _ = withSubjectTarget { target, _ -> OSStatus? in
        let clock = ContinuousClock()
        let started = clock.now
        let status = AEDeterminePermissionToAutomateTarget(target, eventClass, eventID, ask)
        let elapsed = clock.now - started
        report("status", status)
        emit("  call blocked for: \(seconds(elapsed))")
        return status
    }
}

/// Question 3. The sequence is findings §4 verbatim, with one substitution recorded in the
/// task report: the header constant is `kAEDefaultTimeout` (-1); `kAENormalTimeout` does not
/// exist in the SDK.
@discardableResult
func handRolledQuit() -> pid_t? {
    emit("== hand-rolled quit Apple Event ==")
    emit("  thread: \(Thread.isMainThread ? "MAIN" : "background")")
    var sentToPid: pid_t?
    _ = withSubjectTarget { target, pid -> OSStatus? in
        sentToPid = pid
        var event = AppleEvent()
        let created = AECreateAppleEvent(
            kCoreEventClass, kAEQuitApplication, target,
            AEReturnID(kAutoGenerateReturnID), AETransactionID(kAnyTransactionID), &event)
        guard created == noErr else {
            report("AECreateAppleEvent", OSStatus(created))
            return OSStatus(created)
        }
        defer { AEDisposeDesc(&event) }

        let mode = AESendMode(kAENoReply | kAEDoNotPromptForUserConsent)
        emit("  sendMode: kAENoReply | kAEDoNotPromptForUserConsent (0x\(String(mode, radix: 16)))")
        emit("  timeout: kAEDefaultTimeout (\(kAEDefaultTimeout))")

        let clock = ContinuousClock()
        let started = clock.now
        let status = withUnsafePointer(to: &event) {
            AESendMessage($0, nil, mode, kAEDefaultTimeout)
        }
        let elapsed = clock.now - started
        report("AESendMessage", status)
        emit("  AESendMessage blocked for: \(seconds(elapsed))")
        emit("  NOTE: kAENoReply — noErr means 'accepted for delivery', not 'quit'.")
        return status
    }
    return sentToPid
}

/// Death is observed, never inferred from the send's return value (findings §4).
///
/// Two independent views are polled side by side on purpose. sysctl(KERN_PROC_PID) asks the
/// kernel and cannot be stale. NSWorkspace.runningApplications is what findings §2 builds the
/// product's whole detection story on — and it is maintained through the main run loop, so
/// reading it from a background queue may lag. Any gap between the two columns is a finding
/// about the API the engine is going to depend on.
func observeTermination(pid: pid_t?, forSeconds limit: Int) {
    emit("== observing termination (not the return value) ==")
    guard let pid else {
        emit("  nothing was sent — nothing to observe")
        return
    }
    let clock = ContinuousClock()
    let started = clock.now
    var kernelSaw: String?
    var workspaceSaw: String?
    for _ in 0...(limit * 4) {
        if kernelSaw == nil, !pidIsAlive(pid) {
            kernelSaw = seconds(clock.now - started)
            emit("  sysctl(KERN_PROC_PID): pid \(pid) gone after \(kernelSaw!)")
        }
        if workspaceSaw == nil, findSubject() == nil {
            workspaceSaw = seconds(clock.now - started)
            emit("  NSWorkspace.runningApplications: gone after \(workspaceSaw!)")
        }
        if kernelSaw != nil, workspaceSaw != nil { break }
        usleep(250_000)
    }
    if kernelSaw == nil { emit("  sysctl(KERN_PROC_PID): STILL ALIVE after \(limit)s") }
    if workspaceSaw == nil { emit("  NSWorkspace.runningApplications: STILL LISTED after \(limit)s") }
}

/// Question 4, step 4. Addresses a pid only after proving it is not alive.
func deadPidCheck(pid: pid_t, eventClass: AEEventClass, eventID: AEEventID) {
    emit("== AEDeterminePermissionToAutomateTarget against a dead pid ==")
    guard !pidIsAlive(pid) else {
        emit("  REFUSED: pid \(pid) is alive. This command only ever addresses a pid proven dead,")
        emit("           so it cannot be pointed at a recycled pid belonging to something else.")
        return
    }
    emit("  pid \(pid) confirmed not alive via sysctl(KERN_PROC_PID)")
    var target = pid
    var desc = AEAddressDesc()
    let created = AECreateDesc(typeKernelProcessID, &target, MemoryLayout<pid_t>.size, &desc)
    guard created == noErr else {
        report("AECreateDesc", OSStatus(created))
        return
    }
    defer { AEDisposeDesc(&desc) }
    let status = withUnsafePointer(to: &desc) {
        AEDeterminePermissionToAutomateTarget($0, eventClass, eventID, true)
    }
    report("status", status)
}

/// Question 2. Runs both calls in one process so the survival markers say exactly which call
/// killed it, if either did.
func missingUsageDescriptionTrial() {
    emit("== question 2: behaviour with the Info.plist key as built ==")
    printIdentity()
    emit("--- about to call AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true) ---")
    fflush(stdout)
    permission(eventClass: kCoreEventClass, eventID: kAEQuitApplication, ask: true)
    emit("SURVIVED: the AEDeterminePermissionToAutomateTarget call returned")
    fflush(stdout)
    emit("--- about to send the hand-rolled quit ---")
    fflush(stdout)
    let pid = handRolledQuit()
    emit("SURVIVED: the AESendMessage call returned")
    fflush(stdout)
    observeTermination(pid: pid, forSeconds: 5)
}

// MARK: - Entry point

func usage() {
    emit("""
    usage: probe <command>

      identity                    print bundle identity and Info.plist facts
      status                      print subject running state
      check  <wildcard|quit>      AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)
      ask    <wildcard|quit>      AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true)
      quit                        hand-rolled quit Apple Event, then observe termination
      send                        hand-rolled quit Apple Event only, no observation
      deadpid <pid>               permission check against a pid proven dead
      q2                          question 2 combined trial

    This probe can address only these apps, and exactly one of them must be running:
      \(allowedBundleIDs.joined(separator: "\n      "))
    """)
}

func eventPair(_ name: String) -> (AEEventClass, AEEventID)? {
    switch name {
    case "wildcard": return (AEEventClass(typeWildCard), AEEventID(typeWildCard))
    case "quit": return (kCoreEventClass, kAEQuitApplication)
    default: return nil
    }
}

func run() {
    let args = Array(CommandLine.arguments.dropFirst())
    emit("")
    emit("### \(Date()) :: probe \(args.joined(separator: " ")) ###")
    guard let command = args.first else {
        usage()
        return
    }

    switch command {
    case "identity":
        printIdentity()
    case "status":
        printStatus()
    case "check", "ask":
        guard args.count >= 2, let pair = eventPair(args[1]) else {
            usage()
            return
        }
        permission(eventClass: pair.0, eventID: pair.1, ask: command == "ask")
    case "quit":
        let pid = handRolledQuit()
        observeTermination(pid: pid, forSeconds: 20)
    case "send":
        handRolledQuit()
    case "deadpid":
        guard args.count >= 2, let pid = pid_t(args[1]) else {
            usage()
            return
        }
        let which = args.count >= 3 ? args[2] : "quit"
        guard let pair = eventPair(which) else {
            usage()
            return
        }
        deadPidCheck(pid: pid, eventClass: pair.0, eventID: pair.1)
    case "q2":
        missingUsageDescriptionTrial()
    default:
        usage()
    }
}

// Packaged as an .app with LSUIElement, so the process is .accessory: connected to the window
// server (a consent dialog can appear) but with no Dock icon. Findings §7.
let application = NSApplication.shared
application.setActivationPolicy(.accessory)

DispatchQueue.global(qos: .userInitiated).async {
    run()
    fflush(stdout)
    exit(0)
}

application.run()
