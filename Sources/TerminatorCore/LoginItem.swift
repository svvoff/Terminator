import Foundation

/// Состояние автозапуска, как его видит продукт.
///
/// Регистрация — рукописный plist в `~/Library/LaunchAgents`, а не `SMAppService.mainApp`
/// и не helper-режим `SMAppService.loginItem(identifier:)` (findings §12, DEC-006). Причина
/// решающая и не косметическая: legacy-plist ссылается на **путь**, а не на cdhash, поэтому
/// переживает пересборку — а это дерево пересобирается постоянно.
///
/// Случаев ровно четыре, и четвёртый — не заглушка:
///
/// - `enabled` — агент зарегистрирован и включён;
/// - `disabledByUser` — файл на месте, но пользователь выключил пункт в
///   System Settings → General → Login Items. Это **нормальное состояние**, а не ошибка и
///   не повод перерегистрироваться: обход выбора пользователя — ровно то поведение, которое
///   запрещает DEC-006;
/// - `notRegistered` — регистрации нет;
/// - `unknown` — системный статус, о значении которого разведка ничего не измерила.
///
/// `unknown` существует затем, чтобы незнакомый статус **всплыл**, а не растворился в
/// «включено». Продукт не показывает уведомлений (DEC-004): фича, которая выглядит
/// работающей и не делает ничего, не оставила бы пользователю ни одного способа это заметить.
public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case disabledByUser
    case notRegistered
    case unknown(rawValue: Int)
}

extension LoginItemStatus {

    /// Сырые значения `SMAppServiceStatus` из `<ServiceManagement/SMAppService.h>`:
    /// `NS_ENUM(NSInteger, SMAppServiceStatus)` = notRegistered 0, enabled 1,
    /// requiresApproval 2, notFound 3.
    ///
    /// Числа продублированы здесь намеренно. Ядро — только Foundation, `ServiceManagement`
    /// в него не попадает, а отображение обязано быть чистой функцией, которую тест зовёт
    /// без фреймворка. Дублирование безопасно ровно потому, что незнакомое число даёт
    /// `unknown`: если бы Apple когда-нибудь перенумеровала enum, результат был бы явно
    /// «неизвестно», а не тихо «включено».
    private static let systemNotRegistered = 0
    private static let systemEnabled = 1
    private static let systemRequiresApproval = 2

    /// Отображает сырое значение `SMAppService.Status` в доменное состояние.
    ///
    /// Чистая функция над числом: ни ввода-вывода, ни обращения к диску, ни фреймворка.
    /// Адаптер получает статус у `SMAppService.statusForLegacyPlist(at:)` и передаёт сюда
    /// `.rawValue`.
    ///
    /// Отображаются ровно три значения — те, которые разведка **измерила** на реальных
    /// сторонних агентах через `statusForLegacyPlist` (findings §12): включённый агент дал
    /// `enabled`, выключенный пользователем — `requiresApproval`, несуществующий путь —
    /// `notRegistered`.
    ///
    /// Всё остальное, включая `notFound` (3), даёт `unknown`. `notFound` — это
    /// never-registered статус **другого** API, `SMAppService.mainApp`; на legacy-пути его
    /// никто не наблюдал, и притвориться, будто мы знаем его значение здесь, значило бы
    /// выдумать измерение. `unknown` несёт исходное число, чтобы лог отвечал на вопрос
    /// «а что именно вернула система».
    public init(systemStatusRawValue rawValue: Int) {
        switch rawValue {
        case LoginItemStatus.systemNotRegistered:
            self = .notRegistered
        case LoginItemStatus.systemEnabled:
            self = .enabled
        case LoginItemStatus.systemRequiresApproval:
            self = .disabledByUser
        default:
            self = .unknown(rawValue: rawValue)
        }
    }
}

/// Отказ генератора plist. Причина — значение, а не строка: вызывающий различает случаи
/// сопоставлением case, а не разбором текста.
public enum LoginItemPlistError: Error, Equatable, Sendable {

    /// Переданный адрес — не файловый URL. Путь в `ProgramArguments` обязан быть путём.
    case notAFileURL(url: String)

    /// Исполняемый файл лежит не внутри `.app`-бандла.
    ///
    /// Это неупакованный случай: у голого SwiftPM-исполняемого файла `Bundle.main`
    /// пуст, а идентификатор бандла равен nil (findings §7). Такой процесс не получит ни
    /// политики `.accessory`, ни пункта в меню-баре, поэтому регистрировать его как
    /// автозапуск бессмысленно.
    case executableNotInsideAppBundle(path: String)
}

/// Генератор plist автозапуска.
///
/// Чистая функция: исполняемый URL приходит **параметром**, а не ищется внутри. Поэтому
/// содержимое plist проверяется юнит-тестом без бандла и без файловой системы, а
/// приложение просто передаёт `Bundle.main.executableURL`.
///
/// Запись файла, удаление и чтение статуса живут в адаптере: они требуют
/// `ServiceManagement`, а ядро — только Foundation.
public enum LoginItemPlist {

    /// `Label` агента. Совпадает с идентификатором бандла: launchd требует уникальную
    /// метку, а другой уникальной строки у продукта нет.
    public static let label = TerminatorIdentity.bundleIdentifier

    /// Имя файла внутри `~/Library/LaunchAgents`.
    public static let fileName = TerminatorIdentity.bundleIdentifier + ".plist"

    /// Строит содержимое plist для исполняемого файла внутри собранного `.app`.
    ///
    /// Ключей ровно три, и список закрытый:
    ///
    /// - `Label` — метка агента;
    /// - `ProgramArguments` — **один** абсолютный путь к исполняемому файлу внутри бандла
    ///   (`…/Terminator.app/Contents/MacOS/Terminator`). Прямой запуск бинаря из бандла
    ///   сохраняет идентичность бандла и политику `.accessory` (findings §7) — это тот же
    ///   путь, что у дев-лупа. Ни `open -a`, ни путь до продукта `swift build`;
    /// - `RunAtLoad` — `true`.
    ///
    /// Четвёртого ключа нет и не будет: ключ, перезапускающий процесс после выхода,
    /// воскрешал бы сознательно закрытый Terminator, а сопротивление закрытию — явная
    /// не-цель (DEC-006). Отсутствие лишних ключей проверяется тестом.
    ///
    /// Проверка адреса структурная: путь обязан оканчиваться на
    /// `<что-то>.app/Contents/MacOS/<исполняемый файл>`. Ровно такую раскладку собирает
    /// `build.sh`; всё прочее — неупакованный случай, и генератор отказывает, не записав
    /// ничего.
    public static func data(forExecutableAt executable: URL) throws -> Data {
        guard executable.isFileURL else {
            throw LoginItemPlistError.notAFileURL(url: executable.absoluteString)
        }

        let standardized = executable.standardizedFileURL
        let path = standardized.path
        guard isInsideAppBundle(standardized) else {
            throw LoginItemPlistError.executableNotInsideAppBundle(path: path)
        }

        let contents: [String: Any] = [
            "Label": label,
            "ProgramArguments": [path],
            "RunAtLoad": true
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: contents,
            format: .xml,
            options: 0
        )
    }

    /// Лежит ли адрес по раскладке `…/<имя>.app/Contents/MacOS/<файл>`.
    ///
    /// Сравниваются компоненты пути, а не суффикс строки: суффиксное сравнение принимает
    /// относительный путь и путь с `..` внутри, а `ProgramArguments` обязан быть абсолютным.
    private static func isInsideAppBundle(_ executable: URL) -> Bool {
        let components = executable.pathComponents
        let count = components.count
        guard count >= 5, components[0] == "/" else { return false }
        guard components[count - 2] == "MacOS", components[count - 3] == "Contents" else {
            return false
        }
        let bundleName = components[count - 4]
        return bundleName.hasSuffix(".app") && bundleName.count > ".app".count
    }
}
