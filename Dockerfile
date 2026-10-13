# syntax=docker/dockerfile:1.7
#
# SourceTrace: citation-exact retrieval-augmented QA over mixed documents (AMD ROCm).
#
# Important grading constraints:
# - Use the mandated base image and preserve its layers.
# - Keep the uncompressed image at or below 60 GiB.
# - Bake model weights into the image for offline grading.
# - Never allow pip to replace ROCm PyTorch with CUDA PyTorch.

ARG BASE_IMAGE=rocm/pytorch:rocm10.0_ubuntu26.04_py3.14_pytorch_release_2.13.0
FROM ${BASE_IMAGE}

ARG MODEL_ID=Qwen/Qwen3-VL-8B-Instruct
ARG MODEL_REVISION=main
ARG EMBED_MODEL_ID=BAAI/bge-small-en-v1.5
ARG EMBED_MODEL_REVISION=main
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

# Preserve the ROCm versions shipped in the required base image.
COPY app/requirements.txt /app/requirements.txt

RUN python3 -m pip freeze | grep -iE '^(torch|torchvision|torchaudio|triton|pytorch-triton-rocm)==' > /tmp/torch-constraints.txt || true \
 && echo "Pinned packages from the base image:" \
 && cat /tmp/torch-constraints.txt \
 && python3 -m pip install -c /tmp/torch-constraints.txt -r /app/requirements.txt \
 && if [ -n "${TORCHVISION_SPEC}" ]; then python3 -m pip install --no-deps ${TORCHVISION_SPEC}; fi \
 && python3 -c "import torch; v=torch.__version__; print('torch', v, 'HIP', torch.version.hip); assert torch.version.hip and '+rocm' in v, 'torch is no longer the ROCm build'" \
 && rm -f /tmp/torch-constraints.txt

# Bake the main model into the image.
COPY scripts/download_model.py /tmp/download_model.py

RUN python3 /tmp/download_model.py \
      --model-id "${MODEL_ID}" \
      --revision "${MODEL_REVISION}" \
      --dest /models/model \
 && rm -rf /models/model/.cache /root/.cache

# Bake the dense-retrieval model too, unless explicitly disabled.
RUN if [ -n "${EMBED_MODEL_ID}" ]; then \
      python3 /tmp/download_model.py \
        --model-id "${EMBED_MODEL_ID}" \
        --revision "${EMBED_MODEL_REVISION}" \
        --dest /models/embed \
      && rm -rf /models/embed/.cache /root/.cache; \
    fi \
 && rm -f /tmp/download_model.py

# Copy application code after the large model layers.
COPY app/ /app/

RUN mkdir -p /app/corpus /app/output /app/index \
 && chmod 777 /app/output /app/index

# No network access is required at runtime.
ENV SOURCETRACE_MODEL_PATH=/models/model \
    SOURCETRACE_MODE=server \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1

HEALTHCHECK --interval=30s --timeout=5s --start-period=600s --retries=3 \
  CMD ["python3", "/app/app.py", "--healthcheck"]

CMD ["python3", "/app/app.py", "--serve"]