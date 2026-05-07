import Foundation
import CryptoKit

/// Deterministic, well-distributed bucketing for percentage rollouts and A/B splits.
///
/// The bucketing key is `"<flagKey>:<userID>"`, hashed with SHA-256. The first
/// eight bytes of the digest are interpreted as a big-endian `UInt64` and reduced
/// modulo the desired bucket count.
///
/// Because the hash is deterministic, the same `(flagKey, userID)` pair will
/// always land in the same bucket — that's what keeps a user from flickering
/// between variants on every launch.
enum Bucketer {
    /// Returns a bucket in `0..<100` for percentage rollouts.
    static func percentile(flagKey: String, userID: String) -> Int {
        Int(rawBucket(flagKey: flagKey, userID: userID, total: 100))
    }

    /// Returns a bucket in `0..<total` for variant splits.
    /// `total` must be > 0.
    static func bucket(flagKey: String, userID: String, total: Int) -> Int {
        precondition(total > 0, "bucket total must be positive")
        return Int(rawBucket(flagKey: flagKey, userID: userID, total: UInt64(total)))
    }

    private static func rawBucket(flagKey: String, userID: String, total: UInt64) -> UInt64 {
        let input = "\(flagKey):\(userID)"
        let digest = SHA256.hash(data: Data(input.utf8))

        // Take the first 8 bytes as a big-endian UInt64.
        var hash: UInt64 = 0
        for byte in digest.prefix(8) {
            hash = (hash << 8) | UInt64(byte)
        }
        return hash % total
    }
}
