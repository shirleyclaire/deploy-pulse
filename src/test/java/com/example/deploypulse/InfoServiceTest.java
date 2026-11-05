package com.example.deploypulse;

import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class InfoServiceTest {

    private static final Instant START = Instant.parse("2024-01-01T00:00:00Z");

    // Clock fixed 3725 seconds after START
    private static final Clock FIXED_CLOCK =
            Clock.fixed(START.plusSeconds(3725), ZoneOffset.UTC);

    @Test
    void allEnvKeysPresent_fieldsMatch() {
        Map<String, String> env = Map.of(
                "APP_VERSION",   "1.2.3",
                "GIT_SHA",       "abc1234",
                "BUILD_TIME",    "2024-01-01T00:00:00Z",
                "POD_NAME",      "my-pod",
                "POD_NAMESPACE", "production",
                "NODE_NAME",     "node-1"
        );

        InfoService service = new InfoService(env, FIXED_CLOCK, START);
        AppInfo info = service.getInfo();

        assertEquals("Deploy Pulse",                      info.appName());
        assertEquals("Deploy Pulse v1 - pipeline works", info.message());
        assertEquals("1.2.3",                            info.version());
        assertEquals("abc1234",                          info.gitSha());
        assertEquals("2024-01-01T00:00:00Z",             info.buildTime());
        assertEquals("my-pod",                           info.podName());
        assertEquals("production",                       info.namespace());
        assertEquals("node-1",                           info.nodeName());
    }

    @Test
    void emptyEnvMap_allEnvDerivedFieldsAreUnknown() {
        InfoService service = new InfoService(Map.of(), FIXED_CLOCK, START);
        AppInfo info = service.getInfo();

        assertEquals("unknown", info.version());
        assertEquals("unknown", info.gitSha());
        assertEquals("unknown", info.buildTime());
        assertEquals("unknown", info.podName());
        assertEquals("unknown", info.namespace());
        assertEquals("unknown", info.nodeName());
    }

    @Test
    void blankEnvValues_treatedAsUnknown() {
        Map<String, String> env = new HashMap<>();
        env.put("APP_VERSION",   "  ");   // blank
        env.put("GIT_SHA",       "");     // empty
        // rest absent

        InfoService service = new InfoService(env, FIXED_CLOCK, START);
        AppInfo info = service.getInfo();

        assertEquals("unknown", info.version());
        assertEquals("unknown", info.gitSha());
    }

    @Test
    void uptimeSeconds_correctUsingFixedClock() {
        // FIXED_CLOCK is 3725 seconds after START
        InfoService service = new InfoService(Map.of(), FIXED_CLOCK, START);
        AppInfo info = service.getInfo();

        assertEquals(3725L, info.uptimeSeconds());
        assertEquals("1h 2m 5s", info.uptime());
    }

    @Test
    void uptimeSeconds_zeroWhenStartEqualsNow() {
        Clock zeroClock = Clock.fixed(START, ZoneOffset.UTC);
        InfoService service = new InfoService(Map.of(), zeroClock, START);
        AppInfo info = service.getInfo();

        assertEquals(0L, info.uptimeSeconds());
        assertEquals("0h 0m 0s", info.uptime());
    }
}

