package com.fallguardian

/** Persistence operations the relay pass needs (backed by NativeAlertRelay). */
internal interface RelayQueueStore {
    fun find(clientAlertId: String): QueuedAlert?
    fun markSubmitted(clientAlertId: String)
    fun complete(clientAlertId: String, outcome: RelayOutcomeKind?)
    /** Publishes an outcome for Flutter's history without removing the item. */
    fun recordOutcome(clientAlertId: String, outcome: RelayOutcomeKind)
}

internal enum class RelayPassResult { DONE, RETRY, REAUTH_REQUIRED }

/**
 * Pure relay orchestration: sends each queued incident (create, then cancel
 * if requested) and applies [NativeAlertRelayPolicy.outcomeFor]. Free of
 * Android types so JVM tests can drive it with scripted HTTP statuses.
 *
 * [post] returns the HTTP status, or 0 when no response was received.
 */
internal class RelayProcessor(
    private val store: RelayQueueStore,
    private val post: (path: String, body: String?) -> Int,
    private val createPayload: (QueuedAlert, cancelled: Boolean) -> String
) {
    fun relay(clientAlertIds: List<String>): RelayPassResult {
        var retry = false
        for (id in clientAlertIds) {
            when (relayOne(id)) {
                RelayPassResult.DONE -> Unit
                RelayPassResult.RETRY -> retry = true
                // Revoked credentials: stop; every other request would fail too.
                RelayPassResult.REAUTH_REQUIRED -> return RelayPassResult.REAUTH_REQUIRED
            }
        }
        return if (retry) RelayPassResult.RETRY else RelayPassResult.DONE
    }

    private fun relayOne(clientAlertId: String): RelayPassResult {
        var alert = store.find(clientAlertId) ?: return RelayPassResult.DONE

        if (!alert.submitted) {
            val operation = if (alert.cancelRequested) {
                RelayOperation.CREATE_CANCELLED
            } else {
                RelayOperation.CREATE
            }
            val status = post(CREATE_PATH, createPayload(alert, alert.cancelRequested))
            when (NativeAlertRelayPolicy.outcomeFor(operation, status)) {
                RelayHttpOutcome.SUCCESS, RelayHttpOutcome.ALREADY_DONE -> {
                    if (operation == RelayOperation.CREATE_CANCELLED) {
                        store.complete(clientAlertId, RelayOutcomeKind.CANCELLED)
                        return RelayPassResult.DONE
                    }
                    store.markSubmitted(clientAlertId)
                    // Lets Flutter upgrade a provisional "failed" history entry.
                    store.recordOutcome(clientAlertId, RelayOutcomeKind.CREATED)
                }
                RelayHttpOutcome.TOO_LATE -> {
                    store.complete(clientAlertId, RelayOutcomeKind.CANCEL_TOO_LATE)
                    return RelayPassResult.DONE
                }
                RelayHttpOutcome.REJECTED -> {
                    store.complete(
                        clientAlertId,
                        if (alert.cancelRequested) {
                            RelayOutcomeKind.CANCEL_REJECTED
                        } else {
                            RelayOutcomeKind.CREATE_REJECTED
                        }
                    )
                    return RelayPassResult.DONE
                }
                RelayHttpOutcome.REAUTH_REQUIRED -> return RelayPassResult.REAUTH_REQUIRED
                RelayHttpOutcome.RETRY -> return RelayPassResult.RETRY
            }
            // A cancel may have been requested while the create was in flight.
            alert = store.find(clientAlertId) ?: return RelayPassResult.DONE
        }

        if (!alert.cancelRequested) {
            // Keep the submitted state until the retention window ends. A later
            // watch/phone cancel can reschedule the relay without Flutter.
            return RelayPassResult.DONE
        }

        val status = post("$CREATE_PATH/$clientAlertId/cancel", null)
        return when (NativeAlertRelayPolicy.outcomeFor(RelayOperation.CANCEL, status)) {
            RelayHttpOutcome.SUCCESS, RelayHttpOutcome.ALREADY_DONE -> {
                // Lets Flutter upgrade a provisional "cancellation pending" entry.
                store.complete(clientAlertId, RelayOutcomeKind.CANCELLED)
                RelayPassResult.DONE
            }
            RelayHttpOutcome.TOO_LATE -> {
                store.complete(clientAlertId, RelayOutcomeKind.CANCEL_TOO_LATE)
                RelayPassResult.DONE
            }
            RelayHttpOutcome.REJECTED -> {
                store.complete(clientAlertId, RelayOutcomeKind.CANCEL_REJECTED)
                RelayPassResult.DONE
            }
            RelayHttpOutcome.REAUTH_REQUIRED -> RelayPassResult.REAUTH_REQUIRED
            RelayHttpOutcome.RETRY -> RelayPassResult.RETRY
        }
    }

    companion object {
        const val CREATE_PATH = "/api/v1/fall-alerts"
    }
}
