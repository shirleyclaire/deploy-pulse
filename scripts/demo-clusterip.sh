#!/usr/bin/env bash
set -euo pipefail

PROFILE="${MINIKUBE_PROFILE:-minikube}"
NAMESPACE="deploy-pulse"
SERVICE="deploy-pulse"
INGRESS_HOST="deploy-pulse.local"
PORT_FORWARD_PORT="${PORT_FORWARD_PORT:-18080}"
PF_PID=""
PF_LOG=""

for command_name in kubectl minikube curl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $command_name" >&2
        exit 1
    fi
done

cleanup() {
    if [[ -n "$PF_PID" ]]; then
        kill "$PF_PID" >/dev/null 2>&1 || true
        wait "$PF_PID" >/dev/null 2>&1 || true
    fi
    if [[ -n "$PF_LOG" ]]; then
        rm -f "$PF_LOG"
    fi
}
trap cleanup EXIT

kubectl --context="$PROFILE" get deployment deploy-pulse -n "$NAMESPACE" >/dev/null
kubectl --context="$PROFILE" rollout status deployment/deploy-pulse \
    -n "$NAMESPACE" --timeout=180s

echo "Current Service before the demo:"
kubectl --context="$PROFILE" get service "$SERVICE" -n "$NAMESPACE" -o wide

current_type="$(kubectl --context="$PROFILE" get service "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.spec.type}')"
if [[ "$current_type" != "NodePort" ]]; then
    echo "Setting a temporary NodePort baseline for the demo (current type: ${current_type})."
    kubectl --context="$PROFILE" patch service "$SERVICE" -n "$NAMESPACE" \
        --type merge -p '{"spec":{"type":"NodePort"}}'
fi

old_node_port="$(kubectl --context="$PROFILE" get service "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.spec.ports[0].nodePort}')"
if [[ -z "$old_node_port" ]]; then
    echo "ERROR: Could not obtain the temporary NodePort for the demo." >&2
    exit 1
fi
minikube_ip="$(minikube -p "$PROFILE" ip)"
old_node_url="http://${minikube_ip}:${old_node_port}/api/status"
nodeport_baseline_reachable=false

echo "NodePort baseline:"
kubectl --context="$PROFILE" get service "$SERVICE" -n "$NAMESPACE" -o wide
if nodeport_response="$(curl --noproxy '*' -fsS --max-time 5 "$old_node_url" 2>/dev/null)"; then
    nodeport_baseline_reachable=true
    echo "Host could reach the NodePort before the switch: $old_node_url"
    printf '%s\n' "$nodeport_response"
else
    echo "NOTE: This host could not reach Minikube's NodePort before the switch."
    echo "The old NodePort address will still be checked after changing the Service."
fi

echo "Applying the ClusterIP Service manifest:"
kubectl --context="$PROFILE" apply -f k8s/service.yaml
kubectl --context="$PROFILE" get service "$SERVICE" -n "$NAMESPACE" -o wide

new_type="$(kubectl --context="$PROFILE" get service "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.spec.type}')"
remaining_node_port="$(kubectl --context="$PROFILE" get service "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.spec.ports[0].nodePort}')"
if [[ "$new_type" != "ClusterIP" || -n "$remaining_node_port" ]]; then
    echo "ERROR: Service did not become ClusterIP without a nodePort." >&2
    exit 1
fi

old_nodeport_failed=false
for attempt in $(seq 1 10); do
    if curl --noproxy '*' -fsS --max-time 3 "$old_node_url" >/dev/null 2>&1; then
        sleep 1
    else
        old_nodeport_failed=true
        break
    fi
done
if [[ "$old_nodeport_failed" != "true" ]]; then
    echo "ERROR: The old NodePort is still reachable from this host: $old_node_url" >&2
    exit 1
fi
if [[ "$nodeport_baseline_reachable" == "true" ]]; then
    echo "PASS: The old NodePort stopped responding after the switch: $old_node_url"
else
    echo "NOTE: The old NodePort is unreachable from this host, but it was also"
    echo "unreachable before the switch, so this host cannot show the transition."
fi

echo "Checking in-cluster access through the ClusterIP Service:"
kubectl --context="$PROFILE" run deploy-pulse-curl-demo \
    --namespace="$NAMESPACE" \
    --image=curlimages/curl:8.12.1 \
    --restart=Never \
    --rm -i \
    --command -- curl -fsS --max-time 10 "http://${SERVICE}.${NAMESPACE}/api/status"

echo "Enabling Minikube's nginx ingress controller and applying the Ingress:"
minikube -p "$PROFILE" addons enable ingress
kubectl --context="$PROFILE" rollout status deployment/ingress-nginx-controller \
    -n ingress-nginx --timeout=180s
kubectl --context="$PROFILE" apply -f k8s/ingress.yaml

if ingress_response="$(curl --noproxy '*' -fsS --max-time 5 \
    --resolve "${INGRESS_HOST}:80:${minikube_ip}" \
    "http://${INGRESS_HOST}/api/status" 2>/dev/null)"; then
    echo "Ingress is externally reachable at http://${INGRESS_HOST}:"
    printf '%s\n' "$ingress_response"
else
    echo "Ingress was not reachable at the Minikube node IP from this host."
    echo "Use the port-forward URL below; add '${minikube_ip} ${INGRESS_HOST}'"
    echo "to the host's hosts file to try http://${INGRESS_HOST} in a browser."
fi
echo "For browser ingress access, hosts file mapping: ${minikube_ip} ${INGRESS_HOST}"

PF_LOG="$(mktemp)"
kubectl --context="$PROFILE" port-forward \
    --namespace="$NAMESPACE" "service/${SERVICE}" \
    "${PORT_FORWARD_PORT}:80" >"$PF_LOG" 2>&1 &
PF_PID=$!

port_forward_response=""
for attempt in $(seq 1 30); do
    if ! kill -0 "$PF_PID" >/dev/null 2>&1; then
        cat "$PF_LOG" >&2
        echo "ERROR: kubectl port-forward stopped unexpectedly." >&2
        exit 1
    fi
    if port_forward_response="$(curl --noproxy '*' -fsS --max-time 3 \
        "http://127.0.0.1:${PORT_FORWARD_PORT}/api/status" 2>/dev/null)"; then
        break
    fi
    sleep 1
done
if [[ -z "$port_forward_response" ]]; then
    cat "$PF_LOG" >&2
    echo "ERROR: Could not reach the application through kubectl port-forward." >&2
    exit 1
fi

echo "External access through port-forward: http://127.0.0.1:${PORT_FORWARD_PORT}"
printf '%s\n' "$port_forward_response"
if [[ -t 0 ]]; then
    read -r -p "Open the URL above in a browser, then press Enter to stop port-forward: " _
else
    echo "Port-forward will remain available for 30 seconds."
    sleep 30
fi
