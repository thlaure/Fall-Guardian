import Foundation
import XCTest
@testable import FallGuardianWatchLogic

// MARK: - Deadline

final class WatchAlertDeadlineTests: XCTestCase {
    func testWindowIsActiveOnlyWithinThirtySecondsOfTheFall() {
        XCTAssertFalse(WatchAlertDeadline.isActive(timestamp: 0, now: 1_000))
        XCTAssertFalse(WatchAlertDeadline.isActive(timestamp: 2_000, now: 1_000), "future fall")
        XCTAssertTrue(WatchAlertDeadline.isActive(timestamp: 1_000, now: 1_000))
        XCTAssertTrue(WatchAlertDeadline.isActive(timestamp: 1_000, now: 30_999))
        XCTAssertFalse(WatchAlertDeadline.isActive(timestamp: 1_000, now: 31_000))
    }

    func testRemainingMillisecondsNeverGoesNegative() {
        XCTAssertEqual(WatchAlertDeadline.remainingMilliseconds(timestamp: 1_000, now: 11_000), 20_000)
        XCTAssertEqual(WatchAlertDeadline.remainingMilliseconds(timestamp: 1_000, now: 31_000), 0)
        XCTAssertEqual(WatchAlertDeadline.remainingMilliseconds(timestamp: 1_000, now: 90_000), 0)
    }

    func testDisplayEndIsFallDeadlineWhenPresentedImmediately() {
        XCTAssertEqual(WatchAlertDeadline.displayEnd(timestamp: 1_000, presentedAt: 1_000), 31_000)
    }

    func testLateAppleDeliveryStillGetsMinimumDisplayTime() {
        // Apple delivered the event 60 s after the fall (after its own check-in).
        let fall: Int64 = 1_000
        let presented: Int64 = 61_000
        XCTAssertEqual(WatchAlertDeadline.displayEnd(timestamp: fall, presentedAt: presented), 91_000)
        XCTAssertTrue(WatchAlertDeadline.isDisplayable(timestamp: fall, presentedAt: presented, now: 90_999))
        XCTAssertFalse(WatchAlertDeadline.isDisplayable(timestamp: fall, presentedAt: presented, now: 91_000))
    }

    func testDisplayableRejectsMissingTimes() {
        XCTAssertFalse(WatchAlertDeadline.isDisplayable(timestamp: 0, presentedAt: 1_000, now: 1_000))
        XCTAssertFalse(WatchAlertDeadline.isDisplayable(timestamp: 1_000, presentedAt: 0, now: 1_000))
    }
}

// MARK: - Incident identity and payloads

final class WatchIncidentTests: XCTestCase {
    func testMakeUsesLowercaseUUID() {
        let uuid = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let incident = WatchIncident.make(timestamp: 42, uuid: uuid)
        XCTAssertEqual(incident.id, "e621e1f8-c36c-495a-93fc-0c247a3e6e5f")
        XCTAssertEqual(incident.timestamp, 42)
    }

    func testMakeGeneratesDistinctIdsForSameTimestamp() {
        XCTAssertNotEqual(WatchIncident.make(timestamp: 42).id, WatchIncident.make(timestamp: 42).id)
    }

    func testInitNormalisesIdToLowercase() {
        XCTAssertEqual(WatchIncident(id: "ABC-DEF", timestamp: 1).id, "abc-def")
    }
}

final class WatchPayloadsTests: XCTestCase {
    private let incident = WatchIncident(id: "11111111-2222-3333-4444-555555555555", timestamp: 1_700_000_000_123)

    func testFallDetectedKeepsLegacyKeysAndAddsIncidentId() {
        let payload = WatchPayloads.fallDetected(incident)
        XCTAssertEqual(Set(payload.keys), ["event", "timestamp", "incidentId"])
        XCTAssertEqual(payload["event"] as? String, "fall_detected")
        XCTAssertEqual(payload["timestamp"] as? Int64, 1_700_000_000_123)
        XCTAssertEqual(payload["incidentId"] as? String, incident.id)
    }

    func testFallDetectedTimestampIsReadableAsIntByCurrentPhone() {
        // The phone reads `message["timestamp"] as? Int`; WatchConnectivity
        // delivers numbers as NSNumber, which bridges to Int.
        let bridged = WatchPayloads.fallDetected(incident)["timestamp"].map { $0 as! NSNumber }
        XCTAssertEqual(bridged.map { $0 as? Int }, 1_700_000_000_123)
    }

    func testCancelIdentifiesIncident() {
        let payload = WatchPayloads.alertCancelled(incident)
        XCTAssertEqual(Set(payload.keys), ["event", "fallTimestamp", "incidentId"])
        XCTAssertEqual(payload["event"] as? String, "alert_cancelled")
        XCTAssertEqual(payload["fallTimestamp"] as? Int64, incident.timestamp)
        XCTAssertEqual(payload["incidentId"] as? String, incident.id)
    }

    func testCancelWithoutIncidentFallsBackToLegacyShape() {
        let payload = WatchPayloads.alertCancelled(nil)
        XCTAssertEqual(Set(payload.keys), ["event"])
        XCTAssertEqual(payload["event"] as? String, "alert_cancelled")
    }

    func testInt64ParsesEveryNumericBoxing() {
        XCTAssertEqual(WatchPayloads.int64(Int64(5)), 5)
        XCTAssertEqual(WatchPayloads.int64(Int(6)), 6)
        XCTAssertEqual(WatchPayloads.int64(Double(7.9)), 7)
        XCTAssertEqual(WatchPayloads.int64(NSNumber(value: Int32(8))), 8)
        XCTAssertNil(WatchPayloads.int64(nil))
        XCTAssertNil(WatchPayloads.int64("9"))
        XCTAssertNil(WatchPayloads.int64(Double.nan))
        XCTAssertNil(WatchPayloads.int64(Double.infinity))
        XCTAssertNil(WatchPayloads.int64(1e30), "out of range must not trap")
    }
}

// MARK: - Cancel matching

final class WatchCancelMatcherTests: XCTestCase {
    private let active = WatchIncident(id: "aaaaaaaa-0000-0000-0000-000000000001", timestamp: 1_000)

    func testNoActiveAlertRejectsEveryCancel() {
        XCTAssertFalse(WatchCancelMatcher.accepts(["event": "alert_cancelled", "fallTimestamp": 1_000], active: nil))
    }

    func testMatchingIncidentIdIsAccepted() {
        XCTAssertTrue(WatchCancelMatcher.accepts(["incidentId": active.id, "fallTimestamp": 1_000], active: active))
    }

    func testIncidentIdComparisonIgnoresCase() {
        XCTAssertTrue(WatchCancelMatcher.accepts(["incidentId": active.id.uppercased()], active: active))
    }

    func testDifferentIncidentIdIsRejectedEvenWhenTimestampMatches() {
        let message: [String: Any] = ["incidentId": "bbbbbbbb-0000-0000-0000-000000000002", "fallTimestamp": 1_000]
        XCTAssertFalse(WatchCancelMatcher.accepts(message, active: active))
    }

    func testLegacyCancelMatchesByTimestamp() {
        XCTAssertTrue(WatchCancelMatcher.accepts(["fallTimestamp": 1_000], active: active))
        XCTAssertTrue(WatchCancelMatcher.accepts(["fallTimestamp": NSNumber(value: 1_000)], active: active))
        XCTAssertTrue(WatchCancelMatcher.accepts(["incidentId": "", "fallTimestamp": 1_000], active: active))
    }

    func testLegacyCancelWithOtherOrMissingTimestampIsRejected() {
        XCTAssertFalse(WatchCancelMatcher.accepts(["fallTimestamp": 999], active: active))
        XCTAssertFalse(WatchCancelMatcher.accepts(["fallTimestamp": 0], active: active))
        XCTAssertFalse(WatchCancelMatcher.accepts(["event": "alert_cancelled"], active: active))
    }

    func testApplicationContextRequiresAlertCancelledTrue() {
        XCTAssertTrue(WatchCancelMatcher.acceptsApplicationContext(
            ["alertCancelled": true, "fallTimestamp": 1_000], active: active))
        XCTAssertFalse(WatchCancelMatcher.acceptsApplicationContext(
            ["alertCancelled": false, "fallTimestamp": 1_000], active: active), "reset for new incident")
        XCTAssertFalse(WatchCancelMatcher.acceptsApplicationContext(
            ["fallTimestamp": 1_000], active: active))
    }

    func testApplicationContextHonoursIncidentId() {
        XCTAssertTrue(WatchCancelMatcher.acceptsApplicationContext(
            ["alertCancelled": true, "fallTimestamp": 1_000, "incidentId": active.id], active: active))
        XCTAssertFalse(WatchCancelMatcher.acceptsApplicationContext(
            ["alertCancelled": true, "fallTimestamp": 1_000, "incidentId": "stale"], active: active))
    }
}

// MARK: - Apple resolution policy

final class SystemFallPolicyTests: XCTestCase {
    private func decide(_ resolution: SystemFallResolution, timestamp: Int64 = 2_000, last: Int64 = 1_000) -> SystemFallDecision {
        SystemFallPolicy.decide(timestamp: timestamp, resolution: resolution, lastProcessedTimestamp: last)
    }

    func testConfirmedAndUnresponsiveEscalate() {
        XCTAssertEqual(decide(.confirmed), .escalate)
        XCTAssertEqual(decide(.unresponsive), .escalate)
    }

    func testUnknownFutureResolutionEscalates() {
        XCTAssertEqual(decide(.unknown), .escalate)
    }

    func testDismissedIsRecordedWithoutAlert() {
        XCTAssertEqual(decide(.dismissed), .recordDismissed)
    }

    func testRejectedIsIgnored() {
        XCTAssertEqual(decide(.rejected), .ignoreRejected)
    }

    func testRedeliveredOrOlderEventIsDuplicateWhateverTheResolution() {
        XCTAssertEqual(decide(.unresponsive, timestamp: 1_000, last: 1_000), .ignoreDuplicate)
        XCTAssertEqual(decide(.confirmed, timestamp: 900, last: 1_000), .ignoreDuplicate)
        XCTAssertEqual(decide(.rejected, timestamp: 900, last: 1_000), .ignoreDuplicate)
    }

    func testFirstEverEventIsProcessed() {
        XCTAssertEqual(decide(.unresponsive, timestamp: 1, last: 0), .escalate)
    }
}

// MARK: - Alert state machine

final class WatchAlertStateTests: XCTestCase {
    private let incident = WatchIncident(id: "cccccccc-0000-0000-0000-000000000003", timestamp: 10_000)

    func testStartsInactive() {
        let state = WatchAlertState()
        XCTAssertFalse(state.isActive)
        XCTAssertNil(state.phase(now: 10_000))
    }

    func testFreshFallCountsDownFromThirty() {
        var state = WatchAlertState()
        XCTAssertTrue(state.start(incident, presentedAt: 10_000, now: 10_000))
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.phase(now: 10_000), .countdown(seconds: 30))
        XCTAssertEqual(state.phase(now: 10_500), .countdown(seconds: 30), "rounds up")
        XCTAssertEqual(state.phase(now: 11_000), .countdown(seconds: 29))
    }

    func testCountdownNeverShowsZero() {
        var state = WatchAlertState()
        _ = state.start(incident, presentedAt: 10_000, now: 10_000)
        XCTAssertEqual(state.phase(now: 39_999), .countdown(seconds: 1))
        XCTAssertEqual(state.phase(now: 40_000), nil, "fresh alert ends at the deadline")
    }

    func testLateDeliveryShowsNotifyingWithCancelWindow() {
        var state = WatchAlertState()
        // Delivered 45 s after the fall: grace window already over.
        XCTAssertTrue(state.start(incident, presentedAt: 55_000, now: 55_000))
        XCTAssertEqual(state.phase(now: 55_000), .notifyingCaregivers)
        XCTAssertEqual(state.phase(now: 84_999), .notifyingCaregivers)
        XCTAssertNil(state.phase(now: 85_000))
    }

    func testSlightlyLateDeliveryCountsDownThenNotifies() {
        var state = WatchAlertState()
        XCTAssertTrue(state.start(incident, presentedAt: 35_000, now: 35_000))
        XCTAssertEqual(state.phase(now: 35_000), .countdown(seconds: 5))
        XCTAssertEqual(state.phase(now: 40_000), .notifyingCaregivers)
        XCTAssertNil(state.phase(now: 65_000))
    }

    func testSecondStartWhileActiveIsIgnored() {
        var state = WatchAlertState()
        _ = state.start(incident, presentedAt: 10_000, now: 10_000)
        let other = WatchIncident(id: "other", timestamp: 12_000)
        XCTAssertFalse(state.start(other, presentedAt: 12_000, now: 12_000))
        XCTAssertEqual(state.incident, incident)
    }

    func testExpiredRestoreIsRefused() {
        var state = WatchAlertState()
        XCTAssertFalse(state.start(incident, presentedAt: 10_000, now: 40_000))
        XCTAssertFalse(state.isActive)
    }

    func testFinishReturnsIncidentAndResets() {
        var state = WatchAlertState()
        _ = state.start(incident, presentedAt: 10_000, now: 10_000)
        XCTAssertEqual(state.finish(), incident)
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.presentedAt, 0)
        XCTAssertNil(state.finish(), "second finish has nothing to cancel")
        XCTAssertTrue(state.start(incident, presentedAt: 11_000, now: 11_000), "can start again")
    }

    func testHapticCues() {
        XCTAssertNil(WatchAlertState.hapticCue(from: nil, to: nil))
        XCTAssertNil(WatchAlertState.hapticCue(from: .countdown(seconds: 20), to: .countdown(seconds: 20)))
        XCTAssertEqual(WatchAlertState.hapticCue(from: nil, to: .countdown(seconds: 30)), .tick)
        XCTAssertEqual(WatchAlertState.hapticCue(from: .countdown(seconds: 12), to: .countdown(seconds: 11)), .tick)
        XCTAssertEqual(WatchAlertState.hapticCue(from: .countdown(seconds: 11), to: .countdown(seconds: 10)), .urgent)
        XCTAssertEqual(WatchAlertState.hapticCue(from: .countdown(seconds: 1), to: .notifyingCaregivers), .urgent)
        XCTAssertNil(WatchAlertState.hapticCue(from: .notifyingCaregivers, to: .notifyingCaregivers))
    }

    func testVoiceOverAnnouncesMilestonesOnce() {
        XCTAssertTrue(WatchAlertState.shouldAnnounce(.countdown(seconds: 30), previous: nil))
        XCTAssertFalse(WatchAlertState.shouldAnnounce(.countdown(seconds: 30), previous: .countdown(seconds: 30)))
        XCTAssertFalse(WatchAlertState.shouldAnnounce(.countdown(seconds: 29), previous: .countdown(seconds: 30)))
        XCTAssertTrue(WatchAlertState.shouldAnnounce(.countdown(seconds: 20), previous: .countdown(seconds: 21)))
        XCTAssertTrue(WatchAlertState.shouldAnnounce(.countdown(seconds: 10), previous: .countdown(seconds: 11)))
        XCTAssertTrue(WatchAlertState.shouldAnnounce(.countdown(seconds: 5), previous: .countdown(seconds: 6)))
        XCTAssertTrue(WatchAlertState.shouldAnnounce(.notifyingCaregivers, previous: .countdown(seconds: 1)))
        XCTAssertFalse(WatchAlertState.shouldAnnounce(.notifyingCaregivers, previous: .notifyingCaregivers))
        XCTAssertFalse(WatchAlertState.shouldAnnounce(nil, previous: .countdown(seconds: 3)))
    }
}
