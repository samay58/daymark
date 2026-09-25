import AppKit

/// The frame loop and easing curves shared by the editor's small hand-driven animations (the
/// checkbox check and the concealment reveal fade). Progress is derived from elapsed time,
/// so a late tick makes a frame jump rather than stretching the animation.
enum EditorMotion {
    /// Calls `frame` with the seconds elapsed since the loop started, about every 16ms, until
    /// it returns false or the surrounding task is cancelled.
    @MainActor
    static func runFrames(_ frame: (CFTimeInterval) -> Bool) async {
        let start = CACurrentMediaTime()
        while !Task.isCancelled {
            guard frame(CACurrentMediaTime() - start) else { return }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
    }

    static func easeOut(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return 1 - pow(1 - clamped, 3)
    }

    static func easeInOut(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return clamped < 0.5 ? 2 * clamped * clamped : 1 - pow(-2 * clamped + 2, 2) / 2
    }
}
