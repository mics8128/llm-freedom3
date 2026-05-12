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
export HF_HOME

# Accept common token aliases. Hugging Face tooling reads HF_TOKEN.
if [[ -z "${HF_TOKEN:-}" && -n "${HG_TOKEN:-}" ]]; then
  export HF_TOKEN="${HG_TOKEN}"
fi
if [[ -z "${HF_TOKEN:-}" && -n "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
  export HF_TOKEN="${HUGGING_FACE_HUB_TOKEN}"
fi

mkdir -p "${HF_HOME}"

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
