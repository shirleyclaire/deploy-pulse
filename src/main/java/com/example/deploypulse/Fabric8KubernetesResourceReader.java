package com.example.deploypulse;

import io.fabric8.kubernetes.api.model.Pod;
import io.fabric8.kubernetes.api.model.apps.Deployment;
import io.fabric8.kubernetes.client.KubernetesClient;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
public class Fabric8KubernetesResourceReader implements KubernetesResourceReader {

    private final KubernetesClient client;

    public Fabric8KubernetesResourceReader(KubernetesClient client) {
        this.client = client;
    }

    @Override
    public Deployment getDeployment(String namespace, String name) {
        return client.apps().deployments()
                .inNamespace(namespace)
                .withName(name)
                .get();
    }

    @Override
    public List<Pod> listPods(String namespace, String labelKey, String labelValue) {
        return client.pods()
                .inNamespace(namespace)
                .withLabel(labelKey, labelValue)
                .list()
                .getItems();
    }
}
