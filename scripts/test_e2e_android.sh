#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Fall Guardian — Android/Wear OS end-to-end test script
#
# What it tests:
#   1. Wear simulated fall propagates to the Android phone app
#   2. Watch-side cancel propagates back to the phone
#   3. Phone-side cancel propagates to the watch
#   4. 30-second timeout reaches the SMS code path on the phone
#
# Trigger mechanism:
#   - Wear debug receiver:
#       com.fallguardian.debug.SIMULATE_FALL
#       com.fallguardian.debug.CANCEL_ALERT
#   - Phone debug receiver:
#       com.fallguardian.debug.CANCEL_ALERT_TO_WATCH
#
# Prerequisites:
#   - Android phone emulator booted
#   - Wear OS emulator booted
#   - Apps installed (run `make run-android-debug` and `make run-wear` first)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ADB="${HOME}/Library/Android/sdk/platform-tools/adb"
ANDROID_DEVICE="$($ADB devices -l 2>/dev/null | grep sdk_gphone | awk '{print $1}' | head -n1)"
WEAR_DEVICE="$($ADB devices -l 2>/dev/null | grep sdk_gwear | awk '{print $1}' | head -n1)"
PHONE_PACKAGE="com.fallguardian"
PHONE_ACTIVITY="com.fallguardian/.MainActivity"
WEAR_PACKAGE="com.fallguardian"
WEAR_ACTIVITY="com.fallguardian/.MainActivity"

PASS=0
FAIL=0

log()  { echo "[$(date +%H:%M:%S)] $*"; }
pass() { echo "  ✅ PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $*"; FAIL=$((FAIL+1)); }

ensure_devices() {
    if [ -z "$ANDROID_DEVICE" ] || [ -z "$WEAR_DEVICE" ]; then
        echo "Android phone or Wear emulator not detected."
        echo "Detected phone serial: ${ANDROID_DEVICE:-<none>}"
        echo "Detected wear serial:  ${WEAR_DEVICE:-<none>}"
        exit 1
    fi
}

_LOG_PID=""
_LOG_FILE=""

start_log_stream() {
    local serial="$1"
    _LOG_FILE=$(mktemp)
    "$ADB" -s "$serial" logcat -c
    "$ADB" -s "$serial" logcat -v brief >"$_LOG_FILE" 2>&1 &
    _LOG_PID=$!
    sleep 1
}

stop_log_stream() {
    kill "$_LOG_PID" 2>/dev/null || true
    rm -f "$_LOG_FILE"
    _LOG_PID=""
    _LOG_FILE=""
}

wait_for_pattern() {
    local pattern="$1" timeout="$2"
    local elapsed=0
    while [ $elapsed -lt "$timeout" ]; do
        if grep -Eq "$pattern" "$_LOG_FILE" 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed+1))
    done
    return 1
}

relaunch() {
    log "Relaunching Android and Wear apps..."
    "$ADB" -s "$ANDROID_DEVICE" shell am force-stop "$PHONE_PACKAGE" >/dev/null 2>&1 || true
    "$ADB" -s "$WEAR_DEVICE" shell am force-stop "$WEAR_PACKAGE" >/dev/null 2>&1 || true
    sleep 1
    "$ADB" -s "$WEAR_DEVICE" shell am start -n "$WEAR_ACTIVITY" >/dev/null
    "$ADB" -s "$ANDROID_DEVICE" shell am start -n "$PHONE_ACTIVITY" >/dev/null
    sleep 4
}

simulate_fall_on_watch() {
    log "Triggering simulated fall on Wear OS..."
    "$ADB" -s "$WEAR_DEVICE" shell am broadcast \
        -a com.fallguardian.debug.SIMULATE_FALL \
        -n com.fallguardian/.DebugAutomationReceiver >/dev/null
}

cancel_on_watch() {
    log "Triggering cancel on Wear OS..."
    "$ADB" -s "$WEAR_DEVICE" shell am broadcast \
        -a com.fallguardian.debug.CANCEL_ALERT \
        -n com.fallguardian/.DebugAutomationReceiver >/dev/null
}

cancel_on_phone() {
    log "Triggering cancel on Android phone..."
    "$ADB" -s "$ANDROID_DEVICE" shell am broadcast \
        -a com.fallguardian.debug.CANCEL_ALERT_TO_WATCH \
        -n com.fallguardian/.DebugAutomationReceiver >/dev/null
}

run_test_1() {
    log "━━ Test 1: Wear fall propagates to Android phone ━━"
    relaunch
    start_log_stream "$ANDROID_DEVICE"
    simulate_fall_on_watch
    if wait_for_pattern "sendFallDetectedToFlutter: timestamp=" 20; then
        pass "Phone received fall event from watch"
    else
        fail "Phone did not receive fall event within 20 s"
    fi
    stop_log_stream
}

run_test_2() {
    log "━━ Test 2: Cancel from watch propagates to Android phone ━━"
    relaunch
    start_log_stream "$ANDROID_DEVICE"
    simulate_fall_on_watch
    sleep 4
    cancel_on_watch
    if wait_for_pattern "sendCancelAlertToFlutter: forwarding cancel to Flutter|pending_alert_cancelled" 20; then
        pass "Phone received cancel from watch"
    else
        fail "Phone did not receive cancel from watch within 20 s"
    fi
    stop_log_stream
}

run_test_3() {
    log "━━ Test 3: Cancel from phone propagates to Wear OS ━━"
    relaunch
    start_log_stream "$WEAR_DEVICE"
    simulate_fall_on_watch
    sleep 4
    cancel_on_phone
    if wait_for_pattern "cancelAlertListener: received /cancel_alert|cancelAlertFromPhone: alertActive=" 20; then
        pass "Watch received cancel from phone"
    else
        fail "Watch did not receive cancel from phone within 20 s"
    fi
    stop_log_stream
}

run_test_4() {
    log "━━ Test 4: Timeout reaches Android SMS path ━━"
    log "  (this test takes ~38 seconds)"
    relaunch
    start_log_stream "$ANDROID_DEVICE"
    simulate_fall_on_watch
    if wait_for_pattern "SmsService.*(Attempting send|No contacts configured|Rate limited|Send reported success|Send failed with exception)" 45; then
        pass "Android timeout reached SMS code path"
    else
        fail "Android timeout did not reach SMS code path within 45 s"
    fi
    stop_log_stream
}

ensure_devices

ONLY_TEST="${2:-}"
if [ "${1:-}" = "--test" ] && [ -n "$ONLY_TEST" ]; then
    "run_test_${ONLY_TEST}"
else
    run_test_1
    run_test_2
    run_test_3
    run_test_4
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[ $FAIL -eq 0 ]
