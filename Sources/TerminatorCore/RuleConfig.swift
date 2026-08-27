import Foundation

/// Набор правил — то, что лежит в конфиге целиком.
///
/// Правила хранятся словарём с ключом по bundle id, поэтому «два правила на одно
/// приложение» невозможны по типу: второе правило с тем же идентификатором заменяет первое,
/// а не соседствует с ним. Форма на диске та же — JSON-объект, ключ = bundle id.
public struct RuleConfig: Equatable, Sendable {

    /// Правила по точному bundle id приложения-цели.
    public private(set) var rules: [String: Rule]

    /// Пустой конфиг: ни одного правила. Он же — результат загрузки, когда файла нет.
    public static let empty = RuleConfig()

    public init() {
        self.rules = [:]
    }

    /// Собирает конфиг из списка правил.
    ///
    /// Порядок значим только при совпадении идентификаторов: правило, идущее позже,
    /// вытесняет более раннее с тем же ключом.
    public init(_ rules: [Rule]) {
        self.rules = [:]
        for rule in rules {
            self.rules[rule.bundleIdentifier] = rule
        }
    }

    /// Правило для приложения, если оно есть.
    public func rule(for bundleIdentifier: String) -> Rule? {
        rules[bundleIdentifier]
    }

    /// Добавляет правило или заменяет прежнее правило того же приложения.
    public mutating func set(_ rule: Rule) {
        rules[rule.bundleIdentifier] = rule
    }
}
