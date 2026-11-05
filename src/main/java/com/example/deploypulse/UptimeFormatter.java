package com.example.deploypulse;

/**
 * Formats a duration expressed in seconds as {@code Xh Ym Zs}.
 * Hours never roll into days (e.g. 25h 0m 0s is valid output).
 */
public class UptimeFormatter {

    private UptimeFormatter() {}

    /**
     * Converts {@code totalSeconds} into a human-readable string.
     *
     * @param totalSeconds total elapsed seconds (non-negative)
     * @return formatted string such as {@code "0h 0m 5s"} or {@code "2h 3m 4s"}
     */
    public static String format(long totalSeconds) {
        long seconds = totalSeconds % 60;
        long totalMinutes = totalSeconds / 60;
        long minutes = totalMinutes % 60;
        long hours = totalMinutes / 60;
        return hours + "h " + minutes + "m " + seconds + "s";
    }
}

