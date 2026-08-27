import Foundation
import Testing

import TerminatorCore

@Suite("Доменная модель правила")
struct RuleModelTests {

    /// Критерий 15. Ответ на «либо невозможно по типу, либо отвергается на декоде» —
    /// **невозможно по типу**: правила хранятся словарём с ключом по bundle id, и на диске
    /// форма та же. Второе правило с тем же идентификатором вытесняет первое, а не
    /// соседствует с ним, поэтому состояние «два правила на одно приложение» невыразимо.
    @Test func oneRulePerBundleIdentifier() throws {
        let first = try Rule(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            limit: .constant(.seconds(600))
        )
        let second = try Rule(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            limit: .constant(.seconds(1800)),
            enabledAt: enabledAtFixture
        )

        let config = RuleConfig([first, second])
        #expect(config.rules.count == 1)
        #expect(config.rule(for: "com.tinyspeck.slackmacgap") == second)

        var mutated = RuleConfig([first])
        mutated.set(second)
        #expect(mutated.rules.count == 1)
        #expect(mutated == config)

        // И на диске: rules — JSON-объект с ключом по bundle id, а не массив, в котором
        // дубликат был бы выразим.
        try withTemporaryDirectory { directory in
            let store = ConfigStore(dataDirectory: directory)
            store.load()
            try store.save(config)

            let bytes = try Data(contentsOf: store.configURL)
            let root = try #require(
                try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            )
            let rules = try #require(root["rules"] as? [String: Any])
            #expect(rules.count == 1)
            #expect(rules["com.tinyspeck.slackmacgap"] != nil)
        }
    }

    /// Лимит — тегированный enum с одним case и одним ассоциированным значением, и целые
    /// минуты 1…480 он проверяет сам.
    @Test func wholeMinutesAreTheOnlyValidLimits() {
        #expect(Limit.constant(.seconds(60)).wholeMinutes == 1)
        #expect(Limit.constant(.seconds(28800)).wholeMinutes == 480)
        #expect(Limit.constant(.seconds(90)).wholeMinutes == nil)
        #expect(Limit.constant(.milliseconds(60_500)).wholeMinutes == nil)
        #expect(Limit.allowedMinutes == 1...480)
    }
}
