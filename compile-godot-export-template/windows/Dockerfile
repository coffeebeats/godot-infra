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
    pkg-config \
    python3.12

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
#                           Image: Setup - MinGW-LLVM                          #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-mingw-llvm

# ----------------------- Install: MinGW-LLVM compiler ----------------------- #

ARG MINGW_LLVM_VERSION
RUN test -n "$MINGW_LLVM_VERSION" || (echo "Missing build argument: 'MINGW_LLVM_VERSION'" && exit 1)

ENV MINGW_LLVM_PKG_NAME="llvm-mingw-$MINGW_LLVM_VERSION-ucrt-ubuntu-20.04-x86_64.tar.xz"

RUN \
    # Install dependencies required for compiler installation
    apt-get install -y --no-install-recommends \
    curl \
    xz-utils && \
    # Install the prebuilt MinGW-LLVM compiler
    mkdir "/mingw-llvm" && \
    curl -LO "https://github.com/mstorsjo/llvm-mingw/releases/download/$MINGW_LLVM_VERSION/$MINGW_LLVM_PKG_NAME" && \
    tar -C "/mingw-llvm" -xf "$MINGW_LLVM_PKG_NAME" --strip-components=1

# ---------------------------------------------------------------------------- #
#                           Image: Setup - Compilers                           #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-compilers

# ------------------------------ Install: Python ----------------------------- #

COPY --from=img-setup-python "/venv" "/opt/python3"

ENV \
    PATH="/opt/python3/bin:$PATH" \
    VIRTUAL_ENV="/opt/python3"

# ---------------------------- Install: MinGW-LLVM --------------------------- #

COPY --from=img-setup-mingw-llvm "/mingw-llvm" "/opt/mingw-llvm"

ENV PATH="/opt/mingw-llvm/bin:$PATH"

# ------------------------------ Install: SCons ------------------------------ #

RUN python3.12 -m pip install \
    SCons==4.*

# ---------------------------------------------------------------------------- #
#                      Image: Setup - Direct3D 12 support                      #
# ---------------------------------------------------------------------------- #

FROM img-setup-compilers AS img-setup-dx12

# -------------------------- Install: Mesa libraries ------------------------- #

ARG GODOT_NIR_STATIC_VERSION
RUN test -n "$GODOT_NIR_STATIC_VERSION" || (echo "Missing build argument: 'GODOT_NIR_STATIC_VERSION'" && exit 1)

RUN \
    # Install installation dependencies
    apt-get install -y --no-install-recommends \
    git && \
    # Clone the 'godot-nir-static' repository
    git clone \
    --no-tags \
    --depth=1 \
    -b $GODOT_NIR_STATIC_VERSION \
    https://github.com/godotengine/godot-nir-static.git \
    /godot-nir-static && \
    # Initialize submodules and dependencies
    python3.12 -m pip install mako && \
    cd /godot-nir-static && \
    git submodule update --init && \
    ./update_mesa.sh && \
    # Build the static library for supported platforms
    scons platform=windows arch=arm64 use_mingw=yes use_llvm=yes optimize=speed && \
    scons platform=windows arch=x86_64 use_mingw=yes use_llvm=yes optimize=speed && \
    mkdir /mesa && \
    mv bin /mesa && \
    cp --parents godot-mesa/VERSION.info /mesa && \
    find godot-mesa -name "*.h" -exec cp --parents {} /mesa \; && \
    find godot-mesa -name "*.hpp" -exec cp --parents {} /mesa \;

# -------------------------- Install: PIX on Windows ------------------------- #

# NOTE: See https://www.nuget.org/packages/WinPixEventRuntime for all versions.

ARG PIX_VERSION
RUN test -n "$PIX_VERSION" || (echo "Missing build argument: 'PIX_VERSION'" && exit 1)

RUN \
    # Install installation dependencies
    apt-get install -y --no-install-recommends \
    curl \
    unzip && \
    # Install the PIX event runtime
    curl -L -o pix.zip "https://www.nuget.org/api/v2/package/WinPixEventRuntime/$PIX_VERSION" && \
    mkdir /pix && \
    unzip pix.zip -d /pix && \
    # Generate x86_64-specific import libraries
    cd /pix && \
    gendef ./bin/x64/WinPixEventRuntime.dll && \
    llvm-dlltool --machine i386:x86-64 --no-leading-underscore -d WinPixEventRuntime.def -D WinPixEventRuntime.dll -l ./bin/x64/libWinPixEventRuntime.a && \
    # Generate arm64-specific import libraries
    gendef ./bin/ARM64/WinPixEventRuntime.dll && \
    llvm-dlltool --machine arm64 --no-leading-underscore -d WinPixEventRuntime.def -D WinPixEventRuntime.dll -l ./bin/ARM64/libWinPixEventRuntime.a

# --------------------------- Install: Agility SDK --------------------------- #

# NOTE: See https://www.nuget.org/packages/Microsoft.Direct3D.D3D12 for all versions.

ARG AGILITY_VERSION
RUN test -n "$AGILITY_VERSION" || (echo "Missing build argument: 'AGILITY_VERSION'" && exit 1)

RUN \
    # Install the Agility SDK
    curl -L -o agility.zip "https://www.nuget.org/api/v2/package/Microsoft.Direct3D.D3D12/$AGILITY_VERSION" && \
    mkdir /agility && \
    unzip agility.zip -d /agility

# ---------------------------------------------------------------------------- #
#                         Image: Setup - ANGLE support                         #
# ---------------------------------------------------------------------------- #

FROM img-setup-compilers AS img-setup-angle

# -------------------------- Install: ANGLE library -------------------------- #

ARG GODOT_ANGLE_STATIC_VERSION
RUN test -n "$GODOT_ANGLE_STATIC_VERSION" || (echo "Missing build argument: 'GODOT_ANGLE_STATIC_VERSION'" && exit 1)

RUN \
    # Install installation dependencies
    apt-get install -y --no-install-recommends \
    git && \
    # Clone the 'godot-angle-static' repository
    git clone \
    --no-tags \
    --depth=1 \
    -b $GODOT_ANGLE_STATIC_VERSION \
    https://github.com/godotengine/godot-angle-static.git \
    /godot-angle-static && \
    # Initialize submodules and dependencies
    cd /godot-angle-static && \
    git submodule update --init && \
    ./update_angle.sh && \
    # Build the static library for supported platforms
    scons platform=windows arch=arm64 use_mingw=yes use_llvm=yes optimize=speed && \
    scons platform=windows arch=x86_64 use_mingw=yes use_llvm=yes optimize=speed && \
    mkdir /angle && \
    mv bin/* /angle

# ---------------------------------------------------------------------------- #
#                             Image: Setup - Final                             #
# ---------------------------------------------------------------------------- #

FROM img-setup-compilers

# ----------------------------- Clean: Apt cache ----------------------------- #

RUN apt-get clean

# ----------------------- Install: Direct3D 12 support ----------------------- #

COPY --from=img-setup-dx12 "/mesa" "/opt/mesa"
COPY --from=img-setup-dx12 "/agility" "/opt/agility"
COPY --from=img-setup-dx12 "/pix" "/opt/pix"

# -------------------------- Install: ANGLE support -------------------------- #

COPY --from=img-setup-angle "/angle" "/opt/angle"

# ------------------------------ Set: SCONSFLAGS ----------------------------- #

# Update 'SCONSFLAGS' so that consumers don't need to know the details of
# Windows-related settings.

# NOTE: PIX on Windows is not included by default as it should only be used for
# debug builds. Set `pix_path=/opt/pix` when building to enable support.

ENV SCONSFLAGS="platform=windows use_mingw=yes use_llvm=yes"
ENV SCONSFLAGS="$SCONSFLAGS d3d12=yes mesa_libs=/opt/mesa agility_sdk_path=/opt/agility"
ENV SCONSFLAGS="$SCONSFLAGS angle_libs=/opt/angle"
