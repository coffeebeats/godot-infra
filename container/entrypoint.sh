#!/usr/bin/env bash
set -Eeuo pipefail

#
# This script is an entrypoint for the 'godot-infra' image.
#

# ------------------------- Configure: Python3 (venv) ------------------------ #

. .venv/bin/activate

# -------------------------- Run: Passed-in command -------------------------- #

exec "$@"
