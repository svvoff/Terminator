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

    /// Человекочитаемые имена приложений, снятые на текущее открытие поповера.
    ///
    /// Ключ — bundle id, значение — то же имя, которое показывает Finder. Идентификатор, для
    /// которого имя не нашлось, в словаре **отсутствует**: правило переживает удаление
    /// приложения, и пустая строка на месте имени была бы хуже самого идентификатора.
    ///
    /// Словарь живёт только в памяти. В `config.json` имя не попадает никогда: это сменило бы
    /// человекочитаемый контракт на диске ради значения, которое протухает от переименования,
    /// смены языка или замены приложения.
    private var displayNames: [String: String] = [:]

    /// Регистрация записана, но система ещё не сообщает включённое состояние.
    ///
    /// Сообщит ли `statusForLegacyPlist` включённое состояние сразу после записи файла или
    /// только после следующего входа — **измерено**: `3` через 4 мс и `1` через 28 мин 54 с без
    /// входа между чтениями (findings §12). Оба прочтения нормальны, и это не отказ.
    ///
    /// Флаг ставится, только когда `enable` не бросил **и** перечитанный статус допускает, что
    /// регистрация вступит сама, — то есть по `LoginItemStatus.registrationCanTakeEffect`, а не
    /// по одному лишь «не `.enabled`». Разница ровно в `disabledByUser`: там запись состоялась,
    /// а вступить ей не даст пользователь, и обещание следующего входа было бы неправдой.
    /// Снимается при любом следующем чтении.
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
        // Строго после `refresh()`: имена резолвятся по тому набору правил, который только что
        // пришёл с диска, иначе правило, дописанное в файл руками, осталось бы без имени до
        // следующего открытия.
        resolveDisplayNames()
        readLoginItemStatus()
        if let quarantine {
            let reason = String(describing: quarantine)
            popoverLog.notice("popover opened with quarantined store, edits will be refused: reason=\(reason, privacy: .public)")
        }
    }

    /// Имя приложения для строки списка. `nil` означает «не резолвится» — приложение не
    /// установлено, а правило его пережило; вью в этом случае показывает идентификатор.
    func displayName(for bundleIdentifier: String) -> String? {
        displayNames[bundleIdentifier]
    }

    /// Резолв имён — **одно чтение на открытие поповера, а не на кадр**.
    ///
    /// Содержимое поповера перерисовывается раз в секунду ради отсчёта, а
    /// `urlForApplication(withBundleIdentifier:)` — запрос в LaunchServices. Один запрос на
    /// строку на кадр был бы платой за значение, которое при открытом поповере не меняется. Та
    /// же дисциплина уже применена к статусу автозапуска: одно чтение на открытие.
    ///
    /// **Имя берётся у Finder, а не из `Info.plist`.** Ключи не годятся: `CFBundleDisplayName`
    /// у `com.tdesktop.Telegram` отсутствует, а обёрнутое iOS-приложение
    /// `org.khronos.gltf.glTFViewer` не несёт на верхнем уровне даже каталога `Contents/` —
    /// его настоящий бандл лежит под `Wrapper/`, и `CFBundleName` там читается как
    /// `glTFViewer`, без пробела, то есть не так, как это приложение называет Finder.
    /// Реализация через ключи выглядит правильной и молча даёт то отсутствие, то не то имя;
    /// `displayName(atPath:)` вдобавок отдаёт локализованное имя.
    ///
    /// Имя — presentation и ничего больше: в сортировку, в фильтрацию и ни в одно решение оно
    /// не входит. Порядок строк остаётся за ядром — по остатку, затем по `bundleIdentifier`.
    private func resolveDisplayNames() {
        var resolved: [String: String] = [:]
        resolved.reserveCapacity(config.rules.count)
        for bundleIdentifier in config.rules.keys {
            guard
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            else {
                // Приложение не установлено. Случай настоящий: правило переживает удаление
                // приложения, и строка обязана остаться на месте — со своим идентификатором.
                continue
            }
            let name = FileManager.default.displayName(atPath: url.path)
            guard !name.isEmpty else { continue }
            resolved[bundleIdentifier] = name
        }
        displayNames = resolved
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
    /// `registrationWritten` ставится только на пути успешной записи. Но одного факта записи
    /// для обещания «вступит в силу при следующем входе» мало, и решает это не данная функция,
    /// а `registrationCanTakeEffect` в ядре: из `disabledByUser` регистрация сама не вступит
    /// никогда, сколько её ни перезаписывай, и обещание было бы там прямой неправдой поверх
    /// правильного текста о System Settings. Любое другое чтение флаг снимает.
    private func readLoginItemStatus(registrationWritten: Bool = false) {
        let status = loginItem.status()
        loginItemStatus = status
        loginItemRegistrationPending = registrationWritten && status.registrationCanTakeEffect
    }

    // MARK: - Действия пользователя

    /// Валидатор выбора в панели добавления, **удерживаемый хранимым свойством**.
    ///
    /// `NSOpenPanel.delegate` — слабая ссылка. Делегат, созданный инлайн в
    /// `addApplication()`, освободился бы сразу после присваивания: `panel(_:validate:)` не
    /// вызвался бы ни разу, панель закрывалась бы по-прежнему, отказ снова уходил бы в
    /// невидимую строку `notice` — и дефект выглядел бы неисправленным, молча. Сильная
    /// ссылка живёт здесь, панель одалживает её на время `runModal()`.
    private let addPanelValidator = AddApplicationValidator()

    /// Проверка выбора **внутри** панели: панель, отклонившая выбор, не закрывается и сама
    /// показывает причину — пользователь остаётся в том же диалоге и может выбрать другое
    /// приложение, не открывая поповер заново.
    ///
    /// Зачем это здесь, а не в `notice`: путь добавления — единственный в поповере, который
    /// открывает модальную панель, а открытие панели закрывает сам поповер вместе со
    /// строкой `notice`. Отказ, поднятый после `runModal()`, пользователю уже не виден;
    /// поднятый отсюда — виден в момент действия.
    ///
    /// Проверяются ровно два условия и только они: нет `bundleIdentifier` и правило для него
    /// уже есть. Ни подпись, ни платформа, ни запущенность не проверяются — обёрнутое
    /// iOS-приложение законная цель, его идентификатор резолвится через `Wrapper/`.
    private final class AddApplicationValidator: NSObject, NSOpenSavePanelDelegate {

        /// Идентификаторы, у которых правило уже есть. Снимок, снятый перед `runModal()`:
        /// пока панель модальна, ни один путь записи конфига не исполняется, так что снимок
        /// и живой конфиг совпадают на всё время проверки.
        var identifiersOnTheList: Set<String> = []

        /// Формулировка отказа читается внутри открытой панели, поэтому говорит о самом
        /// выборе, а не о ненаступившем последствии: правило здесь ещё и не начинали
        /// создавать.
        func panel(_ sender: Any, validate url: URL) throws {
            guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
                throw Self.refusal(
                    "\(url.lastPathComponent) has no bundle identifier and cannot be put on a time limit."
                )
            }
            guard !identifiersOnTheList.contains(bundleIdentifier) else {
                throw Self.refusal("\(bundleIdentifier) is already on the list.")
            }
        }

        /// Панель показывает `localizedDescription` брошенной ошибки сама. Своей поверхности
        /// — ни алерта, ни окна, ни второй модальной — здесь не заводится.
        private static func refusal(_ message: String) -> NSError {
            NSError(
                domain: TerminatorLog.subsystem + ".addapplication",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    /// Добавление приложения: панель выбора, `Bundle(url:)`, правило.
    ///
    /// Панель отфильтрована по типу содержимого `.application`. Это единственный механизм
    /// добавления и он покрывает оба случая — запущенное приложение и незапущенное, — а
    /// список процессов не покрыл бы второй вовсе (findings §10).
    ///
    /// **Метод разделён на два витка рантайма, и это не косметика.** `NSApp.activate()` —
    /// *запрос* активации у оконного сервера, а не смена состояния: сама активация приезжает
    /// более поздним витком (ровно поэтому существует
    /// `NSApplicationDidBecomeActiveNotification`). `runModal()`, вызванный тем же витком,
    /// блокирует его — и панель показывается **до** того, как активация доехала. Гонка: иногда
    /// успевает одно, иногда другое, и один и тот же неизменный код то работает, то нет.
    ///
    /// Поэтому на текущем витке остаются ровно два действия — закрыть поповер и попросить
    /// активацию, — а всё остальное уходит следующим витком.
    func addApplication() {
        notice = nil

        // Окно `MenuBarExtra` — key, пока поповер открыт, и живёт на уровне статус-бара, то
        // есть выше обычного окна панели. Активация приложения этого конкурента не убирает:
        // убирает только закрытие. Надежда «перебить уровнем» здесь не рассматривается —
        // конкурент устраняется совсем.
        dismissPopoverWindow()

        // Приложение `.accessory` (`LSUIElement=true`, findings §7) не активируется ничем в
        // дереве: открытие поповера даёт временное key-окно, но не активацию. Модальная панель
        // неактивного приложения получает окно, которое не является key, и первые клики уходят
        // на активацию окна вместо выбора строки. `NSApp.activate()` — без
        // `ignoringOtherApps:`, устаревшего с macOS 14, а таргет ровно `.macOS(.v14)`.
        //
        // Вызов необходим и ошибкой никогда не был — он был недостаточен в одиночку.
        NSApp.activate()

        // Следующий виток: к моменту показа панели закрытие поповера уже обработано, а запрос
        // активации успел доехать.
        DispatchQueue.main.async {
            self.presentAddApplicationPanel()
        }
    }

    /// Закрытие окна поповера перед показом панели.
    ///
    /// У приложения нет других окон: сцена одна — `MenuBarExtra`, — и пока поповер открыт,
    /// key-окно только он. Отсюда и форма: закрывается ровно текущее key-окно, а не окно,
    /// найденное перебором по признаку.
    ///
    /// `close()`, а не `orderOut(_:)`: закрытие рассылает `willCloseNotification`, по которому
    /// SwiftUI приводит в порядок собственное состояние показа. Окно, убранное `orderOut`,
    /// осталось бы «показанным» с точки зрения сцены, и следующее нажатие на пункт меню-бара
    /// только переключило бы флаг, не открыв поповер.
    ///
    /// Это **единственное** место, где временное окно поповера трогается, и трогается оно
    /// ровно одним способом — закрывается. Ни закрепления, ни перестилизации, ни пересоздания.
    private func dismissPopoverWindow() {
        NSApp.keyWindow?.close()
    }

    /// Вторая половина `addApplication()`: настройка панели, показ, разбор выбора и запись.
    /// Исполняется отдельным витком рантайма — см. доку `addApplication()`.
    private func presentAddApplicationPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add"
        panel.message = "Choose an application to put on a time limit."
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        // Снимок списка отдаётся валидатору перед показом панели, а сам валидатор — сильная
        // ссылка на хранимом свойстве: `panel.delegate` слабая и локальный объект не удержит.
        addPanelValidator.identifiersOnTheList = Set(config.rules.keys)
        panel.delegate = addPanelValidator

        // Инструментирование, а не украшение: «первый клик не выбирает» — дефект, стоивший
        // трёх раундов правок вслепую, и следующее решение принимается по этой строке, а не по
        // четвёртой догадке. Пишется непосредственно перед `runModal()`, то есть уже после
        // закрытия поповера и после витка, которым должна была доехать активация.
        //
        // Три факта и все три нужны порознь. `appActive=false` означает, что активация не
        // доехала (шов 1 не сработал). Оставшееся key-окно на уровне статус-бара
        // (`NSWindow.Level.statusBar.rawValue` = 25) означает, что поповер закрыть не удалось
        // (шов 2 не сработал). `panelLevel` отвечает на отложенный вопрос — хватает ли швов
        // без подъёма уровня самой панели; поднимать его эта карточка запрещает, измерить —
        // нет. Значения снимаются в локальные переменные: интерполяция `Logger` принимает
        // `@autoclosure`, и состояние приложения читается здесь, а не когда-то потом.
        let appIsActive = NSApp.isActive
        let keyWindow = NSApp.keyWindow
        let keyWindowPresence = keyWindow == nil ? "none" : "present"
        let keyWindowLevel = keyWindow.map { String($0.level.rawValue) } ?? "none"
        let panelLevel = panel.level.rawValue
        popoverLog.notice(
            "add-app panel about to run modal: appActive=\(appIsActive, privacy: .public) keyWindow=\(keyWindowPresence, privacy: .public) keyWindowLevel=\(keyWindowLevel, privacy: .public) panelLevel=\(panelLevel, privacy: .public)"
        )

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Оба гарда ниже — запасной путь: при живом валидаторе панель не закрывается и сюда
        // такой выбор не доходит. Сработавший гард означает, что `panel(_:validate:)` не
        // выполнился, то есть делегат умер, — и лог-строка будет единственным свидетельством
        // этого, потому что `notice` пользователь на этом пути не увидит.
        //
        // Идентификатор берётся из бандла, а не из имени файла: сопоставление идёт по точной
        // строке `bundleIdentifier` и ни по чему больше (findings §10).
        guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
            notice = "\(url.lastPathComponent) has no bundle identifier. No rule was created."
            popoverLog.notice("rule not created, bundle has no identifier: path=\(url.path, privacy: .public)")
            return
        }

        guard config.rule(for: bundleIdentifier) == nil else {
            notice = "\(bundleIdentifier) is already on the list."
            popoverLog.notice("rule not created, bundle already on the list: bundle=\(bundleIdentifier, privacy: .public)")
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
