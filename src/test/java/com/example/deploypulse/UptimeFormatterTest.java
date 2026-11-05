package com.example.deploypulse;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class UptimeFormatterTest {

    @Test
    void fiveSeconds() {
        assertEquals("0h 0m 5s", UptimeFormatter.format(5));
    }

    @Test
    void sixtyFiveSeconds() {
        assertEquals("0h 1m 5s", UptimeFormatter.format(65));
    }

    @Test
    void threeThousandSevenHundredTwentyFiveSeconds() {
        // 3725s = 1h 2m 5s
        assertEquals("1h 2m 5s", UptimeFormatter.format(3725));
    }

    @Test
    void zeroSeconds() {
        assertEquals("0h 0m 0s", UptimeFormatter.format(0));
    }

    @Test
    void largeValueDoesNotRollIntoDays() {
        // 90061s = 25h 1m 1s — hours must NOT wrap into days
        assertEquals("25h 1m 1s", UptimeFormatter.format(90061));
    }
}

