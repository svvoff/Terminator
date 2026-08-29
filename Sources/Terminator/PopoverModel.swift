import AppKit
import Foundation
import UniformTypeIdentifiers
import os

import TerminatorAppKit
import TerminatorCore

/// Логгер поповера. Категория ровно одна — `store`: всё, что поповер логирует, это состояние
/// хранилища, которое он показывает. Новых категорий эта карточка не заводит.
///
/// Каждая интерполяция несёт `privacy: .public` — без исключений. Редакция происходит в момент
/// записи и необратима (findings §14), а лог — единственный диагностический канал продукта:
/// предупреждений перед закрытием нет (DEC-004).
private let popoverLog = Logger(
    subsystem: TerminatorLog.subsystem,
    category: TerminatorLog.Category.store
)

/// Модель поповера: снимок состояния движка и хранилища плюс действия пользователя.
///
/// **Живёт вне поповера.** Её держит `AppDelegate`, а не вью, потому что состояние глаз
/// глифа обязано быть верным, когда поповер закрыт и его вью не существует.
///
/// Модель ничего не считает про время: остаток и порядок строк — дело `PopoverViewModel` в
/// ядре, которому `now` приходит параметром на каждый рендер.
@Observable
final class PopoverModel {

    /// Лимит по умолчанию для только что добавленного правила, в целых минутах. Значение
    /// внутри `Limit.allowedMinutes`; поменять его — дело редактора в строке правила.
    static let defaultLimitMinutes = 60

    private let controller: WatchController

    /// Снимок конфига, снятый с контроллера. Не источник истины — источник на диске.
    private(set) var config: RuleConfig = .empty

    /// Снимок живых отсчётов движка.
    private(set) var sessions: [ProcessSession] = []

    /// Состояние карантина хранилища.
    private(set) var quarantine: ConfigLoadFailure?

    /// Состояние глаз глифа: функция фаз сессий, а не флаг, который ставит вью (DEC-009).
    private(set) var eyes: MenuBarGlyphEyes = .idle

    /// Одна строка обратной связи на действие пользователя, живущая до следующего действия.
    /// Ни алерта, ни уведомления, ни HUD: поповер — единственный канал продукта.
    private(set) var notice: String?

    init(controller: WatchController) {
        self.controller = controller
    }

    /// Перечитывает состояние движка и хранилища. Зовётся из `onStateChanged`, то есть на
    /// каждый вход движка, и после каждого действия пользователя.
    func refresh() {
        config = controller.config
        sessions = controller.activeSessions
        quarantine = controller.quarantine
        eyes = PopoverViewModel.anyCountdownInFlight(in: sessions) ? .active : .idle
    }

    /// Состояние списка на переданный момент. Единственный источник чисел для вью.
    func state(at now: Date) -> PopoverViewModel {
        PopoverViewModel(config: config, sessions: sessions, quarantine: quarantine, now: now)
    }

    // MARK: - Открытие поповера

    /// Поповер открылся: перечитать файл с диска и обновить снимок.
    ///
    /// Перечитывание обязательно и не косметично: `load()` зовётся один раз за жизнь
    /// процесса, карантин выставляется только внутри него. Без этого порча файла на живом
    /// приложении осталась бы незамеченной, а следующая правка затёрла бы ручное
    /// редактирование. Чинить файл при этом нельзя — только сообщить.
    ///
    /// `notice` здесь **не** сбрасывается: панель выбора приложения забирает key-статус и
    /// может закрыть поповер, и тогда единственное место, где виден отказ, — следующий его
    /// открытие.
    func popoverDidOpen() {
        controller.reloadFromDisk()
        refresh()
        if let quarantine {
            let reason = String(describing: quarantine)
            popoverLog.notice("popover opened with quarantined store, edits will be refused: reason=\(reason, privacy: .public)")
        }
    }

    // MARK: - Действия пользователя

    /// Добавление приложения: панель выбора, `Bundle(url:)`, правило.
    ///
    /// Панель отфильтрована по типу содержимого `.application`. Это единственный механизм
    /// добавления и он покрывает оба случая — запущенное приложение и незапущенное, — а
    /// список процессов не покрыл бы второй вовсе (findings §10).
    func addApplication() {
        notice = nil

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add"
        panel.message = "Choose an application to put on a time limit."
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Идентификатор берётся из бандла, а не из имени файла: сопоставление идёт по точной
        // строке `bundleIdentifier` и ни по чему больше (findings §10).
        guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
            notice = "\(url.lastPathComponent) has no bundle identifier. No rule was created."
            popoverLog.notice("rule not created, bundle has no identifier: path=\(url.path, privacy: .public)")
            return
        }

        guard config.rule(for: bundleIdentifier) == nil else {
            notice = "\(bundleIdentifier) is already on the list."
            return
        }

        do {
            // Новое правило приходит включённым: `enabledAt = now` — это и флаг, и якорь
            // отсчёта (DEC-001), и та же формула `max(processStartTime, enabledAt) + limit`
            // даёт полный лимит от момента добавления.
            let rule = try Rule(
                bundleIdentifier: bundleIdentifier,
                limit: .constant(.seconds(Self.defaultLimitMinutes * 60)),
                enabledAt: Date()
            )
            var next = config
            next.set(rule)
            apply(next, describing: bundleIdentifier)
        } catch let rejected as RuleRejected {
            notice = rejected.reason.editorMessage
        } catch {
            notice = "Could not add \(bundleIdentifier)."
        }
    }

    /// Удаление правила. Подтверждения нет: пользователь — союзник, а не противник (DEC-006).
    ///
    /// Удаления в модели правил нет, и заводить его в ядре эта карточка не вправе: набор
    /// пересобирается публичным конструктором из оставшихся правил.
    func removeRule(_ bundleIdentifier: String) {
        notice = nil
        let kept = config.rules.values.filter { $0.bundleIdentifier != bundleIdentifier }
        apply(RuleConfig(Array(kept)), describing: bundleIdentifier)
    }

    /// Переключатель правила. Включение ставит `enabledAt = now` и тем самым переякоривает
    /// дедлайн на `max(processStartTime, enabledAt) + limit`; выключение ставит `nil` и
    /// снимает сессию целиком (DEC-001). Ни подтверждения, ни трения (DEC-006).
    func setEnabled(_ isEnabled: Bool, for bundleIdentifier: String) {
        notice = nil
        guard let rule = config.rule(for: bundleIdentifier) else { return }
        replace(rule, limit: rule.limit, enabledAt: isEnabled ? Date() : nil)
    }

    /// Правка лимита. Валидация — в ядре и по строке, потому что «нецелое» выразимо только
    /// на входе редактора. Смена лимита **не** переякоривает: `enabledAt` переносится
    /// как есть.
    ///
    /// Возвращает `true`, если правка принята: вью по этому ответу решает, оставить ли
    /// набранный текст или вернуть прежний.
    @discardableResult
    func setLimit(fromMinutesText text: String, for bundleIdentifier: String) -> Bool {
        notice = nil
        guard let rule = config.rule(for: bundleIdentifier) else { return false }
        if rule.limit.wholeMinutes.map(String.init) == text.trimmingCharacters(in: .whitespaces) {
            return true
        }
        switch PopoverViewModel.limit(fromMinutesText: text) {
        case .rejected(let reason):
            notice = reason.editorMessage
            return false
        case .accepted(let limit):
            replace(rule, limit: limit, enabledAt: rule.enabledAt)
            return notice == nil
        }
    }

    // MARK: - Запись

    /// `Rule` неизменяем: любая правка — построение нового правила с повтором двух других
    /// полей. Валидация лимита сработает даже на «выключить», хотя лимит не менялся, — это
    /// свойство модели.
    private func replace(_ rule: Rule, limit: Limit, enabledAt: Date?) {
        do {
            let updated = try Rule(
                bundleIdentifier: rule.bundleIdentifier,
                limit: limit,
                enabledAt: enabledAt
            )
            var next = config
            next.set(updated)
            apply(next, describing: rule.bundleIdentifier)
        } catch let rejected as RuleRejected {
            notice = rejected.reason.editorMessage
        } catch {
            notice = "Could not update \(rule.bundleIdentifier)."
        }
    }

    /// **Единственная дверь записи.** Никогда не `ConfigStore.save(_:)` напрямую: контроллер
    /// пишет через хранилище, сообщает движку новый набор правил и делает сверку. Без
    /// последних двух шагов файл был бы записан, список обновлён, а движок продолжил бы
    /// считать по старым правилам — отказ, бессимптомный до самого закрытия приложения.
    ///
    /// Обработчик не ограничивается `ConfigStoreError`: из пути записи приходят и
    /// `DurableWriteError`, и ошибки Foundation от создания каталога.
    private func apply(_ next: RuleConfig, describing bundleIdentifier: String) {
        do {
            try controller.apply(next)
        } catch let error as ConfigStoreError {
            switch error {
            case .quarantined:
                notice = "Not saved: the config file is quarantined and left untouched."
            }
            log(error, bundleIdentifier: bundleIdentifier)
        } catch {
            notice = "Not saved: the config file could not be written."
            log(error, bundleIdentifier: bundleIdentifier)
        }
        refresh()
    }

    private func log(_ error: any Error, bundleIdentifier: String) {
        let reason = String(describing: error)
        popoverLog.notice("edit refused: bundle=\(bundleIdentifier, privacy: .public) reason=\(reason, privacy: .public)")
    }
}
