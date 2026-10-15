# syntax=docker/dockerfile:1

# dev-lane: one coding lane — OpenCode CLI + Nix (nixpkgs unstable escape hatch)
# + a full toolchain, running as non-root user `lane` (uid 1000).
# Multi-arch: linux/amd64 + linux/arm64.

ARG NODE_IMAGE=node:24-bookworm-slim

FROM debian:stable-slim AS apt-layer
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        cargo \
        curl \
        elixir \
        erlang \
        file \
        findutils \
        git \
        golang-go \
        jq \
        less \
        openssh-client \
        procps \
        python3 \
        python3-pip \
        python3-venv \
        rustc \
        tmux \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

FROM apt-layer AS node-layer
ARG NODE_IMAGE
COPY --from=node:24-bookworm-slim /usr/local/ /usr/local/

FROM node-layer AS opencode-layer
ARG OPENCODE_VERSION=latest
RUN npm install -g "opencode-ai@${OPENCODE_VERSION}" \
    && opencode --version \
# Claude Code too — never know when you need it :) (auth via env, nothing baked in)
    && npm install -g @anthropic-ai/claude-code \
    && claude --version

FROM opencode-layer AS nix-layer
# Non-root user that owns /nix (single-user nix install).
RUN useradd --create-home --uid 1000 --shell /bin/bash lane \
    && mkdir -p /nix /work \
    && chown lane:lane /nix /work

USER lane
ENV HOME=/home/lane
RUN curl -fsSL https://nixos.org/nix/install -o /tmp/nix-install.sh \
    && sh /tmp/nix-install.sh --no-daemon \
    && rm /tmp/nix-install.sh

# Channel pinned to nixpkgs-unstable (legacy nix-env path) + flake registry
# pointing at the unstable branch (nix run nixpkgs#<pkg> path).
RUN . "$HOME/.nix-profile/etc/profile.d/nix.sh" \
    && nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs \
    && nix-channel --update
USER root
COPY nix/registry.json /etc/nix/registry.json
COPY nix/nix.conf /etc/nix/nix.conf

# Keep the seeded store inside the image; at runtime a volume may be mounted
# over /nix — the entrypoint seeds an empty /nix from /nix-seed on first run,
# so the store AND everything installed into it later persists on the volume.
RUN mv /nix /nix-seed \
    && mkdir -p /nix \
    && chown lane:lane /nix

FROM nix-layer
COPY entrypoint.sh /usr/local/bin/lane-entrypoint
COPY scripts/ /opt/lane/
RUN chmod +x /usr/local/bin/lane-entrypoint /opt/lane/*.sh

ENV HOME=/home/lane \
    USER=lane \
    PATH="/home/lane/.nix-profile/bin:/nix/var/nix/profiles/profile/bin:/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/local/go/bin:${PATH}" \
    OC_MODEL=opencode/step-5-preview-free \
    NIX_SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

USER lane
WORKDIR /work

ENTRYPOINT ["/usr/local/bin/lane-entrypoint"]
CMD ["bash"]
