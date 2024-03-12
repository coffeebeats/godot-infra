#!/usr/bin/env bash
set -Eeuo pipefail

#
# This script is an entrypoint for the 'godot-infra' image.
#

# -------------------------- Run: Passed-in command -------------------------- #

exec "$@"
