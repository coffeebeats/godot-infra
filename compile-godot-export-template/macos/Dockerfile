# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------- #
#                              Image: Setup - Base                             #
# ---------------------------------------------------------------------------- #

FROM ubuntu:25.10 AS img-setup-base

# ------------------------- Update: Package registry ------------------------- #

# NOTE: This will install security updates. This image should be periodically
# rebuilt in order to receive the newest updates.

RUN \
    # update base image dependencies
    apt-get update -y && \
    apt-get dist-upgrade -y

# ------------------------- Install: System Packages ------------------------- #

RUN \
    # Install tzdata
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends tzdata && \
    # Install global dependencies
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    pkg-config \
    python3.13 \
    software-properties-common \
    xz-utils \
    zip \
    wget

# ---------------------------------------------------------------------------- #
#                             Image: Setup - Python                            #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-python

# --------------------- Install: Python and Python 'venv' -------------------- #

RUN apt-get install -y --no-install-recommends \
    # Install 'python3' and 'venv'
    python3.13-venv && \
    # Set up the virtual environment
    python3.13 -m venv "/venv"

# ---------------------------------------------------------------------------- #
#                       Image: Setup - rcodesign (MacOS)                       #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-rcodesign

# ------------------------ Install: Rust dependencies ------------------------ #

RUN \
    apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl

# ------------------------------- Install: Rust ------------------------------ #

ARG RUST_VERSION=""
ENV \
    CARGO_HOME="/opt/cargo" \
    RUSTUP_HOME="/opt/rustup" \
    PATH="/opt/cargo/bin:$PATH"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- \
    -y \
    --profile minimal \
    $([ ! -z "${RUST_VERSION}" ] && echo "--default-toolchain=${RUST_VERSION}")

# ---------------------------- Install: rcodesign ---------------------------- #

# See https://github.com/indygreg/apple-platform-rs/tree/main/apple-codesign#rcodesign-cli
RUN cargo install --locked --bin rcodesign apple-codesign

# ---------------------------------------------------------------------------- #
#                      Image: Setup - OSXCross SDK (MacOS)                     #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-osxcross

# ------------------------ Install: Build dependencies ----------------------- #

RUN apt-get install -y --no-install-recommends \
    binutils \
    build-essential \
    cmake \
    git \
    libssl-dev \
    liblzma-dev \
    libxml2-dev \
    make \
    patch \
    unzip \
    zlib1g-dev && \
    # NOTE: Ubuntu 25.10 switched to using Rust-based GNU coreutils instead of
    # the GNU implementation. The new 'ln' seems to have different behavior
    # under parallel execution that causes race conditions in osxcross's
    # 'build_compiler_rt.sh' script; install GNU 'ln' as a workaround.
    apt-get install -y --no-install-recommends coreutils && \
    mkdir -p /opt/gnu-coreutils/bin && \
    ln -sf "/usr/bin/gnuln" "/opt/gnu-coreutils/bin/ln"

# Verify GNU 'ln' is prioritized.
ENV PATH "/opt/gnu-coreutils/bin:$PATH"
RUN echo "PATH=$PATH\nln=$(which ln)" && ls /opt/gnu-coreutils/bin && ln --version && ln --version | grep -q "GNU coreutils" || (echo "Wrong 'ln' found; expected GNU coreutils version" && exit 1)

# ------------------------- Add: OSXCross source code ------------------------ #

# Verify build arguments were set.
ARG CLANG_VERSION
RUN test -n "$CLANG_VERSION" || (echo "Missing build argument: 'CLANG_VERSION'" && exit 1)

ARG MACOS_VERSION
RUN test -n "$MACOS_VERSION" || (echo "Missing build argument: 'MACOS_VERSION'" && exit 1)

ARG MACOS_VERSION_MINIMUM
RUN test -n "$MACOS_VERSION_MINIMUM" || (echo "Missing build argument: 'MACOS_VERSION_MINIMUM'" && exit 1)

ARG OSXCROSS_SDK
RUN test -n "$OSXCROSS_SDK" || (echo "Missing build argument: 'OSXCROSS_SDK'" && exit 1)

# Add osxcross repository into container
# NOTE: This step requires that the macOS SDK is already packaged in the
# 'osxcross/tarballs' directory.
COPY --from=osxcross . "/osxcross-src"

# Apply patches to osxcross
COPY --from=patches osxcross-*.patch "/patches/"
RUN for p in /patches/osxcross-*.patch; do patch -d /osxcross-src -p1 < "$p"; done

# Verify MacOS SDK is present in the expected format
RUN test -f "/osxcross-src/tarballs/MacOSX${MACOS_VERSION}.sdk.tar.gz" || \
    (echo "Missing MacOS SDK tarball: 'tarballs/MacOSX${MACOS_VERSION}.sdk.tar.gz'" && exit 1)

# ------------------------------ Build: OSXCross ----------------------------- #

ENV \
    UNATTENDED=1 \
    TARGET_DIR="/osxcross" \
    SDK_VERSION="$MACOS_VERSION" \
    OSX_VERSION_MIN="$MACOS_VERSION_MINIMUM" \
    OSXCROSS_ENABLE_WERROR_IMPLICIT_FUNCTION_DECLARATION="1"

WORKDIR /osxcross-src

# Build Apple clang
RUN \
    CLANG_VERSION=$CLANG_VERSION \
    ENABLE_CLANG_INSTALL=1 \
    INSTALLPREFIX=/opt/clang \
    ./build_apple_clang.sh

# Run the build script
RUN \
    PATH="/opt/clang/bin:$PATH" \
    ./build.sh

RUN \
    # NOTE: Skip 'arm64e'; it's not required for Godot. This requires the
    # 'osxcross-allow-archs-override.patch' patch.
    ARCHS="x86_64 arm64" \
    # NOTE: The "build_compiler_rt.sh" checks for osxcross to be installed into
    # the PATH variable. Since we don't necessarily want to do that at this
    # point, fake it for the script.
    PATH="$TARGET_DIR/bin:/opt/clang/bin:$PATH" \
    # NOTE: Variable `ENABLE_COMPILER_RT_INSTALL=1` is needed to prevent linker
    # errors with using "___isPlatformVersionAtLeast". See
    # https://github.com/tpoechtrager/osxcross/issues/278 for reference.
    ENABLE_COMPILER_RT_INSTALL=1 \
    ./build_compiler_rt.sh

# Verify "*-apple-$OSXCROSS_SDK-*" tools are present in the expected format
RUN test "$OSXCROSS_SDK" = "$(ls /osxcross/bin | \grep 'darwin' | head -1 | cut -f3 -d-)" || \
    (echo "Missing OSXCross tools for OSXCross SDK: $OSXCROSS_SDK" && exit 1)

# ---------------------------------------------------------------------------- #
#                         Image: Setup - ANGLE support                         #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-angle

# -------------------------- Install: ANGLE library -------------------------- #

# NOTE: Cross-compiling ANGLE for 'macos' requires building Apple 'clang'. This
# is an expensive operation, so unless demonstrated to be required, just use the
# prebuilt libraries.

ARG GODOT_ANGLE_STATIC_VERSION
RUN test -n "$GODOT_ANGLE_STATIC_VERSION" || (echo "Missing build argument: 'GODOT_ANGLE_STATIC_VERSION'" && exit 1)

ENV GODOT_ANGLE_STATIC_BASE_URL="https://github.com/godotengine/godot-angle-static/releases/download/"

RUN \
    # Install installation dependencies
    apt-get install -y --no-install-recommends \
    jq \
    unzip && \
    # Download prebuilt 'arm64' and 'x86_64' ANGLE libraries
    mkdir /angle && \
    GODOT_ANGLE_STATIC_BASE_URL="https://github.com/godotengine/godot-angle-static/releases/download/$(printf "${GODOT_ANGLE_STATIC_VERSION}" | jq -sRr '@uri')"; \
    curl -L -o macos_arm64.zip "$GODOT_ANGLE_STATIC_BASE_URL/godot-angle-static-arm64-macos-release.zip" && \
    curl -L -o macos_x86_64.zip "$GODOT_ANGLE_STATIC_BASE_URL/godot-angle-static-x86_64-macos-release.zip" && \
    unzip -o -d /angle macos_arm64.zip && rm -f macos_arm64.zip && \
    unzip -o -d /angle macos_x86_64.zip && rm -f macos_x86_64.zip

# ---------------------------------------------------------------------------- #
#                             Image: Setup - Final                             #
# ---------------------------------------------------------------------------- #

FROM img-setup-base

# ----------------------------- Clean: Apt cache ----------------------------- #

RUN apt-get clean

# ------------------------------ Install: Python ----------------------------- #

COPY --from=img-setup-python "/venv" "/opt/python3"

ENV \
    PATH="/opt/python3/bin:$PATH" \
    VIRTUAL_ENV="/opt/python3"

# ----------------------- Install: OSXCross SDK (MacOS) ---------------------- #

# Copy and install Apple 'clang'
COPY \
    --from=img-setup-osxcross \
    "/opt/clang" \
    "/opt/clang"
ENV \
    PATH="/opt/clang/bin:$PATH"

# Copy osxcross files
COPY \
    --from=img-setup-osxcross \
    "/osxcross" "/usr/local/lib/osxcross/target"

ARG MACOS_VERSION
ARG MACOS_VERSION_MINIMUM
ARG OSXCROSS_SDK
ENV \
    MACOS_VERSION="$MACOS_VERSION" \
    MACOS_VERSION_MINIMUM="$MACOS_VERSION_MINIMUM" \
    OSXCROSS_ROOT="/usr/local/lib/osxcross" \
    # NOTE: Godot expects $OSXCROSS_ROOT to mirror an osxcross repository. As such,
    # the target directory for the darwin toolchains must be `$OSXCROSS_ROOT/target/...`.
    # See https://github.com/godotengine/godot/blob/c3ed7af12347aa04a3d3bb91bc726170e894758e/platform/macos/detect.py#L136-L140.
    PATH="/usr/local/lib/osxcross/target/bin:$PATH" \
    LD_LIBRARY_PATH="/usr/local/lib/osxcross/target/lib"

# Fixes a linker error (see https://ttys3.dev/post/rust-cross-compile-mac-osx-target-under-linux/):
# "x86_64-apple-darwin*-ld: error while loading shared libraries:
#   libxar.so.1: cannot open shared object file: No such file or directory
# NOTE: This also ensures 'OSXCross' libraries are available to 'SCons'.
RUN echo /usr/local/lib/osxcross/target/lib | tee /etc/ld.so.conf.d/darwin.conf && \
    ldconfig

# ------------------------ Install: Vulkan SDK (MacOS) ----------------------- #

# NOTE: If using MoltenVK, see https://github.com/KhronosGroup/MoltenVK/issues/1756.

ENV VULKAN_SDK_ROOT="/usr/local/lib/vulkan-sdk"

COPY --from=vulkan . "$VULKAN_SDK_ROOT"

# -------------------------- Install: ANGLE support -------------------------- #

COPY --from=img-setup-angle "/angle" "/opt/angle"

# ------------------------------ Install: SCons ------------------------------ #

RUN python3.13 -m pip install \
    SCons==4.*

# ------------------------ Install: rcodesign (MacOS) ------------------------ #

COPY \
    --from=img-setup-rcodesign \
    "/opt/cargo/bin/rcodesign" \
    "/bin/rcodesign"

# ------------------------------ Set: SCONSFLAGS ----------------------------- #

# Update 'SCONSFLAGS' so that consumers don't need to know the details of MacOS-
# related settings.

ENV SCONSFLAGS="platform=macos osxcross_sdk=$OSXCROSS_SDK"
ENV SCONSFLAGS="$SCONSFLAGS use_volk=no vulkan_sdk_path=$VULKAN_SDK_ROOT/macOS/lib/MoltenVK.xcframework"
ENV SCONSFLAGS="$SCONSFLAGS angle_libs=/opt/angle"

# NOTE: As of Godot 4.0.3, the 'SCons' configuration does not correctly
# detect clang usage via 'OSXCross'. Add in the missing compiler flags and
# "common warnings" here (see https://github.com/godotengine/godot/blob/2267646bf4c29acf1342951d8726626817c742bd/SConstruct#L727-L730).
ENV SCONSFLAGS="$SCONSFLAGS CC=clang CXX=clang++ ccflags=-Wno-ordered-compare-function-pointers"
