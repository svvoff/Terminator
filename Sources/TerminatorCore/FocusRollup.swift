import Foundation

/// Локальная календарная дата — ключ одного дня в свёртке.
///
/// Год-месяц-день, а не `Date`: день — это не момент, а интервал, и два разных момента одного
/// дня обязаны давать один ключ. Он же дословно ложится в JSON строкой `"2026-08-29"`, потому
/// что файл читается и правится глазами.
///
/// Календарь всегда `.gregorian` с **подставленным** поясом. `Calendar.current` здесь
/// запрещён: ядро не читает окружение (`Now.swift`), а `.current` утащил бы ещё и локаль,
/// то есть чужой календарь — и день поехал бы у пользователя с не-григорианским календарём.
public struct DayKey: Hashable, Comparable, Sendable, CustomStringConvertible {

    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Календарный день, в который попадает `date` в поясе `timeZone`.
    public static func containing(_ date: Date, in timeZone: TimeZone) -> DayKey {
        let parts = calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        return DayKey(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// Полночь, которой **заканчивается** день, содержащий `date`.
    ///
    /// Считается прибавлением одних календарных суток к началу дня, а не 86 400 секундами:
    /// в день перехода на зимнее время суток 25 часов, в день перехода на летнее — 23, и
    /// арифметика на секундах поставила бы границу не туда. Полночь, которой в поясе не
    /// существует, `startOfDay(for:)` разрешает сам.
    public static func startOfNextDay(after date: Date, in timeZone: TimeZone) -> Date {
        let calendar = calendar(in: timeZone)
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// `2026-08-29`. Он же ключ в JSON: строковая сортировка таких ключей совпадает с
    /// хронологической, поэтому файл с `sortedKeys` читается сверху вниз по времени.
    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Разбор ключа из файла. Формат строгий: ровно `YYYY-MM-DD`, только цифры и дефисы.
    /// Всё остальное — правка руками, которую чинит человек, а не догадка кодека.
    public init?(text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day)
        else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

/// Дневная свёртка фокуса: сколько каждое приложение было фронтмост в каждый календарный день.
///
/// Длительность в памяти — `Duration`, то есть с субсекундным остатком. Усечение до целых
/// секунд происходит **только** на границе диска (findings §11): иначе каждый слив отъедал бы
/// у накопителя долю секунды, и за сутки набежала бы минута.
public struct FocusRollup: Equatable, Sendable {

    /// День → bundle id → накопленная длительность фокуса.
    public private(set) var days: [DayKey: [String: Duration]]

    /// Ни одного записанного дня.
    public static let empty = FocusRollup()

    public init() {
        self.days = [:]
    }

    public init(days: [DayKey: [String: Duration]]) {
        self.days = days
    }

    /// Прибавляет длительность к одному приложению одного дня.
    ///
    /// Нулевая и отрицательная длительности не создают записи: пустая запись в файле
    /// означала бы «приложение было фронтмост ноль секунд», чего не бывает, и мусорила бы
    /// свёртку на каждой границе дня.
    public mutating func add(_ duration: Duration, to bundleIdentifier: String, on day: DayKey) {
        guard duration > .zero else { return }
        days[day, default: [:]][bundleIdentifier, default: .zero] += duration
    }

    /// Накопленное для приложения в этот день. Записи нет — ноль.
    public func duration(for bundleIdentifier: String, on day: DayKey) -> Duration {
        days[day]?[bundleIdentifier] ?? .zero
    }

    /// Дни в хронологическом порядке.
    public var sortedDays: [DayKey] {
        days.keys.sorted()
    }

    /// Складывает две свёртки по паре «день + приложение».
    ///
    /// Именно **сложение**, а не замена, и это существенно: слив прибавляет накопленное этим
    /// запуском Terminator к тому, что записали прошлые запуски. Дни, которых нет во втором
    /// слагаемом, переносятся нетронутыми — это и есть защита от «перезапуск стирает историю».
    public func adding(_ other: FocusRollup) -> FocusRollup {
        var merged = self
        for (day, apps) in other.days {
            for (bundleIdentifier, duration) in apps {
                merged.add(duration, to: bundleIdentifier, on: day)
            }
        }
        return merged
    }
}
