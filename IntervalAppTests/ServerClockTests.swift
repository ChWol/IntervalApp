import XCTest

/// A device with a wrong clock used to win every conflict, or lose every one. Timestamps are
/// therefore exchanged in server time.
final class ServerClockTests: XCTestCase {
    private let now = TestTime.now
    
    func testLearnsTheOffsetFromOneRoundTrip() {
        var clock = ServerClock()
        // This device is five minutes behind the server.
        let serverDate = now.addingTimeInterval(300)
        
        XCTAssertTrue(clock.adopt(serverDate: serverDate, sentAt: now, receivedAt: now.addingTimeInterval(0.2)))
        XCTAssertEqual(clock.offset, 300, accuracy: 1)
    }
    
    func testIgnoresSubSecondNoise() {
        var clock = ServerClock()
        XCTAssertFalse(
            clock.adopt(serverDate: now.addingTimeInterval(0.6), sentAt: now, receivedAt: now.addingTimeInterval(0.1)),
            "The HTTP Date header only has second resolution; churning the offset is worse than ignoring it"
        )
        XCTAssertEqual(clock.offset, 0)
    }
    
    func testUsesTheMiddleOfASlowRoundTrip() {
        var clock = ServerClock()
        // A four second request: the server stamped its response around the midpoint.
        let sentAt = now
        let receivedAt = now.addingTimeInterval(4)
        let serverDate = now.addingTimeInterval(2)
        
        clock.adopt(serverDate: serverDate, sentAt: sentAt, receivedAt: receivedAt)
        XCTAssertEqual(clock.offset, 0, accuracy: 0.001, "Latency alone must not look like clock skew")
    }
    
    func testConvertsBothWays() {
        var clock = ServerClock()
        clock.offset = 3600
        
        XCTAssertEqual(clock.toServer(now), now.addingTimeInterval(3600))
        XCTAssertEqual(clock.toLocal(clock.toServer(now)), now)
    }
    
    /// The point of the correction: a local edit made after a remote one must still look newer
    /// on a device whose clock is an hour behind.
    func testSkewedDeviceStillOrdersEditsCorrectly() {
        var skewed = ServerClock()
        skewed.offset = 3600
        
        let remoteEditInServerTime = now
        let laterLocalEdit = skewed.toLocal(now.addingTimeInterval(5))
        
        XCTAssertTrue(skewed.toServer(laterLocalEdit) > remoteEditInServerTime)
        XCTAssertEqual(
            MergePolicy.resolve(remoteUpdatedAt: skewed.toLocal(remoteEditInServerTime),
                                localUpdatedAt: laterLocalEdit,
                                localSyncedAt: nil),
            .republishLocal
        )
    }
    
    func testParsesTheHTTPDateHeader() {
        let parsed = ServerClock.parseHTTPDate("Mon, 15 Jun 2026 12:00:00 GMT")
        XCTAssertEqual(parsed, now)
        XCTAssertNil(ServerClock.parseHTTPDate(nil))
        XCTAssertNil(ServerClock.parseHTTPDate("yesterday"))
    }
}

/// Retries have to space out, or an unreachable server is hammered every ten seconds.
final class SyncBackoffTests: XCTestCase {
    private let now = TestTime.now
    
    func testAllowsAttemptsWhileHealthy() {
        let backoff = SyncBackoff()
        XCTAssertTrue(backoff.allowsAttempt(now: now))
    }
    
    func testBlocksTheNextScheduledAttemptAfterAFailure() {
        var backoff = SyncBackoff()
        backoff.recordFailure(now: now)
        
        XCTAssertFalse(backoff.allowsAttempt(now: now.addingTimeInterval(1)))
        XCTAssertTrue(backoff.allowsAttempt(now: now.addingTimeInterval(3)))
    }
    
    func testDelayGrowsWithConsecutiveFailuresAndIsCapped() {
        var backoff = SyncBackoff()
        for _ in 0..<3 { backoff.recordFailure(now: now) }
        XCTAssertFalse(backoff.allowsAttempt(now: now.addingTimeInterval(7)))
        XCTAssertTrue(backoff.allowsAttempt(now: now.addingTimeInterval(9)))
        
        for _ in 0..<40 { backoff.recordFailure(now: now) }
        XCTAssertTrue(backoff.allowsAttempt(now: now.addingTimeInterval(SyncBackoff.maxDelay + 1)),
                      "A long outage must not push the next attempt beyond the cap")
    }
    
    func testSuccessClearsTheDelay() {
        var backoff = SyncBackoff()
        backoff.recordFailure(now: now)
        backoff.recordSuccess()
        
        XCTAssertTrue(backoff.allowsAttempt(now: now))
        XCTAssertEqual(backoff.consecutiveFailures, 0)
    }
}
