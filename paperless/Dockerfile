# syntax=docker/dockerfile:1.7
#
# paperless-ngx + the paperless-paddleocr plugin, running the `vl-remote`
# engine against the PaddleOCR-VL server on gpu-host.
#
# There is no prebuilt image for this plugin -- upstream ships recipe
# Dockerfiles only (https://github.com/flobernd/paperless-paddleocr), and this
# is their examples/Dockerfile.vl-remote adapted to this repo. "Remote" only
# describes where the VLM runs: the plugin still builds a PaddleOCRVL pipeline
# in-process, so paddlepaddle and paddleocr have to be installed here too. That
# is what takes the image from ~2.5GB to roughly double it.
#
# The plugin registers itself through the `paperless_ngx.parsers` entry point,
# which needs paperless-ngx 3.0+. It claims a parser score of 15 against
# Tesseract's 10, so once this image is running it handles *all* OCR, not just
# documents that opt in. To roll back, drop `build:` from the compose file and
# point `image:` at the stock ghcr.io tag again -- nothing here touches the
# database or the media volume.

# Pinned rather than tracking master: this is a young project (v0.1.0 is its
# only release) and an unpinned ref would rebuild to whatever is on master
# whenever the build cache misses. Renovate cannot see this -- its
# `dockerfile` manager reads FROM lines, not ADD-from-git refs -- so bumping it
# is a manual job, the same trap the github-runner base image has.
ARG PLUGIN_REF=v0.1.0

# --- Stage 1: build the plugin wheel from source --------------------------
FROM python:3.12-slim AS plugin
ARG PLUGIN_REF
ADD https://github.com/flobernd/paperless-paddleocr.git#${PLUGIN_REF} /src
WORKDIR /src
RUN pip install --no-cache-dir build \
 && python -m build --wheel --outdir /dist

# --- Stage 2: layer the plugin onto paperless-ngx -------------------------
#
# The version is spelled out here rather than passed as a build arg so that
# Renovate's `dockerfile` manager keeps updating it under the existing
# "paperless stack" group. Moving it into an ARG would make the bumps stop
# silently.
FROM ghcr.io/paperless-ngx/paperless-ngx:3.0.5

# OpenCV/PaddleOCR native deps. The base image is Debian-slim derived and
# carries none of them.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libgl1 \
      libglib2.0-0 \
      libsm6 \
      libxext6 \
      libxrender1 \
      libgomp1 \
 && rm -rf /var/lib/apt/lists/*

# The base image uses the system interpreter at /usr/local with no virtualenv,
# so a plain pip install is visible to paperless at runtime. The [vl] extra
# pulls paddlex[genai-client,ocr], which only this engine needs.
COPY --from=plugin /dist/*.whl /tmp/plugin/
RUN pip install --no-cache-dir "paddlepaddle>=3.0" \
 && WHEEL=$(ls /tmp/plugin/*.whl) \
 && pip install --no-cache-dir "${WHEEL}[vl]" \
 && rm -rf /tmp/plugin
