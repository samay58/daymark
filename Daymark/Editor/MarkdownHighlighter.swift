import AppKit

/// Applies calm, source-preserving syntax styling to the editable daily note. It only ever
/// sets display attributes on the text storage; the underlying characters stay plain Markdown,
/// so what is written to disk is always the literal text the user typed.
enum MarkdownHighlighter {
    static let bodySize: CGFloat = 16

    static func baseFont() -> NSFont { .systemFont(ofSize: bodySize) }

    static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 6
        style.paragraphSpacing = 8
        return style
    }

    static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont(),
            .foregroundColor: NSColor(DesignTokens.textPrimary),
            .paragraphStyle: paragraphStyle()
        ]
    }

    static func highlight(_ storage: NSTextStorage) {
        let text = storage.string
        let full = NSRange(location: 0, length: (text as NSString).length)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(), range: full)
        applyLineStyles(storage, text: text, full: full)
        applyInlineStyles(storage, text: text, full: full)
        storage.endEditing()
    }

    // MARK: - Colors

    private static var accent: NSColor { NSColor(DesignTokens.accent) }
    private static var secondary: NSColor { NSColor(DesignTokens.textSecondary) }

    // MARK: - Line-anchored styles

    private static func applyLineStyles(_ storage: NSTextStorage, text: String, full: NSRange) {
        let ns = text as NSString

        // Headings: marker tinted, title weighted and sized by level.
        enumerate(Patterns.heading, in: text, range: full) { match in
            let markerRange = match.range(at: 1)
            let level = ns.substring(with: markerRange).count
            storage.addAttribute(.foregroundColor, value: accent, range: markerRange)
            storage.addAttribute(.font, value: headingFont(level: level), range: match.range)
        }

        // Tasks: prefix tinted; completed items struck through and dimmed.
        enumerate(Patterns.task, in: text, range: full) { match in
            let prefixRange = match.range(at: 1)
            let textRange = match.range(at: 2)
            storage.addAttribute(.foregroundColor, value: accent, range: prefixRange)
            let prefix = ns.substring(with: prefixRange).lowercased()
            if prefix.contains("[x]") {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
                storage.addAttribute(.foregroundColor, value: secondary, range: textRange)
            }
        }

        // Plain bullets (not task checkboxes): tint the marker only.
        enumerate(Patterns.bullet, in: text, range: full) { match in
            storage.addAttribute(.foregroundColor, value: accent, range: match.range(at: 1))
        }

        // Blockquotes: dim and italicize the whole line, tint the marker.
        enumerate(Patterns.quote, in: text, range: full) { match in
            storage.addAttribute(.foregroundColor, value: secondary, range: match.range)
            italicize(storage, range: match.range(at: 2))
            storage.addAttribute(.foregroundColor, value: accent, range: match.range(at: 1))
        }
    }

    // MARK: - Inline styles

    private static func applyInlineStyles(_ storage: NSTextStorage, text: String, full: NSRange) {
        enumerate(Patterns.wikiLink, in: text, range: full) { match in
            storage.addAttribute(.foregroundColor, value: accent, range: match.range)
        }
        enumerate(Patterns.inlineCode, in: text, range: full) { match in
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular), range: match.range)
            storage.addAttribute(.foregroundColor, value: accent, range: match.range)
        }
        enumerate(Patterns.bold, in: text, range: full) { match in
            embolden(storage, range: match.range)
        }
        enumerate(Patterns.italic, in: text, range: full) { match in
            italicize(storage, range: match.range)
        }
    }

    // MARK: - Font helpers

    private static func headingFont(level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1: size = 24
        case 2: size = 19
        case 3: size = 17
        default: size = 16
        }
        return .systemFont(ofSize: size, weight: .semibold)
    }

    private static func embolden(_ storage: NSTextStorage, range: NSRange) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let font = (value as? NSFont) ?? baseFont()
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: sub)
        }
    }

    private static func italicize(_ storage: NSTextStorage, range: NSRange) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, sub, _ in
            let font = (value as? NSFont) ?? baseFont()
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: sub)
        }
    }

    // MARK: - Regex plumbing

    private static func enumerate(
        _ regex: NSRegularExpression,
        in text: String,
        range: NSRange,
        body: (NSTextCheckingResult) -> Void
    ) {
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            if let match { body(match) }
        }
    }

    private enum Patterns {
        static let heading = make("^(#{1,6})[ \\t]+(.+)$", [.anchorsMatchLines])
        static let task = make("^([ \\t]*[-*][ \\t]+\\[[ xX]\\][ \\t]*)(.*)$", [.anchorsMatchLines])
        static let bullet = make("^([ \\t]*[-*][ \\t]+)(?!\\[[ xX]\\]).+$", [.anchorsMatchLines])
        static let quote = make("^([ \\t]*>[ \\t]?)(.*)$", [.anchorsMatchLines])
        static let wikiLink = make("\\[\\[[^\\]\\n]+\\]\\]", [])
        static let inlineCode = make("`[^`\\n]+`", [])
        static let bold = make("\\*\\*[^*\\n]+\\*\\*", [])
        static let italic = make("(?<![\\*_])_[^_\\n]+_(?![\\*_])", [])

        private static func make(_ pattern: String, _ options: NSRegularExpression.Options) -> NSRegularExpression {
            // Patterns are static and known-valid; a failure here is a programmer error.
            try! NSRegularExpression(pattern: pattern, options: options)
        }
    }
}
