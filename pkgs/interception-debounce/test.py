"""Drive the debounce binary with timed event streams and check what comes out.

Events are stamped with the wall clock when they are written, like evdev does,
and the gaps are real sleeps, so the binary's own window timer is exercised.
Window is 30 ms; the gaps here stay well clear of it either way.

usage: python3 test.py path/to/debounce
"""
import os
import struct
import subprocess
import sys
import time

EV_SYN, EV_KEY, EV_MSC = 0, 1, 4
SYN_REPORT, MSC_SCAN = 0, 4
KEY_A, KEY_B = 30, 48
FMT = "qqHHi"
SIZE = struct.calcsize(FMT)
DOWN, UP, REPEAT = 1, 0, 2


def run(binary, script):
    """script: list of (sleep_ms, code, value); returns [(code, value)] out."""
    p = subprocess.Popen([binary, "-t", "30", "-n", "100", "-k"],
                         stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    for sleep_ms, code, value in script:
        time.sleep(sleep_ms / 1000)
        t = time.time()
        s, us = int(t), int((t - int(t)) * 1e6)
        frame = struct.pack(FMT, s, us, EV_MSC, MSC_SCAN, 0x70000 + code)
        frame += struct.pack(FMT, s, us, EV_KEY, code, value)
        frame += struct.pack(FMT, s, us, EV_SYN, SYN_REPORT, 0)
        os.write(p.stdin.fileno(), frame)
    time.sleep(0.2)  # let any open window close
    p.stdin.close()
    data = p.stdout.read()
    assert p.wait() == 0, "debounce exited non-zero"
    out = []
    for i in range(0, len(data), SIZE):
        _, _, typ, code, value = struct.unpack(FMT, data[i:i + SIZE])
        if typ == EV_KEY:
            out.append((code, value))
    return out


CASES = {
    "release chatter is dropped": (
        [(0, KEY_A, DOWN), (100, KEY_A, UP), (5, KEY_A, DOWN), (5, KEY_A, UP)],
        [(KEY_A, DOWN), (KEY_A, UP)],
    ),
    "press bounce is dropped": (
        [(0, KEY_A, DOWN), (3, KEY_A, UP), (3, KEY_A, DOWN), (100, KEY_A, UP)],
        [(KEY_A, DOWN), (KEY_A, UP)],
    ),
    "release inside the window is delayed, not lost": (
        [(0, KEY_A, DOWN), (10, KEY_A, UP)],
        [(KEY_A, DOWN), (KEY_A, UP)],
    ),
    "a real re-press inside the window is delayed, not lost": (
        [(0, KEY_A, DOWN), (100, KEY_A, UP), (15, KEY_A, DOWN), (100, KEY_A, UP)],
        [(KEY_A, DOWN), (KEY_A, UP), (KEY_A, DOWN), (KEY_A, UP)],
    ),
    "plain typing passes untouched": (
        [(0, KEY_A, DOWN), (100, KEY_A, UP), (100, KEY_A, DOWN), (100, KEY_A, UP)],
        [(KEY_A, DOWN), (KEY_A, UP), (KEY_A, DOWN), (KEY_A, UP)],
    ),
    "keys have separate windows": (
        [(0, KEY_A, DOWN), (5, KEY_B, DOWN), (100, KEY_A, UP), (5, KEY_B, UP),
         (5, KEY_A, DOWN), (5, KEY_A, UP)],
        [(KEY_A, DOWN), (KEY_B, DOWN), (KEY_A, UP), (KEY_B, UP)],
    ),
    "autorepeat only for keys reported down": (
        [(0, KEY_A, DOWN), (100, KEY_A, REPEAT), (10, KEY_A, UP), (5, KEY_A, REPEAT)],
        [(KEY_A, DOWN), (KEY_A, REPEAT), (KEY_A, UP)],
    ),
}


def main():
    binary = sys.argv[1]
    failed = 0
    for name, (script, want) in CASES.items():
        got = run(binary, script)
        ok = got == want
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name}" + ("" if ok else f": got {got}, want {want}"))
    sys.exit(1 if failed else 0)


main()
