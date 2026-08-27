import AppKit

/// Состояние глаз черепа. Живое переключение — TASK-006; TASK-002 рисует обе версии.
public nonisolated enum MenuBarGlyphEyes: Sendable {

    /// Глаза потушены: кость и глаза идут за темой меню-бара.
    case idle

    /// Глаза горят: идёт обратный отсчёт.
    case active
}

/// Череп для меню-бара, концепт B «Minimal Mask» (DEC-009).
///
/// Геометрия — порт `docs/product/design/menu-bar-icon-idle.svg` и `-active.svg`,
/// у которых `viewBox="0 0 18 18"`. Образ создаётся 18×18 с `flipped: true`, поэтому
/// координаты SVG (y вниз) переносятся один в один, без пересчёта.
///
/// `isTemplate = false` — обязательно: `isTemplate = true` уничтожает цвет целиком,
/// 0 красных пикселей в обеих темах, и компилятор об этом молчит (findings §8).
/// `NSStatusBarButton` non-template образ никогда не тонирует и не инвертирует, так что
/// адаптация к светлой и тёмной теме — целиком работа хендлера отрисовки.
///
/// Хендлер `NSImage(size:flipped:drawingHandler:)` **перевыполняется в момент отрисовки**.
/// В этом весь механизм: `NSColor.labelColor` перерезолвится под текущую тему, а
/// `NSColor.systemRed` — нет. Поэтому ни один `NSColor` не резолвится и не кэшируется
/// снаружи хендлера (findings §8).
public func menuBarSkullImage(eyes: MenuBarGlyphEyes) -> NSImage {
    let image = NSImage(
        size: NSSize(width: Glyph.side, height: Glyph.side),
        flipped: true
    ) { @Sendable rect in
        drawSkullGlyph(eyes: eyes, in: rect)
        return true
    }
    image.isTemplate = false
    image.accessibilityDescription = eyes.accessibilityDescription
    return image
}

extension MenuBarGlyphEyes {

    fileprivate var accessibilityDescription: String {
        switch self {
        case .idle: "Terminator, no countdown running"
        case .active: "Terminator, countdown running"
        }
    }
}

// MARK: - Отрисовка

/// Всё, что вызывается из хендлера, — `nonisolated`: хендлер `@Sendable` и не имеет права
/// трогать MainActor-состояние. Единственное, что он захватывает, — переданный флаг глаз.
private nonisolated enum Glyph {

    /// Сторона эталонного viewBox. Она же размер образа в меню-баре.
    static let side: CGFloat = 18

    /// Ось зеркала: правая глазница — отражение левой относительно середины.
    static func mirrored(_ x: CGFloat) -> CGFloat { side - x }
}

private nonisolated func drawSkullGlyph(eyes: MenuBarGlyphEyes, in rect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    defer { context.restoreGState() }

    // Приводим 18-единичную систему SVG к фактическому прямоугольнику отрисовки.
    context.translateBy(x: rect.minX, y: rect.minY)
    context.scaleBy(x: rect.width / Glyph.side, y: rect.height / Glyph.side)

    // Цвета берутся ЗДЕСЬ, внутри хендлера, и нигде больше: вынесенный наружу
    // labelColor замёрз бы на теме, которая была в момент создания образа.
    fill(skullPath(), with: NSColor.labelColor, alpha: 1)

    let eyeColor: NSColor
    let glowAlpha: CGFloat
    let pupilAlpha: CGFloat
    switch eyes {
    case .idle:
        eyeColor = NSColor.labelColor
        glowAlpha = 0.10
        pupilAlpha = 0.32
    case .active:
        eyeColor = NSColor.systemRed
        glowAlpha = 0.38
        pupilAlpha = 1.0
    }

    // Глаза ложатся в настоящие дыры черепа, поэтому одинаково читаются на светлом
    // и на тёмном меню-баре.
    for isMirrored in [false, true] {
        fill(socketPath(mirrored: isMirrored), with: eyeColor, alpha: glowAlpha)
        fill(pupilPath(mirrored: isMirrored), with: eyeColor, alpha: pupilAlpha)
    }
}

private nonisolated func fill(_ path: NSBezierPath, with color: NSColor, alpha: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    // Прозрачность ставится на контекст, а не через withAlphaComponent: динамический
    // цвет остаётся динамическим и резолвится на .setFill() под текущую тему.
    NSGraphicsContext.current?.cgContext.setAlpha(alpha)
    color.setFill()
    path.fill()
}

// MARK: - Геометрия

/// Череп одним путём с `windingRule = .evenOdd`, чтобы глазницы и прорези челюсти были
/// настоящими дырами, а не залитыми фигурами поверх кости (DEC-009).
private nonisolated func skullPath() -> NSBezierPath {
    let path = NSBezierPath()

    // Внешний контур, по часовой в координатах SVG (y вниз).
    path.move(to: NSPoint(x: 1.2, y: 3.8))
    // Верхний левый скруглённый угол, r = 2.6, затем машинный плоский верх.
    path.appendArc(from: NSPoint(x: 1.2, y: 1.2), to: NSPoint(x: 14.2, y: 1.2), radius: 2.6)
    // Верхний правый скруглённый угол, r = 2.6.
    path.appendArc(from: NSPoint(x: 16.8, y: 1.2), to: NSPoint(x: 16.8, y: 9.2), radius: 2.6)
    path.line(to: NSPoint(x: 16.8, y: 9.2))
    // Правая скула: фаска вниз-внутрь.
    path.line(to: NSPoint(x: 14.3, y: 12))
    // Правый нижний угол челюсти, r = 1.2, затем плоское дно.
    path.appendArc(from: NSPoint(x: 14.3, y: 16.8), to: NSPoint(x: 4.9, y: 16.8), radius: 1.2)
    // Левый нижний угол челюсти, r = 1.2.
    path.appendArc(from: NSPoint(x: 3.7, y: 16.8), to: NSPoint(x: 3.7, y: 12), radius: 1.2)
    path.line(to: NSPoint(x: 3.7, y: 12))
    // Левая скула.
    path.line(to: NSPoint(x: 1.2, y: 9.2))
    path.close()

    // Дыры: две кантованные глазницы и трёхщелевая решётка челюсти.
    path.append(socketPath(mirrored: false))
    path.append(socketPath(mirrored: true))
    for x in [5.3, 8.1, 10.9] as [CGFloat] {
        path.appendRect(NSRect(x: x, y: 12.6, width: 1.8, height: 2.3))
    }

    path.windingRule = .evenOdd
    return path
}

/// Глазница: она же дыра в черепе, она же слой свечения глаза.
private nonisolated func socketPath(mirrored: Bool) -> NSBezierPath {
    quadrilateral(
        [NSPoint(x: 3.3, y: 5.2), NSPoint(x: 8, y: 6.5), NSPoint(x: 8, y: 8.9), NSPoint(x: 3.3, y: 8.9)],
        mirrored: mirrored
    )
}

/// Зрачок: меньший четырёхугольник внутри глазницы.
private nonisolated func pupilPath(mirrored: Bool) -> NSBezierPath {
    quadrilateral(
        [NSPoint(x: 4, y: 6.2), NSPoint(x: 7.3, y: 7.1), NSPoint(x: 7.3, y: 8.2), NSPoint(x: 4, y: 8.2)],
        mirrored: mirrored
    )
}

private nonisolated func quadrilateral(_ points: [NSPoint], mirrored: Bool) -> NSBezierPath {
    let path = NSBezierPath()
    for (index, point) in points.enumerated() {
        let placed = NSPoint(x: mirrored ? Glyph.mirrored(point.x) : point.x, y: point.y)
        if index == 0 {
            path.move(to: placed)
        } else {
            path.line(to: placed)
        }
    }
    path.close()
    return path
}
