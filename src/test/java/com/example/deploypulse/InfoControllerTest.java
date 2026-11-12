package com.example.deploypulse;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Slice test for {@link InfoController}.
 *
 * <p>{@link InfoService} is mocked so the test has zero dependency on
 * real environment variables or wall-clock time.</p>
 */
@WebMvcTest(InfoController.class)
class InfoControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private InfoService infoService;

    @MockBean
    private KubernetesStatusService kubernetesStatusService;

    /** Canonical {@link AppInfo} returned by the stubbed service. */
    private static final AppInfo SAMPLE = new AppInfo(
            "Deploy Pulse",
            "Deploy Pulse v1 - pipeline works",
            "0.0.1-TEST",
            "deadbeef",
            "2024-01-01T00:00:00Z",
            "test-pod",
            "test-ns",
            "test-node",
            "0h 1m 0s",
            60L,
            "2024-01-01T00:01:00Z"
    );

    private static final KubernetesStatus STATUS = new KubernetesStatus(
            true,
            true,
            "Kubernetes status loaded from namespace 'test-ns'.",
            new KubernetesStatus.ReplicaCounts(2, 1, 1),
            "abc1234",
            "Test Kubernetes",
            "Test Dashboard",
            "#123abc",
            java.util.List.of(new KubernetesStatus.PodStatus(
                    "test-pod", "Running", "test-node", "3m", true
            ))
    );

    @BeforeEach
    void setUp() {
        when(infoService.getInfo()).thenReturn(SAMPLE);
        when(kubernetesStatusService.getStatus()).thenReturn(STATUS);
    }

    // ── /api/info ──────────────────────────────────────────────────────────────

    @Test
    void infoEndpoint_returns200() throws Exception {
        mockMvc.perform(get("/api/info"))
               .andExpect(status().isOk());
    }

    @Test
    void infoEndpoint_containsAppName() throws Exception {
        mockMvc.perform(get("/api/info"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.appName").value("Deploy Pulse"));
    }

    @Test
    void infoEndpoint_containsCorrectMessage() throws Exception {
        mockMvc.perform(get("/api/info"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.message").value("Deploy Pulse v1 - pipeline works"));
    }

    @Test
    void infoEndpoint_contentTypeIsJson() throws Exception {
        mockMvc.perform(get("/api/info"))
               .andExpect(status().isOk())
               .andExpect(content().contentTypeCompatibleWith("application/json"));
    }

    // ── /api/status ────────────────────────────────────────────────────────────

    @Test
    void statusEndpoint_returnsReplicaPodAndDisplayMetadata() throws Exception {
        mockMvc.perform(get("/api/status"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.apiAvailable").value(true))
               .andExpect(jsonPath("$.replicas.desired").value(2))
               .andExpect(jsonPath("$.replicas.ready").value(1))
               .andExpect(jsonPath("$.replicas.available").value(1))
               .andExpect(jsonPath("$.pods[0].name").value("test-pod"))
               .andExpect(jsonPath("$.pods[0].serving").value(true))
               .andExpect(jsonPath("$.imageTag").value("abc1234"))
               .andExpect(jsonPath("$.cloudName").value("Test Kubernetes"))
               .andExpect(jsonPath("$.appTitle").value("Test Dashboard"))
               .andExpect(jsonPath("$.accentColor").value("#123abc"));
    }

    // ── /api/health ────────────────────────────────────────────────────────────

    @Test
    void healthEndpoint_returns200() throws Exception {
        mockMvc.perform(get("/api/health"))
               .andExpect(status().isOk());
    }

    @Test
    void healthEndpoint_statusIsUp() throws Exception {
        mockMvc.perform(get("/api/health"))
               .andExpect(status().isOk())
               .andExpect(jsonPath("$.status").value("UP"));
    }
}
