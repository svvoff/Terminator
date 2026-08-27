// swift-tools-version: 6.2
//
// Источник истины по таргетам, зависимостям и настройкам компилятора (DEC-007).
// .xcodeproj не коммитится и не существует.
//
// swift-tools-version: 6.2 переводит все таргеты в Swift 6 language mode (findings §13).
// SwiftSetting.defaultIsolation(MainActor.self) стоит на адаптере и на исполняемом
// таргете и СОЗНАТЕЛЬНО не стоит на TerminatorCore: ядро остаётся чистым и
// nonisolated, чтобы редьюсер TASK-003/TASK-004 тестировался без MainActor.

import PackageDescription

let package = Package(
    name: "Terminator",
    platforms: [
        // Тот же пол, что LSMinimumSystemVersion = 14.0 в Packaging/Info.plist.
        // Поднимать один без другого нельзя.
        .macOS(.v14)
    ],
    products: [
        // Имя продукта = имя бинаря = CFBundleExecutable: build.sh кладёт его
        // в Contents/MacOS/Terminator.
        .executable(name: "Terminator", targets: ["Terminator"])
    ],
    dependencies: [],
    targets: [
        // Только Foundation. Без AppKit и без defaultIsolation (findings §13).
        .target(name: "TerminatorCore"),

        .target(
            name: "TerminatorAppKit",
            dependencies: ["TerminatorCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        // Никаких resources: на исполняемом таргете — Bundle.module непригоден
        // с рукописным бандлом (findings §7).
        .executableTarget(
            name: "Terminator",
            dependencies: ["TerminatorCore", "TerminatorAppKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),

        // Тесты ядра. Без defaultIsolation по той же причине, что и сам TerminatorCore:
        // ядро тестируется вне MainActor. Фреймворк — swift-testing, он идёт с тулчейном
        // и зависимости пакета не требует.
        .testTarget(name: "TerminatorCoreTests", dependencies: ["TerminatorCore"])
    ]
)
