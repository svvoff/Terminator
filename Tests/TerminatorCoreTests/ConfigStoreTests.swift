import Foundation
import Testing

import TerminatorCore

@Suite("Хранилище конфига: карантин, уборка, путь")
struct ConfigStoreTests {

    /// Критерий 5. Файл, записанный более новой сборкой, не грузится, причина карантина
    /// названа отдельным case, и последующая запись не трогает ни байта.
    @Test func higherSchemaVersionIsRefusedAndFileIsNotOverwritten() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            let json = configJSON(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                limitSeconds: 600,
                schemaVersion: 999
            )
            try Data(json.utf8).write(to: store.configURL)
            let before = try Data(contentsOf: store.configURL)

            store.load()

            #expect(store.config == RuleConfig.empty)
            #expect(store.isQuarantined)
            #expect(store.quarantine == .schemaVersionFromTheFuture(found: 999, supported: 1))

            #expect(throws: ConfigStoreError.quarantined(
                .schemaVersionFromTheFuture(found: 999, supported: 1)
            )) {
                try store.save(RuleConfig.empty)
            }

            let after = try Data(contentsOf: store.configURL)
            #expect(after == before)
        }
    }

    /// Критерий 6. Обрезанный файл не уничтожает прежний хороший конфиг: он остаётся в
    /// памяти, запись отказывает, обрезанные байты остаются на диске.
    @Test func truncatedFileDoesNotDestroyPreviousGoodConfig() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            store.load()

            let good = RuleConfig([
                try Rule(
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    limit: .constant(.seconds(600)),
                    enabledAt: enabledAtFixture
                ),
                try Rule(
                    bundleIdentifier: "ru.keepcoder.Telegram",
                    limit: .constant(.seconds(1800))
                )
            ])
            try store.save(good)

            let whole = try Data(contentsOf: store.configURL)
            let half = whole.prefix(whole.count / 2)
            try Data(half).write(to: store.configURL)

            store.load()

            #expect(store.config == good)
            #expect(store.isQuarantined)
            if case .undecodableBytes(let message) = store.quarantine {
                #expect(!message.isEmpty)
            } else {
                Issue.record("ожидался карантин по недекодируемым байтам, получено \(String(describing: store.quarantine))")
            }

            #expect(throws: ConfigStoreError.self) {
                try store.save(RuleConfig.empty)
            }

            let after = try Data(contentsOf: store.configURL)
            #expect(after == Data(half))
        }
    }

    /// Критерий 7. Холодный старт на битом файле: хранилище пустое и read-only, причина —
    /// ошибка декода, байты файла не изменены.
    @Test func corruptFileAtColdStartLeavesFileIntact() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            let garbage = Data("{ это не JSON, это заметка ".utf8)
            try garbage.write(to: store.configURL)

            store.load()

            #expect(store.config == RuleConfig.empty)
            #expect(store.config.rules.isEmpty)
            #expect(store.isQuarantined)
            if case .undecodableBytes(let message) = store.quarantine {
                #expect(!message.isEmpty)
            } else {
                Issue.record("ожидался карантин по недекодируемым байтам, получено \(String(describing: store.quarantine))")
            }

            #expect(throws: ConfigStoreError.self) {
                try store.save(RuleConfig.empty)
            }

            let after = try Data(contentsOf: store.configURL)
            #expect(after == garbage)
            let entries = try directoryEntries(directory)
            #expect(entries == ["config.json"])
        }
    }

    /// Критерий 8. Пустой каталог: пустой конфиг, карантина нет, файла не появилось.
    @Test func missingConfigLoadsEmptyAndWritesNothing() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            store.load()

            #expect(store.config == RuleConfig.empty)
            #expect(store.quarantine == nil)
            #expect(!FileManager.default.fileExists(atPath: store.configURL.path))

            let entries = try directoryEntries(directory)
            #expect(entries.isEmpty)
        }
    }

    /// Критерий 8, продолжение: несуществующего каталога данных загрузка тоже не создаёт.
    /// Каталог заводится при первой записи, а не при чтении.
    @Test func missingDataDirectoryIsNotCreatedByLoad() throws {
        try withTemporaryDirectory { root in
            let directory = root.appendingPathComponent("data", isDirectory: true)
            let store = ConfigStore(dataDirectory: directory)
            store.load()

            #expect(store.config == RuleConfig.empty)
            #expect(store.quarantine == nil)
            #expect(!FileManager.default.fileExists(atPath: directory.path))

            try store.save(RuleConfig.empty)
            #expect(FileManager.default.fileExists(atPath: store.configURL.path))
        }
    }

    /// Критерий 10. Уборка сносит хвосты прерванных записей и только их, и ходит **только**
    /// по каталогу данных: соседний каталог с теми же именами остаётся нетронутым.
    @Test func startupSweepRemovesStrayTempFiles() throws {
        try withTemporaryDirectory { root in
            let manager = FileManager.default
            let data = root.appendingPathComponent("data", isDirectory: true)
            let sibling = root.appendingPathComponent("sibling", isDirectory: true)
            let seeded = ["config.json.sb-abc", "config.json.tmp-def", "keep.json"]

            for directory in [data, sibling] {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                for name in seeded {
                    try Data(name.utf8).write(
                        to: directory.appendingPathComponent(name, isDirectory: false)
                    )
                }
            }

            let store = ConfigStore(dataDirectory: data)
            store.load()

            let remaining = try directoryEntries(data)
            #expect(remaining == ["keep.json"])

            let untouched = try directoryEntries(sibling)
            #expect(untouched == seeded)
        }
    }

    /// Критерий 11. Дефолтный каталог выведен из захардкоженной константы идентификатора.
    /// Обращение к свойству ничего не читает и ничего не создаёт: настоящий
    /// `~/Library/Application Support` тесты не трогают.
    @Test func dataDirectoryIsDerivedFromHardcodedIdentifier() throws {
        let directory = ConfigStore.defaultDataDirectory
        #expect(directory.path.hasSuffix("Application Support/com.svvoff.terminator"))
        #expect(directory.lastPathComponent == TerminatorIdentity.bundleIdentifier)
        #expect(TerminatorIdentity.bundleIdentifier == "com.svvoff.terminator")
        #expect(TerminatorLog.subsystem == TerminatorIdentity.bundleIdentifier)

        try withTemporaryDirectory { temporary in
            let store = ConfigStore(dataDirectory: temporary)
            #expect(store.configURL.lastPathComponent == "config.json")
            #expect(store.configURL.deletingLastPathComponent().path == temporary.path)
        }
    }

    /// Критерий 16. Лимит вне 1…480 целых минут роняет декод — каждый файл по отдельности,
    /// с карантином, отказом записи и нетронутыми байтами. Границы диапазона грузятся.
    /// Тот же диапазон отвергает лимит, построенный в памяти.
    @Test func limitOutsideOneToFourHundredEightyMinutesIsRejected() throws {
        let rejected: [(seconds: Int, reason: RuleRejectionReason)] = [
            (0, .limitMinutesOutOfRange(minutes: 0)),
            (-600, .limitMinutesOutOfRange(minutes: -10)),
            (28860, .limitMinutesOutOfRange(minutes: 481)),
            (90, .limitIsNotWholeMinutes)
        ]

        for sample in rejected {
            try withTemporaryDirectory { directory in
                let store = ConfigStore(dataDirectory: directory)
                let json = configJSON(
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    limitSeconds: sample.seconds
                )
                try Data(json.utf8).write(to: store.configURL)
                let before = try Data(contentsOf: store.configURL)

                store.load()

                #expect(store.config == RuleConfig.empty)
                #expect(store.isQuarantined)
                #expect(store.quarantine == .rejectedRule(RuleRejected(
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    reason: sample.reason
                )))

                #expect(throws: ConfigStoreError.self) {
                    try store.save(RuleConfig.empty)
                }

                let after = try Data(contentsOf: store.configURL)
                #expect(after == before)
            }
        }

        for seconds in [60, 28800] {
            try withTemporaryDirectory { directory in
                let store = ConfigStore(dataDirectory: directory)
                let json = configJSON(
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    limitSeconds: seconds
                )
                try Data(json.utf8).write(to: store.configURL)

                store.load()

                #expect(store.quarantine == nil)
                let rule = try #require(store.config.rule(for: "com.tinyspeck.slackmacgap"))
                #expect(rule.limit == .constant(.seconds(seconds)))
            }
        }

        #expect(throws: RuleRejected(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            reason: .limitMinutesOutOfRange(minutes: 0)
        )) {
            _ = try Rule(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                limit: .constant(.seconds(0))
            )
        }
        #expect(throws: RuleRejected(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            reason: .limitIsNotWholeMinutes
        )) {
            _ = try Rule(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                limit: .constant(.seconds(90))
            )
        }
        #expect(throws: RuleRejected(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            reason: .limitMinutesOutOfRange(minutes: 481)
        )) {
            _ = try Rule(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                limit: .constant(.seconds(28860))
            )
        }
    }

    /// Критерий 17. Правило на самого себя отвергается и на декоде, и при построении в
    /// памяти. Через UI это недостижимо, но файл правится руками, и модель — последняя линия.
    @Test func selfRuleIsRejected() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            let json = configJSON(
                bundleIdentifier: TerminatorIdentity.bundleIdentifier,
                limitSeconds: 600
            )
            try Data(json.utf8).write(to: store.configURL)
            let before = try Data(contentsOf: store.configURL)

            store.load()

            #expect(store.config == RuleConfig.empty)
            #expect(store.isQuarantined)
            #expect(store.quarantine == .rejectedRule(RuleRejected(
                bundleIdentifier: TerminatorIdentity.bundleIdentifier,
                reason: .watchesTerminatorItself
            )))

            #expect(throws: ConfigStoreError.self) {
                try store.save(RuleConfig.empty)
            }

            let after = try Data(contentsOf: store.configURL)
            #expect(after == before)
        }

        #expect(throws: RuleRejected(
            bundleIdentifier: TerminatorIdentity.bundleIdentifier,
            reason: .watchesTerminatorItself
        )) {
            _ = try Rule(
                bundleIdentifier: TerminatorIdentity.bundleIdentifier,
                limit: .constant(.seconds(600))
            )
        }
    }

    /// Карантин снимается только починкой файла и повторной загрузкой — не записью.
    @Test func quarantineIsClearedOnlyByASuccessfulReload() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            try Data("{".utf8).write(to: store.configURL)

            store.load()
            #expect(store.isQuarantined)

            let good = configJSON(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                limitSeconds: 600
            )
            try Data(good.utf8).write(to: store.configURL)

            store.load()
            #expect(!store.isQuarantined)
            #expect(store.quarantine == nil)
            #expect(store.config.rules.count == 1)

            try store.save(RuleConfig.empty)
            #expect(store.config == RuleConfig.empty)
        }
    }
}
