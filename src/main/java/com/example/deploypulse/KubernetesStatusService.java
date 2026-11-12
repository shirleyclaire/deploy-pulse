package com.example.deploypulse;

import io.fabric8.kubernetes.api.model.ContainerStatus;
import io.fabric8.kubernetes.api.model.Pod;
import io.fabric8.kubernetes.api.model.PodStatus;
import io.fabric8.kubernetes.api.model.apps.Deployment;
import io.fabric8.kubernetes.client.KubernetesClientException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

@Service
public class KubernetesStatusService {

    private static final Logger LOGGER = LoggerFactory.getLogger(KubernetesStatusService.class);
    private static final String DEPLOYMENT_NAME = "deploy-pulse";
    private static final String POD_LABEL_KEY = "app";
    private static final String POD_LABEL_VALUE = "deploy-pulse";
    private static final Pattern HEX_COLOR = Pattern.compile("^#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?$");

    private final KubernetesResourceReader resourceReader;
    private final Map<String, String> env;
    private final Clock clock;

    public KubernetesStatusService(
            KubernetesResourceReader resourceReader,
            Map<String, String> env,
            Clock clock
    ) {
        this.resourceReader = resourceReader;
        this.env = env;
        this.clock = clock;
    }

    public KubernetesStatus getStatus() {
        String namespace = resolve("POD_NAMESPACE", resolve("KUBERNETES_NAMESPACE", "deploy-pulse"));
        String gitSha = resolve("GIT_SHA", "unknown");
        String appTitle = resolve("APP_TITLE", "Deploy Pulse");
        String cloudName = resolve("CLOUD_NAME", "Kubernetes");
        String accentColor = resolveAccentColor();

        try {
            Deployment deployment = resourceReader.getDeployment(namespace, DEPLOYMENT_NAME);
            Instant now = clock.instant();
            List<KubernetesStatus.PodStatus> pods = resourceReader
                    .listPods(namespace, POD_LABEL_KEY, POD_LABEL_VALUE)
                    .stream()
                    .map(pod -> toPodStatus(pod, now))
                    .sorted(Comparator.comparing(KubernetesStatus.PodStatus::name))
                    .toList();

            if (deployment == null) {
                return new KubernetesStatus(
                        true,
                        false,
                        "Deployment '" + DEPLOYMENT_NAME + "' was not found in namespace '" + namespace + "'.",
                        gitSha,
                        null,
                        "unknown",
                        cloudName,
                        appTitle,
                        accentColor,
                        pods
                );
            }

            return new KubernetesStatus(
                    true,
                    true,
                    "Kubernetes status loaded from namespace '" + namespace + "'.",
                    gitSha,
                    replicaCounts(deployment),
                    imageTag(deployment),
                    cloudName,
                    appTitle,
                    accentColor,
                    pods
            );
        } catch (KubernetesClientException exception) {
            LOGGER.warn("Could not retrieve Kubernetes status in namespace {}: {}", namespace, exception.getMessage());
            return new KubernetesStatus(
                    false,
                    false,
                    "Kubernetes API is unavailable for namespace '" + namespace + "'.",
                    gitSha,
                    null,
                    "unknown",
                    cloudName,
                    appTitle,
                    accentColor,
                    List.of()
            );
        }
    }

    private KubernetesStatus.ReplicaCounts replicaCounts(Deployment deployment) {
        int desired = deployment.getSpec() == null || deployment.getSpec().getReplicas() == null
                ? 1
                : deployment.getSpec().getReplicas();
        int ready = deployment.getStatus() == null || deployment.getStatus().getReadyReplicas() == null
                ? 0
                : deployment.getStatus().getReadyReplicas();
        int available = deployment.getStatus() == null || deployment.getStatus().getAvailableReplicas() == null
                ? 0
                : deployment.getStatus().getAvailableReplicas();
        return new KubernetesStatus.ReplicaCounts(desired, ready, available);
    }

    private String imageTag(Deployment deployment) {
        if (deployment.getSpec() == null
                || deployment.getSpec().getTemplate() == null
                || deployment.getSpec().getTemplate().getSpec() == null
                || deployment.getSpec().getTemplate().getSpec().getContainers() == null) {
            return "unknown";
        }
        return deployment.getSpec().getTemplate().getSpec().getContainers().stream()
                .filter(container -> DEPLOYMENT_NAME.equals(container.getName()))
                .findFirst()
                .or(() -> deployment.getSpec().getTemplate().getSpec().getContainers().stream().findFirst())
                .map(container -> tagFromImage(container.getImage()))
                .orElse("unknown");
    }

    private String tagFromImage(String image) {
        if (image == null || image.isBlank()) {
            return "unknown";
        }
        int lastSlash = image.lastIndexOf('/');
        int lastColon = image.lastIndexOf(':');
        if (lastColon > lastSlash && lastColon < image.length() - 1) {
            return image.substring(lastColon + 1);
        }
        return image.contains("@") ? image.substring(image.indexOf('@') + 1) : "latest";
    }

    private KubernetesStatus.PodStatus toPodStatus(Pod pod, Instant now) {
        String name = pod.getMetadata() == null || pod.getMetadata().getName() == null
                ? "unknown"
                : pod.getMetadata().getName();
        String node = pod.getSpec() == null || pod.getSpec().getNodeName() == null
                ? "unknown"
                : pod.getSpec().getNodeName();
        PodStatus podStatus = pod.getStatus();
        String status = podPhase(podStatus);
        String creationTimestamp = pod.getMetadata() == null ? null : pod.getMetadata().getCreationTimestamp();
        return new KubernetesStatus.PodStatus(
                name,
                status,
                node,
                formatAge(creationTimestamp, now),
                name.equals(env.get("POD_NAME"))
        );
    }

    private String podPhase(PodStatus podStatus) {
        if (podStatus == null) {
            return "Unknown";
        }
        if (podStatus.getContainerStatuses() != null) {
            for (ContainerStatus containerStatus : podStatus.getContainerStatuses()) {
                if (containerStatus.getState() != null) {
                    if (containerStatus.getState().getWaiting() != null
                            && containerStatus.getState().getWaiting().getReason() != null) {
                        return containerStatus.getState().getWaiting().getReason();
                    }
                    if (containerStatus.getState().getTerminated() != null
                            && containerStatus.getState().getTerminated().getReason() != null) {
                        return containerStatus.getState().getTerminated().getReason();
                    }
                }
            }
        }
        return podStatus.getPhase() == null ? "Unknown" : podStatus.getPhase();
    }

    private String formatAge(String creationTimestamp, Instant now) {
        if (creationTimestamp == null || creationTimestamp.isBlank()) {
            return "unknown";
        }
        try {
            long seconds = Math.max(0, Duration.between(Instant.parse(creationTimestamp), now).getSeconds());
            long days = seconds / 86_400;
            long hours = (seconds % 86_400) / 3_600;
            long minutes = (seconds % 3_600) / 60;
            if (days > 0) {
                return days + "d " + hours + "h";
            }
            if (hours > 0) {
                return hours + "h " + minutes + "m";
            }
            if (minutes > 0) {
                return minutes + "m";
            }
            return seconds + "s";
        } catch (DateTimeParseException exception) {
            return "unknown";
        }
    }

    private String resolveAccentColor() {
        String value = env.get("ACCENT_COLOR");
        return value != null && HEX_COLOR.matcher(value).matches() ? value : "#58a6ff";
    }

    private String resolve(String key, String fallback) {
        String value = env.get(key);
        return value == null || value.isBlank() ? fallback : value;
    }
}
