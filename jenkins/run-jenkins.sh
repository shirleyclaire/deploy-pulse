#!/usr/bin/env bash
# run-jenkins.sh – build the custom Jenkins image and (re)start the container.
#
# SECURITY NOTE: --user root and mounting /var/run/docker.sock give Jenkins
# full control of the host Docker daemon (build images, start/stop containers,
# etc.). This is a known security tradeoff that is acceptable for this lab
# environment. Do NOT use this configuration in production.
#
# Usage: adjust the three variables below, then:  bash jenkins/run-jenkins.sh

set -euo pipefail

JENKINS_CONTAINER_NAME="jenkins-server"
HOST_PORT="8082"
JENKINS_VOLUME="jenkins_home"

IMAGE_NAME="jenkins-devops:latest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ">>> Building Docker image: ${IMAGE_NAME}"
docker build -t "${IMAGE_NAME}" "${SCRIPT_DIR}"

echo ">>> Stopping and removing existing container (if any): ${JENKINS_CONTAINER_NAME}"
docker stop  "${JENKINS_CONTAINER_NAME}" 2>/dev/null || true
docker rm    "${JENKINS_CONTAINER_NAME}" 2>/dev/null || true

echo ">>> Starting new container: ${JENKINS_CONTAINER_NAME}"
docker run \
    --name "${JENKINS_CONTAINER_NAME}" \
    --detach \
    --user root \
    --restart unless-stopped \
    -p "${HOST_PORT}:8080" \
    -p "50000:50000" \
    -v "${JENKINS_VOLUME}:/var/jenkins_home" \
    -v "/var/run/docker.sock:/var/run/docker.sock" \
    "${IMAGE_NAME}"

echo ">>> Jenkins is starting. Open http://localhost:${HOST_PORT} in your browser."
echo ">>> Initial admin password (once the container is ready):"
echo "    docker exec ${JENKINS_CONTAINER_NAME} cat /var/jenkins_home/secrets/initialAdminPassword"
