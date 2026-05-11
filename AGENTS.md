# AGENTS.md

Project rules for this repo. Follow these before changing the Vast.ai/vLLM template, Docker image, or startup parameters.

## Vast.ai template rules

- Do **not** assume a recreated instance re-runs offer search filters. Recreate may keep the same host. For CUDA 12.9 images, rent a new offer with a compatible driver instead of recreating an old CUDA 12.6 host.
- Vast search/template parameter units matter. Official `vastai search offers --help` says:
  - `gpu_ram` is per-GPU RAM in **GB**, not MB. Use `gpu_ram>=45`, not `gpu_ram>=45000`.
  - `driver_version` is a dotted driver version string such as `535.86.05`, not an integer encoding. Use `driver_version>=570.00.00`, not `driver_version>=570000000`.
  - `cuda_vers` is the offer-search field for max supported CUDA version. Use `cuda_vers>=12.9` when filtering CUDA capability. Do not rely on instance-output-only names like `cuda_max_good` for offer search unless verified by current CLI docs.
- For `ghcr.io/mics8128/vllm-cu129:*`, require a host with NVIDIA driver new enough for CUDA 12.9. Use offer filters such as:
  - `driver_version>=570.00.00`
  - `cuda_vers>=12.9`
  - `gpu_ram>=45`
  - `num_gpus=1`
  - `direct_port_count>=2`
  - `verified=true rentable=true`
- Do **not** use the old host with `driver_version=560.35.05` / `cuda_vers≈12.6` for the cu129 image. It fails with:
  - `RuntimeError: The NVIDIA driver on your system is too old (found version 12060)`
- When using Vast SSH/Jupyter runtype, Vast runs its own startup and then executes template `onstart`. Do **not** set `onstart` to `entrypoint.sh`; this image does not provide that command.
- Correct `onstart` for this image:
  ```bash
  nohup /usr/local/bin/vllm-entrypoint > /workspace/vllm.log 2>&1 &
  ```
- If app env vars need to be visible in interactive shells, append them explicitly to `/etc/environment`, but do not treat interactive shell env as source of truth.
- Docker/Vast env vars may be visible in PID 1 even when not present in an SSH shell. Inspect them with:
  ```bash
  tr '\0' '\n' </proc/1/environ | sort
  ```
- Check mapped public API port with:
  ```bash
  vastai show instance <ID> --raw
  ```
  then inspect `ports["8000/tcp"][0].HostPort`.

## vLLM cu129 image rules

- Current clean image is CUDA 12.9 only. Do not install generic `vllm` from PyPI for this image; PyPI may resolve CUDA 13 and fail with `libcudart.so.13` or driver mismatch.
- Use the explicit cu129 GitHub release wheel for vLLM 0.20.2:
  ```text
  https://github.com/vllm-project/vllm/releases/download/v0.20.2/vllm-0.20.2%2Bcu129-cp38-abi3-manylinux_2_31_x86_64.whl
  ```
- Keep CUDA/runtime/vLLM/Torch versions pinned unless intentionally testing a new release. Before bumping vLLM, verify the new release has a `+cu129` wheel.
- Do not bake model weights or Hugging Face tokens into the image. Use `HF_HOME=/workspace/hf` or a Vast volume path such as `HF_HOME=/data/hf`.
- Token env vars supported by the entrypoint:
  - `HF_TOKEN`
  - `HG_TOKEN` (copied to `HF_TOKEN` if `HF_TOKEN` is unset)
  - `HUGGING_FACE_HUB_TOKEN` (copied to `HF_TOKEN` if `HF_TOKEN` is unset)

## Valid vLLM startup parameters for Qwen3.6 on this image

Use conservative, known-good env names. Do not invent env names unless entrypoint maps them to vLLM flags.

Recommended baseline for single 48GB 4090-class GPU:

```env
MODEL=edp1096/Huihui-Qwen3.6-27B-abliterated-FP8
SERVED_MODEL_NAME=huihui-qwen3.6
HOST=0.0.0.0
PORT=8000
HF_HOME=/workspace/hf
MAX_MODEL_LEN=32768
MAX_NUM_SEQS=4
GPU_MEMORY_UTILIZATION=0.90
ENABLE_PREFIX_CACHING=true
LANGUAGE_MODEL_ONLY=true
REASONING_PARSER=qwen3
ENABLE_AUTO_TOOL_CHOICE=true
TOOL_CALL_PARSER=qwen3_coder
```

Equivalent vLLM command expected from those env vars:

```bash
vllm serve edp1096/Huihui-Qwen3.6-27B-abliterated-FP8 \
  --host 0.0.0.0 \
  --port 8000 \
  --served-model-name huihui-qwen3.6 \
  --max-model-len 32768 \
  --max-num-seqs 4 \
  --gpu-memory-utilization 0.90 \
  --enable-prefix-caching \
  --language-model-only \
  --reasoning-parser qwen3 \
  --enable-auto-tool-choice \
  --tool-call-parser qwen3_coder
```

## Parameters to avoid

- Do **not** set `DISABLE_LOG_REQUESTS=true` with the current entrypoint/vLLM image. In the tested image, adding `--disable-log-requests` caused:
  ```text
  vllm: error: unrecognized arguments: --disable-log-requests
  ```
- Do not set `MAX_MODEL_LEN=auto` as the baseline for a 48GB 4090 unless the current vLLM CLI/model docs explicitly support the exact value. Use `32768` first, then tune upward after the model is confirmed running.
- Do not set `MAX_NUM_SEQS=10` as the baseline on a single 48GB 4090. Start with `4`, then benchmark/tune.
- Do not enable speculative decoding as the baseline template default. First confirm plain serving works.

## Optional MTP/speculative parameters

Only after baseline serving works, test MTP with conservative settings:

```env
SPECULATIVE_CONFIG={"method":"mtp","num_speculative_tokens":2}
```

Video/comment-style aggressive settings are experimental and may OOM or reduce acceptance rate:

```env
SPECULATIVE_CONFIG={"method":"mtp","num_speculative_tokens":3}
MAX_NUM_SEQS=10
GPU_MEMORY_UTILIZATION=0.92
```

If using speculative decoding, consider adding/tuning:

```env
MAX_NUM_BATCHED_TOKENS=4096
```

but benchmark before making it a template default.

## Debugging checklist

- Instance ready:
  ```bash
  vastai show instance <ID> --raw
  ```
- Logs:
  ```bash
  vastai logs <ID>
  ```
- SSH direct port from `ports["22/tcp"]`, then:
  ```bash
  tail -f /workspace/vllm.log
  nvidia-smi
  netstat -ltnp | grep 8000 || true
  curl http://127.0.0.1:8000/v1/models
  ```
- If vLLM does not start, first check:
  - onstart command path
  - actual Docker env via `/proc/1/environ`
  - unsupported vLLM flags
  - driver/CUDA compatibility
  - Hugging Face access/rate limits
