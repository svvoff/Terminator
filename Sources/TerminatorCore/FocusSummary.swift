import Foundation

/// Сводка фокуса за семь календарных дней: **чистая функция** от снимка свёртки, конфига и
/// момента времени.
///
/// Живёт в ядре по прецеденту `PopoverViewModel`: каждое число и каждая строка, которые покажет
/// секция «Focus», считаются и проверяются здесь, без AppKit и без запущенного приложения.
/// Снимок приходит параметром — сводка ничего не читает с диска и не смотрит на часы.
///
/// Рамки: DEC-005, DEC-006, DEC-008.
///
/// **Единицы в ячейке и в итоге намеренно разные.** Ячейка — целые минуты (`cellText(_:)`),
/// итог строки — точная величина крупнейшими единицами (`totalText(_:)`). Приложение с 11 с
/// за неделю показывает итог `11 s` и ячейку `<1`. Это не рассогласование, а два разных
/// вопроса: ячейка — «сколько минут в этот день», итог — «сколько всего, без округлений».
public struct FocusSummary: Equatable, Sendable {

    /// Длина окна. Константа, не параметр: других диапазонов нет (non-goal).
    public static let dayCount = 7

    /// Ровно семь ключей в хронологическом порядке: первый — шесть дней назад, последний — сегодня.
    ///
    /// Окно — календарные дни назад от сегодня, а не «последние дни, где есть данные»: в файле
    /// бывают пропуски, и сжатое окно выдало бы разреженные дни за подряд идущие.
    public let days: [DayKey]

    /// Сколько из `days` присутствует в свёртке ключом.
    ///
    /// Определение буквальное: ключ есть — день записан, даже если словарь приложений пуст.
    public let recordedDayCount: Int

    /// Строки в порядке показа: итог по убыванию, при равенстве — `bundleIdentifier` по
    /// возрастанию. Почему здесь допустима сортировка по величине — см. комментарий у сортировки.
    /// Предусловие вызывающего: порядок по величине верен, пока сводку строят один раз на
    /// открытие секции из замороженного снимка, а не в теле периодически перерисовываемого вида.
    public let rows: [FocusSummaryRow]

    /// Строит сводку за окно, заканчивающееся календарным днём `now.wall` в поясе `now.timeZone`.
    ///
    /// Набор строк — **объединение** двух источников: каждый bundle id, у которого есть запись
    /// хотя бы в одном дне окна, и каждое включённое правило конфига. Только из ключей конфига
    /// строить нельзя: история приложения, правило которого удалено или никогда не заводилось,
    /// пропала бы из сводки молча.
    public init(rollup: FocusRollup, config: RuleConfig, now: Now) {
        let days = Self.window(endingAt: now)

        // Для каждого дня окна — словарь приложений, либо nil, если дня в свёртке нет.
        // Именно этот опционал и переезжает в ячейки: второго признака «день записан» нет.
        let recorded: [[String: Duration]?] = days.map { rollup.days[$0] }

        var identifiers = Set<String>()
        for apps in recorded {
            if let apps {
                identifiers.formUnion(apps.keys)
            }
        }
        for rule in config.rules.values where rule.enabledAt != nil {
            identifiers.insert(rule.bundleIdentifier)
        }

        let unsorted: [FocusSummaryRow] = identifiers.map { bundleIdentifier in
            // nil и .zero — разные факты. nil: дня нет в свёртке вовсе, Terminator тогда ничего
            // не записал, и ноль на его месте был бы выдумкой о дне, который не восполнить
            // задним числом. .zero: день записан, а у этого приложения записи в нём нет.
            let perDay: [Duration?] = recorded.map { apps in
                apps.map { $0[bundleIdentifier] ?? .zero }
            }
            let total = perDay.reduce(Duration.zero) { sum, cell in sum + (cell ?? .zero) }
            return FocusSummaryRow(bundleIdentifier: bundleIdentifier, total: total, perDay: perDay)
        }

        // Порядок: итог по убыванию, при равенстве — `bundleIdentifier` по возрастанию, обычным
        // сравнением строк. Идентификаторы в наборе уникальны, поэтому порядок полный и не
        // зависит от порядка обхода `Set`.
        //
        // В `PopoverViewModel` сортировка строк правил по величине запрещена: там все входы
        // меняются при открытом поповере — отсчёт тикает, — и строка уезжала бы из-под курсора.
        // Здесь сортировка по итогу допустима, пока сводку строят один раз на открытие секции из
        // замороженного снимка, а не в теле периодически перерисовываемого вида. Тип этого не
        // обеспечивает: новая сводка на каждый тик поменяла бы местами строки с близкими итогами
        // под курсором. Соблюдать предусловие — обязанность вызывающего (TASK-101).
        self.rows = unsorted.sorted { lhs, rhs in
            if lhs.total != rhs.total {
                return lhs.total > rhs.total
            }
            return lhs.bundleIdentifier < rhs.bundleIdentifier
        }
        self.days = days
        self.recordedDayCount = recorded.filter { $0 != nil }.count
    }

    /// Знаменатель: `"6 of 7 days recorded"`.
    public var recordedDaysText: String {
        "\(recordedDayCount) of \(Self.dayCount) days recorded"
    }

    /// Ячейка одного дня — **целые минуты**, усечение вниз.
    ///
    /// - `nil` — `—` (один символ U+2014): день не записан;
    /// - `.zero` — `0`: день записан, у приложения записи нет;
    /// - больше нуля и меньше минуты — `<1`, чтобы ненулевое значение не выглядело нулём;
    /// - минута и больше — целые минуты: `115 s` даёт `1`, а не `2`.
    /// - от `.seconds(Int64.max)` — `≥153722867280912930`: насыщение вместо падения в `components`.
    ///
    /// Единицы ячейки и итога различаются намеренно — см. описание типа.
    public static func cellText(_ duration: Duration?) -> String {
        guard let duration else { return "\u{2014}" }
        if duration == .zero { return "0" }
        if duration < .seconds(60) { return "<1" }
        if duration >= .seconds(Int64.max) { return "\u{2265}\(Int64.max / 60)" }
        return "\(duration.components.seconds / 60)"
    }

    /// Итог строки — **точная величина** крупнейшими единицами, усечение вниз.
    ///
    /// - `.zero` — `0 s`;
    /// - больше нуля и меньше секунды — `<1 s`: иначе строка показала бы `<1` в ячейке и
    ///   `0 s` в итоге, то есть ноль на ненулевом значении;
    /// - меньше минуты — `N s`;
    /// - меньше часа — `N m`, секунды отбрасываются;
    /// - час и больше — `H h M m`, всегда обе части: `1 h 0 m`, `52 h 10 m`.
    /// - от `.seconds(Int64.max)` — `≥2562047788015215 h`: насыщение вместо падения в `components`.
    ///
    /// Единицы ячейки и итога различаются намеренно — см. описание типа.
    public static func totalText(_ duration: Duration) -> String {
        if duration == .zero { return "0 s" }
        if duration < .seconds(1) { return "<1 s" }
        if duration >= .seconds(Int64.max) { return "\u{2265}\(Int64.max / 3600) h" }
        let seconds = duration.components.seconds
        if seconds < 60 { return "\(seconds) s" }
        if seconds < 3600 { return "\(seconds / 60) m" }
        return "\(seconds / 3600) h \(seconds % 3600 / 60) m"
    }

    // MARK: - Окно

    /// Семь ключей дней, от шести дней назад до сегодняшнего, по календарю `now`.
    ///
    /// Шаг — календарные сутки от начала сегодняшнего дня, а не фиксированное число секунд: в
    /// день перехода на летнее время суток 23 часа, на зимнее — 25, и секундный шаг пропустил
    /// бы день или повторил его. Календарь `.gregorian` с поясом из `now`, окружение не читается.
    private static func window(endingAt now: Now) -> [DayKey] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = now.timeZone
        let start = calendar.startOfDay(for: now.wall)
        return stride(from: dayCount - 1, through: 0, by: -1).map { daysBack in
            guard let date = calendar.date(byAdding: .day, value: -daysBack, to: start) else {
                preconditionFailure(
                    "григорианский календарь не сдвинул начало дня на \(daysBack) сут. назад"
                )
            }
            return DayKey.containing(date, in: now.timeZone)
        }
    }
}

/// Одна строка сводки: одно приложение за окно.
///
/// Публичного инициализатора нет намеренно: строку строит только `FocusSummary`, поэтому
/// строку с числом ячеек, отличным от `FocusSummary.dayCount`, собрать снаружи невозможно.
public struct FocusSummaryRow: Equatable, Sendable {

    /// Точный bundle id приложения.
    public let bundleIdentifier: String

    /// Сумма не-nil элементов `perDay`.
    public let total: Duration

    /// Ровно `FocusSummary.dayCount` элементов, по индексам `FocusSummary.days`.
    ///
    /// `nil` — день не записан (ключа дня нет в свёртке); `.zero` — день записан, а у
    /// приложения в нём записи нет. Различие несёт только опционал: отдельного булева признака
    /// рядом с длительностью нет, потому что два поля могут разъехаться, а опционал — нет.
    public let perDay: [Duration?]
}
