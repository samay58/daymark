import Foundation
import DaymarkCore

/// Stable hashing for block-level reconciliation. Delegates to `ContentHasher` so the
/// digest is reproducible across processes, unlike `String.hashValue`.
public struct BlockHasher {
    public init() {}

    public func hash(_ markdown: String) -> String {
        ContentHasher.hash(markdown)
    }
}
