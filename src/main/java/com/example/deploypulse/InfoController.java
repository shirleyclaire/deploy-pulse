package com.example.deploypulse;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * REST controller exposing deployment-metadata and health endpoints.
 */
@RestController
@RequestMapping("/api")
public class InfoController {

    private final InfoService infoService;

    public InfoController(InfoService infoService) {
        this.infoService = infoService;
    }

    /**
     * Returns a full {@link AppInfo} snapshot as JSON.
     */
    @GetMapping("/info")
    public ResponseEntity<AppInfo> info() {
        return ResponseEntity.ok(infoService.getInfo());
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

