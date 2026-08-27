import Foundation

/// Идентичность логирования продукта: одна подсистема и закрытый список категорий.
///
/// Подсистема — не своя строка, а `TerminatorIdentity.bundleIdentifier`: TASK-003 завела
/// общую константу идентичности приложения, потому что та же строка называет каталог
/// данных и отвергает правило-на-себя. Единственное вхождение литерала в `Sources/` живёт
/// там; здесь его нет.
///
/// Ни одна последующая карточка не заводит вторую подсистему: логи читаются одним предикатом
///
///     log show --predicate 'subsystem == "…"' --style compact --last 1h
///
/// (вместо `…` — значение `TerminatorLog.subsystem`), и вторая подсистема означала бы,
/// что часть строк в этот предикат не попадёт.
///
/// Сам `os.Logger` здесь не создаётся: константы приносит этот файл, а создают логгеры те,
/// кто логирует (findings §14: каждая интерполяция в лог-строке несёт `privacy: .public`).
public enum TerminatorLog {

    /// Подсистема os.Logger для всего продукта.
    public static let subsystem = TerminatorIdentity.bundleIdentifier

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
