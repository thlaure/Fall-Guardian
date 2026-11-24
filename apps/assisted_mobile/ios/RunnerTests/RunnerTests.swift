import UIKit
import XCTest
@testable import Runner

/// Tests for the pure relay rules behind NativeAppleWatchAlertRelay: queue
/// migration, deduplication, bounding, cancel targeting and HTTP retry policy.
final class RelayQueueLogicTests: XCTestCase {
    private let now: Int64 = 1_710_000_000_000
    private let uuidA = "3f2b8c1e-9d4a-4c6b-8e2f-1a2b3c4d5e6f"
    private let uuidB = "7a1c2d3e-4f50-4617-8293-a4b5c6d7e8f9"

    private func item(
        _ id: String,
        _ timestamp: Int64,
        submitted: Bool = false,
        cancelRequested: Bool = false
    ) -> RelayQueueItem {
        RelayQueueItem(
            clientAlertID: id,
            timestamp: timestamp,
            source: RelayQueueItem.appleWatchSource,
            submitted: submitted,
            cancelRequested: cancelRequested,
            enqueuedAt: timestamp
        )
    }

    func testLegacySinglePendingSlotMigratesIntoQueue() {
        let migrated = RelayQueueLogic.migrateLegacy(
            timestamp: now,
            clientAlertID: "apple-watch-\(now)",
            submitted: true,
            cancelRequested: true,
            now: now + 1
        )

        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.clientAlertID, "apple-watch-\(now)")
        XCTAssertEqual(migrated.first?.submitted, true)
        XCTAssertEqual(migrated.first?.cancelRequested, true)
        XCTAssertTrue(RelayQueueLogic.migrateLegacy(timestamp: 0, clientAlertID: "x", submitted: false, cancelRequested: false, now: now).isEmpty)
        XCTAssertTrue(RelayQueueLogic.migrateLegacy(timestamp: now, clientAlertID: nil, submitted: false, cancelRequested: false, now: now).isEmpty)
    }

    func testSecondFallIsQueuedInsteadOfOverwritingFirst() {
        let first = RelayQueueLogic.enqueue([], timestamp: now, requestedID: uuidA, source: RelayQueueItem.appleWatchSource, now: now)
        let second = RelayQueueLogic.enqueue(first.items, timestamp: now + 5_000, requestedID: uuidB, source: RelayQueueItem.appleWatchSource, now: now)

        XCTAssertEqual(second.clientAlertID, uuidB)
        XCTAssertEqual(second.items.map(\.clientAlertID), [uuidA, uuidB])
    }

    func testDuplicateTransportsAreDeduplicated() {
        let first = RelayQueueLogic.enqueue([], timestamp: now, requestedID: uuidA, source: RelayQueueItem.appleWatchSource, now: now)
        let sameID = RelayQueueLogic.enqueue(first.items, timestamp: now, requestedID: uuidA, source: RelayQueueItem.appleWatchSource, now: now)
        let legacySameTimestamp = RelayQueueLogic.enqueue(first.items, timestamp: now, requestedID: nil, source: RelayQueueItem.appleWatchSource, now: now)

        XCTAssertEqual(sameID.items.count, 1)
        XCTAssertEqual(legacySameTimestamp.clientAlertID, uuidA)
        XCTAssertEqual(legacySameTimestamp.items.count, 1)
    }

    func testLegacyRetriggerWindowAndCancelledIncidentIsNeverReused() {
        let first = RelayQueueLogic.enqueue([], timestamp: now, requestedID: nil, source: RelayQueueItem.appleWatchSource, now: now)
        XCTAssertEqual(first.clientAlertID, "apple-watch-\(now)")

        let retrigger = RelayQueueLogic.enqueue(first.items, timestamp: now + 10_000, requestedID: nil, source: RelayQueueItem.appleWatchSource, now: now)
        XCTAssertEqual(retrigger.clientAlertID, "apple-watch-\(now)")

        let cancelled = RelayQueueLogic.requestCancel(first.items, incidentID: nil, fallTimestamp: nil).items
        let afterCancel = RelayQueueLogic.enqueue(cancelled, timestamp: now + 10_000, requestedID: nil, source: RelayQueueItem.appleWatchSource, now: now)
        XCTAssertEqual(afterCancel.clientAlertID, "apple-watch-\(now + 10_000)")
    }

    func testQueueIsBoundedEvictingSubmittedFirst() {
        var items = (0..<RelayQueueLogic.maxItems).map {
            item("apple-watch-\(now + Int64($0))", now + Int64($0), submitted: $0 == 3)
        }
        let result = RelayQueueLogic.enqueue(items, timestamp: now + 100, requestedID: uuidA, source: RelayQueueItem.appleWatchSource, now: now)
        XCTAssertEqual(result.items.count, RelayQueueLogic.maxItems)
        XCTAssertTrue(result.dropped.isEmpty)
        XCTAssertFalse(result.items.contains { $0.clientAlertID == "apple-watch-\(now + 3)" })

        items = result.items
        let overflow = RelayQueueLogic.enqueue(items, timestamp: now + 200, requestedID: uuidB, source: RelayQueueItem.appleWatchSource, now: now)
        XCTAssertEqual(overflow.dropped.map(\.clientAlertID), ["apple-watch-\(now)"])
    }

    func testCancelTargetsOnlyMatchingIncident() {
        let items = [item(uuidA, now), item(uuidB, now + 1), item("apple-watch-9", 9)]

        let byID = RelayQueueLogic.requestCancel(items, incidentID: uuidA, fallTimestamp: nil).items
        XCTAssertEqual(byID.filter(\.cancelRequested).map(\.clientAlertID), [uuidA])

        let byTimestamp = RelayQueueLogic.requestCancel(items, incidentID: nil, fallTimestamp: 9).items
        XCTAssertEqual(byTimestamp.filter(\.cancelRequested).map(\.clientAlertID), ["apple-watch-9"])

        let unknown = RelayQueueLogic.requestCancel(items, incidentID: "nope", fallTimestamp: 42).items
        XCTAssertEqual(unknown, items)

        let legacy = RelayQueueLogic.requestCancel(items, incidentID: nil, fallTimestamp: nil).items
        XCTAssertEqual(legacy.filter(\.cancelRequested).map(\.clientAlertID), [uuidB])
    }

    func testPruneForgetsFinishedAndReportsExpiredUndelivered() {
        let oldSubmitted = item(uuidA, now - RelayQueueLogic.submittedRetentionMilliseconds - 1, submitted: true)
        let recent = item(uuidB, now - 1_000, submitted: true)
        let expired = item("apple-watch-1", now - RelayQueueLogic.undeliveredRetentionMilliseconds - 1)

        let result = RelayQueueLogic.prune([oldSubmitted, recent, expired], now: now)

        XCTAssertEqual(result.kept, [recent])
        XCTAssertEqual(result.outcomes, [RelayOutcome(clientAlertID: expired.clientAlertID, timestamp: expired.timestamp, outcome: RelayOutcome.dropped)])
    }

    func testIncidentIDValidation() {
        XCTAssertEqual(RelayQueueLogic.normalizedIncidentID(uuidA), uuidA)
        XCTAssertEqual(RelayQueueLogic.normalizedIncidentID(" \(uuidA.uppercased()) "), uuidA)
        XCTAssertNil(RelayQueueLogic.normalizedIncidentID(nil))
        XCTAssertNil(RelayQueueLogic.normalizedIncidentID("not-a-uuid"))
        XCTAssertFalse(RelayQueueLogic.isSafeClientAlertID("a|b"))
        XCTAssertTrue(RelayQueueLogic.isSafeClientAlertID(uuidA))
    }

    func testHTTPStatusPolicy() {
        XCTAssertEqual(RelayQueueLogic.outcome(for: .create, status: 201), .success)
        XCTAssertEqual(RelayQueueLogic.outcome(for: .create, status: 401), .reauthRequired)
        XCTAssertEqual(RelayQueueLogic.outcome(for: .cancel, status: 403), .retry, "403 must be retried, never trigger re-pairing")
        for status in [0, 408, 429, 500, 503] {
            XCTAssertEqual(RelayQueueLogic.outcome(for: .create, status: status), .retry)
        }
        XCTAssertEqual(RelayQueueLogic.outcome(for: .create, status: 409), .alreadyDone)
        XCTAssertEqual(RelayQueueLogic.outcome(for: .cancel, status: 409), .tooLate)
        XCTAssertEqual(RelayQueueLogic.outcome(for: .createCancelled, status: 409), .tooLate)
        XCTAssertEqual(RelayQueueLogic.outcome(for: .cancel, status: 404), .alreadyDone)
        XCTAssertEqual(RelayQueueLogic.outcome(for: .create, status: 404), .rejected)
        XCTAssertEqual(RelayQueueLogic.outcome(for: .create, status: 422), .rejected)
        XCTAssertEqual(RelayQueueLogic.outcome(for: .create, status: 400), .rejected)
    }

    func testRetryBackoffGrowsAndIsCapped() {
        XCTAssertEqual(RelayQueueLogic.retryDelay(attempt: 0), 5)
        XCTAssertEqual(RelayQueueLogic.retryDelay(attempt: 1), 15)
        XCTAssertEqual(RelayQueueLogic.retryDelay(attempt: 99), 300)
        XCTAssertEqual(RelayQueueLogic.retryDelay(attempt: -1), 5)
    }
    func testExpiredCancelRequestedIncidentsNeverVanishSilently() {
        let old = now - RelayQueueLogic.undeliveredRetentionMilliseconds - 1
        let result = RelayQueueLogic.prune(
            [item("a", old, submitted: true, cancelRequested: true), item("b", old, cancelRequested: true)],
            now: now
        )

        XCTAssertTrue(result.kept.isEmpty)
        XCTAssertEqual(result.outcomes.map(\.outcome), [RelayOutcome.cancelUnconfirmed, RelayOutcome.cancelledUnsent])
    }

    func testCancelBeforeFallLeavesTombstoneThatCancelsTheFall() {
        let cancel = RelayQueueLogic.requestCancel([], incidentID: uuidA, fallTimestamp: nil, now: now)
        XCTAssertTrue(cancel.items.isEmpty)
        XCTAssertEqual(cancel.tombstones.count, 1)

        let fall = RelayQueueLogic.enqueue(
            cancel.items, timestamp: now + 1_000, requestedID: uuidA,
            source: RelayQueueItem.appleWatchSource, now: now + 1_000, tombstones: cancel.tombstones
        )

        XCTAssertEqual(fall.items.first?.cancelRequested, true)
        XCTAssertTrue(fall.tombstones.isEmpty)
    }

    func testTimestampTombstoneCancelsLegacyFallAndExpires() {
        let cancel = RelayQueueLogic.requestCancel([], incidentID: nil, fallTimestamp: now, now: now)

        let fall = RelayQueueLogic.enqueue(
            [], timestamp: now, requestedID: nil, source: RelayQueueItem.appleWatchSource,
            now: now + 500, tombstones: cancel.tombstones
        )
        XCTAssertEqual(fall.items.first?.cancelRequested, true)

        let late = RelayQueueLogic.enqueue(
            [], timestamp: now, requestedID: nil, source: RelayQueueItem.appleWatchSource,
            now: now + RelayQueueLogic.tombstoneTTLMilliseconds + 1, tombstones: cancel.tombstones
        )
        XCTAssertEqual(late.items.first?.cancelRequested, false)
    }

    func testUntargetedCancelNeverLeavesTombstone() {
        let cancel = RelayQueueLogic.requestCancel([], incidentID: nil, fallTimestamp: nil, now: now)

        XCTAssertTrue(cancel.tombstones.isEmpty)
    }

    func testLaterUUIDForLegacyIncidentIsStoredAsAlias() throws {
        let legacy = RelayQueueLogic.enqueue([], timestamp: now, requestedID: nil, source: RelayQueueItem.appleWatchSource, now: now)
        let withUUID = RelayQueueLogic.enqueue(legacy.items, timestamp: now, requestedID: uuidA, source: RelayQueueItem.appleWatchSource, now: now)

        XCTAssertEqual(withUUID.clientAlertID, "apple-watch-\(now)")
        XCTAssertEqual(withUUID.items.first?.aliases, [uuidA])
        let cancelled = RelayQueueLogic.requestCancel(withUUID.items, incidentID: uuidA, fallTimestamp: nil, now: now)
        XCTAssertEqual(cancelled.items.first?.cancelRequested, true)

        // Entries stored before aliases existed still decode.
        let oldJSON = #"[{"clientAlertID":"a","timestamp":1,"source":"apple_watch","submitted":false,"cancelRequested":false,"enqueuedAt":1}]"#
        let decoded = try JSONDecoder().decode([RelayQueueItem].self, from: Data(oldJSON.utf8))
        XCTAssertNil(decoded.first?.aliases)
    }

    func testRepairReportsQueuedIncidentsInsteadOfSendingThem() {
        let outcomes = RelayQueueLogic.discardForRepair([
            item("a", 1),
            item("b", 2, submitted: true, cancelRequested: true),
            item("c", 3, cancelRequested: true),
            item("d", 4, submitted: true),
        ])

        XCTAssertEqual(outcomes.map(\.outcome), [
            RelayOutcome.repairNotDelivered, RelayOutcome.cancelUnconfirmed, RelayOutcome.cancelledUnsent,
        ])
    }

    func testPendingCancelListNeverOverwritesAndMigrates() {
        let targeted = PendingCancelEntry(entryID: "1", incidentID: uuidA, fallTimestamp: 5)
        let legacy = PendingCancelEntry(entryID: "2", incidentID: nil, fallTimestamp: nil)
        let entries = PendingCancelList.add(PendingCancelList.add([], targeted), legacy)

        XCTAssertEqual(entries, [targeted, legacy])
        XCTAssertEqual(PendingCancelList.add(entries, PendingCancelEntry(entryID: "3", incidentID: uuidA, fallTimestamp: 5)), entries)
        XCTAssertEqual(PendingCancelList.remove(entries, entryID: "1"), [legacy])
        XCTAssertEqual(PendingCancelList.migrateLegacy(pending: true, incidentID: uuidA, fallTimestamp: 5).count, 1)
        XCTAssertTrue(PendingCancelList.migrateLegacy(pending: false, incidentID: nil, fallTimestamp: nil).isEmpty)
    }

    func testBackgroundTaskTokenEndsExactlyOnce() {
        let token = BackgroundTaskToken()
        token.set(UIBackgroundTaskIdentifier(rawValue: 42))
        var ended: [UIBackgroundTaskIdentifier] = []
        // Completion and expiration both try to end the task: only one wins.
        XCTAssertTrue(token.end { ended.append($0) })
        XCTAssertFalse(token.end { ended.append($0) })
        XCTAssertEqual(ended, [UIBackgroundTaskIdentifier(rawValue: 42)])
    }

    func testDelayedCancelForAnotherIncidentKeepsTheDisplayedNotification() {
        let showingB = DisplayedFallNotification(clientAlertID: uuidB, watchIncidentID: uuidB, timestamp: 2_000)

        XCTAssertFalse(FallNotificationMatch.shouldDismiss(displayed: showingB, incidentID: uuidA, fallTimestamp: 1_000))
        XCTAssertFalse(FallNotificationMatch.shouldDismiss(displayed: showingB, incidentID: nil, fallTimestamp: 1_000))
        XCTAssertTrue(FallNotificationMatch.shouldDismiss(displayed: showingB, incidentID: uuidB, fallTimestamp: nil))
        XCTAssertTrue(FallNotificationMatch.shouldDismiss(displayed: showingB, incidentID: nil, fallTimestamp: 2_000))
        // Legacy untargeted cancels always dismiss; unknown display is kept.
        XCTAssertTrue(FallNotificationMatch.shouldDismiss(displayed: showingB, incidentID: nil, fallTimestamp: nil))
        XCTAssertFalse(FallNotificationMatch.shouldDismiss(displayed: nil, incidentID: uuidA, fallTimestamp: nil))
        let legacyShown = DisplayedFallNotification(clientAlertID: "apple-watch-5", watchIncidentID: uuidA, timestamp: 5)
        XCTAssertTrue(FallNotificationMatch.shouldDismiss(displayed: legacyShown, incidentID: uuidA, fallTimestamp: nil))
    }
}

