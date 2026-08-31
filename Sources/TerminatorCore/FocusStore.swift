import Foundation

/// Отказ операции хранилища фокуса.
public enum FocusStoreError: Error, Equatable, Sendable {

    /// Слив отклонён: хранилище в карантине. Молчаливый no-op был бы хуже — он выглядит как
    /// успех, а на диске остаётся файл, который никто не чинит.
    case quarantined(FocusLoadFailure)
}

/// Долговечное хранилище дневной свёртки фокуса: один версионированный JSON-файл в том же
/// каталоге данных, что и правила, но **свой**.
///
/// Читается он не реже, чем пишется, и это ключевое свойство. Движок стартует пустым, так что
/// слив, который пишет файл целиком из памяти, стёр бы всю прошлую историю при первом же
/// запуске. Не-цель «никакого восполнения истории» запрещает реконструировать её из
/// посторонних источников и никогда не означала «не читай свой собственный файл».
///
/// Отсюда контракт слива: **записанное прежними запусками плюс накопленное этим**. Дни,
/// которых этот запуск не касался, переносятся нетронутыми.
///
/// Хранилище намеренно не `Sendable` и синхронно: его зовут с главного потока. Уводить слив в
/// `Task` или на фоновую очередь нельзя — `ConfigStore.load()` подметает из каталога данных
/// любой файл с `.sb-` в имени, а `writeDurably` именует так свой временный файл, и уборка,
/// приехавшая посреди записи, снесла бы его.
public final class FocusStore {

    /// Имя файла фокуса внутри каталога данных.
    public static let focusFileName = "focus.json"

    /// Каталог данных этого экземпляра. Тесты передают временный каталог; настоящий
    /// `~/Library/Application Support` в тестах не участвует.
    public let dataDirectory: URL

    /// Полный путь к файлу фокуса.
    public let focusURL: URL

    /// Что было на диске в момент чтения. Слагаемое каждого слива, и оно не меняется до
    /// следующего `load()`: если прибавлять к текущему содержимому файла, каждый слив
    /// удваивал бы уже записанное.
    public private(set) var recorded: FocusRollup

    /// Причина карантина, либо nil.
    public private(set) var quarantine: FocusLoadFailure?

    /// Хранилище в карантине: слив отказывает, пока файл не починят и не перезагрузят.
    public var isQuarantined: Bool { quarantine != nil }

    private var hasLoaded = false

    public init(dataDirectory: URL = ConfigStore.defaultDataDirectory) {
        self.dataDirectory = dataDirectory
        self.focusURL = dataDirectory.appendingPathComponent(
            FocusStore.focusFileName,
            isDirectory: false
        )
        self.recorded = .empty
        self.quarantine = nil
    }

    /// Читает файл фокуса. Исходов три, и ни один ничего на диске не меняет:
    ///
    /// - файла нет — пустая свёртка, файл **не создаётся**;
    /// - файл разобрался — это записанная история, карантин снимается;
    /// - файл не разобрался или версия схемы из будущего — карантин, байты не тронуты.
    ///
    /// Метод не бросает: отказ — это состояние, которое читают.
    public func load() {
        hasLoaded = true

        let bytes: Data
        do {
            bytes = try Data(contentsOf: focusURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            recorded = .empty
            quarantine = nil
            return
        } catch {
            quarantine = .undecodableBytes(message: String(describing: error))
            return
        }

        do {
            recorded = try FocusFormat.decode(bytes)
            quarantine = nil
        } catch let failure as FocusLoadFailure {
            quarantine = failure
        } catch {
            quarantine = .undecodableBytes(message: String(describing: error))
        }
    }

    /// Долговечно записывает историю плюс накопленное этим запуском.
    ///
    /// Каталог создаётся здесь, при первой записи: `writeDurably` его не создаёт, а чтение из
    /// пустой системы не должно оставлять следов на диске.
    ///
    /// Возвращает записанные байты — их считает вызывающий, чтобы написать в лог размер файла.
    @discardableResult
    public func flush(_ accrued: FocusRollup) throws -> Data {
        // Слив без предшествующего чтения затёр бы всю прошлую историю. Это не удобство, а
        // единственная защита от порядка вызовов, в котором `load()` забыли.
        if !hasLoaded { load() }

        if let quarantine {
            throw FocusStoreError.quarantined(quarantine)
        }

        let bytes = try FocusFormat.encode(recorded.adding(accrued))
        try FileManager.default.createDirectory(
            at: dataDirectory,
            withIntermediateDirectories: true
        )
        try writeDurably(bytes, to: focusURL)
        return bytes
    }
}
