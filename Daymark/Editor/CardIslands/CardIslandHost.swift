import AppKit
import SwiftUI

final class CardIslandHost: NSView {
    let regionHash: String
    var onHeightChange: ((CGFloat) -> Void)?

    private let hosting: NSHostingView<AnyView>
    private let widthConstraint: NSLayoutConstraint
    private var lastReportedHeight: CGFloat = 0

    init(regionHash: String, rootView: AnyView, width: CGFloat) {
        self.regionHash = regionHash
        self.hosting = NSHostingView(rootView: rootView)
        self.widthConstraint = hosting.widthAnchor.constraint(equalToConstant: max(1, width))
        super.init(frame: .zero)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            widthConstraint
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("CardIslandHost does not support coding")
    }

    func update(rootView: AnyView, width: CGFloat) {
        hosting.rootView = rootView
        setWidth(width)
    }

    func setWidth(_ width: CGFloat) {
        let clamped = max(1, width)
        guard widthConstraint.constant != clamped else { return }
        widthConstraint.constant = clamped
    }

    var measuredHeight: CGFloat {
        hosting.fittingSize.height
    }

    override func layout() {
        super.layout()
        let height = measuredHeight
        guard abs(height - lastReportedHeight) > 0.5 else { return }
        lastReportedHeight = height
        onHeightChange?(height)
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}
