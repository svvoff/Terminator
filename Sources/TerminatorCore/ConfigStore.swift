import Foundation
import os

/// Логгер хранилища. Один на файлы конфига: подсистема продукта, категория `store`.
///
/// Каждая интерполяция несёт `privacy: .public` — без исключений. Редакция происходит в
/// момент записи и необратима даже под sudo (findings §14), а лог здесь единственный
/// диагностический канал: предупреждений перед закрытием приложения нет (DEC-004).
let storeLog = Logger(subsystem: TerminatorLog.subsystem, category: TerminatorLog.Category.store)

/// Отказ операции хранилища.
public enum ConfigStoreError: Error, Equatable, Sendable {

    /// Запись отклонена: хранилище в карантине. Молчаливый no-op был бы хуже — он выглядит
    /// как успех, а на диске остаётся файл, который пользователь считает обновлённым.
    case quarantined(ConfigLoadFailure)
}

/// Долговечное хранилище правил: один версионированный JSON-файл, правимый руками.
///
/// Хранилище намеренно не `Sendable`: его держит и зовёт UI на `MainActor`, а ядро остаётся
/// nonisolated и синхронным. Ни `async`, ни акторов, ни таймеров здесь нет.
///
/// Центральное свойство — **карантин**. Если файл не разбирается, версия схемы из будущего
/// или правило нарушает инвариант модели, хранилище:
///
/// - оставляет байты на диске **нетронутыми** — это единственная копия правил пользователя,
///   и правил её человек;
/// - держит в памяти прежний хороший конфиг (на холодном старте — пустой);
/// - **отказывает** в записи, а не пишет молча мимо;
/// - выставляет наружу читаемую причину, которую TASK-006 рисует баннером.
public final class ConfigStore {

    /// Каталог данных приложения по конвенции Apple:
    /// `~/Library/Application Support/<идентификатор приложения>/`.
    ///
    /// Имя каталога — `TerminatorIdentity.bundleIdentifier`, захардкоженная константа. Из
    /// бандла его брать нельзя: у голого SwiftPM-исполняемого файла идентификатор бандла
    /// равен nil (findings §7), то есть путь разъехался бы между `swift build`-бинарём и
    /// собранным `.app`. Хранилище настроек системы тоже не годится: его набор нельзя
    /// привязать к собственному идентификатору бандла, и ломается это только внутри
    /// собранного бандла, то есть уже после ревью (findings §11).
    ///
    /// Обращение к свойству ничего не создаёт и ничего не читает.
    public static let defaultDataDirectory: URL = {
        let library = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return library.appendingPathComponent(TerminatorIdentity.bundleIdentifier, isDirectory: true)
    }()

    /// Имя файла правил внутри каталога данных.
    public static let configFileName = "config.json"

    /// Каталог данных этого экземпляра. Тесты передают временный каталог; настоящий
    /// `~/Library/Application Support` в тестах не участвует.
    public let dataDirectory: URL

    /// Полный путь к файлу правил.
    public let configURL: URL

    /// Живой конфиг в памяти. При отказе загрузки остаётся прежним.
    public private(set) var config: RuleConfig

    /// Причина карантина, либо nil. Read-only состояние, а не только строчка в логе.
    public private(set) var quarantine: ConfigLoadFailure?

    /// Хранилище в карантине: запись отказывает, пока файл не починят и не перезагрузят.
    public var isQuarantined: Bool { quarantine != nil }

    public init(dataDirectory: URL = ConfigStore.defaultDataDirectory) {
        self.dataDirectory = dataDirectory
        self.configURL = dataDirectory.appendingPathComponent(
            ConfigStore.configFileName,
            isDirectory: false
        )
        self.config = .empty
        self.quarantine = nil
    }

    /// Читает конфиг с диска. Делает ровно две вещи и в этом порядке: уборка, затем чтение.
    ///
    /// Исходов четыре, и ни один из них ничего на диске не меняет:
    ///
    /// - файла нет — пустой конфиг, файл **не создаётся**;
    /// - файл разобрался — это и есть живой конфиг, карантин снимается;
    /// - файл не разобрался — карантин, конфиг в памяти прежний;
    /// - версия схемы из будущего — карантин с отдельной причиной.
    ///
    /// Метод не бросает: отказ загрузки — это состояние, которое читают, а не исключение,
    /// которое ловят на старте приложения.
    public func load() {
        sweepStrayTemporaryFiles()

        let bytes: Data
        do {
            bytes = try Data(contentsOf: configURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            config = .empty
            quarantine = nil
            storeLog.notice("config missing, starting empty: path=\(self.configURL.path, privacy: .public)")
            return
        } catch {
            // Файл есть, но не читается. Это не «файла нет»: затирать его нельзя.
            enterQuarantine(.undecodableBytes(message: String(describing: error)))
            return
        }

        do {
            let loaded = try ConfigFormat.decode(bytes)
            config = loaded
            quarantine = nil
            storeLog.notice("config loaded: path=\(self.configURL.path, privacy: .public) rules=\(loaded.rules.count, privacy: .public) schemaVersion=\(ConfigFormat.currentSchemaVersion, privacy: .public)")
        } catch let failure as ConfigLoadFailure {
            enterQuarantine(failure)
        } catch {
            enterQuarantine(.undecodableBytes(message: String(describing: error)))
        }
    }

    /// Долговечно записывает конфиг и делает его живым.
    ///
    /// В карантине бросает и **не пишет ни байта**: сценарий отказа — это как раз запись,
    /// которая сработает через минуту после неудачной загрузки и затрёт ручную правку.
    ///
    /// Каталог данных создаётся здесь, при первой записи, а не при загрузке: загрузка из
    /// пустой системы не должна оставлять следов на диске.
    public func save(_ config: RuleConfig) throws {
        if let quarantine {
            let reason = String(describing: quarantine)
            storeLog.notice("save refused, store is quarantined: path=\(self.configURL.path, privacy: .public) reason=\(reason, privacy: .public)")
            throw ConfigStoreError.quarantined(quarantine)
        }

        let bytes = try ConfigFormat.encode(config)
        try FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true
        )
        try writeDurably(bytes, to: configURL)
        self.config = config
        storeLog.notice("config written: path=\(self.configURL.path, privacy: .public) rules=\(config.rules.count, privacy: .public) schemaVersion=\(ConfigFormat.currentSchemaVersion, privacy: .public) bytes=\(bytes.count, privacy: .public)")
    }

    private func enterQuarantine(_ failure: ConfigLoadFailure) {
        quarantine = failure
        let reason = String(describing: failure)
        storeLog.notice("quarantine entered, file left untouched: path=\(self.configURL.path, privacy: .public) rules=\(self.config.rules.count, privacy: .public) reason=\(reason, privacy: .public)")
    }

    /// Убирает хвосты прерванных записей: файлы, чьё имя содержит `.sb-` или `.tmp-`.
    ///
    /// Уборка ходит **только** по каталогу данных приложения и не рекурсивно. Общий хелпер
    /// записи умеет писать куда угодно — в частности в `~/Library/LaunchAgents` (TASK-008), —
    /// и уборка там означала бы удаление чужих файлов. Каталога нет — уборка молча ничего
    /// не делает. Всё, что не похоже на временный файл, остаётся на месте.
    private func sweepStrayTemporaryFiles() {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: dataDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return
        }

        for entry in entries {
            let name = entry.lastPathComponent
            guard name.contains(".sb-") || name.contains(".tmp-") else { continue }
            let values = try? entry.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            do {
                try manager.removeItem(at: entry)
                storeLog.notice("stray temporary file removed: path=\(entry.path, privacy: .public)")
            } catch {
                let reason = String(describing: error)
                storeLog.notice("stray temporary file could not be removed: path=\(entry.path, privacy: .public) reason=\(reason, privacy: .public)")
            }
        }
    }
}
