ARG BASE_IMAGE=ghcr.io/edulinq/lms-docker-canvas-base:latest
FROM ${BASE_IMAGE}

USER root
WORKDIR /work/canvas-source

ARG MEMURY_RELEASE=2026-08-16
LABEL net.memury.release="${MEMURY_RELEASE}"
LABEL net.memury.component="canvas-integrated"

COPY core.patch /opt/memury-release/core.patch
RUN command -v patch >/dev/null \
  && patch --batch --fuzz=0 --dry-run -p1 < /opt/memury-release/core.patch \
  && patch --batch --fuzz=0 -p1 < /opt/memury-release/core.patch

COPY overlay/ /work/canvas-source/

# Canvas serves the webpack-production manifest even though this compact demo
# stack runs Rails in development mode. Build that exact asset target so the
# Memury dynamic feature bundle is present in the manifest used by browsers.
RUN NODE_OPTIONS=--max-old-space-size=3072 yarn webpack-production

ENV MEMURY_DEMO_MODE=true
