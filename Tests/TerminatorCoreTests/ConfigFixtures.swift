import Foundation

/// Файл конфига с одним правилом — заготовка для проверок отказа декода.
///
/// Литерал набран руками намеренно: формат — человекочитаемый контракт, и тесты читают его
/// теми же глазами, что и пользователь.
func configJSON(bundleIdentifier: String, limitSeconds: Int, schemaVersion: Int = 1) -> String {
    """
    {
      "rules" : {
        "\(bundleIdentifier)" : {
          "limit" : { "kind" : "constant", "limitSeconds" : \(limitSeconds) }
        }
      },
      "schemaVersion" : \(schemaVersion)
    }
    """
}

/// Значение `schemaVersion` в файле, прочитанное независимо от кодека продукта.
func schemaVersion(of url: URL) throws -> Int? {
    let bytes = try Data(contentsOf: url)
    let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
    return root?["schemaVersion"] as? Int
}
