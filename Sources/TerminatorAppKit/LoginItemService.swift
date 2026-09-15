import Foundation
import ServiceManagement

import TerminatorCore
import os

/// Логгер автозапуска. Подсистема продукта, категория `loginitem`.
///
/// Каждая интерполяция несёт `privacy: .public` — без исключений. Редакция происходит в
/// момент записи и необратима (findings §14), а предупреждений перед закрытием приложения
/// нет (DEC-004), так что лог — единственный ответ на вопрос «почему автозапуск не
/// сработал». Читается одним предикатом:
///
///     log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h
let loginItemLog = Logger(
    subsystem: TerminatorLog.subsystem,
    category: TerminatorLog.Category.loginItem
)

/// Автозапуск при входе в систему: запись, удаление и чтение состояния.
///
/// Всё, что требует `ServiceManagement` или файловой системы, живёт здесь. Содержимое
/// plist и отображение статуса — чистые функции ядра (`LoginItemPlist`, `LoginItemStatus`),
/// и именно они покрыты юнит-тестами.
///
/// Механизм — рукописный plist в `~/Library/LaunchAgents` (findings §12). Современный
/// `SMAppService.mainApp` здесь не используется: он требует подписи
/// (`kSMErrorInvalidSignature = 3` иначе), а повторные циклы register/rebuild документированно
/// портят Background Task Management, чинится это `sfltool resetbtm`, и починка стирает
/// **все** логин-элементы на машине. Апгрейд на `SMAppService.mainApp` принадлежит Stage 4
/// (TASK-105) и здесь не открывается.
///
/// Чего сервис не делает и не будет делать:
///
/// - не зовёт `launchctl` ни в каком виде. Вступления в силу при следующем входе достаточно,
///   а второй путь активации был бы вторым источником состояния;
/// - не перерегистрируется, если пользователь выключил пункт в System Settings. Чтение
///   этого состояния — и есть поставляемая функциональность (DEC-006);
/// - не трогает ничего в каталоге, кроме единственного файла `plistURL`. Соседние агенты в
///   `~/Library/LaunchAgents` принадлежат пользователю, а не продукту: они не читаются, не
///   переписываются и не удаляются. Уборки временных файлов здесь тоже нет — она осталась
///   в `ConfigStore` и ходит только по каталогу данных приложения; `writeDurably` убирает
///   свой временный файл сам.
public struct LoginItemService {

    /// `~/Library/LaunchAgents` — единственный каталог, куда пишет этот сервис.
    ///
    /// Обращение к свойству ничего не создаёт и ничего не читает.
    public static let defaultAgentsDirectory: URL = {
        let library = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library", isDirectory: true)
        return library.appendingPathComponent("LaunchAgents", isDirectory: true)
    }()

    /// Каталог агентов этого экземпляра. Параметр, а не константа, ровно по той же причине,
    /// что и `dataDirectory` у `ConfigStore`: настоящий домашний каталог не должен
    /// участвовать нигде, кроме реального запуска.
    public let agentsDirectory: URL

    /// Полный путь к нашему plist.
    public let plistURL: URL

    public init(agentsDirectory: URL = LoginItemService.defaultAgentsDirectory) {
        self.agentsDirectory = agentsDirectory
        self.plistURL = agentsDirectory.appendingPathComponent(
            LoginItemPlist.fileName,
            isDirectory: false
        )
    }

    /// Включает автозапуск: пишет plist для переданного исполняемого файла.
    ///
    /// Приложение передаёт `Bundle.main.executableURL`. Если адрес не лежит внутри
    /// `.app`-бандла, генератор отказывает, отказ уходит в лог на `.notice`, и на диск не
    /// пишется ничего.
    ///
    /// Запись идёт через `writeDurably` — тот же и единственный способ, которым продукт
    /// пишет любой файл. Штатный атомарный `Data.write` не делает ни одного `fsync`
    /// (findings §11), а этот файл читает launchd: порванный файл — это сломанный
    /// логин-элемент.
    ///
    /// Каталог создаётся здесь: `writeDurably` каталог назначения не создаёт, а полагаться
    /// на существование `~/Library/LaunchAgents` нельзя.
    ///
    /// Разовое системное уведомление «Background items added» при первой регистрации
    /// ожидаемо и нарушением DEC-004 не является: это извещение ОС в момент регистрации,
    /// а не наше предупреждение перед закрытием чужого приложения.
    public func enable(executableAt executable: URL) throws {
        let bytes: Data
        do {
            bytes = try LoginItemPlist.data(forExecutableAt: executable)
        } catch {
            let reason = String(describing: error)
            loginItemLog.notice("login item refused, nothing written: executable=\(executable.path, privacy: .public) reason=\(reason, privacy: .public)")
            throw error
        }

        try FileManager.default.createDirectory(
            at: agentsDirectory,
            withIntermediateDirectories: true
        )
        try writeDurably(bytes, to: plistURL)
        loginItemLog.notice("login item written: path=\(self.plistURL.path, privacy: .public) executable=\(executable.path, privacy: .public) bytes=\(bytes.count, privacy: .public)")
    }

    /// Выключает автозапуск: удаляет наш plist. Статус после этого читается как
    /// `notRegistered`.
    ///
    /// Отсутствие файла — не отказ: выключение того, что уже выключено, обязано быть
    /// идемпотентным. Удаляется ровно `plistURL` и ничего больше.
    public func disable() throws {
        do {
            try FileManager.default.removeItem(at: plistURL)
            loginItemLog.notice("login item removed: path=\(self.plistURL.path, privacy: .public)")
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            loginItemLog.notice("login item already absent: path=\(self.plistURL.path, privacy: .public)")
        }
    }

    /// Читает состояние регистрации.
    ///
    /// `SMAppService.statusForLegacyPlist(at:)` работает **из неподписанного бинаря** и
    /// возвращает различимые результаты (findings §12) — это и есть причина, по которой
    /// состояние вообще читаемо на текущей стадии подписи.
    ///
    /// Читается только наш собственный путь. Ни один чужой агент не открывается.
    ///
    /// Сообщает ли система включённое состояние сразу после записи файла или только после
    /// следующего входа — **измерено** (findings §12): `3` через 4 мс после записи и `1` через
    /// 28 мин 54 с, входа между чтениями не было. То есть `enabled` наступает до первого входа,
    /// но не сразу, а `3` — переходное состояние. Оба прочтения нормальны: метод не бросает,
    /// ничего не чинит и ничего не перезаписывает, он только рассказывает.
    public func status() -> LoginItemStatus {
        let system = SMAppService.statusForLegacyPlist(at: plistURL)
        let mapped = LoginItemStatus(systemStatusRawValue: system.rawValue)
        let described = String(describing: mapped)
        loginItemLog.notice("login item status: path=\(self.plistURL.path, privacy: .public) systemStatus=\(system.rawValue, privacy: .public) status=\(described, privacy: .public)")
        return mapped
    }
}
