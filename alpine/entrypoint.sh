#!/bin/bash
set -e

source /docker-lib.sh

start_docker
trap stop_docker EXIT
await_docker

load_images
# Visual check in the log of loaded images.
docker images

# do not exec, because exec disables traps
if [[ "$#" != "0" ]]; then
  "$@"
else
  bash --login
fi
