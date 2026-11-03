/*
 * debounce - interception-tools plugin that filters key chatter
 *
 *   intercept -g $DEVNODE | debounce [-t ms] [-n ms] [-k] [-q] | uinput -d $DEVNODE
 *
 * Eager per-key debounce. A key's first change of state (press or release)
 * goes through at once. Further changes to that key in the next <window> ms
 * are held back. When the window closes, the key's current physical state is
 * emitted if it differs from what was last sent. So:
 *
 *   - a bounce that settles inside the window (release, spurious press,
 *     spurious release) is dropped entirely;
 *   - no transition is ever lost: a real change that happens inside the
 *     window is only delayed until the window closes. That means a key
 *     cannot get stuck down.
 *
 * Presses add no latency. Only a change that comes less than <window> ms
 * after the key's previous change is delayed.
 *
 * Diagnostics go to stderr (the journal under udevmon). Key codes are left
 * out unless -k is given, so the log does not record what was typed.
 */
#include <errno.h>
#include <linux/input.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static int64_t window_us = 30000;
static int64_t near_us = 0;
static int log_codes = 0;
static int quiet = 0;

static uint8_t logical[KEY_CNT]; /* last state written downstream */
static uint8_t raw[KEY_CNT];     /* last state read from the device */
static uint8_t pending[KEY_CNT]; /* raw may differ from logical; recheck at window end */
static int64_t last[KEY_CNT];    /* time of the last change written downstream (us) */

static int64_t ev_us(const struct input_event *e) {
    return (int64_t)e->input_event_sec * 1000000 + e->input_event_usec;
}

/* evdev stamps events with CLOCK_REALTIME unless asked otherwise, and
 * intercept doesn't ask, so the windows are measured on that clock too. */
static int64_t now_us(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

static void put(const struct input_event *e) {
    const char *p = (const char *)e;
    size_t n = sizeof *e;
    while (n) {
        ssize_t w = write(STDOUT_FILENO, p, n);
        if (w < 0) {
            if (errno == EINTR)
                continue;
            exit(EXIT_FAILURE);
        }
        p += w;
        n -= (size_t)w;
    }
}

static void emit(uint16_t type, uint16_t code, int32_t value, int64_t t) {
    struct input_event e;
    memset(&e, 0, sizeof e);
    e.input_event_sec = t / 1000000;
    e.input_event_usec = t % 1000000;
    e.type = type;
    e.code = code;
    e.value = value;
    put(&e);
}

static void note(const char *what, unsigned code, int value, int64_t dt) {
    if (quiet)
        return;
    if (log_codes)
        fprintf(stderr, "debounce: %s %s of key %u, %.1f ms after its last change\n",
                what, value ? "press" : "release", code, dt / 1000.0);
    else
        fprintf(stderr, "debounce: %s %s, %.1f ms after the key's last change\n",
                what, value ? "press" : "release", dt / 1000.0);
}

/* A window has closed if <window> has passed, or if the clock went backwards
 * (a step of the wall clock); closing early is harmless, closing late isn't. */
static int closed(unsigned c, int64_t now) {
    return now - last[c] >= window_us || now < last[c];
}

/* Emit the state of every key whose window has closed and whose physical state
 * differs from what was last sent. Call only between frames. */
static void settle(int64_t now) {
    int any = 0;
    for (unsigned c = 0; c < KEY_CNT; ++c) {
        if (!pending[c] || !closed(c, now))
            continue;
        pending[c] = 0;
        if (raw[c] == logical[c])
            continue;
        note("late", c, raw[c], now - last[c]);
        emit(EV_KEY, (uint16_t)c, raw[c], now);
        logical[c] = raw[c];
        last[c] = now;
        any = 1;
    }
    if (any)
        emit(EV_SYN, SYN_REPORT, 0, now);
}

/* poll timeout (ms) until the next window closes, -1 if none is open */
static int next_timeout(int64_t now) {
    int64_t best = -1;
    for (unsigned c = 0; c < KEY_CNT; ++c) {
        if (!pending[c])
            continue;
        int64_t left = closed(c, now) ? 0 : last[c] + window_us - now;
        if (best < 0 || left < best)
            best = left;
    }
    return best < 0 ? -1 : (int)((best + 999) / 1000);
}

static void key(const struct input_event *e) {
    unsigned c = e->code;
    int64_t t = ev_us(e);

    if (e->value == 2) { /* kernel autorepeat: only for keys we report as down */
        if (logical[c])
            put(e);
        return;
    }
    if (e->value != 0 && e->value != 1) {
        put(e);
        return;
    }

    raw[c] = (uint8_t)e->value;
    if (raw[c] == logical[c]) {
        /* back where we were: whatever happened in between was a bounce */
        pending[c] = 0;
        return;
    }

    int64_t dt = t - last[c];
    if (dt >= 0 && dt < window_us) {
        pending[c] = 1;
        note("held", c, e->value, dt);
        return;
    }

    if (near_us && e->value == 1 && dt >= 0 && dt < near_us)
        note("passed", c, e->value, dt);
    pending[c] = 0;
    logical[c] = raw[c];
    last[c] = t;
    put(e);
}

static void usage(FILE *f, const char *argv0) {
    fprintf(f,
            "debounce - filter key chatter (interception-tools plugin)\n"
            "\n"
            "usage: %s [-h] [-t ms] [-n ms] [-k] [-q]\n"
            "\n"
            "options:\n"
            "    -h     show this message and exit\n"
            "    -t ms  debounce window per key (default 30)\n"
            "    -n ms  also log presses that pass less than ms after the\n"
            "           key's last change, for tuning -t (default off)\n"
            "    -k     include key codes in the log\n"
            "    -q     log nothing\n",
            argv0);
}

static int64_t ms_arg(const char *s, const char *argv0) {
    char *end;
    double v = strtod(s, &end);
    if (*s == '\0' || *end != '\0' || v < 0 || v > 10000) {
        usage(stderr, argv0);
        exit(EXIT_FAILURE);
    }
    return (int64_t)(v * 1000);
}

int main(int argc, char *argv[]) {
    for (int opt; (opt = getopt(argc, argv, "ht:n:kq")) != -1;) {
        switch (opt) {
        case 'h':
            usage(stdout, argv[0]);
            return EXIT_SUCCESS;
        case 't':
            window_us = ms_arg(optarg, argv[0]);
            continue;
        case 'n':
            near_us = ms_arg(optarg, argv[0]);
            continue;
        case 'k':
            log_codes = 1;
            continue;
        case 'q':
            quiet = 1;
            continue;
        }
        usage(stderr, argv[0]);
        return EXIT_FAILURE;
    }
    if (optind != argc) {
        usage(stderr, argv[0]);
        return EXIT_FAILURE;
    }
    setvbuf(stderr, NULL, _IOLBF, 0);

    unsigned char buf[sizeof(struct input_event)];
    size_t have = 0;
    int in_frame = 0;

    for (;;) {
        struct pollfd p = {.fd = STDIN_FILENO, .events = POLLIN};
        int r = poll(&p, 1, in_frame ? -1 : next_timeout(now_us()));
        if (r < 0) {
            if (errno == EINTR)
                continue;
            perror("debounce: poll");
            return EXIT_FAILURE;
        }
        if (r == 0) {
            settle(now_us());
            continue;
        }

        ssize_t n = read(STDIN_FILENO, buf + have, sizeof buf - have);
        if (n == 0)
            return EXIT_SUCCESS;
        if (n < 0) {
            if (errno == EINTR || errno == EAGAIN)
                continue;
            perror("debounce: read");
            return EXIT_FAILURE;
        }
        have += (size_t)n;
        if (have < sizeof buf)
            continue;
        have = 0;

        struct input_event e;
        memcpy(&e, buf, sizeof e);

        if (e.type == EV_KEY && e.code < KEY_CNT) {
            in_frame = 1;
            key(&e);
        } else {
            put(&e);
            if (e.type == EV_SYN && e.code == SYN_REPORT) {
                in_frame = 0;
                settle(now_us());
            } else if (e.type != EV_SYN) {
                in_frame = 1;
            }
        }
    }
}
