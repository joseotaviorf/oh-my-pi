#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#
# Slim adaptation of the docker-outside-of-docker feature docker-init.sh.
# Hardcoded for bi-etl-ejuice (no feature option env vars).
#-------------------------------------------------------------------------------------------------------------

set -e

SOURCE_SOCKET=/var/run/docker-host.sock
TARGET_SOCKET=/var/run/docker.sock
USERNAME=vscode

SOCAT_PATH_BASE=/tmp/vscr-docker-from-docker
SOCAT_LOG=${SOCAT_PATH_BASE}.log
SOCAT_PID=${SOCAT_PATH_BASE}.pid

# Wrapper function to only use sudo if not already root
sudoIf()
{
    if [ "$(id -u)" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

# Log messages
log()
{
    echo -e "[$(date)] $@" | sudoIf tee -a ${SOCAT_LOG} > /dev/null
}

echo -e "\n** $(date) **" | sudoIf tee -a ${SOCAT_LOG} > /dev/null
log "Ensuring ${USERNAME} has access to ${SOURCE_SOCKET} via ${TARGET_SOCKET}"

# If the host socket is mounted and differs from the target, try to update the
# docker group with the right GID. If the group is root or the GID is already
# taken, fall back on using socat to forward the docker socket to another unix
# socket so that we can set permissions on it without affecting the host.
if [ -e "${SOURCE_SOCKET}" ] && [ "${SOURCE_SOCKET}" != "${TARGET_SOCKET}" ]; then
    SOCKET_GID=$(stat -c '%g' "${SOURCE_SOCKET}")
    DOCKER_GID=$(getent group docker | cut -d: -f3)
    if [ "${SOCKET_GID}" != "0" ] && [ "${SOCKET_GID}" != "${DOCKER_GID}" ] && ! grep -E ".+:x:${SOCKET_GID}:" /etc/group >/dev/null; then
        sudoIf groupmod --gid "${SOCKET_GID}" docker
    else
        # Enable proxy if not already running
        if [ ! -f "${SOCAT_PID}" ] || ! ps -p "$(cat ${SOCAT_PID})" > /dev/null 2>&1; then
            log "Enabling socket proxy."
            log "Proxying ${SOURCE_SOCKET} to ${TARGET_SOCKET} for ${USERNAME}"
            sudoIf rm -rf "${TARGET_SOCKET}"
            (sudoIf socat UNIX-LISTEN:${TARGET_SOCKET},fork,mode=660,user=${USERNAME},backlog=128 UNIX-CONNECT:${SOURCE_SOCKET} 2>&1 | sudoIf tee -a ${SOCAT_LOG} > /dev/null & echo "$!" | sudoIf tee ${SOCAT_PID} > /dev/null)
        else
            log "Socket proxy already running."
        fi
    fi
    log "Success"
fi

# Execute whatever commands were passed in (if any). This allows us
# to set this script to ENTRYPOINT while still executing the default CMD.
#
# Re-exec as USERNAME so groupmod GID changes take effect: container start
# freezes supplementary GIDs, and groupmod alone does not update them on
# the current process (needed for non-root DooD on Colima/engine sockets
# whose GID is not 0).
#
# Clear SHELL on re-exec: `sudo -E` otherwise keeps/sets SHELL to the passwd
# shell (zsh), and Makefile load_env_vars then sources ~/.zshrc under /bin/sh
# which aborts the recipe. Cursor still launches /usr/bin/zsh explicitly via
# terminal.integrated.profiles.linux.
set +e
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -E -u "${USERNAME}" SHELL= -- "$@"
fi
exec "$@"
