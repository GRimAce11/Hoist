import Testing
@testable import Hoist

@Suite("Bucketer")
struct BucketerTests {

    @Test func percentileIsInRange() {
        for i in 0..<1000 {
            let bucket = Bucketer.percentile(flagKey: "flag", userID: "user_\(i)")
            #expect((0..<100).contains(bucket), "out-of-range bucket: \(bucket)")
        }
    }

    @Test func percentileIsDeterministic() {
        let a = Bucketer.percentile(flagKey: "checkout", userID: "alice")
        let b = Bucketer.percentile(flagKey: "checkout", userID: "alice")
        #expect(a == b)
    }

    @Test func differentFlagsBucketDifferently() {
        // The same user is independently bucketed per flag — that's the point.
        // Across 100 flags, at least one should disagree with the first bucket.
        let userID = "stable_user"
        let firstBucket = Bucketer.percentile(flagKey: "flag_0", userID: userID)
        var sawDifferent = false
        for i in 1..<100 {
            if Bucketer.percentile(flagKey: "flag_\(i)", userID: userID) != firstBucket {
                sawDifferent = true
                break
            }
        }
        #expect(sawDifferent, "all 100 flags hashed to the same bucket — distribution is broken")
    }

    @Test func bucketRespectsTotal() {
        for total in [3, 10, 257] {
            for i in 0..<200 {
                let bucket = Bucketer.bucket(flagKey: "x", userID: "user_\(i)", total: total)
                #expect((0..<total).contains(bucket))
            }
        }
    }
}
