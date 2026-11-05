package com.example.deploypulse;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Clock;
import java.time.Instant;
import java.util.Map;

/**
 * Spring configuration that exposes the runtime environment map, UTC clock,
 * and application start-time as injectable beans.
 */
@Configuration
public class AppConfig {

    /** Exposes the process environment variables as a bean. */
    @Bean
    public Map<String, String> env() {
        return System.getenv();
    }

    /** UTC clock used for all time computations. */
    @Bean
    public Clock clock() {
        return Clock.systemUTC();
    }

    /**
     * Captured once at startup; used by {@link InfoService} to compute uptime.
     */
    @Bean
    public Instant startTime() {
        return Instant.now();
    }
}

