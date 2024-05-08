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
    python3.12 \
    # Install 'emscripten' dependencies
    lbzip2 \
    xz-utils

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
#                           Image: Setup - Emscripten                          #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-emscripten

# --------------------- Install: Emscripten dependencies --------------------- #

RUN apt-get install -y --no-install-recommends \
    git

# ---------------------- Download: Emscripten repository --------------------- #

RUN git clone \
    --no-tags \
    --depth=1 \
    https://github.com/emscripten-core/emsdk.git \
    /emsdk

# ---------------------------------------------------------------------------- #
#                             Image: Setup - Final                             #
# ---------------------------------------------------------------------------- #

FROM img-setup-base

# ------------------------------ Install: Python ----------------------------- #

COPY --from=img-setup-python "/venv" "/opt/python3"

ENV \
    PATH="/opt/python3/bin:$PATH" \
    VIRTUAL_ENV="/opt/python3"

# ---------------------------- Install: Emscripten --------------------------- #

COPY --from=img-setup-emscripten "/emsdk" "/opt/emsdk"

# NOTE: See https://emscripten.org/docs/getting_started/downloads.html for the
# latest installation instructions.

ARG EMSCRIPTEN_SDK_VERSION=latest

RUN \
    /opt/emsdk/emsdk install "$EMSCRIPTEN_SDK_VERSION" && \
    /opt/emsdk/emsdk activate "$EMSCRIPTEN_SDK_VERSION" && \
    # Clean up installation
    rm -fr /opt/emsdk/upstream/emscripten/tests && \
    apt-get install -y --no-install-recommends binutils && \
    (find /opt/emsdk/upstream/bin -type f -exec strip -s {} + || :) && \
    apt-get remove -y --purge binutils

ENV PATH="/opt/emsdk/upstream/emscripten:/opt/emsdk/upstream/bin:$PATH"

# ----------------------------- Clean: Apt cache ----------------------------- #

RUN apt-get clean

# ------------------------------ Install: SCons ------------------------------ #

RUN python3.12 -m pip install \
    SCons==4.*

# ------------------------------ Set: SCONSFLAGS ----------------------------- #

# Update 'SCONSFLAGS' so that consumers don't need to know the details of
# Web-related settings.

ENV SCONSFLAGS="platform=web javascript_eval=no dlink_enabled=no"
