package com.example.deploypulse;

import io.fabric8.kubernetes.api.model.Pod;
import io.fabric8.kubernetes.api.model.apps.Deployment;

import java.util.List;

public interface KubernetesResourceReader {

    Deployment getDeployment(String namespace, String name);

    List<Pod> listPods(String namespace, String labelKey, String labelValue);
}
