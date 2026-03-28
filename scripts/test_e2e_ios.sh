#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Fall Guardian — iOS/watchOS end-to-end test script
#
# What it tests (automatically, no human interaction needed):
#   1. Fall simulation: writes a debug trigger file → watchOS app calls simulateFall()
#      → verifies the alert appears on the watch (log check)
#   2. Cancel from watch: triggers fall, writes cancel trigger → verifies the phone
#      receives onAlertCancelled (log check)
#   3. Cancel from phone: triggers fall, writes phone cancel flag → verifies the watch
#      countdown stops (log check)
#   4. Timeout / SMS path: triggers a fall and waits 35 s → verifies SMS send
#      attempt logged (contacts must be configured in the app)
#
# Trigger mechanism (simulator only):
#   watchOS polls /tmp flag files every 500 ms (DEBUG build only):
#     /tmp/com.fallguardian.debugSimulateFall  → calls simulateFall()
#     /tmp/com.fallguardian.debugCancelWatch   → calls cancelAlert()
#   iOS polls /tmp/com.fallguardian.fallEvent every 500 ms for the watch fall event IPC
#   Phone cancel uses the existing IPC file:
#     /tmp/com.fallguardian.cancelAlert        → watch polling detects phone cancelled
#
# Usage:
#   ./scripts/test_e2e_ios.sh             # runs all tests
#   ./scripts/test_e2e_ios.sh --test 1   # runs test 1 only
#
# Prerequisites:
#   - iPhone 17 simulator booted (ID in IOS_DEVICE below)
#   - Apple Watch Series 11 simulator booted (ID in WATCH_DEVICE below)
#   - Both apps already installed (run `make run-ios` first)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

IOS_DEVICE="5A2143B9-4E6E-43F6-A6DA-7A74734C9E69"
WATCH_DEVICE="4167470A-88C3-489C-A4FB-7AA9F695E2CB"
IOS_BUNDLE="com.fallguardian.app"
WATCH_BUNDLE="com.fallguardian.app.watchkitapp"

PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { echo "[$(date +%H:%M:%S)] $*"; }
pass() { echo "  ✅ PASS: $*"; PASS=$((PASS+1)); }
fail() { echo "  ❌ FAIL: $*"; FAIL=$((FAIL+1)); }

# Start a background log stream and store the PID and temp file in globals.
# Call stop_log_stream() when done.
_LOG_PID=""
_LOG_FILE=""

start_log_stream() {
    local device="$1"
    _LOG_FILE=$(mktemp)
    xcrun simctl spawn "$device" log stream --level debug > "$_LOG_FILE" 2>&1 &
    _LOG_PID=$!
    sleep 0.5  # let the stream initialise before triggering actions
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
        if grep -q "$pattern" "$_LOG_FILE" 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed+1))
    done
    return 1
}

# Relaunch both apps cleanly and clear any leftover IPC files.
relaunch() {
    log "Relaunching apps..."
    xcrun simctl terminate "$WATCH_DEVICE" "$WATCH_BUNDLE" 2>/dev/null || true
    xcrun simctl terminate "$IOS_DEVICE"   "$IOS_BUNDLE"   2>/dev/null || true
    rm -f /tmp/com.fallguardian.debugSimulateFall \
          /tmp/com.fallguardian.debugCancelWatch \
          /tmp/com.fallguardian.cancelAlert \
          /tmp/com.fallguardian.cancelFromWatch \
          /tmp/com.fallguardian.fallEvent
    sleep 1
    xcrun simctl launch "$WATCH_DEVICE" "$WATCH_BUNDLE" > /dev/null
    xcrun simctl launch "$IOS_DEVICE"   "$IOS_BUNDLE"   > /dev/null
    sleep 3   # give apps time to initialise WCSession and start polling
}

# Write the debug trigger file that makes the watchOS app call simulateFall().
simulate_fall_on_watch() {
    log "Triggering simulated fall on watch (debug flag file)..."
    echo "trigger" > /tmp/com.fallguardian.debugSimulateFall
}

# Write the debug trigger file that makes the watchOS app call cancelAlert().
cancel_on_watch() {
    log "Cancelling alert from watch (debug flag file)..."
    echo "trigger" > /tmp/com.fallguardian.debugCancelWatch
}

# Write the IPC flag the phone would write when the user taps Cancel.
# Tests the watch's cancel-detection polling (same code path as a real phone cancel).
cancel_on_phone() {
    log "Cancelling alert from phone (IPC flag file)..."
    echo "cancelled" > /tmp/com.fallguardian.cancelAlert
}

# ── Tests ─────────────────────────────────────────────────────────────────────

run_test_1() {
    log "━━ Test 1: Fall simulation triggers alert on watch ━━"
    relaunch
    start_log_stream "$WATCH_DEVICE"
    simulate_fall_on_watch
    if wait_for_pattern "alertDidFire\|isAlertActive\|FallDetected\|debugSimulateFall" 15; then
        pass "Watch alert activated"
    else
        fail "Watch alert did not activate within 15 s"
    fi
    stop_log_stream
}

run_test_2() {
    log "━━ Test 2: Cancel from watch propagates to phone ━━"
    relaunch
    start_log_stream "$IOS_DEVICE"
    simulate_fall_on_watch
    sleep 4   # wait for fall event to propagate to phone
    cancel_on_watch
    if wait_for_pattern "onAlertCancelled\|cancelFromWatch\|flag file found\|cancelAlert" 15; then
        pass "Phone received cancel from watch"
    else
        fail "Phone did not receive cancel from watch within 15 s"
    fi
    stop_log_stream
}

run_test_3() {
    log "━━ Test 3: Cancel from phone propagates to watch ━━"
    relaunch
    start_log_stream "$WATCH_DEVICE"
    simulate_fall_on_watch
    sleep 4   # wait for alert to be active on watch and cancel poll to start
    cancel_on_phone
    if wait_for_pattern "onAlertCancelled\|cancelAlert\|poll: cancelled=true" 15; then
        pass "Watch received cancel from phone"
    else
        fail "Watch did not receive cancel from phone within 15 s"
    fi
    stop_log_stream
}

run_test_4() {
    log "━━ Test 4: 30 s timeout triggers SMS ━━"
    log "  (this test takes ~38 seconds)"
    relaunch
    start_log_stream "$IOS_DEVICE"
    simulate_fall_on_watch
    if wait_for_pattern "sendFallAlert\|SmsService\|sendingSms\|alertSent" 40; then
        pass "SMS send path reached after timeout"
    else
        fail "SMS send path not reached within 40 s"
    fi
    stop_log_stream
}

# ── Main ──────────────────────────────────────────────────────────────────────

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
