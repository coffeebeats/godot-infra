# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------- #
#                               Image: Setup - OS                              #
# ---------------------------------------------------------------------------- #

FROM ubuntu:24.04 AS img-setup-os

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

FROM img-setup-os AS img-setup-python

# --------------------- Install: Python and Python 'venv' -------------------- #

RUN apt-get install -y --no-install-recommends \
    # Install 'python3' and 'venv'
    python3.12-venv && \
    # Set up the virtual environment
    python3.12 -m venv "/venv"


# ---------------------------------------------------------------------------- #
#                              Image: Setup - Base                             #
# ---------------------------------------------------------------------------- #

FROM img-setup-os AS img-setup-base

# ------------------------------ Install: Python ----------------------------- #

COPY --from=img-setup-python "/venv" "/opt/python3"

ENV \
    PATH="/opt/python3/bin:$PATH" \
    VIRTUAL_ENV="/opt/python3"

# ---------------------------------------------------------------------------- #
#                           Image: Setup - Emscripten                          #
# ---------------------------------------------------------------------------- #

FROM img-setup-base AS img-setup-emscripten

# NOTE: See https://emscripten.org/docs/getting_started/downloads.html for the
# latest installation instructions.

ARG EMSCRIPTEN_SDK_VERSION=latest

# --------------------------- Install: Dependencies -------------------------- #

RUN apt-get install -y --no-install-recommends \
    git \
    lbzip2 \
    xz-utils

# ---------------------- Download: Emscripten repository --------------------- #

RUN git clone \
    --no-tags \
    --depth=1 \
    $([ $EMSCRIPTEN_SDK_VERSION != latest ] && echo -b $EMSCRIPTEN_SDK_VERSION) \
    https://github.com/emscripten-core/emsdk.git \
    /emsdk

# ---------------------------- Install: Emscripten --------------------------- #

RUN \
    /emsdk/emsdk install "$EMSCRIPTEN_SDK_VERSION" && \
    /emsdk/emsdk activate "$EMSCRIPTEN_SDK_VERSION" && \
    # Clean up installation
    rm -rf /emsdk/upstream/emscripten/tests && \
    apt-get install -y --no-install-recommends binutils && \
    (find /emsdk/upstream/bin -type f -exec strip -s {} + || :)

# ---------------------------------------------------------------------------- #
#                             Image: Setup - Final                             #
# ---------------------------------------------------------------------------- #

FROM img-setup-base

# ----------------------------- Clean: Apt cache ----------------------------- #

RUN apt-get clean

# ---------------------------- Install: Emscripten --------------------------- #

COPY --from=img-setup-emscripten "/emsdk" "/opt/emsdk"

ENV PATH="/opt/emsdk/upstream/emscripten:/opt/emsdk/upstream/bin:$PATH"

# ------------------------------ Install: SCons ------------------------------ #

RUN python3.12 -m pip install \
    SCons==4.*

# ------------------------------ Set: SCONSFLAGS ----------------------------- #

# Update 'SCONSFLAGS' so that consumers don't need to know the details of
# Web-related settings.

ENV SCONSFLAGS="platform=web"
