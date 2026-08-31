import Foundation

/// Момент на **suspending**-шкале часов: той семье, которая **стоит, пока Mac спит**.
///
/// Тип отдельный и назван по семье часов намеренно. В продукте живут две шкалы, и они хотят
/// противоположного поведения во сне системы (findings §9):
///
/// - **стенные часы** (`Date`, `Now.wall`) идут во сне, и на них живёт дедлайн убийцы:
///   восемь часов сна засчитываются в лимит (DEC-001);
/// - **suspending-семья** (`SuspendingClock`, `mach_absolute_time`, `CLOCK_UPTIME_RAW`,
///   `ProcessInfo.systemUptime`) во сне стоит, и на ней живёт накопление фокуса: восемь
///   часов сна дают **ноль** секунд фокуса (DEC-005).
///
/// Путаница между семьями молчалива — она даёт правдоподобные, но неверные числа месяцами, —
/// поэтому здесь нет и не будет ни одного инициализатора, преобразования или арифметики,
/// превращающих `Date` в `AwakeInstant` или `AwakeInstant` в `Date`. Единственное, что из
/// него извлекается, — `Duration` между двумя такими моментами.
///
/// Отдельно про Darwin: привычная идиома `clock_gettime(CLOCK_MONOTONIC)` сюда **не** годится
/// — на Darwin `CLOCK_MONOTONIC` считает сон, в противоположность Linux (findings §9), то
/// есть принадлежит семье дедлайна, ровно неверной здесь.
public struct AwakeInstant: Equatable, Hashable, Comparable, Sendable {

    /// Сколько бодрствования прошло от неуказанного начала — на практике от загрузки машины.
    ///
    /// Начало отсчёта не определено и определяться не должно: осмыслена только **разность**
    /// двух моментов, снятых в одном запуске машины.
    public let sinceOrigin: Duration

    public init(sinceOrigin: Duration) {
        self.sinceOrigin = sinceOrigin
    }

    /// Момент на той же шкале, отстоящий на `duration` вперёд.
    ///
    /// Нужен ровно для одного: сдвинуть якорь открытого спана на уже начисленную часть, не
    /// теряя субсекундного остатка.
    public func advanced(by duration: Duration) -> AwakeInstant {
        AwakeInstant(sinceOrigin: sinceOrigin + duration)
    }

    /// Бодрствование, прошедшее от `earlier` до этого момента.
    ///
    /// Отрицательного результата не бывает: шкала монотонна, а отрицательная разность
    /// означала бы перезагрузку между двумя чтениями — тогда честный ответ «ноль», а не
    /// отрицательные секунды фокуса.
    public func awakeSince(_ earlier: AwakeInstant) -> Duration {
        let delta = sinceOrigin - earlier.sinceOrigin
        return delta > .zero ? delta : .zero
    }

    public static func < (lhs: AwakeInstant, rhs: AwakeInstant) -> Bool {
        lhs.sinceOrigin < rhs.sinceOrigin
    }
}
