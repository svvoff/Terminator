import AppKit
import Darwin
import Foundation
import os

import TerminatorCore

/// Логгер адаптеров движка: подсистема продукта, категория `engine`.
///
/// Категорий у этой задачи две — `engine` и `quit` — и список закрытый. Читатель времени
/// старта и наблюдатель за списком процессов пишут в `engine`: это движковая сторона, а
/// `quit` принадлежит собственным строкам отправителя Apple Event.
///
/// Каждая интерполяция несёт `privacy: .public` — без исключений. Редакция происходит в
/// момент записи и необратима даже под sudo (findings §14).
nonisolated let engineLog = Logger(subsystem: TerminatorLog.subsystem, category: TerminatorLog.Category.engine)

/// Время старта процесса из ядра: `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID)` →
/// `kinfo_proc.kp_proc.p_starttime`.
///
/// Это канонический источник: он вернул значение для **90 из 90** процессов, не требует
/// разрешений и сходится с `launchDate` в пределах 0.4 с там, где есть оба (findings §3).
/// `p_starttime` — `timeval` на шкале стенных часов, то есть ровно той шкале, на которой
/// живут `enabledAt` и дедлайн (DEC-001), поэтому перевод в `Date` прямой.
///
/// Возвращает nil, если процесса нет или ядро не ответило. Никакого отката на `Date()`
/// здесь нет и быть не может: он выдал бы свежий полный лимит ровно тем запущенным при
/// логине приложениям, ради которых продукт существует (findings §3).
public nonisolated func kernelProcessStartTime(pid: pid_t) -> Date? {
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
    var info = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride

    let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
    guard result == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }

    let started = info.kp_proc.p_un.__p_starttime
    return Date(
        timeIntervalSince1970: TimeInterval(started.tv_sec)
            + TimeInterval(started.tv_usec) / 1_000_000
    )
}

/// Якорь отсчёта для одного приложения: `p_starttime`, а `launchDate` — только сверка.
///
/// Исходов два, и отката между ними нет (амендмент 3 карточки TASK-004):
///
/// - `p_starttime` есть — он и побеждает. Если `launchDate` тоже есть и расходится больше
///   чем на 0.4 с (findings §3), расхождение логируется, но решение не меняется;
/// - `p_starttime` нет — nil, каким бы ни был `launchDate`. Отсчёт для такого процесса не
///   начинается, и он переоценивается на следующей сверке.
///
/// Откат на `launchDate` был здесь и удалён по измерению 2026-08-28. У живого процесса
/// `p_starttime` доступен всегда — 90 из 90 (findings §3), — поэтому единственное состояние,
/// в котором откат вообще мог сработать, это процесс, который уже мёртв, но ещё висит в
/// `NSWorkspace.runningApplications`: список отстаёт от ядра до 19 с (findings §4). Там откат
/// не деградирует мягко, а выдумывает живой процесс из трупа: `launchDate` расходится с
/// `p_starttime` на миллисекунды, ключ сессии `(pid, p_starttime)` не сходится, и движок
/// снимает настоящую сессию ложным `app-exited`, чтобы завести на её месте фантомную и сразу
/// просроченную. На закрытии TextEdit это дало два `quit-requested` и три `app-exited` на одно
/// закрытие.
///
/// pid читается из живого объекта здесь, в точке использования, и никуда не кэшируется:
/// `processIdentifier` документирован как изменяемый на живом объекте (findings §10).
nonisolated func launchAnchor(of application: NSRunningApplication) -> Date? {
    let pid = application.processIdentifier
    let launchDate = application.launchDate

    guard let kernelTime = kernelProcessStartTime(pid: pid) else { return nil }

    if let launchDate {
        let disagreement = abs(launchDate.timeIntervalSince(kernelTime))
        if disagreement > 0.4 {
            engineLog.notice("launch time disagreement, p_starttime wins: bundleID=\(application.bundleIdentifier ?? "nil", privacy: .public) pid=\(pid, privacy: .public) pStarttime=\(logStamp(kernelTime), privacy: .public) launchDate=\(logStamp(launchDate), privacy: .public) deltaSeconds=\(disagreement, privacy: .public)")
        }
    }
    return kernelTime
}

/// Политика активации в терминах ядра продукта. `TerminatorCore` — только Foundation, и
/// системного enum там нет (findings §13); перевод живёт здесь.
nonisolated func corePolicy(_ policy: NSApplication.ActivationPolicy) -> ProcessActivationPolicy {
    switch policy {
    case .regular: .regular
    case .accessory: .accessory
    case .prohibited: .prohibited
    @unknown default: .prohibited
    }
}
