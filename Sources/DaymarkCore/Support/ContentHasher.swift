import Foundation
import CryptoKit

/// Stable content hashing for reconciliation between Markdown files and the SQLite
/// projection. Uses SHA-256 so the hash is reproducible across processes, unlike
/// `String.hashValue`, which is randomized per run.
public enum ContentHasher {
    public static func hash(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
