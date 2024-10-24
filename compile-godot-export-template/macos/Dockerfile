# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------- #
#                              Image: Setup - Base                             #
# ---------------------------------------------------------------------------- #

FROM ubuntu:24.04 AS img-setup-base

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
    pkg-config \
    python3.12 \
    # Add support for compressing/extracting archive files
    xz-utils \
    zip

# ----------------------- Install: Clang / LLVM (MacOS) ---------------------- #

ARG LLVM_VERSION

RUN apt-get install -y --no-install-recommends \
    gnupg \
    lsb-release \
    software-properties-common \
    wget

RUN \
    # Install LLVM/Clang
    curl -LSsf https://apt.llvm.org/llvm.sh | bash -s $LLVM_VERSION && \
    # Set 'clang-$LLVM_VERSION' as default 'clang'
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-$LLVM_VERSION 1 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-$LLVM_VERSION 1

# ---------------------------------------------------------------------------- #
#                             Image: Setup - Python                            #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-python

# --------------------- Install: Python and Python 'venv' -------------------- #

RUN apt-get install -y --no-install-recommends \
    # Install 'python3' and 'venv'
    python3.12-venv && \
    # Set up the virtual environment
    python3.12 -m venv "/venv"

# ---------------------------------------------------------------------------- #
#                      Image: Setup - OSXCross SDK (MacOS)                     #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-osxcross

# ------------------------ Install: Build dependencies ----------------------- #

RUN apt-get install -y --no-install-recommends \
    cmake \
    git \
    libssl-dev \
    libxml2-dev \
    lzma-dev \
    make \
    patch

# ------------------------- Add: OSXCross source code ------------------------ #

# Verify build arguments were set.
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
    OSX_VERSION_MIN="$MACOS_VERSION_MINIMUM" \
    OSXCROSS_ENABLE_WERROR_IMPLICIT_FUNCTION_DECLARATION="1"

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

# Copy osxcross files
COPY \
    --from=img-setup-osxcross \
    "/osxcross" "/usr/local/lib/osxcross/target"


# The 'osxcross/build_compiler_rt.sh' script installs libraries into these directories.
ARG LLVM_VERSION
COPY \
    --from=img-setup-osxcross \
    "/usr/lib/llvm-$LLVM_VERSION/lib/clang" \
    "/usr/lib/llvm-$LLVM_VERSION/lib/clang"

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
    LD_LIBRARY_PATH="/usr/local/lib/osxcross/target/lib:$LD_LIBRARY_PATH"

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

# ------------------------------ Install: SCons ------------------------------ #

RUN python3.12 -m pip install \
    SCons==4.*

# ------------------------------ Set: SCONSFLAGS ----------------------------- #

# Update 'SCONSFLAGS' so that consumers don't need to know the details of MacOS-
# related settings.

ENV SCONSFLAGS="platform=macos osxcross_sdk=$OSXCROSS_SDK"
ENV SCONSFLAGS="use_volk=no vulkan_sdk_path=$VULKAN_SDK_ROOT/macOS/lib/MoltenVK.xcframework $SCONSFLAGS"

# NOTE: As of Godot 4.0.3, the 'SCons' configuration does not correctly
# detect clang usage via 'OSXCross'. Add in the missing "common
# warnings" here (see https://github.com/godotengine/godot/blob/2267646bf4c29acf1342951d8726626817c742bd/SConstruct#L727-L730).
ENV SCONSFLAGS="CCFLAGS='-Wno-ordered-compare-function-pointers' $SCONSFLAGS"
