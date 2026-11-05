package com.example.deploypulse;

import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/**
 * Builds an {@link AppInfo} snapshot from environment variables, a {@link Clock},
 * and the application {@link Instant startTime}.
 *
 * <p>All constructor parameters are injected so the class is fully testable
 * without touching real environment variables or real wall-clock time.</p>
 */
@Service
public class InfoService {

    private static final String APP_NAME = "Deploy Pulse";
    private static final String MESSAGE   = "Deploy Pulse v1 - pipeline works";

    private static final DateTimeFormatter ISO_FORMATTER =
            DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'")
                             .withZone(ZoneOffset.UTC);

    private final Map<String, String> env;
    private final Clock               clock;
    private final Instant             startTime;

    public InfoService(Map<String, String> env, Clock clock, Instant startTime) {
        this.env       = env;
        this.clock     = clock;
        this.startTime = startTime;
    }

    /**
     * Returns a fresh {@link AppInfo} snapshot computed at the moment of the call.
     */
    public AppInfo getInfo() {
        Instant now          = Instant.now(clock);
        long    uptimeSecs   = now.getEpochSecond() - startTime.getEpochSecond();

        return new AppInfo(
                APP_NAME,
                MESSAGE,
                resolve("APP_VERSION"),
                resolve("GIT_SHA"),
                resolve("BUILD_TIME"),
                resolve("POD_NAME"),
                resolve("POD_NAMESPACE"),
                resolve("NODE_NAME"),
                UptimeFormatter.format(uptimeSecs),
                uptimeSecs,
                ISO_FORMATTER.format(now)
        );
    }

    // Returns the env value, or "unknown" if absent or blank.
    private String resolve(String key) {
        String value = env.get(key);
        return (value != null && !value.isBlank()) ? value : "unknown";
    }
}

