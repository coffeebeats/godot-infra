#!/usr/bin/env bash
set -Eeuo pipefail

# logging functions

VERBOSE=0

debug() {
    [[ "$VERBOSE" -eq 0 ]] && return 0
    echo >&2 -e "${BLUE}DEBUG${NOFORMAT} ${1:-}"
}

detail() {
    echo >&2 -e "   > ${1:-}"
}

err() {
    echo >&2 -e "${RED}ERR${NOFORMAT} ${1:-}"
}

info() {
    echo >&2 -e "${GREEN}INFO${NOFORMAT} ${1:-}"
}

warn() {
    echo >&2 -e "${YELLOW}WARN${NOFORMAT} ${1:-}"
}

# special-case functions

die() {
    local msg=$1
    local code=${2-1} # default exit status 1
    err "$msg"
    exit "$code"
}

msg() {
    echo >&2 -e "${1:-}"
}

print_newline() {
    echo ""
}

set_verbose() {
    VERBOSE=1
}

setup_colors() {
    if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then
        NOFORMAT='\033[0m' \
            RED='\033[0;31m' \
            GREEN='\033[0;32m' \
            ORANGE='\033[0;33m' \
            BLUE='\033[0;34m' \
            PURPLE='\033[0;35m' \
            CYAN='\033[0;36m' \
            YELLOW='\033[1;33m'
    else
        NOFORMAT='' \
            RED='' \
            GREEN='' \
            ORANGE='' \
            BLUE='' \
            PURPLE='' \
            CYAN='' \
            YELLOW=''
    fi

}

# set up colors
setup_colors
