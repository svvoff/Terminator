import Foundation
import Testing

import TerminatorCore

@Suite("Автозапуск: содержимое plist и отображение статуса")
struct LoginItemTests {

    /// Адрес исполняемого файла внутри собранного бандла. Файла на диске не существует и
    /// существовать не должно: генератор — чистая функция над адресом, файловой системы он
    /// не касается.
    private static let bundledExecutable = URL(
        fileURLWithPath: "/Users/example/Developer/terminator/build/Terminator.app/Contents/MacOS/Terminator"
    )

    /// Критерий 1. Отображение статуса — чистая функция над сырым значением
    /// `SMAppService.Status`.
    ///
    /// Три значения, измеренные разведкой через `statusForLegacyPlist` (findings §12),
    /// дают свои доменные случаи. Всё остальное — **явное «неизвестно»**, а не падение и не
    /// молчаливое «включено»: сюда попадают и `notFound` (3), never-registered статус
    /// другого API, на legacy-пути не наблюдавшийся, и любое число, которого сегодня в
    /// enum нет вовсе.
    @Test func statusMappingSurfacesEverythingItDoesNotKnow() {
        #expect(LoginItemStatus(systemStatusRawValue: 0) == .notRegistered)
        #expect(LoginItemStatus(systemStatusRawValue: 1) == .enabled)
        #expect(LoginItemStatus(systemStatusRawValue: 2) == .disabledByUser)

        #expect(LoginItemStatus(systemStatusRawValue: 3) == .unknown(rawValue: 3))
        #expect(LoginItemStatus(systemStatusRawValue: 4) == .unknown(rawValue: 4))
        #expect(LoginItemStatus(systemStatusRawValue: 99) == .unknown(rawValue: 99))
        #expect(LoginItemStatus(systemStatusRawValue: -1) == .unknown(rawValue: -1))

        // Ни одно значение не отображается в .enabled, кроме единственного измеренного.
        for raw in -5...20 where raw != 1 {
            #expect(LoginItemStatus(systemStatusRawValue: raw) != .enabled)
        }
    }

    /// Критерий 2. Содержимое plist для известного адреса: три ключа, и других нет.
    ///
    /// Отдельной строкой проверяется отсутствие ключа, перезапускающего процесс после
    /// выхода: он воскрешал бы сознательно закрытый Terminator (DEC-006, findings §12).
    @Test func generatedPlistCarriesExactlyThreeKeys() throws {
        let bytes = try LoginItemPlist.data(forExecutableAt: Self.bundledExecutable)
        let contents = try Self.parse(bytes)

        #expect(contents.keys.sorted() == ["Label", "ProgramArguments", "RunAtLoad"])
        #expect(contents.keys.contains("KeepAlive") == false)

        #expect(contents["Label"] as? String == "com.svvoff.terminator")
        #expect(contents["RunAtLoad"] as? Bool == true)

        let arguments = try #require(contents["ProgramArguments"] as? [String])
        #expect(arguments.count == 1)
        let executablePath = try #require(arguments.first)
        #expect(executablePath.hasPrefix("/"))
        #expect(executablePath.hasSuffix("Terminator.app/Contents/MacOS/Terminator"))
        #expect(executablePath == Self.bundledExecutable.path)

        // launchd читает булево, а не число: `RunAtLoad` обязан сериализоваться тегом.
        let text = try #require(String(data: bytes, encoding: .utf8))
        #expect(text.contains("<true/>"))
    }

    /// Критерий 3. Сгенерированные байты разбираются как property list, и разбираются как
    /// XML — тот формат, который `plutil -lint` читает глазами человека.
    @Test func generatedPlistRoundTripsThroughPropertyListSerialization() throws {
        let bytes = try LoginItemPlist.data(forExecutableAt: Self.bundledExecutable)

        var format = PropertyListSerialization.PropertyListFormat.binary
        let object = try PropertyListSerialization.propertyList(
            from: bytes,
            options: [],
            format: &format
        )

        #expect(format == .xml)
        let contents = try #require(object as? [String: Any])
        #expect(contents["Label"] as? String == LoginItemPlist.label)
        #expect(contents["RunAtLoad"] as? Bool == true)
        #expect((contents["ProgramArguments"] as? [String])?.count == 1)
    }

    /// Критерий 4. Генератор отказывает адресу, который не лежит внутри `.app`-бандла, и
    /// не возвращает при этом ничего наполовину.
    ///
    /// Первый случай — настоящий: так выглядит продукт `swift build`. У такого процесса
    /// `Bundle.main.bundleIdentifier` равен nil, политика активации `.prohibited`, и пункта
    /// в меню-баре он не покажет никогда (findings §7).
    @Test func generatorRefusesAnythingOutsideAnAppBundle() throws {
        let outside = [
            "/Users/example/Developer/terminator/.build/debug/Terminator",
            "/usr/local/bin/terminator",
            "/Users/example/Terminator.app/Terminator",
            "/Users/example/Terminator.app/Contents/Terminator",
            "/Users/example/Terminator.app/Contents/MacOS/nested/Terminator",
            "/Users/example/Terminator/Contents/MacOS/Terminator",
            "/.app/Contents/MacOS/Terminator"
        ]

        for path in outside {
            #expect(throws: LoginItemPlistError.executableNotInsideAppBundle(path: path)) {
                _ = try LoginItemPlist.data(forExecutableAt: URL(fileURLWithPath: path))
            }
        }

        let remote = try #require(
            URL(string: "https://example.com/Terminator.app/Contents/MacOS/Terminator")
        )
        #expect(throws: LoginItemPlistError.notAFileURL(url: remote.absoluteString)) {
            _ = try LoginItemPlist.data(forExecutableAt: remote)
        }
    }

    /// Записанный долговечным хелпером plist читается с диска и разбирается.
    ///
    /// Каталог назначения — **временный**, созданный этим тестом, с именем `LaunchAgents`
    /// только ради узнаваемости раскладки. Ни один тест этого таргета не имеет права
    /// прикоснуться к настоящему `~/Library/LaunchAgents`: там лежат агенты пользователя,
    /// не принадлежащие продукту.
    ///
    /// Проверяется здесь то, чего чистый генератор проверить не может: `writeDurably`
    /// оставляет на диске ровно один файл, без хвостов временных имён рядом, и файл этот —
    /// валидный property list.
    @Test func durablyWrittenPlistParsesBackFromDisk() throws {
        try withTemporaryDirectory { directory in
            let agents = directory.appendingPathComponent("LaunchAgents", isDirectory: true)
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)

            let destination = agents.appendingPathComponent(
                LoginItemPlist.fileName,
                isDirectory: false
            )
            let bytes = try LoginItemPlist.data(forExecutableAt: Self.bundledExecutable)
            try writeDurably(bytes, to: destination)

            let entries = try directoryEntries(agents)
            #expect(entries == ["com.svvoff.terminator.plist"])

            let written = try Data(contentsOf: destination)
            #expect(written == bytes)
            let contents = try Self.parse(written)
            #expect(contents.keys.sorted() == ["Label", "ProgramArguments", "RunAtLoad"])
        }
    }

    private static func parse(_ bytes: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(
            from: bytes,
            options: [],
            format: nil
        )
        return try #require(object as? [String: Any])
    }
}
