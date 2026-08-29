import AppKit
import Foundation
import os

import TerminatorCore

/// Логгер отправителя: собственные строки Apple Event, категория `quit`.
nonisolated let quitLog = Logger(subsystem: TerminatorLog.subsystem, category: TerminatorLog.Category.quit)

/// Отправитель вежливого quit — рукописный Apple Event и ничего больше (DEC-002).
///
/// Почему рукописный: `NSRunningApplication.terminate()` дизассемблирован и **хвостовым
/// вызовом уходит в `forceTerminate()` → `_LSKillApplication` по двум путям, которые
/// вызывающий не может отключить**, и оба достижимее всего для давно простаивающих фоновых
/// приложений — ровно тех, за которыми смотрит продукт (findings §4). Здесь отправляется то
/// же самое событие, без эскалации, с `kAEDoNotPromptForUserConsent` и с настоящим
/// `OSStatus` вместо `Bool`.
///
/// Ни `forceTerminate`, ни `terminate()`, ни сигналов здесь нет и быть не может.
///
/// Отправка идёт **вне главного потока**, как предписывают findings §4 и DEC-002.
public struct QuitSender: Sendable {

    public init() {}

    /// Просит приложение закрыться и возвращает исход на главный поток.
    ///
    /// `completion` зовётся ровно один раз.
    public func send(
        _ session: ProcessSession,
        completion: @escaping @MainActor @Sendable (QuitOutcome) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async {
            let outcome = Self.perform(session)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(outcome) }
            }
        }
    }

    /// Синхронная отправка. `nonisolated`, потому что вызывается только с фонового потока:
    /// отправка Apple Event на главном потоке запрещена (DEC-002, findings §4).
    private nonisolated static func perform(_ session: ProcessSession) -> QuitOutcome {
        // Значение `QuitOutcome.eventNotPermitted` продублировано в ядре числом: символ
        // живёт в CoreServices, а `TerminatorCore` — только Foundation. Совпадение с SDK
        // проверяется здесь, в единственном месте, где символ доступен.
        assert(QuitOutcome.eventNotPermitted == errAEEventNotPermitted)

        // Перепроверка идентичности **непосредственно перед отправкой**, по ядру.
        //
        // Присутствие процесса в `NSWorkspace.runningApplications` решением быть не может:
        // список отстаёт от ядра — измерено 0.52 с, 1.53 с и один раз более 19 с при 16 мс
        // на четырёх других подопытных (findings §4). Ядро авторитетно, список — нет.
        //
        // Оба отрицательных исхода дают `.notRunning`: и «`sysctl` не вернул ничего»
        // (процесс исчез), и «вернул другое время старта» (pid переиспользован, и он
        // принадлежит уже другому процессу).
        guard let currentStart = kernelProcessStartTime(pid: session.pid) else {
            quitLog.notice("quit not sent, process is gone: bundleID=\(session.bundleIdentifier, privacy: .public) pid=\(session.pid, privacy: .public) expectedStart=\(logStamp(session.processStartTime), privacy: .public)")
            return .notRunning
        }
        guard currentStart == session.processStartTime else {
            quitLog.notice("quit not sent, pid belongs to another process: bundleID=\(session.bundleIdentifier, privacy: .public) pid=\(session.pid, privacy: .public) expectedStart=\(logStamp(session.processStartTime), privacy: .public) actualStart=\(logStamp(currentStart), privacy: .public)")
            return .notRunning
        }

        var pid = session.pid
        var target = AEAddressDesc()
        let addressed = AECreateDesc(typeKernelProcessID, &pid, MemoryLayout<pid_t>.size, &target)
        guard addressed == noErr else {
            quitLog.notice("AECreateDesc failed: bundleID=\(session.bundleIdentifier, privacy: .public) pid=\(session.pid, privacy: .public) status=\(addressed, privacy: .public)")
            return .refused(OSStatus(addressed))
        }
        defer { AEDisposeDesc(&target) }

        var event = AppleEvent()
        let created = withUnsafePointer(to: &target) { targetPointer in
            AECreateAppleEvent(
                kCoreEventClass,
                kAEQuitApplication,
                targetPointer,
                AEReturnID(kAutoGenerateReturnID),
                AETransactionID(kAnyTransactionID),
                &event
            )
        }
        guard created == noErr else {
            quitLog.notice("AECreateAppleEvent failed: bundleID=\(session.bundleIdentifier, privacy: .public) pid=\(session.pid, privacy: .public) status=\(created, privacy: .public)")
            return .refused(OSStatus(created))
        }
        defer { AEDisposeDesc(&event) }

        // `kAENormalTimeout` в SDK не существует: константы — `kAEDefaultTimeout` (-1) и
        // `kNoTimeOut` (-2), `AEDataModel.h:431-432` (findings §4, амендмент 2.2 карточки).
        let mode = AESendMode(kAENoReply | kAEDoNotPromptForUserConsent)
        let status = withUnsafePointer(to: &event) {
            AESendMessage($0, nil, mode, kAEDefaultTimeout)
        }

        guard status == noErr else {
            quitLog.notice("quit refused: bundleID=\(session.bundleIdentifier, privacy: .public) pid=\(session.pid, privacy: .public) status=\(status, privacy: .public)")
            return .refused(status)
        }

        // `noErr` значит «принято к доставке» и ничего больше: приложение с несохранённым
        // документом ответило так же и оставалось живым на 20-й секунде и на 6-й минуте
        // (findings §4). Смерть приходит позже и отдельным путём.
        quitLog.notice("quit accepted for delivery: bundleID=\(session.bundleIdentifier, privacy: .public) pid=\(session.pid, privacy: .public) startTime=\(logStamp(session.processStartTime), privacy: .public) deadline=\(logStamp(session.deadline), privacy: .public)")
        return .requestSent
    }
}
