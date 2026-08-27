import Foundation
import Testing

import TerminatorCore

@Suite("Формат конфига на диске")
struct ConfigFormatTests {

    /// Критерий 2. Конфиг с двумя правилами — одно включено с конкретным `enabledAt`,
    /// второе выключено — переживает запись и чтение равным значением, поле в поле.
    @Test func configRoundTripPreservesAllFields() throws {
        try withTemporaryDirectory { directory in
            let enabled = try Rule(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                limit: .constant(.seconds(600)),
                enabledAt: enabledAtFixture
            )
            let disabled = try Rule(
                bundleIdentifier: "ru.keepcoder.Telegram",
                limit: .constant(.seconds(1800))
            )
            let original = RuleConfig([enabled, disabled])

            let writer = ConfigStore(dataDirectory: directory)
            writer.load()
            try writer.save(original)

            let reader = ConfigStore(dataDirectory: directory)
            reader.load()

            #expect(reader.quarantine == nil)
            #expect(reader.config == original)

            let slack = try #require(reader.config.rule(for: "com.tinyspeck.slackmacgap"))
            #expect(slack.bundleIdentifier == "com.tinyspeck.slackmacgap")
            #expect(slack.limit == .constant(.seconds(600)))
            #expect(slack.enabledAt == enabledAtFixture)

            let telegram = try #require(reader.config.rule(for: "ru.keepcoder.Telegram"))
            #expect(telegram.bundleIdentifier == "ru.keepcoder.Telegram")
            #expect(telegram.limit == .constant(.seconds(1800)))
            #expect(telegram.enabledAt == nil)
        }
    }

    /// Критерий 3. Лимит на диске — целые секунды. Доменный тип длительности кодируется
    /// непрозрачным массивом из двух целых; в файле нет ни одного массива вообще.
    @Test func limitIsPersistedAsIntegerSecondsNotDuration() throws {
        try withTemporaryDirectory { directory in
            let rule = try Rule(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                limit: .constant(.seconds(600)),
                enabledAt: enabledAtFixture
            )
            let store = ConfigStore(dataDirectory: directory)
            store.load()
            try store.save(RuleConfig([rule]))

            let bytes = try Data(contentsOf: store.configURL)
            let text = try #require(String(data: bytes, encoding: .utf8))

            #expect(text.contains("\"limitSeconds\" : 600"))
            #expect(!text.contains("["))
            #expect(!text.contains("]"))

            let root = try #require(
                try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            )
            let rules = try #require(root["rules"] as? [String: Any])
            let entry = try #require(rules["com.tinyspeck.slackmacgap"] as? [String: Any])
            let limit = try #require(entry["limit"] as? [String: Any])
            #expect(limit["kind"] as? String == "constant")
            #expect(limit["limitSeconds"] as? Int == 600)
            #expect(entry["enabledAt"] as? String == "2026-08-27T13:00:00Z")
        }
    }

    /// Критерий 4. Номер версии схемы есть в первом же записанном байте — в том числе в
    /// файле, записанном для пустого конфига.
    @Test func schemaVersionIsWrittenOnEveryFile() throws {
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            store.load()

            try store.save(RuleConfig.empty)
            let emptyVersion = try schemaVersion(of: store.configURL)
            #expect(emptyVersion == 1)

            let emptyBytes = try Data(contentsOf: store.configURL)
            let emptyText = try #require(String(data: emptyBytes, encoding: .utf8))
            #expect(emptyText.contains("\"rules\" : {"))
            #expect(emptyText.contains("\"schemaVersion\" : 1"))

            let rule = try Rule(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                limit: .constant(.seconds(600))
            )
            try store.save(RuleConfig([rule]))
            let populatedVersion = try schemaVersion(of: store.configURL)
            #expect(populatedVersion == 1)
        }
    }

    /// Критерий 12. Литерал набран руками: pretty, ISO 8601, одно включённое правило и одно
    /// выключенное. Этот тест **и есть** человекочитаемый контракт формата — смена формата
    /// означает осознанную правку этого литерала.
    @Test func handWrittenMinimalJSONLoads() throws {
        try withTemporaryDirectory { directory in
            let json = """
            {
              "rules" : {
                "com.tinyspeck.slackmacgap" : {
                  "enabledAt" : "2026-08-27T13:00:00Z",
                  "limit" : { "kind" : "constant", "limitSeconds" : 600 }
                },
                "ru.keepcoder.Telegram" : {
                  "limit" : { "kind" : "constant", "limitSeconds" : 1800 }
                }
              },
              "schemaVersion" : 1
            }
            """

            let store = ConfigStore(dataDirectory: directory)
            try Data(json.utf8).write(to: store.configURL)
            store.load()

            #expect(store.quarantine == nil)

            let expectedSlack = try Rule(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                limit: .constant(.seconds(600)),
                enabledAt: enabledAtFixture
            )
            let expectedTelegram = try Rule(
                bundleIdentifier: "ru.keepcoder.Telegram",
                limit: .constant(.seconds(1800))
            )
            #expect(store.config == RuleConfig([expectedSlack, expectedTelegram]))
        }
    }

    /// Критерий 13. Отсутствующий `enabledAt` и явный `null` — оба «выключено». Булева
    /// флага включённости нет ни на одном типе: `enabledAt: Date?` и есть флаг (DEC-001).
    @Test func nilEnabledAtMeansDisabled() throws {
        try withTemporaryDirectory { directory in
            let json = """
            {
              "rules" : {
                "com.example.absent" : {
                  "limit" : { "kind" : "constant", "limitSeconds" : 600 }
                },
                "com.example.explicitnull" : {
                  "enabledAt" : null,
                  "limit" : { "kind" : "constant", "limitSeconds" : 600 }
                }
              },
              "schemaVersion" : 1
            }
            """

            let store = ConfigStore(dataDirectory: directory)
            try Data(json.utf8).write(to: store.configURL)
            store.load()

            #expect(store.quarantine == nil)
            #expect(store.config.rules.count == 2)

            let absent = try #require(store.config.rule(for: "com.example.absent"))
            let explicitNull = try #require(store.config.rule(for: "com.example.explicitnull"))
            #expect(absent.enabledAt == nil)
            #expect(explicitNull.enabledAt == nil)

            // Выключенное правило записывается обратно без ключа enabledAt, а не с null.
            try store.save(store.config)
            let bytes = try Data(contentsOf: store.configURL)
            let text = try #require(String(data: bytes, encoding: .utf8))
            #expect(!text.contains("enabledAt"))
        }
    }

    /// Критерий 14. Двойное кодирование одного конфига даёт идентичные байты: сортировка
    /// ключей включена, поэтому повторная запись не создаёт дифф на пустом месте.
    @Test func encodingIsDeterministic() throws {
        try withTemporaryDirectory { directory in
            let config = RuleConfig([
                try Rule(
                    bundleIdentifier: "ru.keepcoder.Telegram",
                    limit: .constant(.seconds(1800)),
                    enabledAt: earlierEnabledAtFixture
                ),
                try Rule(
                    bundleIdentifier: "com.tinyspeck.slackmacgap",
                    limit: .constant(.seconds(600)),
                    enabledAt: enabledAtFixture
                ),
                try Rule(
                    bundleIdentifier: "com.apple.Safari",
                    limit: .constant(.seconds(28800))
                )
            ])

            let store = ConfigStore(dataDirectory: directory)
            store.load()

            try store.save(config)
            let first = try Data(contentsOf: store.configURL)
            try store.save(config)
            let second = try Data(contentsOf: store.configURL)

            #expect(first == second)

            // И порядок ключей не зависит от порядка построения конфига.
            let reordered = RuleConfig(Array(config.rules.values.reversed()))
            try store.save(reordered)
            let third = try Data(contentsOf: store.configURL)
            #expect(first == third)
        }
    }

    /// Неизвестные ключи внутри известной версии схемы игнорируются: файл правится руками,
    /// и чужой комментарий-поле не должен ронять конфиг в карантин.
    @Test func unknownKeysAreIgnored() throws {
        try withTemporaryDirectory { directory in
            let json = """
            {
              "note" : "правил руками",
              "rules" : {
                "com.tinyspeck.slackmacgap" : {
                  "comment" : "работа",
                  "limit" : { "kind" : "constant", "limitSeconds" : 600, "note" : "10 минут" }
                }
              },
              "schemaVersion" : 1
            }
            """

            let store = ConfigStore(dataDirectory: directory)
            try Data(json.utf8).write(to: store.configURL)
            store.load()

            #expect(store.quarantine == nil)
            let rule = try #require(store.config.rule(for: "com.tinyspeck.slackmacgap"))
            #expect(rule.limit == .constant(.seconds(600)))
        }
    }
}
