import AppKit
import Foundation
import UniformTypeIdentifiers
import os

import TerminatorAppKit
import TerminatorCore

/// Логгер поповера. Категория `store`: всё, что поповер логирует про список правил, — это
/// состояние хранилища, которое он показывает.
///
/// Каждая интерполяция несёт `privacy: .public` — без исключений. Редакция происходит в момент
/// записи и необратима (findings §14), а лог — единственный диагностический канал продукта:
/// предупреждений перед закрытием нет (DEC-004).
private let popoverLog = Logger(
    subsystem: TerminatorLog.subsystem,
    category: TerminatorLog.Category.store
)

/// Логгер автозапуска. Категория `loginitem` — та же, в которую пишет `LoginItemService`:
/// автор, разбирающий, почему не сработал автозапуск, читает одну категорию, а не две.
///
/// Пишутся отсюда ровно три строки, и все три — отказы, которых в логе иначе не будет:
/// `Bundle.main.executableURL == nil` (до сервиса не доходит вовсе), бросок из `enable` и
/// бросок из `disable`. Сервис логирует успех записи, успех удаления, каждое чтение статуса и
/// отказ генератора plist — но не броски из `createDirectory`, `writeDurably` и `removeItem`.
/// Молчаливый отказ записи не оставил бы ответа на вопрос «почему автозапуск не сработал»:
/// `notice` живёт до следующего действия пользователя и исчезает вместе с поповером
/// (DEC-004, findings §14).
private let loginItemLog = Logger(
    subsystem: TerminatorLog.subsystem,
    category: TerminatorLog.Category.loginItem
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

    /// Сервис автозапуска с каталогом по умолчанию. Живёт здесь, а не в композиционном
    /// корне: состояния у него нет, кроме двух URL, а конструктор ничего не создаёт и
    /// ничего не читает.
    private let loginItem = LoginItemService()

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

    /// Последнее прочитанное состояние автозапуска. `nil` означает «ещё не читали».
    ///
    /// Опционал здесь несёт смысл, а не осторожность: доменный случай по умолчанию
    /// (`notRegistered`) нарисовал бы выключенный тумблер, не прочитав ничего, на первом
    /// кадре каждого открытия. Статус читается **ровно дважды** — при открытии поповера и
    /// сразу после переключения, — потому что каждое чтение пишет строку в лог, а вью
    /// перерисовывается раз в секунду (findings §14).
    private(set) var loginItemStatus: LoginItemStatus?

    /// Регистрация записана, но система ещё не сообщает включённое состояние.
    ///
    /// Сообщит ли `statusForLegacyPlist` включённое состояние сразу после записи файла или
    /// только после следующего входа — разведкой не установлено (findings §12), и **оба
    /// прочтения нормальны**. Флаг ставится, только когда `enable` не бросил, а перечитанный
    /// статус не стал `.enabled`, и снимается при любом следующем чтении. Это не отказ.
    private(set) var loginItemRegistrationPending = false

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
        readLoginItemStatus()
        if let quarantine {
            let reason = String(describing: quarantine)
            popoverLog.notice("popover opened with quarantined store, edits will be refused: reason=\(reason, privacy: .public)")
        }
    }

    // MARK: - Автозапуск

    /// Положение тумблера автозапуска: **есть ли на диске наша регистрация**.
    ///
    /// `disabledByUser` даёт **включённый** тумблер, и это не описка: наш plist на месте,
    /// выключил пункт пользователь в System Settings. Тумблер отвечает на вопрос
    /// «зарегистрировали ли мы себя», текст строки — на вопрос «что об этом думает система».
    var launchAtLoginIsOn: Bool {
        guard let loginItemStatus else { return false }
        switch loginItemStatus {
        case .enabled, .disabledByUser: return true
        case .notRegistered, .unknown: return false
        }
    }

    /// Интерактивен ли тумблер.
    ///
    /// Нет в двух состояниях: пока статус не прочитан и когда система вернула значение, о
    /// котором разведка ничего не измерила. Предлагать переключатель в неизвестном состоянии
    /// значило бы врать о том, что произойдёт по нажатию.
    var launchAtLoginIsInteractive: Bool {
        guard let loginItemStatus else { return false }
        switch loginItemStatus {
        case .enabled, .disabledByUser, .notRegistered: return true
        case .unknown: return false
        }
    }

    /// Во что превращается нажатие на тумблер.
    private enum LaunchAtLoginGesture {
        case register
        case unregister
        case ignore
    }

    /// Единственное место, где решается, что делает жест. Чистая функция статуса.
    ///
    /// Главное её свойство: из `.disabledByUser` она не возвращает `.register` ни при каком
    /// значении `turningOn`. Перерегистрация после того, как пользователь выключил пункт в
    /// System Settings, — ровно то поведение, которое запрещает DEC-006, и запрет выражен
    /// здесь конструкцией, а не дисциплиной вызывающего: `enable(executableAt:)` пишет
    /// безусловно и перекрыл бы файл, не глядя на состояние.
    ///
    /// Из `.disabledByUser` остаётся один законный жест — снять нашу регистрацию, — и он
    /// ничем не отличается от того же жеста из `.enabled`.
    private static func gesture(
        for status: LoginItemStatus?,
        turningOn: Bool
    ) -> LaunchAtLoginGesture {
        guard let status else { return .ignore }
        switch status {
        case .unknown:
            return .ignore
        case .notRegistered:
            return turningOn ? .register : .ignore
        case .enabled, .disabledByUser:
            return turningOn ? .ignore : .unregister
        }
    }

    /// Переключатель автозапуска.
    ///
    /// Отказ виден пользователю существующей строкой `notice` — там же, где остальные отказы
    /// поповера: ни уведомления, ни алерта, ни HUD у продукта нет (DEC-004). Второго
    /// пользовательского канала не заводится. В лог отказ уходит отдельно и по другой
    /// причине: `notice` живёт до следующего действия, а лог остаётся.
    ///
    /// Строка обновляется **перечитанным** статусом, а не тем, что нажали: система — источник
    /// истины и в успешном случае тоже.
    func setLaunchAtLogin(_ isOn: Bool) {
        switch Self.gesture(for: loginItemStatus, turningOn: isOn) {
        case .ignore:
            // Жест ничего не значит в текущем состоянии. Ни записи, ни удаления, ни чтения:
            // `notice` тоже не трогается, иначе исчезла бы обратная связь прошлого действия.
            return

        case .register:
            notice = nil
            // Неупакованный случай: у голого исполняемого файла адреса нет, до сервиса он не
            // доходит — поэтому логируется здесь. Силой разворачивать нечего.
            guard let executable = Bundle.main.executableURL else {
                notice = "Launch at login was not turned on: this build has no executable path."
                loginItemLog.notice("login item not written: Bundle.main.executableURL is nil")
                return
            }
            do {
                try loginItem.enable(executableAt: executable)
                readLoginItemStatus(registrationWritten: true)
            } catch {
                // Сервис логирует только отказ генератора plist: броски из `createDirectory`
                // и `writeDurably` уходят вызывающему молча. `notice` живёт до следующего
                // действия и исчезает вместе с поповером, а лог — единственный ответ на
                // вопрос «почему автозапуск не сработал» (DEC-004, findings §14).
                let reason = String(describing: error)
                loginItemLog.notice("login item not written: executable=\(executable.path, privacy: .public) reason=\(reason, privacy: .public)")
                notice = "Launch at login was not turned on. The login item was not written."
                readLoginItemStatus()
            }

        case .unregister:
            notice = nil
            do {
                try loginItem.disable()
            } catch {
                // `disable()` логирует успех и отсутствие файла; любой другой отказ
                // `removeItem` уходит молча — по той же причине он записывается здесь.
                let reason = String(describing: error)
                loginItemLog.notice("login item not removed: path=\(self.loginItem.plistURL.path, privacy: .public) reason=\(reason, privacy: .public)")
                notice = "Launch at login was not turned off. The login item file is still there."
            }
            readLoginItemStatus()
        }
    }

    /// Единственное место во всём приложении, где зовётся `status()`. Зовут его отсюда
    /// ровно двое: `popoverDidOpen()` и `setLaunchAtLogin(_:)`, то есть на одно открытие
    /// поповера и на одно переключение приходится по одному чтению — и по одной строке в
    /// логе (findings §14).
    ///
    /// `registrationWritten` ставится только на пути успешной записи: тогда статус, не
    /// ставший `.enabled`, означает «вступит в силу при следующем входе», а не отказ. Любое
    /// другое чтение флаг снимает.
    private func readLoginItemStatus(registrationWritten: Bool = false) {
        let status = loginItem.status()
        loginItemStatus = status
        loginItemRegistrationPending = registrationWritten && status != .enabled
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
