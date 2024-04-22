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
    python3.12

# ---------------------- Install: 'mingw-w64' toolchain ---------------------- #

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
#                       Image: Setup - @coffeebeats tools                      #
# ---------------------------------------------------------------------------- #

FROM img-setup-base as img-setup-godot-tools

# ------------------------------- Install: curl ------------------------------ #

RUN apt-get install -y \
    curl

# ------------------------------ Install: gdenv ------------------------------ #

ARG GDENV_VERSION=""
RUN export GDENV_HOME="/gdenv" GDENV_VERSION=$GDENV_VERSION; \
    curl https://raw.githubusercontent.com/coffeebeats/gdenv/main/scripts/install.sh | sh -s -- --no-modify-path; \
    command -v /gdenv/bin/gdenv

# ---------------------------------------------------------------------------- #
#                             Image: Setup - Final                             #
# ---------------------------------------------------------------------------- #

FROM img-setup-base

# ------------------------------ Install: Python ----------------------------- #

COPY --from=img-setup-python "/venv" "/opt/python3"

ENV \
    PATH="/opt/python3/bin:$PATH" \
    VIRTUAL_ENV="/opt/python3"

# ------------------------------ Install: SCons ------------------------------ #

RUN python3.12 -m pip install \
    SCons==4.*

# ------------- Install: ImageMagick + pngcrush (Icon conversion) ------------ #

# NOTE: 'ImageMagick' is used on all platforms to convert '.svg' files into
# raster image formats (e.g. '.png' or '.jpg'). It's also used on the Windows
# platform to create '.ico' files.

RUN \
    # Install image conversion tool
    apt-get install -y \
    imagemagick && \
    # Add an alias for the installed command 'convert'
    ln -s "$(which convert)" "/usr/bin/magick" && \
    # Install 'pngcrush' for PNG image optimization
    apt-get install -y --no-install-recommends \
    pngcrush

# ------------------------------ Install: gdenv ------------------------------ #

COPY --from=img-setup-godot-tools "/gdenv/bin/*" "/opt/gdenv/bin"

ENV \
    GDENV_HOME="/opt/gdenv" \
    PATH="/opt/gdenv/bin:$PATH"

VOLUME "/opt/gdenv"

# ----------------------------- Clean: Apt cache ----------------------------- #

RUN apt-get clean