# syntax=docker/dockerfile:1.7
# CUDA 12.9 + Python 3.12 minimal vLLM runtime for Vast.ai templates.
FROM nvidia/cuda:12.9.1-cudnn-runtime-ubuntu24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG VLLM_WHEEL_URL="https://github.com/vllm-project/vllm/releases/download/v0.20.2/vllm-0.20.2%2Bcu129-cp38-abi3-manylinux_2_31_x86_64.whl"

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:/usr/local/cuda/bin:/usr/local/nvidia/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HF_HOME=/workspace/hf \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    XDG_CACHE_HOME=/workspace/.cache \
    VLLM_CACHE_ROOT=/workspace/.cache/vllm \
    TORCHINDUCTOR_CACHE_DIR=/workspace/.cache/vllm/torch_compile_cache \
    FLASHINFER_CACHE_DIR=/workspace/.cache/flashinfer \
    VLLM_USE_V1=1 \
    MODEL=Qwen/Qwen3.6-27B-FP8 \
    HOST=0.0.0.0 \
    PORT=8000 \
    MAX_MODEL_LEN=131072 \
    MAX_NUM_SEQS=2 \
    GPU_MEMORY_UTILIZATION=0.90 \
    AUTO_TENSOR_PARALLEL=true \
    SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":3}'

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        g++ \
        gcc \
        libc6-dev \
        libgomp1 \
        make \
        cuda-nvcc-12-9 \
        libcurand-dev-12-9 \
        python3.12 \
        python3.12-dev \
        python3.12-venv \
        tini \
    && python3.12 -m venv /opt/venv \
    && pip install --no-cache-dir --upgrade pip setuptools wheel \
    && pip install --no-cache-dir hf_transfer \
    && pip install --no-cache-dir nvidia-modelopt==0.43.0 \
    && pip install --no-cache-dir "${VLLM_WHEEL_URL}" \
    && rm -rf /var/lib/apt/lists/* /root/.cache/pip

WORKDIR /workspace
COPY entrypoint.sh /usr/local/bin/vllm-entrypoint
COPY vllm-restart vllm-status vllm-set-param vllm-wait-ready /usr/local/bin/
RUN chmod +x /usr/local/bin/vllm-entrypoint \
    /usr/local/bin/vllm-restart \
    /usr/local/bin/vllm-status \
    /usr/local/bin/vllm-set-param \
    /usr/local/bin/vllm-wait-ready \
    && mkdir -p /workspace/hf /workspace/.cache/vllm/torch_compile_cache /workspace/.cache/flashinfer /root/.cache \
    && ln -sfn /workspace/.cache/flashinfer /root/.cache/flashinfer

EXPOSE 8000
ENTRYPOINT ["tini", "--", "/usr/local/bin/vllm-entrypoint"]
