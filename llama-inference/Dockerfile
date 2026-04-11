# Thin layer on top of the upstream llama.cpp server image that adds tzdata.
# The base image is a minimal Ubuntu build without zoneinfo, so TZ environment
# variables resolve to UTC. Installing tzdata gives us working Australia/Brisbane.
FROM ghcr.io/ggml-org/llama.cpp:server-cuda

USER root
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata && \
    rm -rf /var/lib/apt/lists/*
