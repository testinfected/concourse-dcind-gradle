#!/usr/bin/env bash

# Inspired by https://github.com/karlkfi/concourse-dcind

set -e          # exit on command errors
set -o nounset  # abort on unbound variable
set -o pipefail # capture fail exit codes in piped commands

# Waits seconds for startup (default: 60)
STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-60}"
# Accepts optional options for Docker (default: --data-root /scratch/docker)
DOCKER_OPTS="${DOCKER_OPTS:-}"

# Constants
PID_FILE="/tmp/docker.pid"
LOG_FILE="/tmp/docker.log"

sanitize_cgroups() {
  local cgroup="/sys/fs/cgroup"

  mkdir -p "${cgroup}"
  if ! mountpoint -q "${cgroup}"; then
    if ! mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup "${cgroup}"; then
      echo >&2 "Could not make a tmpfs mount. Did you use --privileged?"
      exit 1
    fi
  fi
  mount -o remount,rw "${cgroup}"

  # Skip AppArmor
  # See: https://github.com/moby/moby/commit/de191e86321f7d3136ff42ff75826b8107399497
  export container=docker

  # Mount /sys/kernel/security
  if [[ -d /sys/kernel/security ]] && ! mountpoint -q /sys/kernel/security; then
    if ! mount -t securityfs none /sys/kernel/security; then
      echo >&2 "Could not mount /sys/kernel/security."
      echo >&2 "AppArmor detection and --privileged mode might break."
    fi
  fi

  sed -e 1d /proc/cgroups | while read sys hierarchy num enabled; do
    if [[ "${enabled}" != "1" ]]; then
      # subsystem disabled; skip
      continue
    fi

    grouping="$(cat /proc/self/cgroup | cut -d: -f2 | grep "\\<${sys}\\>")"
    if [[ -z "${grouping}" ]]; then
      # subsystem not mounted anywhere; mount it on its own
      grouping="${sys}"
    fi

    mountpoint="${cgroup}/${grouping}"

    mkdir -p "${mountpoint}"

    # clear out existing mount to make sure new one is read-write
    if mountpoint -q "${mountpoint}"; then
      umount "${mountpoint}"
    fi

    mount -n -t cgroup -o "${grouping}" cgroup "${mountpoint}"

    if [[ "${grouping}" != "${sys}" ]]; then
      if [[ -L "${cgroup}/${sys}" ]]; then
        rm "${cgroup}/${sys}"
      fi

      ln -s "${mountpoint}" "${cgroup}/${sys}"
    fi
  done

  # Initialize systemd cgroup if host isn't using systemd.
  # Workaround for https://github.com/docker/for-linux/issues/219
  if ! [[ -d /sys/fs/cgroup/systemd ]]; then
    mkdir "${cgroup}/systemd"
    mount -t cgroup -o none,name=systemd cgroup "${cgroup}/systemd"
  fi
}

# Setup container environment and start docker daemon in the background.
start_docker() {
  echo >&2 "Setting up Docker environment..."
  mkdir -p /var/log
  mkdir -p /var/run

  sanitize_cgroups

  # check for /proc/sys being mounted readonly, as systemd does
  if grep '/proc/sys\s\+\w\+\s\+ro,' /proc/mounts >/dev/null; then
    mount -o remount,rw /proc/sys
  fi

  local docker_opts="${DOCKER_OPTS:-}"

  # Pass through `--garden-mtu` from gardian container
  if [[ "${docker_opts}" != *'--mtu'* ]]; then
    local mtu="$(cat /sys/class/net/$(ip route get 8.8.8.8|awk '{ print $5 }')/mtu)"
    docker_opts+=" --mtu ${mtu}"
  fi

  # Use Concourse's scratch volume to bypass the graph filesystem by default
  if [[ "${docker_opts}" != *'--data-root'* ]] && [[ "${docker_opts}" != *'--graph'* ]]; then
    docker_opts+=' --data-root /scratch/docker'
  fi

  rm -f "${PID_FILE}"
  touch "${LOG_FILE}"

  echo >&2 "Starting Docker..."
  dockerd ${docker_opts} &>"${LOG_FILE}" &
  echo "$!" > "${PID_FILE}"
}

# Wait for docker daemon to be healthy
# Timeout after STARTUP_TIMEOUT seconds
await_docker() {
  local timeout="${STARTUP_TIMEOUT}"

  echo >&2 "Waiting ${timeout} seconds for Docker to be available..."
  local start=${SECONDS}
  timeout=$(( timeout + start ))

  until docker info &>/dev/null; do
    if (( SECONDS >= timeout )); then
      echo >&2 'Timed out trying to connect to docker daemon.'
      if [[ -f "${LOG_FILE}" ]]; then
        echo >&2 '---DOCKERD LOGS---'
        cat >&2 "${LOG_FILE}"
      fi
      exit 1
    fi

    if [[ -f "${PID_FILE}" ]] && ! kill -0 $(cat "${PID_FILE}"); then
      echo >&2 'Docker daemon failed to start.'
      if [[ -f "${LOG_FILE}" ]]; then
        echo >&2 '---DOCKERD LOGS---'
        cat >&2 "${LOG_FILE}"
      fi
      exit 1
    fi
    sleep 1
  done

  local duration=$(( SECONDS - start ))
  echo >&2 "Docker available after ${duration} seconds."
}

# Gracefully stop Docker daemon.
stop_docker() {
  if ! [[ -f "${PID_FILE}" ]]; then
    return 0
  fi
  local docker_pid="$(cat ${PID_FILE})"
  if [[ -z "${docker_pid}" ]]; then
    return 0
  fi

  echo >&2 "Terminating Docker daemon."
  kill -TERM ${docker_pid}
  local start=${SECONDS}

  echo >&2 "Waiting for Docker daemon to exit..."
  wait ${docker_pid}
  local duration=$(( SECONDS - start ))

  echo >&2 "Docker exited after ${duration} seconds."
}

# Strictly speaking, preloading of Docker images is not required.
# However, you might want to do this for a couple of reasons:
# - If the image comes from a private repository, it is much easier to let Concourse pull it,
#   and then pass it through to the task.
# - When the image is passed to the task, Concourse can often get the image from its cache.
load_images() {
  echo "Preloading Docker images..."
  # Load images in OCI format
  while read -r image; do
    echo >&2 "Found ${image}."
    docker load -i "${image}"
  done < <(find . -name 'image.tar' -type f)
}