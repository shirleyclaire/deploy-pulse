#!/usr/bin/env bash
set -euo pipefail

AGENT_NAME="deploy-pulse-linux"
AGENT_IMAGE="deploy-pulse-agent:latest"
AGENT_CONTAINER="${AGENT_NAME}"
AGENT_WORKSPACE_VOLUME="deploy-pulse-agent-work"
JENKINS_URL="${JENKINS_URL:-http://host.docker.internal:8082}"

: "${JENKINS_AGENT_SECRET:?Set JENKINS_AGENT_SECRET to the secret shown for the Jenkins inbound agent}"

if docker container inspect "${AGENT_CONTAINER}" >/dev/null 2>&1; then
    echo "ERROR: Container ${AGENT_CONTAINER} already exists; inspect or remove it before retrying." >&2
    exit 1
fi

docker volume inspect "${AGENT_WORKSPACE_VOLUME}" >/dev/null 2>&1 || \
    docker volume create "${AGENT_WORKSPACE_VOLUME}" >/dev/null

docker run \
    --name "${AGENT_CONTAINER}" \
    --detach \
    --restart unless-stopped \
    --group-add 0 \
    --env JENKINS_URL="${JENKINS_URL}" \
    --env JENKINS_AGENT_NAME="${AGENT_NAME}" \
    --env JENKINS_SECRET="${JENKINS_AGENT_SECRET}" \
    --env JENKINS_AGENT_WORKDIR="/home/jenkins/agent" \
    --env JENKINS_WEB_SOCKET=true \
    --volume "${AGENT_WORKSPACE_VOLUME}:/home/jenkins/agent" \
    --volume "/var/run/docker.sock:/var/run/docker.sock" \
    "${AGENT_IMAGE}"

echo "Started ${AGENT_CONTAINER}. Check Jenkins > Manage Jenkins > Nodes."
