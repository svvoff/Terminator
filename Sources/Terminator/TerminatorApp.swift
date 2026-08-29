import AppKit
import SwiftUI
import TerminatorCore
import TerminatorAppKit

/// Точка входа и **композиционный корень**. Файл намеренно НЕ называется `main.swift`:
/// SwiftPM трактует `main.swift` как top-level code и `@main` в нём не работает.
///
/// Граф объектов строится один раз, при запуске, в `AppDelegate` ниже: хранилище конфига
/// (TASK-003), движок, KVO-наблюдатель, два таймера, отправитель quit и рендерер лога.
/// Больше им жить негде — движок это value type в ядре, а адаптеры инертны, пока их никто
/// не держит.
///
/// `setActivationPolicy(.accessory)` не вызывается: внутри бандла с `LSUIElement=true`
/// политика уже `.accessory`, и вызов вернул бы `false` (findings §7).
@main
struct TerminatorApp: App {

    /// Делегат приложения — держатель графа. Сцена SwiftUI не годится на эту роль: её тело
    /// перевычисляется, а наблюдение и таймеры должны быть заведены ровно один раз.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: appDelegate.popover)
        } label: {
            // Готовый Image(nsImage:) и ничего больше. Произвольное SwiftUI-вью
            // компилируется, но не соблюдается: лейбл принимает только Text, Image
            // или Label, а .symbolRenderingMode(.palette) сплющивается в template
            // и теряет красные глаза (findings §8).
            //
            // Прямая реактивная форма: состояние → готовый образ. Никаких .id(...),
            // пересозданий сцены и ручных инвалидаций — на реактивности этого лейбла
            // строится TASK-006, и если её нет, это измерение, а не повод обходить.
            //
            // Бит приезжает из модели, которая живёт в AppDelegate: глаза обязаны быть
            // верны, когда поповер закрыт и его вью не существует.
            Image(nsImage: menuBarSkullImage(eyes: appDelegate.popover.eyes))
        }
        .menuBarExtraStyle(.window)
    }
}

/// Владелец графа объектов и единственное место, где он собирается.
///
/// Здесь нет ни одного решения о поведении: делегат строит контроллер и запускает его.
/// Что считать, когда закрывать и что писать в лог, решает редьюсер в `TerminatorCore`.
///
/// Сопротивления закрытию здесь нет и не будет: закрыть Terminator — штатное действие,
/// которое останавливает всё, что он делает (DEC-006). Ни перезапуска, ни вспомогательного
/// процесса, ни персистенции отсчётов.
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Хранилище конфига (TASK-003) — первый узел графа: контроллер грузит его на старте и
    /// кормит движок входом `.configChanged`.
    let controller = WatchController(store: ConfigStore())

    /// Модель поповера (TASK-006). Держится **здесь**, а не во вью: состояние глаз глифа
    /// обязано быть верным, когда поповер закрыт и его вью не существует.
    private(set) lazy var popover = PopoverModel(controller: controller)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ровно одно присваивание и ровно один раз. Слот заполняется до `start()`, чтобы
        // первый же вход движка — загруженный конфиг и стартовая сверка — уже дошёл до
        // модели, а с ней до глаз глифа.
        controller.onStateChanged = { [weak self] in self?.popover.refresh() }
        controller.start()
    }
}
