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

            Divider()

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

                Text(row.bundleIdentifier)
                    .font(.system(.body, design: .monospaced))
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

            statusLines
        }
        .onAppear { limitText = displayedLimit }
        .onChange(of: row.limitMinutes) { _, _ in limitText = displayedLimit }
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
