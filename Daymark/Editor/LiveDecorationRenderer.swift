import AppKit

enum LiveDecorationRenderer {
    static func drawCheckbox(in boxRect: CGRect, done: Bool, progress: CGFloat) {
        let side = DesignMetrics.checkboxSize
        let originY = boxRect.midY - side / 2
        let rect = CGRect(x: boxRect.minX, y: originY, width: side, height: side)
        let path = NSBezierPath(roundedRect: rect, xRadius: DesignMetrics.checkboxRadius, yRadius: DesignMetrics.checkboxRadius)

        if done {
            NSColor(DesignTokens.accent).setFill()
            path.fill()
            drawCheck(in: rect, progress: progress)
        } else {
            path.lineWidth = 1
            NSColor(DesignTokens.checkboxBorder).setStroke()
            path.stroke()
        }
    }

    private static func drawCheck(in rect: CGRect, progress: CGFloat) {
        let clamped = max(0, min(1, progress))
        guard clamped > 0 else { return }
        let check = NSBezierPath()
        check.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.52))
        check.line(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.36))
        check.line(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.68))
        check.lineWidth = 1.6
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(clamped).setStroke()
        check.stroke()
    }

    static func drawTagPillBackground(in glyphRect: CGRect) {
        let rect = glyphRect.insetBy(dx: -3, dy: -1)
        let path = NSBezierPath(roundedRect: rect, xRadius: DesignMetrics.pillRadius, yRadius: DesignMetrics.pillRadius)
        NSColor(DesignTokens.accentSoft).setFill()
        path.fill()
    }

    static func drawDuePill(in glyphRect: CGRect, display: String) {
        let font = NSFont.systemFont(ofSize: 13)
        let symbolWidth: CGFloat = 15
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(DesignTokens.textSecondary)
        ]
        let textSize = (display as NSString).size(withAttributes: textAttributes)
        let contentWidth = symbolWidth + textSize.width
        let padH: CGFloat = 4
        let height = max(glyphRect.height, font.ascender - font.descender + 4)
        let pill = CGRect(
            x: glyphRect.minX,
            y: glyphRect.midY - height / 2,
            width: contentWidth + padH * 2,
            height: height
        )
        let path = NSBezierPath(roundedRect: pill, xRadius: DesignMetrics.pillRadius, yRadius: DesignMetrics.pillRadius)
        NSColor(DesignTokens.pillDueFill).setFill()
        path.fill()

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        if let symbol = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) {
            let symbolRect = CGRect(
                x: pill.minX + padH,
                y: pill.midY - symbol.size.height / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
            NSColor(DesignTokens.textSecondary).set()
            symbol.isTemplate = true
            symbol.draw(in: symbolRect)
        }

        let textPoint = CGPoint(
            x: pill.minX + padH + symbolWidth,
            y: pill.midY - textSize.height / 2
        )
        (display as NSString).draw(at: textPoint, withAttributes: textAttributes)
    }
}
