package com.fallguardian

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AlertPresentationAccessTest {
    @Test
    fun preAndroid13DoesNotRequireNotificationRuntimePermission() {
        assertNull(alertPresentationIssue(32, false, false))
    }

    @Test
    fun android13ReportsDisabledNotifications() {
        assertEquals(
            AlertPresentationIssue.NOTIFICATIONS_DISABLED,
            alertPresentationIssue(33, false, false)
        )
    }

    @Test
    fun android14ReportsDisabledFullScreenAccess() {
        assertEquals(
            AlertPresentationIssue.FULL_SCREEN_DISABLED,
            alertPresentationIssue(34, true, false)
        )
    }

    @Test
    fun allRequiredAccessGrantedHasNoIssue() {
        assertNull(alertPresentationIssue(34, true, true))
    }
}
