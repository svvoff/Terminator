import Foundation
import Testing

import TerminatorCore

@Suite("Долговечная запись")
struct DurableWriteTests {

    /// Критерий 9. Десять сохранений не оставляют в каталоге данных ничего, кроме
    /// `config.json`; и тот же хелпер, позванный с адресом в **другом** каталоге, создаёт
    /// там файл и не оставляет рядом хвостов. Хелпер знает только про переданный ему адрес:
    /// его же зовут TASK-007 для дневного rollup и TASK-008 для plist автозапуска.
    @Test func durableWriteLeavesNoTempFilesBehind() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            store.load()

            for minutes in 1...10 {
                let rule = try Rule(
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    limit: .constant(.seconds(minutes * 60)),
                    enabledAt: enabledAtFixture
                )
                try store.save(RuleConfig([rule]))
            }

            let entries = try directoryEntries(directory)
            #expect(entries == ["config.json"])

            let reader = ConfigStore(dataDirectory: directory)
            reader.load()
            let rule = try #require(reader.config.rule(for: "com.tinyspeck.slackmacgap"))
            #expect(rule.limit == .constant(.seconds(600)))
        }

        try withTemporaryDirectory { elsewhere in
            let destination = elsewhere.appendingPathComponent(
                "focus-2026-08-27.json",
                isDirectory: false
            )
            let payload = Data("{\"minutes\":12}".utf8)

            try writeDurably(payload, to: destination)

            let entries = try directoryEntries(elsewhere)
            #expect(entries == ["focus-2026-08-27.json"])
            let written = try Data(contentsOf: destination)
            #expect(written == payload)
        }
    }

    /// Запись поверх существующего файла заменяет его целиком, а не дописывает: rename(2)
    /// подменяет содержимое, короткая запись не оставляет хвоста прежней.
    @Test func durableWriteReplacesExistingContentWholly() throws {
        try withTemporaryDirectory { directory in
            let destination = directory.appendingPathComponent("payload.json", isDirectory: false)
            let long = Data(String(repeating: "a", count: 4096).utf8)
            let short = Data("b".utf8)

            try writeDurably(long, to: destination)
            try writeDurably(short, to: destination)

            let written = try Data(contentsOf: destination)
            #expect(written == short)
            let entries = try directoryEntries(directory)
            #expect(entries == ["payload.json"])
        }
    }

    /// Несуществующий каталог назначения — это ошибка записи, а не молчаливый успех.
    /// Хелпер каталогов не создаёт: это дело того, кто знает, куда пишет.
    @Test func durableWriteFailsWhenDestinationDirectoryIsMissing() throws {
        try withTemporaryDirectory { root in
            let destination = root
                .appendingPathComponent("absent", isDirectory: true)
                .appendingPathComponent("payload.json", isDirectory: false)

            #expect(throws: DurableWriteError.cannotCreateTemporaryFile(errno: ENOENT)) {
                try writeDurably(Data("{}".utf8), to: destination)
            }

            let entries = try directoryEntries(root)
            #expect(entries.isEmpty)
        }
    }
}
