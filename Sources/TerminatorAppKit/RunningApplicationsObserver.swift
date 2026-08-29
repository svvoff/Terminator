import AppKit
import Foundation

import TerminatorCore

/// Наблюдатель за списком запущенных приложений: KVO по
/// `NSWorkspace.shared.runningApplications` с `[.new, .old]`.
///
/// Почему KVO, а не уведомления: `willLaunch` / `didLaunch` / `didTerminate` приходят только
/// для `.regular` приложений и за три минуты живого наблюдения **не пришли вообще ни разу**,
/// тогда как KVO сработал для всех политик активации (findings §2). Уведомления здесь не
/// используются вовсе — ни как источник истины, ни как удобство.
///
/// Обе стороны наблюдения — подсказки, а не истина. Пропущенная вставка или удаление
/// восстанавливается 30-секундной сверкой, и именно поэтому сверка не опциональна: продукт
/// не показывает предупреждений, так что у пропущенного события нет ни одного видимого
/// симптома (DEC-004, findings §2).
public final class RunningApplicationsObserver {

    private var observation: NSKeyValueObservation?

    public init() {}

    /// Начинает наблюдение. Вставки уходят в `onInsertions`, удаления — в `onRemovals`.
    ///
    /// pid удалённого объекта отдаётся только если он ещё осмыслен: у завершившегося
    /// `NSRunningApplication` `processIdentifier` документирован как `-1`. Такое удаление
    /// молча пропускается — сессию снимет ближайшая сверка по отсутствию в снимке, ровно
    /// тот путь, ради которого сверка авторитетна в обе стороны.
    public func start(
        onInsertions: @escaping @MainActor @Sendable ([ObservedProcess]) -> Void,
        onRemovals: @escaping @MainActor @Sendable ([pid_t]) -> Void
    ) {
        // Поток доставки KVO не оговорен: уведомление приходит на том потоке, который
        // изменил список. Поэтому здесь снимаются только Sendable-значения, а движок
        // трогается уже на главной очереди — `MainActor.assumeIsolated` на чужом потоке
        // не «предположил бы», а уронил бы процесс.
        observation = NSWorkspace.shared.observe(
            \.runningApplications,
            options: [.new, .old]
        ) { _, change in
            switch change.kind {
            case .insertion:
                let inserted = (change.newValue ?? []).map(observedProcess(from:))
                guard !inserted.isEmpty else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { onInsertions(inserted) }
                }

            case .removal:
                let pids = (change.oldValue ?? [])
                    .map(\.processIdentifier)
                    .filter { $0 > 0 }
                guard !pids.isEmpty else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { onRemovals(pids) }
                }

            case .setting, .replacement:
                // Список заменён целиком: что именно изменилось, отсюда не видно.
                // Разберётся сверка.
                break

            @unknown default:
                break
            }
        }
    }

    public func stop() {
        observation?.invalidate()
        observation = nil
    }

    deinit {
        observation?.invalidate()
    }
}

/// Перевод живого `NSRunningApplication` в то, что понимает ядро.
///
/// `processIdentifier` читается здесь, в точке использования, и никуда не кэшируется
/// (findings §10). Обе опциональности передаются в ядро как есть: и процесс без bundle id,
/// и процесс без времени старта переоцениваются на следующей сверке, а не отбрасываются
/// навсегда — и решает это редьюсер, а не адаптер.
nonisolated func observedProcess(from application: NSRunningApplication) -> ObservedProcess {
    ObservedProcess(
        pid: application.processIdentifier,
        bundleIdentifier: application.bundleIdentifier,
        startTime: launchAnchor(of: application),
        activationPolicy: corePolicy(application.activationPolicy)
    )
}
