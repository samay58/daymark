import AppKit
import SwiftUI
import DaymarkCore

@MainActor
final class CardIslandController: NSObject, @preconcurrency NSTextLayoutManagerDelegate {
    var contentProvider: CardIslandContentProvider = { _ in AnyView(EmptyView()) }

    private weak var textView: LiveTextView?
    private weak var layoutManager: NSTextLayoutManager?
    private weak var renderController: LiveRenderController?

    /// Reveal is two-way: caret-driven (cleared the instant the caret leaves) and
    /// user-driven (the card's view-source toggle, cleared only by the user). A region is
    /// revealed while either is set; `isRevealed` below is always the union of the two.
    private var caretRevealedHashes: Set<String> = []
    private var userRevealedHashes: Set<String> = []
    private var cardHeights: [String: CGFloat] = [:]
    private var hosts: [String: CardIslandHost] = [:]
    private var scrollObserver: NSObjectProtocol?
    private var isReconciling = false

    private let defaultHeight: CGFloat = 64
    private let viewportCushion: CGFloat = 400

    func attach(textView: LiveTextView, layoutManager: NSTextLayoutManager, renderController: LiveRenderController) {
        self.textView = textView
        self.layoutManager = layoutManager
        self.renderController = renderController
        layoutManager.delegate = self
        textView.cardController = self
        renderController.cardController = self
    }

    deinit {
        if let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
    }

    // MARK: - Fragment reveal state

    func isRevealed(_ hash: String) -> Bool {
        caretRevealedHashes.contains(hash) || userRevealedHashes.contains(hash)
    }

    func cardHeight(for hash: String) -> CGFloat {
        cardHeights[hash] ?? defaultHeight
    }

    // MARK: - Delegate

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let range = textElement.elementRange
        guard let contentManager = textLayoutManager.textContentManager else {
            return NSTextLayoutFragment(textElement: textElement, range: range)
        }
        let offset = contentManager.offset(from: contentManager.documentRange.location, to: location)
        for region in currentRegions {
            let start = region.range.location
            let end = region.range.location + region.range.length
            guard offset >= start, offset < end else { continue }
            return CardLayoutFragment(
                textElement: textElement,
                range: range,
                regionHash: region.hash,
                isFirstLine: offset == start,
                controller: self
            )
        }
        return NSTextLayoutFragment(textElement: textElement, range: range)
    }

    // MARK: - Region and selection changes

    func regionsDidChange() {
        let live = Set(currentRegions.map(\.hash))
        for hash in Array(hosts.keys) where !live.contains(hash) { removeHost(hash) }
        caretRevealedHashes.formIntersection(live)
        userRevealedHashes.formIntersection(live)
        for hash in Array(cardHeights.keys) where !live.contains(hash) { cardHeights[hash] = nil }
        repositionCards()
    }

    func selectionDidChange() {
        guard let textView else { return }
        let regions = currentRegions
        let selection = textView.selectedRange()
        let docLength = (textView.string as NSString).length
        var nextCaret: Set<String> = []
        for region in regions where isRevealing(region.range, selection: selection, docLength: docLength) {
            nextCaret.insert(region.hash)
        }
        guard nextCaret != caretRevealedHashes else { return }

        let before = caretRevealedHashes.union(userRevealedHashes)
        caretRevealedHashes = nextCaret
        let after = caretRevealedHashes.union(userRevealedHashes)
        let changed = before.symmetricDifference(after)
        guard !changed.isEmpty else { return }

        for region in regions where changed.contains(region.hash) {
            invalidateRegionLayout(region.range)
            refreshHostContent(region.hash)
        }
        textView.needsLayout = true
        // A reveal flip changes the region's fragment heights. Invalidating layout alone can
        // leave stale source glyphs over the reflowed text below, so repaint the full surface.
        textView.needsDisplay = true
        repositionCards()
    }

    // MARK: - Viewport positioning

    func repositionCards() {
        guard !isReconciling, let textView, let layoutManager else { return }
        installScrollObserverIfNeeded()
        isReconciling = true
        let started = CFAbsoluteTimeGetCurrent()
        defer {
            isReconciling = false
            logReposition(CFAbsoluteTimeGetCurrent() - started)
        }

        let origin = textView.textContainerOrigin
        let padding = textView.textContainer?.lineFragmentPadding ?? 0
        let visible = textView.visibleRect
        let start = topEnumerationStart(layoutManager: layoutManager, origin: origin, visible: visible)

        var wanted: Set<String> = []
        var heightChanged = false

        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY + origin.y > visible.maxY + self.viewportCushion { return false }
            guard let card = fragment as? CardLayoutFragment, card.isFirstLine else { return true }
            if self.isRevealed(card.regionHash) {
                self.positionStrip(card: card, fragmentFrame: frame, origin: origin, padding: padding, wanted: &wanted)
            } else {
                self.position(card: card, fragmentFrame: frame, origin: origin, padding: padding, wanted: &wanted, heightChanged: &heightChanged)
            }
            return true
        }

        for hash in Array(hosts.keys) where !wanted.contains(hash) { removeHost(hash) }

        if heightChanged {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for hash in self.hosts.keys { self.invalidateRegionLayout(self.regionRange(for: hash)) }
                self.textView?.needsLayout = true
                // A card height change reflows the note below it; repaint to clear the
                // pre-reflow text.
                self.textView?.needsDisplay = true
                self.repositionCards()
            }
        }
    }

    /// Resolves a layout location roughly `viewportCushion` points above the visible rect's
    /// top edge, clamped to the document start, so a tall card whose lower rows are still
    /// visible does not lose its host on the way in (mirrors the existing bottom overscan).
    private func topEnumerationStart(layoutManager: NSTextLayoutManager, origin: CGPoint, visible: CGRect) -> NSTextLocation {
        let fallback = layoutManager.textViewportLayoutController.viewportRange?.location
            ?? layoutManager.documentRange.location
        let cushionedY = max(0, visible.minY - origin.y - viewportCushion)
        let probePoint = CGPoint(x: 0, y: cushionedY)
        guard let fragment = layoutManager.textLayoutFragment(for: probePoint) else {
            return fallback
        }
        return fragment.rangeInElement.location
    }

    private func position(
        card: CardLayoutFragment,
        fragmentFrame: CGRect,
        origin: CGPoint,
        padding: CGFloat,
        wanted: inout Set<String>,
        heightChanged: inout Bool
    ) {
        let width = max(40, fragmentFrame.width - padding * 2)
        let x = fragmentFrame.minX + origin.x + padding
        let y = fragmentFrame.minY + origin.y
        wanted.insert(card.regionHash)

        let host = ensureHost(regionHash: card.regionHash, width: width)
        host.setWidth(width)
        let stored = cardHeights[card.regionHash] ?? defaultHeight
        let measured = host.measuredHeight
        let height = measured > 1 ? measured : stored
        host.frame = CGRect(x: x, y: y, width: width, height: height)
        if abs(height - stored) > 0.5 {
            cardHeights[card.regionHash] = height
            heightChanged = true
        }
    }

    /// Positions the strip-chrome host in the extra top slice `CardLayoutFragment` reserves
    /// on the region's first line while revealed. The full card height in `cardHeights` is
    /// left untouched here so re-collapsing restores the same card size.
    private func positionStrip(
        card: CardLayoutFragment,
        fragmentFrame: CGRect,
        origin: CGPoint,
        padding: CGFloat,
        wanted: inout Set<String>
    ) {
        let width = max(40, fragmentFrame.width - padding * 2)
        let x = fragmentFrame.minX + origin.x + padding
        let y = fragmentFrame.minY + origin.y
        wanted.insert(card.regionHash)

        let host = ensureHost(regionHash: card.regionHash, width: width)
        host.setWidth(width)
        host.frame = CGRect(x: x, y: y, width: width, height: CardLayoutFragment.stripHeight)
    }

    // MARK: - Host lifecycle

    private func ensureHost(regionHash: String, width: CGFloat) -> CardIslandHost {
        if let host = hosts[regionHash] { return host }
        let root = contentProvider(context(for: regionHash))
        let host = CardIslandHost(regionHash: regionHash, rootView: root, width: width)
        host.onHeightChange = { [weak self] height in
            guard let self else { return }
            // While revealed the host is a fixed-height strip; its measured height must never
            // overwrite the stored full-card height used once the region collapses again.
            guard !self.isRevealed(regionHash) else { return }
            let previous = self.cardHeights[regionHash] ?? self.defaultHeight
            guard abs(height - previous) > 0.5 else { return }
            self.cardHeights[regionHash] = height
            self.invalidateRegionLayout(self.regionRange(for: regionHash))
            self.textView?.needsLayout = true
            DispatchQueue.main.async { [weak self] in self?.repositionCards() }
        }
        textView?.addSubview(host)
        hosts[regionHash] = host
        #if DEBUG
        NSLog("[Daymark] card island host created: %@", regionHash)
        #endif
        return host
    }

    private func removeHost(_ hash: String) {
        hosts[hash]?.removeFromSuperview()
        hosts[hash] = nil
    }

    /// Re-renders an existing host's content with fresh `CardIslandContext` (in particular a
    /// changed `isRevealed`), preserving its current width. Called on reveal transitions;
    /// `repositionCards` only creates or repositions hosts, it does not refresh their content.
    private func refreshHostContent(_ hash: String) {
        guard let host = hosts[hash] else { return }
        let width = host.frame.width > 0 ? host.frame.width : 1
        host.update(rootView: contentProvider(context(for: hash)), width: width)
    }

    private func context(for hash: String) -> CardIslandContext {
        let region = currentRegions.first { $0.hash == hash }
        let ns = textView?.string as NSString?
        let inner = region.flatMap { substring(ns, $0.innerRange) } ?? ""
        let commandLine = region?.commandLineRange.flatMap { substring(ns, $0) }
        let fallback = region ?? NoteTokens.GeneratedRegion(
            hash: hash,
            range: NSRange(location: 0, length: 0),
            innerRange: NSRange(location: 0, length: 0),
            commandLineRange: nil
        )
        return CardIslandContext(
            region: fallback,
            command: CardIslandCommand.parse(commandLine),
            innerText: inner,
            isRevealed: isRevealed(hash),
            setSourceRevealed: { [weak self] revealed in self?.setSourceRevealed(hash, revealed: revealed) },
            notifyHeightChanged: { [weak self] in
                DispatchQueue.main.async { self?.repositionCards() }
            }
        )
    }

    // MARK: - Helpers

    private var currentRegions: [NoteTokens.GeneratedRegion] {
        renderController?.cachedTokens.regions ?? []
    }

    private func regionRange(for hash: String) -> NSRange {
        currentRegions.first { $0.hash == hash }?.range ?? NSRange(location: 0, length: 0)
    }

    /// Sets the user-driven half of reveal state. If the caret is still inside the region,
    /// the composite reveal state does not change (the caret keeps it open); the layout and
    /// host content only need to refresh when the composite value actually flips.
    private func setSourceRevealed(_ hash: String, revealed: Bool) {
        let before = isRevealed(hash)
        if revealed { userRevealedHashes.insert(hash) } else { userRevealedHashes.remove(hash) }
        let after = isRevealed(hash)
        refreshHostContent(hash)
        guard before != after else { return }
        invalidateRegionLayout(regionRange(for: hash))
        textView?.needsLayout = true
        // The view-source flip resizes the region's fragments, so repaint the whole surface to
        // clear stale source text.
        textView?.needsDisplay = true
        repositionCards()
    }

    private func isRevealing(_ range: NSRange, selection: NSRange, docLength: Int) -> Bool {
        if selection.location == 0, selection.length == docLength, docLength > 0 { return false }
        if selection.length == 0 {
            let caret = selection.location
            return caret >= range.location && caret < range.location + range.length
        }
        return NSIntersectionRange(range, selection).length > 0
    }

    private func invalidateRegionLayout(_ nsRange: NSRange) {
        guard nsRange.length > 0,
              let layoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: nsRange.location),
              let end = contentManager.location(start, offsetBy: nsRange.length),
              let textRange = NSTextRange(location: start, end: end) else { return }
        layoutManager.invalidateLayout(for: textRange)
    }

    private func substring(_ ns: NSString?, _ range: NSRange) -> String? {
        guard let ns, range.location >= 0, range.location + range.length <= ns.length else { return nil }
        return ns.substring(with: range).trimmingCharacters(in: .newlines)
    }

    private func logReposition(_ seconds: Double) {
        #if DEBUG
        NSLog("[Daymark] card reposition: %.3f ms (%d hosts)", seconds * 1000, hosts.count)
        #endif
    }

    private func installScrollObserverIfNeeded() {
        guard scrollObserver == nil, let clipView = textView?.enclosingScrollView?.contentView else { return }
        clipView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.repositionCards() }
        }
    }
}
