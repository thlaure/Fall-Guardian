package com.fallguardian

enum class AlertPresentationIssue {
    NOTIFICATIONS_DISABLED,
    FULL_SCREEN_DISABLED
}

fun alertPresentationIssue(
    sdkInt: Int,
    notificationsGranted: Boolean,
    fullScreenGranted: Boolean
): AlertPresentationIssue? {
    if (sdkInt >= 33 && !notificationsGranted) {
        return AlertPresentationIssue.NOTIFICATIONS_DISABLED
    }
    if (sdkInt >= 34 && !fullScreenGranted) {
        return AlertPresentationIssue.FULL_SCREEN_DISABLED
    }
    return null
}
