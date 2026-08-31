import Foundation

/// Учёт фокуса внутри редьюсера: открытый спан, набор причин паузы и дневная свёртка.
///
/// Отдельный тип, а не россыпь полей на `WatchEngine`, по двум причинам: инвариант порядка
/// («слить открытый спан **до** удаления сессии из таблицы») проверяется в одном месте, и
/// дифф по принятому 370-строчному редьюсеру остаётся точечным.
///
/// Ничего не логирует и не эмитит эффектов: фокус — это состояние, которое читают, а лог
/// пишет адаптер своим логгером категории `focus`.
struct FocusLedger: Equatable, Sendable {

    /// Открытый спан: одно приложение, непрерывно фронтмост с двух якорей.
    ///
    /// Якорей **два**, и оба обязательны. Длительность приходит с suspending-шкалы
    /// (`startAwake`), календарный день — со стенной (`startWall`), а конверсия между
    /// семьями запрещена (findings §9). Без стенного якоря спан нельзя расщепить по
    /// полуночи; без suspending-якоря восемь часов сна дали бы восемь часов фокуса.
    struct Span: Equatable, Sendable {

        let bundleIdentifier: String

        /// Ключ сессии, если время старта процесса прочитано. По нему срабатывает слив при
        /// удалении сессии из таблицы движка.
        let key: SessionKey?

        var startWall: Date

        var startAwake: AwakeInstant
    }

    /// Накопленное **этим запуском** Terminator. К записанному прошлыми запусками это
    /// прибавляет писатель (`FocusStore`), а не редьюсер.
    private(set) var rollup: FocusRollup = .empty

    private(set) var span: Span?

    /// Последнее известное фронтмост-приложение. Нужно, чтобы возобновление открыло новый
    /// спан для того, что фронтмост в тот момент: вход `.focusResumed` несёт только причину.
    private(set) var frontmost: FrontmostApp?

    /// Непогашенные причины паузы. Накопление идёт, только пока множество пусто.
    private(set) var outstandingPauses: Set<FocusPauseReason> = []

    var isPaused: Bool { !outstandingPauses.isEmpty }

    // MARK: - Начисление

    /// Копия леджера, в которой всё бодрствование до `now` уже начислено.
    ///
    /// Функция **чистая**, и это не украшение: тот же расчёт нужен и для записи состояния
    /// (`accrue`), и для чтения свёртки «по состоянию на сейчас» (`rollup(in:at:)`) — иначе
    /// открытый спан не попадал бы в слив, и каждый слив терял бы всё с момента последнего
    /// входа. Идемпотентна: якоря сдвигаются ровно на начисленное, поэтому повторный вызов
    /// с тем же `now` ничего не добавляет.
    func accrued(in config: RuleConfig, at now: Now) -> FocusLedger {
        guard var span else { return self }
        var updated = self

        // Расщепление по границам локальных дней. Цикл, а не один шаг: спан может пережить
        // не одну полночь — Mac, разбуженный через двое суток, приносит именно это.
        while true {
            let boundary = DayKey.startOfNextDay(after: span.startWall, in: now.timeZone)
            guard boundary > span.startWall, now.wall >= boundary else { break }

            let wallTotal = now.wall.timeIntervalSince(span.startWall)
            let wallBefore = boundary.timeIntervalSince(span.startWall)
            let awake = now.awake.awakeSince(span.startAwake)

            // Делится **пропорционально стенным интервалам** до и после полуночи: сама
            // awake-дельта не знает, где внутри неё была полночь. Остаток считается
            // вычитанием, а не второй долей, поэтому сумма двух частей точно равна целому и
            // граничная секунда посчитана один раз.
            let before = wallTotal > 0 ? Self.portion(of: awake, byWallFraction: wallBefore / wallTotal) : .zero
            updated.rollup.add(
                before,
                to: span.bundleIdentifier,
                on: DayKey.containing(span.startWall, in: now.timeZone)
            )
            span.startAwake = span.startAwake.advanced(by: before)
            span.startWall = boundary
        }

        updated.rollup.add(
            now.awake.awakeSince(span.startAwake),
            to: span.bundleIdentifier,
            on: DayKey.containing(span.startWall, in: now.timeZone)
        )
        span.startAwake = now.awake
        // Стенной якорь назад не едет: перевод часов назад не должен воскрешать уже
        // начисленный интервал.
        span.startWall = max(span.startWall, now.wall)
        updated.span = span

        // Правило выключили или удалили, пока приложение было фронтмост: заработанное
        // остаётся, спан закрывается. Для сессии, снятой тем же `.configChanged`, это
        // происходит ровно в момент правки — слив по удалению сессии зовётся уже с новым
        // конфигом.
        if config.rule(for: span.bundleIdentifier)?.enabledAt == nil {
            updated.span = nil
        }
        return updated
    }

    /// Доля длительности по стенной пропорции.
    ///
    /// Считается через **секунды**, а не штатным `Duration * Double`: тот переводит
    /// длительность в аттосекунды и умножает их как Double, теряя на суточном масштабе
    /// ~4·10⁻¹² с. Дребезга хватает, чтобы у следующего дня завелась запись «фокус
    /// 0,000000000004 секунды». В секундах Double на этом масштабе точен, а остаток всё
    /// равно берётся вычитанием, поэтому сумма двух частей точно равна целому.
    private static func portion(of duration: Duration, byWallFraction fraction: Double) -> Duration {
        guard fraction > 0 else { return .zero }
        guard fraction < 1 else { return duration }
        let seconds = Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        return .seconds(seconds * fraction)
    }

    /// Свёртка по состоянию на `now`, включая ещё не закрытый спан. Это то, что уходит в файл.
    func rollup(in config: RuleConfig, at now: Now) -> FocusRollup {
        accrued(in: config, at: now).rollup
    }

    private mutating func accrue(in config: RuleConfig, at now: Now) {
        self = accrued(in: config, at: now)
    }

    // MARK: - Входы

    /// Фронтмост сменился.
    mutating func frontmostChanged(to app: FrontmostApp?, in config: RuleConfig, at now: Now) {
        // Активация не-`.regular` приложения **прозрачна**: `frontmostApplication` законно
        // сообщает помощников и системный UI — один прогон разведки поймал фронтмостом
        // `com.apple.UserNotificationCenter` (findings §10). Системная модалка, укравшая
        // фокус на две секунды, обязана оставить прерванный спан целым и накапливающим,
        // поэтому здесь не меняется вообще ничего — включая память о фронтмосте.
        if let app, app.activationPolicy != .regular { return }

        accrue(in: config, at: now)
        frontmost = app
        span = nil
        openSpan(in: config, at: now)
    }

    /// Пауза: накопление останавливается, открытый спан закрывается.
    mutating func pause(_ reason: FocusPauseReason, in config: RuleConfig, at now: Now) {
        accrue(in: config, at: now)
        outstandingPauses.insert(reason)
        span = nil
    }

    /// Возобновление. Открывает **новый** спан для того, что фронтмост в этот момент, — и
    /// только когда снята последняя причина.
    ///
    /// Причина, которая не поднималась, игнорируется: адаптер не может погасить чужую паузу.
    mutating func resume(_ reason: FocusPauseReason, in config: RuleConfig, at now: Now) {
        guard outstandingPauses.remove(reason) != nil, outstandingPauses.isEmpty else { return }
        openSpan(in: config, at: now)
    }

    /// Смена календарного дня. Расщепление делает `accrued`, потому что день выводится из
    /// `now.wall`, а не из входа: опоздавший или потерянный `.dayRollover` исправляется
    /// ближайшим следующим начислением, а не теряет секунды.
    mutating func dayRollover(in config: RuleConfig, at now: Now) {
        accrue(in: config, at: now)
    }

    // MARK: - Инвариант порядка

    /// **Слить открытый спан до того, как запись удалена из таблицы сессий.**
    ///
    /// Вызывается непосредственно перед удалением, из всех четырёх мест, где движок снимает
    /// сессию. Гард на присутствие ключа в таблице — не перестраховка, а сам инвариант:
    /// переставь этот вызов за удаление, и спан не сольётся. Пробник разведки поймал ровно
    /// этот баг на первом прогоне — движок чистил состояние процесса до слива и молча терял
    /// финальный спан каждой сессии, закончившейся закрытием (findings §13). Закрытием
    /// заканчивается обычный случай, так что баг съел бы бо́льшую часть данных, оставив итоги
    /// правдоподобными.
    mutating func endSpan(
        ofSession key: SessionKey,
        in sessions: [SessionKey: ProcessSession],
        config: RuleConfig,
        at now: Now
    ) {
        guard sessions[key] != nil else { return }

        if let frontmost, frontmost.sessionKey == key {
            self.frontmost = nil
        }
        guard span?.key == key else { return }
        accrue(in: config, at: now)
        span = nil
    }

    // MARK: - Открытие спана

    /// Открывает спан, если для этого есть всё: пауз нет, фронтмост известен, у него есть
    /// bundle id и **включённое** правило.
    ///
    /// Наличие записи в таблице сессий здесь не требуется, и это не упущение: `adopt`
    /// заводит сессию только при прочитанном `p_starttime`, так что приложение может быть
    /// фронтмост, иметь включённое правило и не иметь записи в таблице. Не записывать ему
    /// фокус было бы тихой потерей.
    private mutating func openSpan(in config: RuleConfig, at now: Now) {
        guard !isPaused,
              let app = frontmost,
              app.activationPolicy == .regular,
              let bundleIdentifier = app.bundleIdentifier,
              config.rule(for: bundleIdentifier)?.enabledAt != nil
        else {
            return
        }
        span = Span(
            bundleIdentifier: bundleIdentifier,
            key: app.sessionKey,
            startWall: now.wall,
            startAwake: now.awake
        )
    }
}
