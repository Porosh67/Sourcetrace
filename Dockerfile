# syntax=docker/dockerfile:1.7
#
# SourceTrace: citation-exact retrieval-augmented QA over mixed documents (AMD ROCm).
#
# Hard rules this file follows (any one of them failing scores ZERO):
#   * the FINAL image starts FROM the mandated ROCm base image (checked by layer identity);
#   * never squash/flatten the image - it destroys the layer identity the grader compares;
#   * image <= 60 GiB uncompressed: the base is ~29 GiB, Qwen3-VL-8B (bf16) ~17 GiB, the rest
#     (python packages, embedding model, code) ~2 GiB;
#   * pip must NEVER replace the base image's ROCm torch with a CUDA wheel (see step 1);
#   * the container has NO network at grading time: all weights are baked in below;
#   * everything under /app, weights under /models; no secrets (the image is public).
#
# Build:   docker build -t sourcetrace:local .
# Pin the weights for a reproducible build:
#          docker build --build-arg MODEL_REVISION=<commit-sha> -t sourcetrace:local .

ARG BASE_IMAGE=rocm/pytorch:rocm10.0_ubuntu26.04_py3.14_pytorch_release_2.13.0
FROM ${BASE_IMAGE}

ARG MODEL_ID=Qwen/Qwen3-VL-8B-Instruct
ARG MODEL_REVISION=main
# Dense retrieval model (130 MB). Set EMBED_MODEL_ID="" to build without it (BM25 only).
ARG EMBED_MODEL_ID=BAAI/bge-small-en-v1.5
ARG EMBED_MODEL_REVISION=main
# Only if the processor complains about torchvision (see README > Known risks):
#   --build-arg TORCHVISION_SPEC="torchvision==<matching> --index-url https://download.pytorch.org/whl/rocm<ver>"
ARG TORCHVISION_SPEC=""

LABEL org.opencontainers.image.title="SourceTrace" \
      org.opencontainers.image.description="Citation-exact RAG over mixed documents on AMD ROCm" \
      org.opencontainers.image.licenses="MIT"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1

WORKDIR /app

# 1) Python dependencies. torch/torchvision/triton are pinned to what the base already ships
#    (a pip constraints file), so resolving `transformers`/`accelerate` can never swap the
#    ROCm torch for a CUDA wheel (torch 2.14.0+cu130 over 2.13.0+rocm10.0.0 was measured on
#    the evaluation hardware). The last command fails the BUILD if torch ever stops being ROCm.
COPY app/requirements.txt /app/requirements.txt
RUN python3 -m pip freeze | grep -iE '^(torch|torchvision|torchaudio|triton|pytorch-triton-rocm)==' > /tmp/torch-constraints.txt || true \
 && echo "pinned from the base image:" && cat /tmp/torch-constraints.txt \
 && python3 -m pip install -c /tmp/torch-constraints.txt -r /app/requirements.txt \
 && if [ -n "${TORCHVISION_SPEC}" ]; then python3 -m pip install --no-deps ${TORCHVISION_SPEC}; fi \
 && python3 -c "import torch; v=torch.__version__; print('torch', v, 'hip', torch.version.hip); assert torch.version.hip and '+rocm' in v, 'torch is no longer the ROCm build'" \
 && rm -f /tmp/torch-constraints.txt

# 2) Weights are baked into the image (no network at grading; downloading at start-up
#    would also eat the 10 minute startup budget). Separate layers: they never change when
#    the code does.
COPY scripts/download_model.py /tmp/download_model.py
RUN python3 /tmp/download_model.py --model-id "${MODEL_ID}" --revision "${MODEL_REVISION}" --dest /models/model \
 && rm -rf /models/model/.cache /root/.cache
RUN if [ -n "${EMBED_MODEL_ID}" ]; then \
      python3 /tmp/download_model.py --model-id "${EMBED_MODEL_ID}" --revision "${EMBED_MODEL_REVISION}" --dest /models/embed \
      && rm -rf /models/embed/.cache /root/.cache; \
    fi \
 && rm -f /tmp/download_model.py

# 3) Application code (last, so code edits never invalidate the big layers above).
COPY app/ /app/
RUN mkdir -p /app/corpus /app/output /app/index && chmod 777 /app/output /app/index

# Offline from here on; the resident server starts with the container.
ENV SOURCETRACE_MODEL_PATH=/models/model \
    SOURCETRACE_MODE=server \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1

# The harness never starts a service for us; it `docker exec`s `python3 /app/app.py ...` into
# the running container, once per question, each time as a NEW process. The container's main
# process is therefore the resident server that keeps the model and the index in memory.
# (If a runner overrides CMD, app.py starts the server itself on the first call.)
HEALTHCHECK --interval=30s --timeout=5s --start-period=600s --retries=3 \
  CMD ["python3", "/app/app.py", "--healthcheck"]

CMD ["python3", "/app/app.py", "--serve"]
