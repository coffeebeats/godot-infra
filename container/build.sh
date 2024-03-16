#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
WORKSPACE_DIR="$(cd $SCRIPT_DIR/.. && pwd)"

trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
    trap - SIGINT SIGTERM ERR EXIT

    if [[ ! -z "${CONTEXT:-}" && -d "${CONTEXT:-}" ]]; then
        debug " > removing context: $CONTEXT"
        rm -rf $CONTEXT
    fi
}

# --------------------------- Install: Dependencies -------------------------- #

source "$WORKSPACE_DIR/scripts/lib/logging.sh"
source "$WORKSPACE_DIR/scripts/lib/utils.sh"

# ------------------------- Define: Script Arguments ------------------------- #

VERSION="0.0.1" # x-release-please-version

usage() {
    cat <<EOF
Builds the Godot build container image.

Usage: $(basename "${BASH_SOURCE[0]}") <OPTIONS>

NOTE: The following dependencies are required:
    - podman | docker

Available options:
    -a, --arch          The base image architecture (defaults to host)
    -b, --base          The base image (default=docker.io/library/ubuntu:lunar)
    -d, --dry-run       Whether to skip running the command (default=false)
    -r, --runner        A specific container runtime command to build with
    -t, --tag           Additional image tag (can be specified multiple times)
    --timestamp         A created timestamp for the image (default=seconds since Unix epoch)

    --osxcross          Path to an OSXCross SDK
    --vulkan            Path to a macOS Vulkan SDK

    --gdenv             Version of github.com/coffeebeats/gdenv to install (defaults to latest).
    --gdpack            Version of github.com/coffeebeats/gdpack to install (defaults to latest).
    --gdbuild           Version of github.com/coffeebeats/gdbuild to install (defaults to latest).

    -h, --help          Print this help and exit
    -v, --verbose       Print script debug info (default=false)
    --[no]color         Whether to enable colored output for logging (default=enabled)
EOF
    exit
}

parse_params() {
    ACCEPT=0
    NO_COLOR=

    DRY_RUN=0
    RUNNER=

    BASE_IMG=""
    HOST_ARCH=$(
        case $(uname -m) in
        arm64 | armv8) echo arm64/v8 ;;
        x86_64) echo amd64 ;;
        *) die "Unsupported host architecture: '$HOST_ARCH'" ;;
        esac
    )
    TAGS=()
    TIMESTAMP=$(date +%s)

    # Define: Library paths
    OSXCROSS_HOST_PATH="${OSXCROSS_HOST_PATH:-"$WORKSPACE_DIR/thirdparty/osxcross"}"
    VULKAN_SDK_HOST_PATH="${VULKAN_SDK_HOST_PATH:-"$WORKSPACE_DIR/thirdparty/moltenvk"}"

    ARGS=()
    ARGS_EXTRA=()

    while :; do
        case "${1:-}" in
        -h | --help) usage ;;
        -v | --verbose) set_verbose ;;

        --color) NO_COLOR= setup_colors ;;
        --nocolor) NO_COLOR=1 setup_colors ;;

        -d | --dry-run) DRY_RUN=1 ;;

        -a | --arch)
            HOST_ARCH="${2:-}"
            [[ -z "$HOST_ARCH" ]] && die "Missing value for option: 'arch'"
            if [[ "$HOST_ARCH" == "x86_64" ]]; then
                HOST_ARCH="amd64"
            fi
            shift
            ;;
        -b | --base)
            BASE_IMG="${2:-}"
            [[ -z "$BASE_IMG" ]] && die "Missing value for option: 'base'"
            shift
            ;;

        -r | --runner)
            RUNNER="${2:-}"
            ! check_cmd "$RUNNER" && die "Command not found: $RUNNER"
            shift
            ;;
        -t | --tag)
            tag="${2:-}"
            tag="${tag#*:}"
            [[ -z "$tag" ]] && die "Missing value for option: 'tag'"

            TAGS+=("$tag")
            shift
            ;;
        --timestamp)
            TIMESTAMP="${2:-}"
            [[ -z "$TIMESTAMP" ]] && die "Missing value for option: 'timestamp'"
            shift
            ;;
        --osxcross)
            OSXCROSS_HOST_PATH="${2:-}"
            [[ ! -d "$OSXCROSS_HOST_PATH" ]] && die "Missing directory: '${2:-}'"
            shift
            ;;
        --vulkan)
            VULKAN_SDK_HOST_PATH="${2:-}"
            [[ ! -d "$VULKAN_SDK_HOST_PATH" ]] && die "Missing directory: '${2:-}'"
            shift
            ;;
        --gdenv)
            GDENV_VERSION="${2:-}"
            [[ -z "$GDENV_VERSION" ]] && die "Missing 'gdenv' version: '${2:-}'"
            shift
            ;;
        --gdpack)
            GDPACK_VERSION="${2:-}"
            [[ -z "$GDPACK_VERSION" ]] && die "Missing 'gdpack' version: '${2:-}'"
            shift
            ;;
        --gdbuild)
            GDBUILD_VERSION="${2:-}"
            [[ -z "$GDBUILD_VERSION" ]] && die "Missing 'gdbuild' version: '${2:-}'"
            shift
            ;;
        --)
            shift
            ARGS_EXTRA+=(${@})
            break
            ;;
        -?*) die "Unknown option: $1" ;;
        "") break ;;
        *) ARGS+=("${1:-}") ;;
        esac
        shift
    done

    return 0
}

parse_params "$@"

# Validate: Working directory
if [[ "$PWD" != "$(cd $WORKSPACE_DIR && pwd)" ]]; then
    die "This script must be run from the repository root!"
fi

if [[ -z "$BASE_IMG" ]]; then
    die "Missing 'BASE_IMAGE' parameter!"
fi

# Define: Library paths (on host)
OSXCROSS_HOST_PATH="$(cd $OSXCROSS_HOST_PATH && pwd)"
VULKAN_SDK_HOST_PATH="$(cd $VULKAN_SDK_HOST_PATH && pwd)"

info "Building container image:"
info "container platform: $BASE_IMG ($HOST_ARCH)"

# ------------------------ Build: Image build command ------------------------ #

print_newline
info "Creating build command..."

CMD=()

if check_cmd "$RUNNER"; then
    CMD+=("$RUNNER build")
elif check_cmd podman >/dev/null 2>&1; then
    CMD+=("podman build")
elif check_cmd docker >/dev/null 2>&1; then
    CMD+=("docker build")
else
    die "Missing container runtime: please install 'podman' or 'docker'!"
fi

# Define: Common build contexts
# ...

# Define: Platform-specific build contexts
CMD+=("--build-context osxcross=$OSXCROSS_HOST_PATH")
CMD+=("--build-context vulkan=$VULKAN_SDK_HOST_PATH")

# Define: Common arguments
CMD+=("--build-arg BASE_IMG=$BASE_IMG")
CMD+=("--build-arg RUST_VERSION=${RUST_VERSION:-}")
CMD+=("--build-arg GDENV_VERSION=${GDENV_VERSION:-}")
CMD+=("--build-arg GDPACK_VERSION=${GDPACK_VERSION:-}")
CMD+=("--build-arg GDBUILD_VERSION=${GDBUILD_VERSION:-}")

# Define: Platform-specific arguments
CMD+=("--build-arg LLVM_VERSION=${LLVM_VERSION:-17}")
CMD+=("--build-arg MACOS_VERSION=${MACOS_VERSION:-"14"}")
CMD+=("--build-arg MACOS_VERSION_MINIMUM=${MACOS_VERSION_MINIMUM:-}")
CMD+=("--build-arg OSXCROSS_SDK=${OSXCROSS_SDK:-}")

# Define: Image tags
TAGS+=("$VERSION")
TAGS+=("latest")
for t in "${TAGS[@]}"; do
    CMD+=("-t localhost/godot-infra:$t")
done

CMD+=("--platform linux/$HOST_ARCH")
CMD+=("--compress")

case $RUNNER in
podman) CMD+=("--timestamp $TIMESTAMP") ;;
esac

CMD+=(${ARGS_EXTRA[@]})

CMD+=("$SCRIPT_DIR")
CMD_STR="${CMD[@]}"

print_newline

CMD_LEN="${#CMD[@]}"
echo "${CMD[0]}"
for l in "${CMD[@]:1:$(($CMD_LEN - 2))}"; do
    echo "  $l \\"
done
echo "  ${CMD[$(($CMD_LEN - 1))]}"

if [[ "$DRY_RUN" -eq 1 ]]; then
    exit 0
fi

# --------------------------- Run: Build the image --------------------------- #

print_newline
info "Building container image..."

CMD="${CMD[@]}"
exec bash -c "$CMD"
