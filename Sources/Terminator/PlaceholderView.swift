import AppKit
import SwiftUI
import TerminatorAppKit

/// Плейсхолдер поповера. Настоящий поповер — TASK-006; здесь ровно четыре вещи, и каждая
/// нужна для приёмки TASK-002.
struct PlaceholderView: View {

    /// Состояние глаз глифа в меню-баре, поднятое в `TerminatorApp`.
    ///
    /// Владелец — **TASK-006**: там этот бит выводится из состояния движка, а плейсхолдер
    /// вместе с кнопкой ниже заменяется целиком и уезжает. Существует ради **амендмента 2**
    /// и Review trigger DEC-009: пара образцов ниже отвечает на вопрос «различимы ли версии
    /// рядом», а кнопка — на вопрос «различимы ли они в меню-баре», и ответить на него можно
    /// только оттуда. Это не проводка движка: за биндингом нет ничего, кроме нажатия кнопки.
    @Binding var glyphEyes: MenuBarGlyphEyes

    /// Считается в момент появления вью, а не в `init()` приложения.
    @State private var runtimeFacts: RuntimeFacts?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Terminator")
                .font(.headline)

            // 1. Обе версии глифа рядом, в меню-барном размере. Это НЕ закрывает
            //    Review trigger DEC-009: он спрашивает про различимость на фоне
            //    меню-бара, а здесь фон поповера. Ответ даёт кнопка ниже; эта пара
            //    полезна другим — показывает обе версии одновременно.
            HStack(alignment: .top, spacing: 24) {
                glyphSample("idle", eyes: .idle)
                glyphSample("active", eyes: .active)
            }

            // 2. Ручное переключение глаз глифа **в меню-баре** (амендмент 2).
            //    Владелец состояния — TASK-006: там бит приходит из движка, а этот
            //    плейсхолдер вместе с кнопкой исчезает. Кнопка существует ровно затем,
            //    чтобы закрыть Review trigger DEC-009 — сравнение idle и active делается
            //    на фоне меню-бара, а не на фоне поповера. Ни движка, ни таймера за ней
            //    нет; заголовок называет состояние, В КОТОРОЕ она переключит, а строка
            //    выше — состояние, которое показывает бар прямо сейчас.
            VStack(alignment: .leading, spacing: 6) {
                Text("menu bar glyph: \(glyphEyes.placeholderTitle)")
                    .font(.system(.caption, design: .monospaced))

                Button("Switch to \(glyphEyes.flipped.placeholderTitle)") {
                    glyphEyes = glyphEyes.flipped
                }
            }

            Divider()

            // 3. Единственный канал доказательства для двух acceptance criteria.
            VStack(alignment: .leading, spacing: 4) {
                Text(runtimeFacts?.activationPolicyLine ?? "activationPolicy: —")
                Text(runtimeFacts?.bundleIdentifierLine ?? "bundleIdentifier: —")
            }
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)

            Divider()

            // 4. У LSUIElement-приложения нет ни дока, ни меню: без этой кнопки
            //    единственный способ его остановить — сигнал. Закрытие себя —
            //    штатное действие (DEC-006); запрет DEC-002 касается чужих приложений.
            Button("Quit Terminator") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .onAppear {
            let facts = RuntimeFacts()
            runtimeFacts = facts
            print(facts.stdoutLine)
        }
    }

    private func glyphSample(_ title: String, eyes: MenuBarGlyphEyes) -> some View {
        VStack(spacing: 6) {
            Image(nsImage: menuBarSkullImage(eyes: eyes))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Имя состояния и его переключение нужны только плейсхолдеру: это подписи и кнопка
/// амендмента 2, а не часть глифа. Поэтому они живут здесь и `fileprivate`, а
/// `MenuBarGlyph.swift` о них не знает — рисующая функция уже принимает состояние
/// параметром, ровно поэтому амендмент маленький. В TASK-006 уезжает вместе с
/// плейсхолдером.
extension MenuBarGlyphEyes {

    fileprivate var placeholderTitle: String {
        switch self {
        case .idle: "idle"
        case .active: "active"
        }
    }

    fileprivate var flipped: MenuBarGlyphEyes {
        switch self {
        case .idle: .active
        case .active: .idle
        }
    }
}

/// Два факта об окружении, которые невозможно получить иначе как из запущенного бандла:
/// голый SwiftPM-исполняемый файл даёт `.prohibited` и `bundleIdentifier == nil`
/// (findings §7).
private struct RuntimeFacts {

    let activationPolicyLine: String
    let bundleIdentifierLine: String

    init() {
        let policy = NSApplication.shared.activationPolicy()
        activationPolicyLine = "activationPolicy: \(policy) (rawValue \(policy.rawValue))"
        bundleIdentifierLine = "bundleIdentifier: \(Bundle.main.bundleIdentifier ?? "nil")"
    }

    /// Одна строка в stdout — её человек вставляет в отчёт.
    var stdoutLine: String {
        "TASK-002 \(activationPolicyLine) \(bundleIdentifierLine)"
    }
}
