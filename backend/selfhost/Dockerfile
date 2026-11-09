# Self-hosted Omi backend image.
#
# The in-tree backend/Dockerfile builds FROM a private base image
# (gcr.io/based-hardware-dev/python:3.11-slim-forky) that this deployment cannot pull, so this
# is the public-base equivalent: same Python pin, same locked dependency sync, same runtime
# command. Build from the REPOSITORY ROOT, because the context needs both backend/ and
# .github/scripts/:
#
#   docker build -f backend/selfhost/Dockerfile -t omi-selfhost .
#   docker run --rm -p 8080:8080 --env-file backend/.env omi-selfhost

ARG PYTHON_BASE_IMAGE=python:3.11-slim
ARG UV_VERSION=0.11.13

FROM ${PYTHON_BASE_IMAGE} AS builder

ARG UV_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
      git gcc g++ python3-dev \
      && rm -rf /var/lib/apt/lists/*
RUN python -m venv /opt/venv
RUN /opt/venv/bin/pip install --no-cache-dir "uv==${UV_VERSION}"
ENV PATH="/opt/venv/bin:$PATH"

# Locked sync from the checked-in runtime lock. Build tools above are what let source
# distributions such as webrtcvad compile.
WORKDIR /opt/venv
COPY backend/pylock.runtime.toml /tmp/pylock.runtime.toml
RUN uv pip sync /tmp/pylock.runtime.toml --python /opt/venv/bin/python --compile-bytecode


FROM ${PYTHON_BASE_IMAGE}

WORKDIR /app
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    LD_PRELOAD=libjemalloc.so.2

# ffmpeg transcodes uploads; libjemalloc2 avoids the glibc fragmentation that grows RSS under
# sustained WebSocket audio (see the in-tree Dockerfile).
RUN apt-get update && apt-get install -y --no-install-recommends \
      ffmpeg curl libjemalloc2 \
      && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv
# backend/desktop_release_manifest.py imports this; without it startup fails.
COPY .github/scripts/desktop_release_manifest.py /app/desktop_release_manifest_contract.py
COPY backend/ .

# Bind-mounted service-account JSON lands here; keep it out of the image.
RUN mkdir -p /app/secrets

RUN python -m compileall -q -j 0 -x '(^|/)tests/' /app && \
    groupadd --system --gid 10001 omi && \
    useradd --system --uid 10001 --gid omi --no-create-home omi && \
    chown -R omi:omi /app
USER omi

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--loop", "uvloop", "--timeout-graceful-shutdown", "60"]
