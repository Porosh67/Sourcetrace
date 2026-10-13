# AMD AI League MC3 mandated base image (ROCm built PyTorch)
FROM rocm/pytorch:rocm6.2_ubuntu22.04_py3.10_pytorch_2.3.0

# Set system environment variables
ENV PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    HF_HUB_OFFLINE=1

WORKDIR /app

# Install system dependencies securely
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-pip \
    python3-setuptools \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements or directly install needed packages using the safe --no-deps method
# This prevents pip from accidentally replacing ROCm torch with a CUDA version!
RUN pip install --no-cache-dir --no-deps -U transformers tokenizers safetensors pypdf openpyxl python-docx

# Copy the actual application files into the image
COPY . /app

# Magic Step: Download Qwen3-VL-8B-Instruct directly into the image path
# and instantly delete huggingface cache in the SAME LINE to save huge space!
RUN python3 -c "from huggingface_hub import snapshot_download; \
    snapshot_download(repo_id='Qwen/Qwen3-VL-8B-Instruct', local_dir='/models/model')" && \
    rm -rf ~/.cache/huggingface/hub/models--*

# Verify ROCm torch installation status before packaging closes
RUN python3 -c "import torch; print('ROCm Active:', torch.cuda.is_available(), torch.__version__)"

# Default command to run the resident server setup required by Match 3 brief
CMD ["python3", "/app/app.py", "--serve"]
