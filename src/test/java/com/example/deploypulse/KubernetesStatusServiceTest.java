package com.example.deploypulse;

import io.fabric8.kubernetes.api.model.Container;
import io.fabric8.kubernetes.api.model.ObjectMeta;
import io.fabric8.kubernetes.api.model.Pod;
import io.fabric8.kubernetes.api.model.PodSpec;
import io.fabric8.kubernetes.api.model.PodTemplateSpec;
import io.fabric8.kubernetes.api.model.apps.Deployment;
import io.fabric8.kubernetes.api.model.apps.DeploymentSpec;
import io.fabric8.kubernetes.api.model.apps.DeploymentStatus;
import io.fabric8.kubernetes.client.KubernetesClientException;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class KubernetesStatusServiceTest {

    private static final Instant NOW = Instant.parse("2026-11-12T04:00:00Z");
    private static final String NAMESPACE = "deploy-pulse";

    @Test
    void getStatus_readsReplicasPodsImageAndConfig() {
        KubernetesResourceReader reader = mock(KubernetesResourceReader.class);
        when(reader.getDeployment(NAMESPACE, "deploy-pulse")).thenReturn(deployment());
        when(reader.listPods(NAMESPACE, "app", "deploy-pulse"))
                .thenReturn(List.of(pod("pod-b", "node-2", "2026-11-12T03:30:00Z"),
                                    pod("pod-a", "node-1", "2026-11-12T03:00:00Z")));
        KubernetesStatusService service = service(reader, Map.of(
                "POD_NAMESPACE", NAMESPACE,
                "POD_NAME", "pod-a",
                "GIT_SHA", "abc1234",
                "APP_TITLE", "Cluster Dashboard",
                "ACCENT_COLOR", "#123abc",
                "CLOUD_NAME", "Azure AKS"
        ));

        KubernetesStatus result = service.getStatus();

        assertTrue(result.apiAvailable());
        assertTrue(result.deploymentFound());
        assertEquals("abc1234", result.gitSha());
        assertEquals(new KubernetesStatus.ReplicaCounts(3, 2, 1), result.replicas());
        assertEquals("build-42", result.imageTag());
        assertEquals("Azure AKS", result.cloudName());
        assertEquals("Cluster Dashboard", result.appTitle());
        assertEquals("#123abc", result.accentColor());
        assertEquals(List.of("pod-a", "pod-b"), result.pods().stream().map(KubernetesStatus.PodStatus::name).toList());
        assertTrue(result.pods().get(0).serving());
        assertEquals("node-1", result.pods().get(0).node());
        assertEquals("1h 0m", result.pods().get(0).age());
    }

    @Test
    void getStatus_degradesWhenKubernetesApiIsUnavailable() {
        KubernetesResourceReader reader = mock(KubernetesResourceReader.class);
        when(reader.getDeployment(NAMESPACE, "deploy-pulse"))
                .thenThrow(new KubernetesClientException("connection refused"));
        KubernetesStatusService service = service(reader, Map.of(
                "POD_NAMESPACE", NAMESPACE,
                "APP_TITLE", "Local Dashboard"
        ));

        KubernetesStatus result = service.getStatus();

        assertFalse(result.apiAvailable());
        assertFalse(result.deploymentFound());
        assertNull(result.replicas());
        assertTrue(result.message().contains("unavailable"));
        assertEquals("Local Dashboard", result.appTitle());
        assertEquals(List.of(), result.pods());
        verify(reader, never()).listPods(anyString(), anyString(), anyString());
    }

    @Test
    void getStatus_usesSafeAccentFallbackWhenConfigIsInvalid() {
        KubernetesResourceReader reader = mock(KubernetesResourceReader.class);
        when(reader.getDeployment(NAMESPACE, "deploy-pulse")).thenThrow(new KubernetesClientException("offline"));
        KubernetesStatusService service = service(reader, Map.of("ACCENT_COLOR", "red; background:url(javascript:1)"));

        assertEquals("#58a6ff", service.getStatus().accentColor());
    }

    private KubernetesStatusService service(KubernetesResourceReader reader, Map<String, String> env) {
        Clock clock = Clock.fixed(NOW, ZoneOffset.UTC);
        return new KubernetesStatusService(reader, env, clock);
    }

    private Deployment deployment() {
        Container container = new Container();
        container.setName("deploy-pulse");
        container.setImage("registry.example/deploy-pulse:build-42");

        PodSpec podSpec = new PodSpec();
        podSpec.setContainers(List.of(container));

        PodTemplateSpec template = new PodTemplateSpec();
        template.setSpec(podSpec);

        DeploymentSpec spec = new DeploymentSpec();
        spec.setReplicas(3);
        spec.setTemplate(template);

        DeploymentStatus status = new DeploymentStatus();
        status.setReadyReplicas(2);
        status.setAvailableReplicas(1);

        Deployment deployment = new Deployment();
        deployment.setSpec(spec);
        deployment.setStatus(status);
        return deployment;
    }

    private Pod pod(String name, String node, String creationTimestamp) {
        ObjectMeta metadata = new ObjectMeta();
        metadata.setName(name);
        metadata.setCreationTimestamp(creationTimestamp);

        PodSpec spec = new PodSpec();
        spec.setNodeName(node);

        Pod pod = new Pod();
        pod.setMetadata(metadata);
        pod.setSpec(spec);
        io.fabric8.kubernetes.api.model.PodStatus status = new io.fabric8.kubernetes.api.model.PodStatus();
        status.setPhase("Running");
        pod.setStatus(status);
        return pod;
    }
}
