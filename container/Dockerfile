# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------- #
#                               Image: OS (Base)                               #
# ---------------------------------------------------------------------------- #

ARG BASE_IMG
FROM $BASE_IMG AS img-os-base

# ------------------------- Update: Package registry ------------------------- #

# NOTE: This will install security updates. This image should be periodically
# rebuilt in order to receive the newest updates.

ARG DISTRO_ARCHIVE="http://archive.ubuntu.com/ubuntu"

# Use a mirror for faster downloads
RUN \
    # Use a mirror for faster downloads
    DISTRO_ARCHIVE_ESCAPED="$(echo "${DISTRO_ARCHIVE}" | sed 's/\//\\\//g')"; \
    sed -i \
    "s/http:\/\/archive.ubuntu.com\/ubuntu\//$DISTRO_ARCHIVE_ESCAPED/" \
    "/etc/apt/sources.list" && \
    # update base image dependencies
    apt-get update && \
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
    pkg-config \
    python3.12 \
    # Add support for compressing/extracting archive files
    xz-utils \
    zip

# ----------------------- Install: Clang / LLVM (MacOS) ---------------------- #

RUN apt-get install -y --no-install-recommends \
    gnupg \
    lsb-release \
    software-properties-common \
    wget

# Install llvm/clang
ARG LLVM_VERSION

RUN \
    # Install LLVM/Clang
    curl -LSsf https://apt.llvm.org/llvm.sh | bash -s $LLVM_VERSION && \
    # Set 'clang-$LLVM_VERSION' as default 'clang'
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-$LLVM_VERSION 1 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-$LLVM_VERSION 1

# ----------------- Install: 'mingw-w64' toolchain (Windows) ----------------- #

RUN \
    # Install toolchain
    apt-get install -y --no-install-recommends \
    mingw-w64 && \
    # Switch to *-posix toolchains (64-bit)
    update-alternatives --set 'x86_64-w64-mingw32-gcc' "/usr/bin/x86_64-w64-mingw32-gcc-posix" && \
    update-alternatives --set 'x86_64-w64-mingw32-g++' "/usr/bin/x86_64-w64-mingw32-g++-posix" && \
    # Switch to *-posix toolchains (32-bit)
    update-alternatives --set 'i686-w64-mingw32-gcc' "/usr/bin/i686-w64-mingw32-gcc-posix" && \
    update-alternatives --set 'i686-w64-mingw32-g++' "/usr/bin/i686-w64-mingw32-g++-posix"

# ----------------------------- Define: Workspace ---------------------------- #

# Switch to 'ubuntu' user for workspace directory creation.
USER ubuntu

# The working directory of the image.
ENV WORKSPACE="/home/ubuntu/godot-infra"
LABEL workspace_dir="$WORKSPACE"

# A workspace subdirectory for executables.
ENV WORKSPACE_BIN_DIR="$WORKSPACE/bin" PATH="$WORKSPACE/bin:$PATH"
RUN mkdir -p $WORKSPACE_BIN_DIR

# Switch back to 'root' user for continuing setup.
USER root

# ---------------------------------------------------------------------------- #
#                             Image: Setup - Python                            #
# ---------------------------------------------------------------------------- #

FROM img-os-base AS img-setup-python

# --------------------- Install: Python and Python 'venv' -------------------- #

RUN apt-get install -y --no-install-recommends \
    # Install 'python3' and 'venv'
    python3.12-venv && \
    # Set up the virtual environment
    python3.12 -m venv "$WORKSPACE/.venv"

# ---------------------------------------------------------------------------- #
#                      Image: Setup - OSXCross SDK (MacOS)                     #
# ---------------------------------------------------------------------------- #

FROM img-os-base AS img-setup-osxcross

# ------------------------ Install: Build dependencies ----------------------- #

RUN apt-get install -y --no-install-recommends \
    gcc \
    cmake \
    git \
    libssl-dev \
    libxml2-dev \
    lzma-dev \
    make \
    patch

# ------------------------- Add: OSXCross source code ------------------------ #

ARG MACOS_VERSION
RUN test -n $MACOS_VERSION || (echo "Missing build argument: 'MACOS_VERSION'" && exit 1)

ARG MACOS_VERSION_MINIMUM
RUN test -n $MACOS_VERSION_MINIMUM || (echo "Missing build argument: 'MACOS_VERSION_MINIMUM'" && exit 1)

ARG OSXCROSS_SDK
RUN test -n $OSXCROSS_SDK || (echo "Missing build argument: 'OSXCROSS_SDK'" && exit 1)

# Add osxcross repository into container
# NOTE: This step requires that the macOS SDK is already packaged in the
# 'osxcross/tarballs' directory.
COPY --from=osxcross . "/osxcross-src"

# Verify MacOS SDK is present in the expected format
RUN test -f "/osxcross-src/tarballs/MacOSX${MACOS_VERSION}.sdk.tar.gz" || \
    (echo "Missing MacOS SDK tarball: 'tarballs/MacOSX${MACOS_VERSION}.sdk.tar.gz'" && exit 1)

# ------------------------------ Build: OSXCross ----------------------------- #

ENV \
    TARGET_DIR="/osxcross" \
    SDK_VERSION="$MACOS_VERSION" \
    OSX_VERSION_MIN=$MACOS_VERSION_MINIMUM \
    OSXCROSS_ENABLE_WERROR_IMPLICIT_FUNCTION_DECLARATION=1

WORKDIR /osxcross-src

# Run the build script
RUN \
    UNATTENDED=1 \
    ./build.sh

RUN \
    # NOTE: The "build_compiler_rt.sh" checks for osxcross to be installed into
    # the PATH variable. Since we don't necessarily want to do that at this
    # point, fake it for the script.
    PATH="$TARGET_DIR/bin:$PATH" \
    # NOTE: Variable `ENABLE_COMPILER_RT_INSTALL=1` is needed to prevent linker
    # errors with using "___isPlatformVersionAtLeast".
    # See https://github.com/tpoechtrager/osxcross/issues/278 for reference.
    ENABLE_COMPILER_RT_INSTALL=1 \
    ./build_compiler_rt.sh

# Verify "*-apple-$OSXCROSS_SDK-*" tools are present in the expected format
RUN test "$OSXCROSS_SDK" = "$(ls /osxcross/bin | \grep 'darwin' | head -1 | cut -f3 -d-)" || \
    (echo "Missing OSXCross tools for OSXCross SDK: $OSXCROSS_SDK" && exit 1)

# ---------------------------------------------------------------------------- #
#                           Image: Build dependencies                          #
# ---------------------------------------------------------------------------- #

FROM img-os-base as img-build-dependencies

# ------------------------ Install: Python environment ----------------------- #

ENV PYVENV_DIR="$WORKSPACE/.venv"
COPY --from=img-setup-python --chown=ubuntu "$PYVENV_DIR" "$PYVENV_DIR"

# ------------------------------ Install: SCons ------------------------------ #

RUN $PYVENV_DIR/bin/python3.12 -m pip install \
    SCons==4.*

# ----------------------- Install: OSXCross SDK (MacOS) ---------------------- #

# Copy osxcross files
COPY \
    --from=img-setup-osxcross \
    --chown=ubuntu \
    "/osxcross" "/usr/local/lib/osxcross/target"

# osxcross/build_compiler_rt.sh script installs libraries into these directories.
ARG LLVM_VERSION
LABEL llvm="$LLVM_VERSION"

COPY \
    --from=img-setup-osxcross \
    "/usr/lib/llvm-$LLVM_VERSION/lib/clang" \
    "/usr/lib/llvm-$LLVM_VERSION/lib/clang"

ARG MACOS_VERSION
ARG MACOS_VERSION_MINIMUM
ARG OSXCROSS_SDK
LABEL macos="$MACOS_VERSION" macos_min="$MACOS_VERSION_MINIMUM" osxcross_sdk="$OSXCROSS_SDK"

ENV \
    MACOS_VERSION=$MACOS_VERSION \
    MACOS_VERSION_MINIMUM=$MACOS_VERSION_MINIMUM \
    OSXCROSS_ROOT="/usr/local/lib/osxcross" \
    # NOTE: Godot expects $OSXCROSS_ROOT to mirror an osxcross repository. As such,
    # the target directory for the darwin toolchains must be `$OSXCROSS_ROOT/target/...`.
    # See https://github.com/godotengine/godot/blob/c3ed7af12347aa04a3d3bb91bc726170e894758e/platform/macos/detect.py#L136-L140.
    PATH="/usr/local/lib/osxcross/target/bin:${PATH}" \
    LD_LIBRARY_PATH="/usr/local/lib/osxcross/target/lib:${LD_LIBRARY_PATH}"

# Fixes a linker error (see https://ttys3.dev/post/rust-cross-compile-mac-osx-target-under-linux/):
# "x86_64-apple-darwin*-ld: error while loading shared libraries:
#   libxar.so.1: cannot open shared object file: No such file or directory
# NOTE: This also ensures 'OSXCross' libraries are available to 'SCons'.
RUN echo /usr/local/lib/osxcross/target/lib | tee /etc/ld.so.conf.d/darwin.conf && \
    ldconfig

# ------------------------ Install: Vulkan SDK (MacOS) ----------------------- #

# NOTE: If using MoltenVK, see https://github.com/KhronosGroup/MoltenVK/issues/1756.

ENV VULKAN_SDK_ROOT="/usr/local/lib/vulkan-sdk"
LABEL vulkan_sdk_path="$VULKAN_SDK_ROOT"

COPY --from=vulkan --chown=ubuntu . "$VULKAN_SDK_ROOT"

# ---------------------------------------------------------------------------- #
#                       Image: Setup - rcodesign (MacOS)                       #
# ---------------------------------------------------------------------------- #

FROM img-os-base as img-setup-rcodesign

# ------------------------ Install: Rust dependencies ------------------------ #

RUN \
    apt-get install -y --no-install-recommends \
    build-essential

# ------------------------------- Install: Rust ------------------------------ #

ARG RUST_VERSION=""
ENV \
    CARGO_HOME="$WORKSPACE/.cargo" \
    RUSTUP_HOME="$WORKSPACE/.rustup" \
    PATH="$WORKSPACE/.cargo/bin:$PATH"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- \
    -y \
    --profile minimal \
    $([ ! -z "${RUST_VERSION}" ] && echo "--default-toolchain=${RUST_VERSION}")

# ---------------------------- Install: rcodesign ---------------------------- #

# See https://github.com/indygreg/apple-platform-rs/tree/main/apple-codesign#rcodesign-cli
RUN cargo install --locked --bin rcodesign apple-codesign

# ---------------------------------------------------------------------------- #
#                          Image: Export dependencies                          #
# ---------------------------------------------------------------------------- #

FROM img-build-dependencies AS img-export-dependencies

# ------------------------ Install: icnsutils (MacOS) ------------------------ #

RUN \
    apt-get install -y --no-install-recommends \
    icnsutils

# ------------- Install: ImageMagick (Windows + Icon conversion) ------------- #

# NOTE: 'ImageMagick' is used on all platforms to convert '.svg' files into
# raster image formats (e.g. '.png' or '.jpg'). It's also used on the Windows
# platform to create '.ico' files.

RUN \
    # Install toolchain
    apt-get install -y \
    imagemagick && \
    # Add an alias for the installed command 'convert'
    ln -s "$(which convert)" "/usr/bin/magick"

# --------------- Install: pngcrush (Windows + Icon conversion) -------------- #

RUN \
    apt-get install -y --no-install-recommends \
    pngcrush

# ------------------------ Install: rcodesign (MacOS) ------------------------ #

COPY \
    --from=img-setup-rcodesign \
    "$WORKSPACE/.cargo/bin/rcodesign" \
    "$WORKSPACE_BIN_DIR/rcodesign"

# ---------------------- Install: osslsigncode (Windows) --------------------- #

RUN apt-get install -y --no-install-recommends \
    osslsigncode

# ---------------------------------------------------------------------------- #
#                                 Image: Final                                 #
# ---------------------------------------------------------------------------- #

# ----------------------------- Clean: Apt cache ----------------------------- #

RUN apt-get clean

# ----------------------- Configure: Working directory ----------------------- #

WORKDIR $WORKSPACE

# ------------------------------ Configure: User ----------------------------- #

# See https://bugs.launchpad.net/cloud-images/+bug/2005129
USER ubuntu

# ------------------------- Define: Entrypoint script ------------------------ #

ADD --chown=ubuntu "./entrypoint.sh" "/entrypoint.sh"

ENTRYPOINT [ "/entrypoint.sh" ]
