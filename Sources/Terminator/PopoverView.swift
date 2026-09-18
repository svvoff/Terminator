import AppKit
import SwiftUI

import TerminatorCore

/// Поповер — **единственная поверхность продукта, обращённая к пользователю**. Отдельного
/// окна настроек нет: сцена `Settings` выброшена из скоупа, потому что `openSettings` на
/// macOS 26 не делает ничего.
///
/// Числа во вью не считаются: всё, что видно, приходит из `PopoverViewModel` в ядре, которому
/// момент времени подаёт `TimelineView`. Собственного `Timer` здесь нет, и остаток не
/// уменьшается счётчиком — он пересчитывается от абсолютного дедлайна на каждый рендер
/// (findings §9).
struct PopoverView: View {

    let model: PopoverModel

    var body: some View {
        // Секундная каденция и ничего больше: `context.date` — это `now`, который уезжает
        // параметром во вью-модель. Ассертов активности не берётся.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(model.state(at: context.date))
        }
        .frame(width: 340, alignment: .leading)
        // Перечитывание файла при открытии: без него порча конфига на живом приложении
        // осталась бы незамеченной, а следующая правка затёрла бы ручное редактирование.
        .onAppear { model.popoverDidOpen() }
    }

    private func content(_ state: PopoverViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let banner = state.banner {
                QuarantineBanner(banner: banner)
            }

            if state.isEmpty {
                // Пустое состояние: одна строка о том, что делает Terminator, — и больше
                // ничего. Ни подсказок, ни онбординга, ни карточки разрешений.
                Text("Terminator asks the apps on this list to quit when their time is up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(state.rows, id: \.bundleIdentifier) { row in
                        RuleRowView(row: row, model: model)
                    }
                }
            }

            if let notice = model.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Вне ветки `state.isEmpty`: история фокуса переживает удаление правил, и секция
            // видна в обоих состояниях списка. В состоянии hidden она не рисует ничего.
            FocusFold(model: model)

            Divider()

            LaunchAtLoginRow(model: model)

            HStack {
                Button("Add App…") { model.addApplication() }
                Spacer()
                // У LSUIElement-приложения нет ни дока, ни меню приложения: без этой кнопки
                // остановить продукт можно только сигналом. Закрыть Terminator — штатное
                // действие, которому не сопротивляются (DEC-006); запрет DEC-002 касается
                // чужих приложений.
                Button("Quit Terminator") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
    }
}

/// Строка автозапуска: подпись, тумблер и текущий статус текстом. Текст присутствует во всех
/// состояниях, а не только в проблемных.
///
/// Тумблер отвечает на вопрос «зарегистрировали ли мы себя», текст — на вопрос «что об этом
/// думает система». Расходятся эти два ответа ровно в одном состоянии: пользователь выключил
/// пункт в System Settings. Продукт это показывает и на этом останавливается — обход выбора
/// пользователя запрещает DEC-006, и включить обратно можно там же, где выключили.
///
/// Статус здесь не читается: он приходит из модели, которая зовёт `status()` ровно дважды —
/// при открытии поповера и после переключения. Чтение в `body` или в вычисляемом свойстве
/// залило бы лог сотнями строк: содержимое перерисовывается раз в секунду (findings §14).
private struct LaunchAtLoginRow: View {

    let model: PopoverModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { model.launchAtLoginIsOn },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            // Пока статус не прочитан и в неизвестном состоянии контрол неинтерактивен.
            .disabled(!model.launchAtLoginIsInteractive)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusText: String {
        guard let status = model.loginItemStatus else { return "status not read yet" }

        // Наступает ли `enabled` сразу после записи файла или только после следующего входа —
        // измерено (findings §12): до входа, но не мгновенно, через переходный `3`. Оба
        // прочтения обязаны рендериться нормальным состоянием: это не отказ и не ошибка.
        // Флаг ниже ставится только там, где регистрация действительно может вступить сама,
        // — из `disabledByUser` он не ставится никогда (`registrationCanTakeEffect`).
        if model.loginItemRegistrationPending {
            return "registered — takes effect at the next login"
        }

        switch status {
        case .enabled:
            return "on"
        case .notRegistered:
            return "off"
        case .disabledByUser:
            return "turned off in System Settings › General › Login Items — turn it back on there"
        case .unknown(let rawValue):
            // Сырое число показывается как есть: придумывать ему измеренный смысл нельзя.
            return "unknown state (system status \(rawValue))"
        }
    }
}

/// Строка списка — **одно правило**. Экземпляров у него может не быть ни одного, а может быть
/// несколько, и каждый показывает свой остаток: схлопывать дедлайны в одно неподписанное
/// число нельзя (findings §10).
private struct RuleRowView: View {

    let row: PopoverRow
    let model: PopoverModel

    /// Набранный текст лимита. Живёт во вью, потому что редактируется посимвольно; правкой
    /// он становится только на commit, и только пройдя валидатор ядра.
    @State private var limitText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { row.isEnabled },
                        // Ни подтверждения, ни трения: выключить правило — законное
                        // «дай мне ещё N минут» (DEC-006).
                        set: { model.setEnabled($0, for: row.bundleIdentifier) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)

                primaryLabel
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(row.bundleIdentifier)

                Spacer(minLength: 4)

                TextField("", text: $limitText)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .onSubmit(commitLimit)

                Text("min")
                    .foregroundStyle(.secondary)

                Button {
                    // Подтверждения на удаление нет (DEC-006).
                    model.removeRule(row.bundleIdentifier)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove this rule")
            }

            identifierLine

            statusLines
        }
        .onAppear { limitText = displayedLimit }
        .onChange(of: row.limitMinutes) { _, _ in limitText = displayedLimit }
    }

    /// Имя приложения на текущее открытие поповера. Резолв сделан один раз в
    /// `popoverDidOpen()`; здесь — только чтение словаря, потому что тело вью выполняется
    /// раз в секунду.
    private var displayName: String? {
        model.displayName(for: row.bundleIdentifier)
    }

    /// Первая строка правила: имя приложения, если оно резолвится, иначе идентификатор.
    ///
    /// Имя идёт обычным body-шрифтом: моноширинный нужен идентификатору, у которого значим
    /// каждый символ, а не имени. Подсказка `.help(...)` с полным идентификатором висит на
    /// этой строке в обоих случаях — она навешана на месте вызова.
    @ViewBuilder
    private var primaryLabel: some View {
        if let displayName {
            Text(displayName)
        } else {
            // Приложение не установлено, имени нет. Строка выглядит ровно так, как выглядела
            // до появления имён.
            Text(row.bundleIdentifier)
                .font(.system(.body, design: .monospaced))
        }
    }

    /// Идентификатор под именем. Отдельной строкой, а не припиской к статусу: приписка
    /// читается в ветке без экземпляров и разваливается во второй, где статусных строк
    /// столько же, сколько запущенных экземпляров.
    ///
    /// Идентификатор остаётся на виду намеренно: это точный ключ сопоставления (findings §10),
    /// он же лежит в `config.json`, который автор правит руками, и он же печатается в каждой
    /// строке лога. Когда имя не резолвится, идентификатор уже стоит первой строкой — и здесь
    /// не повторяется.
    @ViewBuilder
    private var identifierLine: some View {
        if displayName != nil {
            Text(row.bundleIdentifier)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                // Длинный идентификатор переносится, а не усекается: усечение по середине на
                // первой строке — ровно тот дефект, из-за которого имя и появилось.
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 30)
        }
    }

    private var displayedLimit: String {
        row.limitMinutes.map(String.init) ?? ""
    }

    private func commitLimit() {
        if !model.setLimit(fromMinutesText: limitText, for: row.bundleIdentifier) {
            limitText = displayedLimit
        }
    }

    @ViewBuilder
    private var statusLines: some View {
        if row.instances.isEmpty {
            Text(row.isEnabled ? "not running" : "off")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 30)
        } else {
            ForEach(row.instances, id: \.key) { instance in
                HStack(spacing: 6) {
                    Text(instance.remainingText)
                        .font(.caption)
                        .monospacedDigit()
                    Text(statusText(instance))
                        .font(.caption)
                        .foregroundStyle(instance.isRefused ? .red : .secondary)
                    if row.instances.count > 1 {
                        // Несколько экземпляров одного bundle id — нормальное состояние,
                        // и каждый остаток обязан быть подписан, чей он.
                        Text("· pid \(instance.pid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 30)
            }
        }
    }

    /// Терминальный отказ обязан быть отличим от идущего отсчёта. Числовое значение
    /// `OSStatus` здесь не показывается и ни во что не отображается — ветвление идёт по
    /// случаю, который уже пришёл из ядра.
    private func statusText(_ instance: PopoverInstance) -> String {
        switch instance.status {
        case .counting:
            "left"
        case .quitting(let attempts):
            attempts == 1 ? "asked to quit" : "asked to quit, \(attempts) times"
        case .refused(.attemptsExhausted):
            "will not quit — it ignored every request"
        case .refused(.systemRefused):
            "will not quit — the system refused"
        }
    }
}

extension PopoverInstance {

    fileprivate var isRefused: Bool {
        if case .refused = status { return true }
        return false
    }
}

/// Секция «Focus»: сколько каждое наблюдаемое приложение было фронтмост в каждый из семи
/// дней. Ambient status, как отсчёт, — ни уведомлений, ни бейджей (DEC-004). Числа — нижняя
/// граница, а не мера (DEC-005), поэтому подписи говорят, что значит каждое, и не оценивают.
///
/// **Здесь ничего не строится.** Секция приходит готовой из модели, которая строит её ровно в
/// двух точках — на открытии поповера и на раскрытии. Это тело выполняется изнутри
/// `TimelineView` раз в секунду, и сводка, построенная здесь, пересортировывала бы строки под
/// курсором. Вью читает только `focusSection`, `isFocusExpanded` и `displayName(for:)`.
///
/// Строк столько, сколько в сводке, — все и в данном порядке: без прокрутки и без потолка.
/// Как это выглядит в 340 pt, решает ручной чеклист, а не догадка.
private struct FocusFold: View {

    let model: PopoverModel

    var body: some View {
        switch model.focusSection {
        case .hidden:
            // Ни заголовка, ни разделителя, ни заглушки.
            EmptyView()

        case .unreadable:
            DisclosureGroup(isExpanded: expansion) {
                Text("The focus file could not be read when Terminator started. It was left untouched. Fix it by hand, then relaunch Terminator.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                // Без знаменателя: в карантине история не прочитана, и «N of 7» был бы выдумкой.
                Text("Focus")
            }

        case .summary(let summary):
            DisclosureGroup(isExpanded: expansion) {
                VStack(alignment: .leading, spacing: 6) {
                    grid(summary)
                    Text("Minutes frontmost per day. Totals are exact.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("— means nothing was recorded that day: Terminator wasn't running, or no watched app was frontmost. It can't tell which.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Focus")
                    Text(summary.recordedDaysText)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Раскрытие живёт в модели: вью создаётся заново на каждом открытии поповера, а модель —
    /// нет. Сеттер модели сам решает, строить ли секцию заново.
    private var expansion: Binding<Bool> {
        Binding(
            get: { model.isFocusExpanded },
            set: { model.setFocusExpanded($0) }
        )
    }

    /// Сетка: имя, семь дней от старшего к сегодняшнему, итог. Числа — готовые строки
    /// форматтеров ядра; здесь они только расставляются.
    private func grid(_ summary: FocusSummary) -> some View {
        Grid(alignment: .trailing, horizontalSpacing: 6, verticalSpacing: 3) {
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                    .gridColumnAlignment(.leading)
                // День месяца из ключа — ни названий дней недели, ни форматтера дат.
                ForEach(summary.days, id: \.self) { day in
                    Text(String(day.day))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Text("total")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }

            ForEach(summary.rows, id: \.bundleIdentifier) { row in
                GridRow {
                    nameCell(row.bundleIdentifier)
                    ForEach(row.perDay.indices, id: \.self) { index in
                        Text(FocusSummary.cellText(row.perDay[index]))
                            .fixedSize()
                    }
                    Text(FocusSummary.totalText(row.total))
                        .fixedSize()
                }
            }
        }
        .font(.caption)
        .monospacedDigit()
    }

    /// Имя приложения, если оно отрезолвилось, иначе идентификатор моноширинным. Числа
    /// усекаться не должны, поэтому уступает место именно эта колонка — усечением посередине.
    /// Подсказка с полным идентификатором висит в обоих случаях.
    private func nameCell(_ bundleIdentifier: String) -> some View {
        Group {
            if let name = model.displayName(for: bundleIdentifier) {
                Text(name)
            } else {
                Text(bundleIdentifier)
                    .font(.system(.caption, design: .monospaced))
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .help(bundleIdentifier)
    }
}

/// Баннер карантина: правки не сохраняются, и это единственное место, где такое видно —
/// канала уведомлений у продукта нет (DEC-004). Файл при этом не чинится и не переписывается.
private struct QuarantineBanner: View {

    let banner: PopoverBanner

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(banner.title)
                .font(.callout.weight(.semibold))
            Text(banner.detail)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.orange)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .textSelection(.enabled)
    }
}
