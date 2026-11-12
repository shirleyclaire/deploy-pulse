#!/usr/bin/env bash
# run-jenkins.sh – start Jenkins from the official image.
#
# Build tools belong on a Jenkins agent, not in the controller image.
# Usage: bash jenkins/run-jenkins.sh

set -euo pipefail

JENKINS_CONTAINER_NAME="jenkins-server"
HOST_PORT="8082"
JENKINS_VOLUME="jenkins_home"
JENKINS_IMAGE="jenkins/jenkins:lts"

if docker container inspect "${JENKINS_CONTAINER_NAME}" >/dev/null 2>&1; then
    EXISTING_IMAGE="$(docker inspect --format '{{.Config.Image}}' "${JENKINS_CONTAINER_NAME}")"
    if [[ "${EXISTING_IMAGE}" == "${JENKINS_IMAGE}" ]]; then
        if [[ "$(docker inspect --format '{{.State.Running}}' "${JENKINS_CONTAINER_NAME}")" == "true" ]]; then
            echo ">>> ${JENKINS_CONTAINER_NAME} is already running from ${JENKINS_IMAGE}."
            exit 0
        fi

        echo ">>> Starting existing Jenkins container: ${JENKINS_CONTAINER_NAME}"
        docker start "${JENKINS_CONTAINER_NAME}"
        exit 0
    fi

    JENKINS_VOLUME="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/jenkins_home"}}{{.Name}}{{end}}{{end}}' "${JENKINS_CONTAINER_NAME}")"
    if [[ -z "${JENKINS_VOLUME}" ]]; then
        echo "ERROR: Existing Jenkins container has no /var/jenkins_home volume; refusing to replace it." >&2
        exit 1
    fi

    echo ">>> Replacing ${EXISTING_IMAGE} while preserving Jenkins volume ${JENKINS_VOLUME}"
    docker stop "${JENKINS_CONTAINER_NAME}"
    docker rm "${JENKINS_CONTAINER_NAME}"
fi

docker volume inspect "${JENKINS_VOLUME}" >/dev/null 2>&1 || docker volume create "${JENKINS_VOLUME}" >/dev/null
docker pull "${JENKINS_IMAGE}"

echo ">>> Starting new container: ${JENKINS_CONTAINER_NAME}"
docker run \
    --name "${JENKINS_CONTAINER_NAME}" \
    --detach \
    --restart unless-stopped \
    -p "${HOST_PORT}:8080" \
    -p "50000:50000" \
    -v "${JENKINS_VOLUME}:/var/jenkins_home" \
    "${JENKINS_IMAGE}"

echo ">>> Jenkins is starting. Open http://localhost:${HOST_PORT} in your browser."
echo ">>> If this is a fresh setup, retrieve the initial admin password with:"
echo "    docker exec ${JENKINS_CONTAINER_NAME} cat /var/jenkins_home/secrets/initialAdminPassword"
