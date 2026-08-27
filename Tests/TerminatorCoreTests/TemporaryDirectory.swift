import Foundation

/// Уникальный временный каталог на время одного теста, убирается за собой.
///
/// Ни один тест этого таргета не имеет права прочитать или записать что-либо под настоящим
/// `~/Library/Application Support` и тем более под `~/Library/LaunchAgents`. Каждое
/// хранилище в тестах конструируется каталогом отсюда.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let manager = FileManager.default
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("terminator-tests-" + UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { _ = try? manager.removeItem(at: directory) }
    return try body(directory)
}

/// Имена файлов в каталоге, отсортированные — для сравнения содержимого каталога.
func directoryEntries(_ directory: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
}

/// Момент `2026-08-27T13:00:00Z` — ровно то, что записано ISO-литералом в тестах формата.
/// Целые секунды намеренно: `Date()` несёт доли секунды, которые формат не хранит, и
/// round-trip на нём не сошёлся бы полем в поле.
let enabledAtFixture = Date(timeIntervalSince1970: 1_787_835_600)

/// Момент `2026-08-27T09:30:00Z`.
let earlierEnabledAtFixture = Date(timeIntervalSince1970: 1_787_823_000)
