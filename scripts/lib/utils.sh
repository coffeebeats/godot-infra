#!/usr/bin/env bash
set -Eeuo pipefail

# platform functions

get_os_type() {
    case "$(uname | tr '[:upper:]' '[:lower:]')" in
    darwin*) echo "darwin" ;;
    linux*) echo "linux" ;;
    msys* | mingw64*) echo "windows" ;;
    *) die "Unknown platform type; please file an issue!" ;;
    esac
}

check_linux() {
    [[ "$(get_os_type)" == "linux" ]]
}

check_osx() {
    [[ "$(get_os_type)" == "darwin" ]]
}

check_windows() {
    [[ "$(get_os_type)" == "windows" ]]
}

maybe_exe_ext() {
    [[ "$(get_os_type)" == "windows" ]] && echo ".exe" || :
}

# assert functions
need_dir() {
    DIR="${1:-}"
    if ! dir_exists $DIR; then
        die "Missing required directory: $DIR"
    fi
}

need_cmd() {
    if ! check_cmd "$1"; then
        die "Failed to execute; need '$1' (command not found)" 1
    fi
}

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# validate functions
dir_exists() {
    [[ -d "${1:-}" ]] && return 0 || return 1
}

# string functions

to_lowercase() {
    echo $(echo "${1:-}" | tr '[:upper:]' '[:lower:]')
}
