package com.example.deploypulse;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * REST controller exposing deployment metadata, Kubernetes status, and health endpoints.
 */
@RestController
@RequestMapping("/api")
public class InfoController {

    private final InfoService infoService;
    private final KubernetesStatusService kubernetesStatusService;

    public InfoController(InfoService infoService, KubernetesStatusService kubernetesStatusService) {
        this.infoService = infoService;
        this.kubernetesStatusService = kubernetesStatusService;
    }

    /**
     * Returns a full {@link AppInfo} snapshot as JSON.
     */
    @GetMapping("/info")
    public ResponseEntity<AppInfo> info() {
        return ResponseEntity.ok(infoService.getInfo());
    }

    @GetMapping("/status")
    public ResponseEntity<KubernetesStatus> status() {
        return ResponseEntity.ok(kubernetesStatusService.getStatus());
    }

    /**
     * Simple liveness probe.
     *
     * @return {@code {"status":"UP"}}
     */
    @GetMapping("/health")
    public ResponseEntity<Map<String, String>> health() {
        return ResponseEntity.ok(Map.of("status", "UP"));
    }
}

