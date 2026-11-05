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

    @BeforeEach
    void setUp() {
        when(infoService.getInfo()).thenReturn(SAMPLE);
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
