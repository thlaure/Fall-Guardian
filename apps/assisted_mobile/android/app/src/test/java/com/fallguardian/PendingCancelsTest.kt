package com.fallguardian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class PendingCancelsTest {
    private val uuid = "3f2b8c1e-9d4a-4c6b-8e2f-1a2b3c4d5e6f"

    @Test
    fun `an untargeted cancel never overwrites a targeted one`() {
        val targeted = PendingCancel("c1", uuid, 5)
        val legacy = PendingCancel("c2", null, null)

        val entries = PendingCancels.add(PendingCancels.add(emptyList(), targeted), legacy)

        assertEquals(listOf(targeted, legacy), entries)
    }

    @Test
    fun `duplicate targets are delivered once and removal is per entry`() {
        val first = PendingCancel("c1", uuid, 5)

        val entries = PendingCancels.add(listOf(first), PendingCancel("c2", uuid, 5))

        assertEquals(listOf(first), entries)
        assertTrue(PendingCancels.remove(entries, "c1").isEmpty())
    }

    @Test
    fun `list is bounded`() {
        var entries = emptyList<PendingCancel>()
        repeat(PendingCancels.MAX_ENTRIES + 5) {
            entries = PendingCancels.add(entries, PendingCancel("c$it", null, it.toLong()))
        }

        assertEquals(PendingCancels.MAX_ENTRIES, entries.size)
        assertEquals("c5", entries.first().entryId)
    }

    @Test
    fun `legacy single slot migrates into one entry`() {
        assertEquals(
            listOf(PendingCancel("legacy", uuid, 5)),
            PendingCancels.migrateLegacy(true, uuid, 5)
        )
        assertTrue(PendingCancels.migrateLegacy(false, uuid, 5).isEmpty())
    }

    @Test
    fun `entries round trip and corrupted lines are skipped`() {
        val entries = listOf(PendingCancel("c1", uuid, 5), PendingCancel("c2", null, null))

        assertEquals(entries, PendingCancels.decode(PendingCancels.encode(entries)))
        assertTrue(PendingCancels.decode("bad|line").isEmpty())
        assertTrue(PendingCancels.decode(null).isEmpty())
    }
}

class FallNotificationPolicyTest {
    private val uuidA = "3f2b8c1e-9d4a-4c6b-8e2f-1a2b3c4d5e6f"
    private val uuidB = "7a1c2d3e-4f50-4617-8293-a4b5c6d7e8f9"
    private val showingB = DisplayedFallNotification(uuidB, uuidB, 2_000)

    @Test
    fun `a delayed cancel for incident A keeps incident B's notification`() {
        assertEquals(false, FallNotificationPolicy.shouldDismiss(showingB, uuidA, 1_000))
        assertEquals(false, FallNotificationPolicy.shouldDismiss(showingB, null, 1_000))
    }

    @Test
    fun `a cancel matching the displayed incident removes it`() {
        assertEquals(true, FallNotificationPolicy.shouldDismiss(showingB, uuidB, null))
        assertEquals(true, FallNotificationPolicy.shouldDismiss(showingB, null, 2_000))
        val legacyShown = DisplayedFallNotification("wear-os-5", uuidA, 5)
        assertEquals(true, FallNotificationPolicy.shouldDismiss(legacyShown, uuidA, null))
    }

    @Test
    fun `legacy untargeted cancels always dismiss, unknown display is kept`() {
        assertEquals(true, FallNotificationPolicy.shouldDismiss(showingB, null, null))
        assertEquals(true, FallNotificationPolicy.shouldDismiss(null, null, null))
        assertEquals(false, FallNotificationPolicy.shouldDismiss(null, uuidA, null))
    }

    @Test
    fun `displayed notification round trips`() {
        val shown = DisplayedFallNotification("wear-os-5", null, 5)
        assertEquals(shown, FallNotificationPolicy.decode(FallNotificationPolicy.encode(shown)))
        assertEquals(showingB, FallNotificationPolicy.decode(FallNotificationPolicy.encode(showingB)))
        assertEquals(null, FallNotificationPolicy.decode("bad"))
    }
}
