import AppKit

final class CardLayoutFragment: NSTextLayoutFragment {
    /// Height of the strip chrome shown above the region's first line while revealed. Shared
    /// with `CardIslandController`, which positions the strip host in this same top slice.
    static let stripHeight: CGFloat = 28

    let regionHash: String
    let isFirstLine: Bool
    weak var controller: CardIslandController?

    init(
        textElement: NSTextElement,
        range: NSTextRange?,
        regionHash: String,
        isFirstLine: Bool,
        controller: CardIslandController
    ) {
        self.regionHash = regionHash
        self.isFirstLine = isFirstLine
        self.controller = controller
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) {
        fatalError("CardLayoutFragment does not support coding")
    }

    private func snapshot() -> (revealed: Bool, cardHeight: CGFloat)? {
        guard let controller else { return nil }
        return MainActor.assumeIsolated {
            (controller.isRevealed(regionHash), controller.cardHeight(for: regionHash))
        }
    }

    override var layoutFragmentFrame: CGRect {
        let base = super.layoutFragmentFrame
        guard let snapshot = snapshot() else { return base }
        if snapshot.revealed {
            guard isFirstLine else { return base }
            return CGRect(x: base.minX, y: base.minY, width: base.width, height: base.height + Self.stripHeight)
        }
        if isFirstLine {
            return CGRect(x: base.minX, y: base.minY, width: base.width, height: snapshot.cardHeight)
        }
        return CGRect(x: base.minX, y: base.minY, width: base.width, height: 0)
    }

    override var renderingSurfaceBounds: CGRect {
        guard let snapshot = snapshot() else { return super.renderingSurfaceBounds }
        if snapshot.revealed {
            guard isFirstLine else { return super.renderingSurfaceBounds }
            return super.renderingSurfaceBounds.offsetBy(dx: 0, dy: Self.stripHeight)
        }
        return .zero
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        guard let snapshot = snapshot() else {
            super.draw(at: point, in: context)
            return
        }
        guard snapshot.revealed else { return }
        if isFirstLine {
            super.draw(at: CGPoint(x: point.x, y: point.y + Self.stripHeight), in: context)
        } else {
            super.draw(at: point, in: context)
        }
    }
}
