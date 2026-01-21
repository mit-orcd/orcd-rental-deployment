#!/bin/bash
# Attach an interactive shell to the running container
CONTAINER_NAME="${1:-devcontainer}"

exec apptainer exec instance://"$CONTAINER_NAME" bash
