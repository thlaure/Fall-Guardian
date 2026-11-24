#!/usr/bin/env python3
"""Regenerates the synthetic accelerometer traces used by FallTraceReplayTest.

The traces are hand-shaped approximations of wrist motion at 25 Hz, written in
the exact CSV format exported by the watch diagnostics (FallDiagnosticSample).
They are MODEL-GENERATED regression fixtures, NOT real recordings, and do
not validate real-world detection accuracy. Real labelled recordings can be dropped into
app/src/test/resources/traces/ next to them (see the README section
"Replay traces").

Usage: python3 scripts/generate_synthetic_traces.py
"""
import math
import os
import random

G = 9.81
DT_MS = 40  # 25 Hz, matching AccelerometerPlan.SAMPLING_PERIOD_US
HEADER = (
    "wall_ms,sensor_elapsed_ms,delivery_elapsed_ms,ax_ms2,ay_ms2,az_ms2,"
    "interactive,detected,alert_dispatched,low_threshold_g,impact_threshold_g,"
    "orientation_threshold_deg,low_minimum_ms,impact_seen,low_qualified,"
    "orientation_qualified,orientation_deg,stillness_ms,candidate_age_ms,"
    "candidate_expired"
)
OUT = os.path.join(os.path.dirname(__file__), "..", "app", "src", "test", "resources", "traces")


def lerp(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def noisy(v, sigma, rnd):
    return tuple(x + rnd.gauss(0, sigma) for x in v)


def write(name, samples):
    wall0, elapsed0 = 1_763_700_000_000, 5_000_000
    path = os.path.join(OUT, name)
    with open(path, "w") as f:
        f.write(HEADER + "\n")
        for i, (ax, ay, az) in enumerate(samples):
            t = i * DT_MS
            # Detector/state columns are left neutral: the replay test
            # recomputes detection from raw acceleration only.
            f.write(
                f"{wall0 + t},{elapsed0 + t},{elapsed0 + t + 120},"
                f"{ax:.3f},{ay:.3f},{az:.3f},false,false,false,"
                "0.35,4.2,80.0,160,false,false,false,0.0,0,0,false\n"
            )


def hold(vec, seconds, sigma, rnd):
    return [noisy(vec, sigma, rnd) for _ in range(int(seconds * 1000 / DT_MS))]


def walking(seconds, rnd, phase=0.0):
    out = []
    for i in range(int(seconds * 1000 / DT_MS)):
        t = i * DT_MS / 1000.0
        swing = math.radians(35) * math.sin(2 * math.pi * 0.9 * t + phase)
        bounce = 3.0 * math.sin(2 * math.pi * 1.8 * t)
        mag = G + bounce
        out.append(noisy((mag * math.sin(swing), 0.4, mag * math.cos(swing)), 0.4, rnd))
    return out


def fall(rnd, final, low_samples):
    s = walking(3.0, rnd)
    # Loss of balance: near weightless for low_samples * 40 ms.
    s += [noisy((0.6, 0.3, 1.0), 0.25, rnd) for _ in range(low_samples)]
    # Impact: two-sample spike above 4.2 g, then rebound.
    s += [noisy((28.0, 9.0, 36.0), 1.0, rnd), noisy((-14.0, 6.0, 22.0), 1.0, rnd)]
    # Tumble towards the final lying posture.
    start = (2.0, 1.0, 8.0)
    for k in range(10):
        t = (k + 1) / 10.0
        v = lerp(start, final, t)
        s.append(noisy(tuple(x * (1.0 + 0.5 * math.sin(k)) for x in v), 0.8, rnd))
    s += hold(final, 6.0, 0.06, rnd)
    return s


def main():
    os.makedirs(OUT, exist_ok=True)
    rnd = random.Random(20261121)
    write("synthetic-fall-forward.csv", fall(rnd, (9.70, 0.50, 1.10), low_samples=7))
    write("synthetic-fall-sideways.csv", fall(rnd, (-0.60, -9.70, 1.20), low_samples=5))

    # Sitting down hard: partial unloading (0.5 g), 3.2 g landing, wrist
    # rotates ~35 degrees onto the thigh, then rests.
    sit = walking(3.0, rnd)
    sit += [noisy((0.8, 0.2, 4.5), 0.2, rnd) for _ in range(4)]
    sit += [noisy((8.0, 2.0, 30.0), 0.8, rnd), noisy((4.0, 1.0, 16.0), 0.8, rnd)]
    seated = (G * math.sin(math.radians(35)), 0.3, G * math.cos(math.radians(35)))
    sit += hold(seated, 6.0, 0.06, rnd)
    write("synthetic-sit-down-hard.csv", sit)

    # Table bump: watch flat on a table, a fist hits the table once.
    flat = (0.05, 0.08, G)
    bump = hold(flat, 3.0, 0.02, rnd)
    bump += [(6.0, 3.0, 60.0), (-2.0, -1.0, 2.0), (1.0, 0.5, 15.0)]
    bump += hold(flat, 5.0, 0.02, rnd)
    write("synthetic-table-bump.csv", bump)

    write("synthetic-walking.csv", walking(12.0, rnd, phase=0.4))


if __name__ == "__main__":
    main()
