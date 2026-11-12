package com.example.deploypulse;

import java.util.List;

public record KubernetesStatus(
        boolean apiAvailable,
        boolean deploymentFound,
        String message,
        String gitSha,
        ReplicaCounts replicas,
        String imageTag,
        String cloudName,
        String appTitle,
        String accentColor,
        List<PodStatus> pods
) {
    public record ReplicaCounts(int desired, int ready, int available) {}

    public record PodStatus(String name, String status, String node, String age, boolean serving) {}
}
