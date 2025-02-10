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
    # Install dependencies required for compiler installation.
    apt-get install -y --no-install-recommends \
    curl \
    xz-utils && \
    # Install the prebuilt MinGW-LLVM compiler
    mkdir "/mingw-llvm" && \
    curl -LO "https://github.com/mstorsjo/llvm-mingw/releases/download/$MINGW_LLVM_VERSION/$MINGW_LLVM_PKG_NAME" && \
    ls && \
    tar -C "/mingw-llvm" -xf "$MINGW_LLVM_PKG_NAME" --strip-components=1

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

# ---------------------------- Install: MinGW-LLVM --------------------------- #

COPY --from=img-setup-mingw-llvm "/mingw-llvm" "/opt/mingw-llvm"

ENV PATH="/opt/mingw-llvm/bin:$PATH"

# ------------------------------ Install: SCons ------------------------------ #

RUN python3.12 -m pip install \
    SCons==4.*

# ------------------------------ Set: SCONSFLAGS ----------------------------- #

# Update 'SCONSFLAGS' so that consumers don't need to know the details of
# Windows-related settings.

ENV SCONSFLAGS="platform=windows use_mingw=yes use_llvm=yes"
