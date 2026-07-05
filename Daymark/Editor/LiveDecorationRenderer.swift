import AppKit

enum LiveDecorationRenderer {
    static func drawCheckbox(in boxRect: CGRect, done: Bool, progress: CGFloat, alpha: CGFloat = 1) {
        guard alpha > 0.01 else { return }
        let side = DesignMetrics.checkboxSize
        let originY = boxRect.midY - side / 2
        let rect = CGRect(x: boxRect.minX, y: originY, width: side, height: side)
        let path = NSBezierPath(roundedRect: rect, xRadius: DesignMetrics.checkboxRadius, yRadius: DesignMetrics.checkboxRadius)

        if done {
            NSColor(DesignTokens.accent).withAlphaComponent(alpha).setFill()
            path.fill()
            drawCheck(in: rect, progress: progress, alpha: alpha)
        } else {
            path.lineWidth = 1
            NSColor(DesignTokens.checkboxBorder).withAlphaComponent(alpha).setStroke()
            path.stroke()
        }
    }

    private static func drawCheck(in rect: CGRect, progress: CGFloat, alpha: CGFloat) {
        let clamped = max(0, min(1, progress))
        guard clamped > 0 else { return }
        let check = NSBezierPath()
        check.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.52))
        check.line(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.36))
        check.line(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.minY + rect.height * 0.68))
        check.lineWidth = 1.6
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(clamped * alpha).setStroke()
        check.stroke()
    }

    static func drawTagPillBackground(in glyphRect: CGRect) {
        let rect = glyphRect.insetBy(dx: -3, dy: -1)
        let path = NSBezierPath(roundedRect: rect, xRadius: DesignMetrics.pillRadius, yRadius: DesignMetrics.pillRadius)
        NSColor(DesignTokens.accentSoft).setFill()
        path.fill()
    }

    /// Draws the due pill over the concealed literal. `fillToWidth`, when set, stretches the pill
    /// fill to the full width of the concealed literal so a mid-line due token leaves no trailing
    /// gap where its raw text used to be; the concealed footprint stays constant, so revealing or
    /// concealing the pill never shifts the rest of the line. At line end the caller passes nil
    /// and the pill stays snug.
    static func drawDuePill(in glyphRect: CGRect, display: String, fillToWidth: CGFloat? = nil, alpha: CGFloat = 1) {
        guard alpha > 0.01 else { return }
        let font = NSFont.systemFont(ofSize: 13)
        let symbolWidth: CGFloat = 15
        let textColor = NSColor(DesignTokens.textSecondary).withAlphaComponent(alpha)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let textSize = (display as NSString).size(withAttributes: textAttributes)
        let contentWidth = symbolWidth + textSize.width
        let padH: CGFloat = 4
        let snugWidth = contentWidth + padH * 2
        let width = max(snugWidth, fillToWidth ?? snugWidth)
        let height = max(glyphRect.height, font.ascender - font.descender + 4)
        let pill = CGRect(
            x: glyphRect.minX,
            y: glyphRect.midY - height / 2,
            width: width,
            height: height
        )
        let path = NSBezierPath(roundedRect: pill, xRadius: DesignMetrics.pillRadius, yRadius: DesignMetrics.pillRadius)
        NSColor(DesignTokens.pillDueFill).withAlphaComponent(alpha).setFill()
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
            textColor.set()
            symbol.isTemplate = true
            symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: alpha)
        }

        let textPoint = CGPoint(
            x: pill.minX + padH + symbolWidth,
            y: pill.midY - textSize.height / 2
        )
        (display as NSString).draw(at: textPoint, withAttributes: textAttributes)
    }
}
