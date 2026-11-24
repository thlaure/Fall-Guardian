package com.fallguardian

/** What the urgent alert surface (notification, sound, haptics) must do. */
enum class AlertPresentation {
    SHOW,
    DISMISS,
    /** Dismiss, then confirm the wearer's own cancel with a haptic tick. */
    DISMISS_CONFIRMED
}

/** Side effects requested by [AlertSession], executed in order by WearDataSender. */
sealed interface AlertEffect {
    data class SendMessage(val path: String, val payload: ByteArray) : AlertEffect {
        override fun equals(other: Any?) =
            other is SendMessage && other.path == path && other.payload.contentEquals(payload)
        override fun hashCode() = 31 * path.hashCode() + payload.contentHashCode()
    }
    data class PutDataItem(val path: String, val fields: Map<String, Any>) : AlertEffect
    data class DeleteDataItem(val path: String) : AlertEffect
    data class Present(val presentation: AlertPresentation) : AlertEffect
}

/**
 * Single-threaded alert state machine: decides what happens on a detected
 * fall, a watch cancel, a phone cancel, countdown expiry and process restart.
 * It holds no Android types; WearDataSender runs it on the main thread and
 * executes the returned effects (Data Layer, presentation) in order.
 *
 * Ordering rules (safety-critical):
 * - State is persisted / cleared before any effect is emitted, so a process
 *   death mid-way never leaves a cancelled alert that would be restored.
 * - Fall: delete the previous incident's undelivered cancel *before* queuing
 *   the new fall, so an old cancel cannot close the new alert on an older
 *   phone build.
 * - Cancel: delete the queued fall *before* queuing the cancel, so a
 *   cancelled fall is never replayed and can never overtake its cancel.
 * - Restore: a live persisted alert was never cancelled (cancel clears state
 *   first), so its fall is re-sent with the SAME incident id and original
 *   timestamp in case the process died before the Data Layer put; the phone
 *   de-duplicates by incident id.
 */
class AlertSession(
    private val store: ActiveAlertStore,
    private val newIncidentId: () -> String = AlertContract::newIncidentId
) {
    var active: ActiveAlert? = null
        private set

    fun onFallDetected(fallTimestampMs: Long, now: ClockReading): List<AlertEffect> {
        if (!shouldStartAlert(active != null, fallTimestampMs, now.wallMs)) return emptyList()
        val alert = ActiveAlert.detected(newIncidentId(), fallTimestampMs, now)
        store.save(alert)
        active = alert
        return fallDelivery(alert, now) + AlertEffect.Present(AlertPresentation.SHOW)
    }

    fun restore(now: ClockReading): List<AlertEffect> {
        if (active != null) {
            // Process alive; a (re)attached presenter just needs the state.
            return listOf(AlertEffect.Present(AlertPresentation.SHOW))
        }
        val restored = store.restore(now) ?: return emptyList()
        active = restored
        return fallDelivery(restored, now) + AlertEffect.Present(AlertPresentation.SHOW)
    }

    fun onWatchCancel(now: ClockReading): List<AlertEffect> {
        val alert = end() ?: return emptyList()
        return listOf(
            AlertEffect.Present(AlertPresentation.DISMISS_CONFIRMED),
            AlertEffect.SendMessage(AlertContract.CANCEL_PATH, AlertContract.cancelMessagePayload(alert)),
            AlertEffect.DeleteDataItem(AlertContract.FALL_PATH),
            AlertEffect.PutDataItem(AlertContract.CANCEL_PATH, AlertContract.cancelDataFields(alert, now.wallMs))
        )
    }

    /**
     * The phone cancel can start this process on its own (via
     * PhoneMessageListenerService) after the process died mid-countdown,
     * before the service or Activity restored the alert. The persisted live
     * incident is therefore evaluated too; otherwise a matching cancel would
     * be rejected, the saved state kept, and a later restart would resurrect
     * the cancelled alert (alarm, notification, re-sent fall).
     */
    fun onPhoneCancel(cancel: PhoneCancel, now: ClockReading): List<AlertEffect> {
        // store.restore() also discards an expired or corrupt saved alert.
        val candidate = active ?: store.restore(now)
        if (!AlertContract.shouldAcceptPhoneCancel(candidate, cancel)) return emptyList()
        active = null
        store.clear()
        // No echo to the phone: it originated the cancel.
        return listOf(AlertEffect.Present(AlertPresentation.DISMISS))
    }

    /** Seconds left for the countdown UI; 0 when idle. */
    fun remainingSeconds(now: ClockReading): Int = active?.remainingSeconds(now) ?: 0

    /** Called by the countdown tick; ends the alert once the window is over. */
    fun onTick(now: ClockReading): List<AlertEffect> {
        val alert = active ?: return emptyList()
        if (alert.remainingSeconds(now) > 0) return emptyList()
        // Expiry: the phone escalates independently; the fall item stays
        // queued so a briefly disconnected phone still receives it.
        end()
        return listOf(AlertEffect.Present(AlertPresentation.DISMISS))
    }

    private fun end(): ActiveAlert? {
        val alert = active ?: return null
        store.clear()
        active = null
        return alert
    }

    private fun fallDelivery(alert: ActiveAlert, now: ClockReading): List<AlertEffect> = listOf(
        AlertEffect.DeleteDataItem(AlertContract.CANCEL_PATH),
        AlertEffect.SendMessage(AlertContract.FALL_PATH, AlertContract.fallMessagePayload(alert)),
        AlertEffect.PutDataItem(AlertContract.FALL_PATH, AlertContract.fallDataFields(alert, now.wallMs))
    )
}
