#!/usr/bin/env bash
set -euo pipefail

bool_on() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

MODEL="${MODEL:-${VLLM_MODEL:-}}"
if [[ -z "${MODEL}" ]]; then
  echo "ERROR: set MODEL, e.g. MODEL=Qwen/Qwen3.6-27B-FP8" >&2
  exit 64
fi

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
HF_HOME="${HF_HOME:-/workspace/hf}"
VLLM_CACHE_ROOT="${VLLM_CACHE_ROOT:-/workspace/.cache/vllm}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-/workspace/.cache}"
TORCHINDUCTOR_CACHE_DIR="${TORCHINDUCTOR_CACHE_DIR:-${VLLM_CACHE_ROOT}/torch_compile_cache}"
FLASHINFER_CACHE_DIR="${FLASHINFER_CACHE_DIR:-${XDG_CACHE_HOME}/flashinfer}"
export HF_HOME VLLM_CACHE_ROOT XDG_CACHE_HOME TORCHINDUCTOR_CACHE_DIR FLASHINFER_CACHE_DIR

# Accept common token aliases. Hugging Face tooling reads HF_TOKEN.
if [[ -z "${HF_TOKEN:-}" && -n "${HG_TOKEN:-}" ]]; then
  export HF_TOKEN="${HG_TOKEN}"
fi
if [[ -z "${HF_TOKEN:-}" && -n "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
  export HF_TOKEN="${HUGGING_FACE_HUB_TOKEN}"
fi

mkdir -p "${HF_HOME}" "${VLLM_CACHE_ROOT}" "${XDG_CACHE_HOME}" "${TORCHINDUCTOR_CACHE_DIR}" "${FLASHINFER_CACHE_DIR}" /root/.cache
if [[ -e /root/.cache/flashinfer && ! -L /root/.cache/flashinfer ]]; then
  cp -a /root/.cache/flashinfer/. "${FLASHINFER_CACHE_DIR}/" 2>/dev/null || true
  rm -rf /root/.cache/flashinfer
fi
ln -sfn "${FLASHINFER_CACHE_DIR}" /root/.cache/flashinfer

# Persist Vast.ai template/runtime environment for SSH debug helpers such as
# vllm-restart. Keep this in the image so Vast template onstart can stay tiny.
VLLM_ENV_FILE="${VLLM_ENV_FILE:-/workspace/vllm.env}"
VLLM_ENV_KEYS=(
  MODEL VLLM_MODEL SERVED_MODEL_NAME HOST PORT HF_HOME XDG_CACHE_HOME
  VLLM_CACHE_ROOT TORCHINDUCTOR_CACHE_DIR FLASHINFER_CACHE_DIR DOWNLOAD_DIR
  DTYPE QUANTIZATION TRUST_REMOTE_CODE TENSOR_PARALLEL_SIZE
  PIPELINE_PARALLEL_SIZE AUTO_TENSOR_PARALLEL MAX_MODEL_LEN MAX_NUM_SEQS
  MAX_NUM_BATCHED_TOKENS GPU_MEMORY_UTILIZATION ENABLE_PREFIX_CACHING
  DISABLE_PREFIX_CACHING LANGUAGE_MODEL_ONLY LIMIT_MM_PER_PROMPT
  MM_PROCESSOR_KWARGS ALLOWED_LOCAL_MEDIA_PATH REASONING_PARSER
  ENABLE_REASONING ENABLE_AUTO_TOOL_CHOICE TOOL_CALL_PARSER VLLM_API_KEY
  SPECULATIVE_CONFIG CHAT_TEMPLATE ENFORCE_EAGER EXTRA_ARGS
  VLLM_NVFP4_GEMM_BACKEND VLLM_USE_FLASHINFER_MOE_FP4
  VLLM_USE_FLASHINFER_SAMPLER HF_TOKEN HG_TOKEN HUGGING_FACE_HUB_TOKEN
)
mkdir -p "$(dirname "${VLLM_ENV_FILE}")"
{
  for key in "${VLLM_ENV_KEYS[@]}"; do
    if [[ -n "${!key+x}" ]]; then
      printf '%s=%q\n' "${key}" "${!key}"
    fi
  done
} > "${VLLM_ENV_FILE}.tmp"
mv "${VLLM_ENV_FILE}.tmp" "${VLLM_ENV_FILE}"
chmod 600 "${VLLM_ENV_FILE}" || true

# vLLM defaults tensor parallelism to 1. For Vast.ai multi-GPU rentals,
# auto-use all visible GPUs unless TENSOR_PARALLEL_SIZE is explicitly set.
AUTO_TENSOR_PARALLEL="${AUTO_TENSOR_PARALLEL:-true}"
if [[ -z "${TENSOR_PARALLEL_SIZE:-}" ]] && bool_on "${AUTO_TENSOR_PARALLEL}" && command -v nvidia-smi >/dev/null 2>&1; then
  gpu_count="$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${gpu_count}" =~ ^[0-9]+$ && "${gpu_count}" -gt 1 ]]; then
    export TENSOR_PARALLEL_SIZE="${gpu_count}"
  fi
fi

args=(
  "${MODEL}"
  --host "${HOST}"
  --port "${PORT}"
)

[[ -n "${SERVED_MODEL_NAME:-}" ]] && args+=(--served-model-name "${SERVED_MODEL_NAME}")
[[ -n "${DOWNLOAD_DIR:-}" ]] && args+=(--download-dir "${DOWNLOAD_DIR}")
[[ -n "${DTYPE:-}" ]] && args+=(--dtype "${DTYPE}")
[[ -n "${QUANTIZATION:-}" ]] && args+=(--quantization "${QUANTIZATION}")
[[ -n "${TENSOR_PARALLEL_SIZE:-}" ]] && args+=(--tensor-parallel-size "${TENSOR_PARALLEL_SIZE}")
[[ -n "${PIPELINE_PARALLEL_SIZE:-}" ]] && args+=(--pipeline-parallel-size "${PIPELINE_PARALLEL_SIZE}")
[[ -n "${MAX_MODEL_LEN:-}" ]] && args+=(--max-model-len "${MAX_MODEL_LEN}")
[[ -n "${MAX_NUM_SEQS:-}" ]] && args+=(--max-num-seqs "${MAX_NUM_SEQS}")
[[ -n "${MAX_NUM_BATCHED_TOKENS:-}" ]] && args+=(--max-num-batched-tokens "${MAX_NUM_BATCHED_TOKENS}")
[[ -n "${GPU_MEMORY_UTILIZATION:-}" ]] && args+=(--gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}")
[[ -n "${REASONING_PARSER:-}" ]] && args+=(--reasoning-parser "${REASONING_PARSER}")
[[ -n "${TOOL_CALL_PARSER:-}" ]] && args+=(--tool-call-parser "${TOOL_CALL_PARSER}")
[[ -n "${VLLM_API_KEY:-}" ]] && args+=(--api-key "${VLLM_API_KEY}")
[[ -n "${SPECULATIVE_CONFIG:-}" ]] && args+=(--speculative-config "${SPECULATIVE_CONFIG}")
[[ -n "${CHAT_TEMPLATE:-}" ]] && args+=(--chat-template "${CHAT_TEMPLATE}")
[[ -n "${LIMIT_MM_PER_PROMPT:-}" ]] && args+=(--limit-mm-per-prompt "${LIMIT_MM_PER_PROMPT}")
[[ -n "${MM_PROCESSOR_KWARGS:-}" ]] && args+=(--mm-processor-kwargs "${MM_PROCESSOR_KWARGS}")
[[ -n "${ALLOWED_LOCAL_MEDIA_PATH:-}" ]] && args+=(--allowed-local-media-path "${ALLOWED_LOCAL_MEDIA_PATH}")

if bool_on "${TRUST_REMOTE_CODE:-}"; then
  args+=(--trust-remote-code)
fi
if bool_on "${ENABLE_PREFIX_CACHING:-}"; then
  args+=(--enable-prefix-caching)
fi
if bool_on "${DISABLE_PREFIX_CACHING:-}"; then
  args+=(--disable-prefix-caching)
fi
if bool_on "${ENABLE_AUTO_TOOL_CHOICE:-}"; then
  args+=(--enable-auto-tool-choice)
fi
if bool_on "${ENABLE_REASONING:-}"; then
  args+=(--enable-reasoning)
fi
if bool_on "${LANGUAGE_MODEL_ONLY:-}"; then
  args+=(--language-model-only)
fi
if bool_on "${ENFORCE_EAGER:-}"; then
  args+=(--enforce-eager)
fi
if [[ -n "${EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra=( ${EXTRA_ARGS} )
  args+=("${extra[@]}")
fi

if [[ "$#" -gt 0 ]]; then
  exec "$@"
fi

exec vllm serve "${args[@]}"
