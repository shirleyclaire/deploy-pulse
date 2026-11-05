package com.example.deploypulse;

/**
 * Immutable record carrying all deployment-metadata fields returned by the /api/info endpoint.
 */
public record AppInfo(
        String appName,
        String message,
        String version,
        String gitSha,
        String buildTime,
        String podName,
        String namespace,
        String nodeName,
        String uptime,
        long   uptimeSeconds,
        String serverTime
) {}

