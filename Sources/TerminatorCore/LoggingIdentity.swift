import Foundation

/// Идентичность логирования продукта: одна подсистема и закрытый список категорий.
///
/// Здесь живёт единственное в дереве исходников вхождение строки подсистемы — ниже, в
/// `subsystem`, и больше нигде. Ни одна последующая карточка не заводит вторую: логи
/// читаются одним предикатом
///
///     log show --predicate 'subsystem == "…"' --style compact --last 1h
///
/// (вместо `…` — значение `TerminatorLog.subsystem`), и вторая подсистема означала бы,
/// что часть строк в этот предикат не попадёт.
///
/// Совпадение значения с bundle id из `Packaging/Info.plist` — совпадение по смыслу,
/// а не общая константа: это разные сущности, живущие в разных файлах.
///
/// Сам `os.Logger` здесь не создаётся. TerminatorCore на этом этапе не логирует и не
/// импортирует `os` — константы приносит эта карточка, пользуются ими те, кто логирует
/// (findings §14: каждая интерполяция в лог-строке несёт `privacy: .public`).
public enum TerminatorLog {

    /// Подсистема os.Logger для всего продукта.
    public static let subsystem = "com.svvoff.terminator"

    /// Категории os.Logger. Список закрытый: новая категория — это решение, а не деталь.
    public enum Category {

        /// Редьюсер: входы, переходы состояния, эффекты.
        public static let engine = "engine"

        /// Завершение чужих приложений вежливым Apple Event.
        public static let quit = "quit"

        /// Согласие на Apple Events (TCC).
        public static let consent = "consent"

        /// Чтение и запись конфига на диске.
        public static let store = "store"

        /// Учёт фокуса.
        public static let focus = "focus"

        /// Автозапуск при входе в систему.
        public static let loginItem = "loginitem"
    }
}
