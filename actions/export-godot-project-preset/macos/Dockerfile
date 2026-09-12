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
    apt-get install -y --no-install-recommends tzdata

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
#                             Image: Setup - Final                             #
# ---------------------------------------------------------------------------- #

FROM img-setup-base

# ----------------------------- Clean: Apt cache ----------------------------- #

RUN apt-get clean

# ------------------------ Install: rcodesign (MacOS) ------------------------ #

COPY \
    --from=img-setup-rcodesign \
    "/opt/cargo/bin/rcodesign" \
    "/bin/rcodesign"
