# vLLM CUDA 12.9 Vast.ai Docker Setup

OpenAI-compatible vLLM server image for Vast.ai templates.

## Contents

- `Dockerfile` — CUDA 12.9.1 cuDNN runtime, Ubuntu 24.04, Python 3.12, vLLM `0.20.2+cu129` GitHub release wheel.
- `entrypoint.sh` — starts `vllm serve` OpenAI-compatible server with env-driven options.
- `vllm-restart`, `vllm-status`, `vllm-set-param`, `vllm-wait-ready` — helper commands for SSH-mode Vast.ai debugging and short-downtime parameter changes.

## Build

From repo root:

```bash
docker build -t vllm-cu129:0.20.2 -f docker/vllm-cu129/Dockerfile docker/vllm-cu129

docker buildx build --platform linux/amd64 \
  -t ghcr.io/mics8128/vllm-cu129:0.20.2-cu129-nvfp4 \
  -f docker/vllm-cu129/Dockerfile docker/vllm-cu129 --push
```

Override wheel if release asset name changes:

```bash
docker build \
  --build-arg VLLM_WHEEL_URL='https://github.com/vllm-project/vllm/releases/download/v0.20.2/vllm-0.20.2%2Bcu129-cp38-abi3-manylinux_2_31_x86_64.whl' \
  -t vllm-cu129:0.20.2 \
  -f docker/vllm-cu129/Dockerfile docker/vllm-cu129
```

## Run locally

```bash
docker run --gpus all --rm -p 8000:8000 \
  -e HF_TOKEN="$HF_TOKEN" \
  -e MODEL=Qwen/Qwen3.6-27B-FP8 \
  -e MAX_MODEL_LEN=32768 \
  -e MAX_NUM_SEQS=16 \
  -e GPU_MEMORY_UTILIZATION=0.92 \
  -e ENABLE_PREFIX_CACHING=true \
  -e ENABLE_REASONING=true \
  -e REASONING_PARSER=qwen3 \
  -v "$PWD/.hf:/workspace/hf" \
  vllm-cu129:0.20.2
```

Health/API checks:

```bash
curl http://localhost:8000/v1/models
curl http://localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen/Qwen3.6-27B-FP8","messages":[{"role":"user","content":"Say hi"}],"max_tokens":32}'
```

## Debug helpers

These helpers are most useful on Vast.ai SSH templates, where vLLM runs as a background process and the container remains alive after vLLM exits.

Inspect status:

```bash
vllm-status
```

Persist parameter overrides to `/workspace/vllm.env`:

```bash
vllm-set-param MAX_NUM_SEQS=2 GPU_MEMORY_UTILIZATION=0.92
```

Restart vLLM on the same port, loading `/workspace/vllm.env` first:

```bash
vllm-restart
vllm-wait-ready 300
```

Use a different env/log path if needed:

```bash
VLLM_ENV_FILE=/workspace/video.env VLLM_LOG_FILE=/workspace/vllm-video.log vllm-restart
```

In normal Docker entrypoint mode, killing vLLM exits the container. Use these helpers with SSH/Jupyter mode, a supervisor, or an external restart policy.

## Vast.ai template guidance

Template image should be built/pushed to registry first, then used in Vast.ai as Docker image.

Recommended template fields:

- Docker image: your pushed image tag.
- Launch mode/command: leave empty. Entrypoint starts server.
- Expose port: `8000/tcp`.
- Port mapping: map container `8000` to Vast.ai public HTTP port.
- Disk: enough for model cache. 27B FP8 can need large cache; use 80GB+ if unsure.
- GPU: choose VRAM for model and context. Tune `MAX_MODEL_LEN`, `MAX_NUM_SEQS`, and `GPU_MEMORY_UTILIZATION` for fit.
- Volume: mount persistent volume for Hugging Face cache.
  - If mounted at `/data`, set `HF_HOME=/data/hf`.
  - Otherwise default is `HF_HOME=/workspace/hf`.
- Secrets: pass `HF_TOKEN` only if model or rate limits require login. `HG_TOKEN` and `HUGGING_FACE_HUB_TOKEN` aliases are also accepted and exported as `HF_TOKEN`. Do not bake tokens into image.

Vast.ai environment variables example:

```env
MODEL=Qwen/Qwen3.6-27B-FP8
PORT=8000
HOST=0.0.0.0
HF_HOME=/data/hf
MAX_MODEL_LEN=32768
MAX_NUM_SEQS=4
GPU_MEMORY_UTILIZATION=0.90
ENABLE_PREFIX_CACHING=true
LANGUAGE_MODEL_ONLY=true
REASONING_PARSER=qwen3
ENABLE_AUTO_TOOL_CHOICE=true
TOOL_CALL_PARSER=qwen3_coder
DISABLE_LOG_REQUESTS=true
```

If no `/data` volume is mounted, use:

```env
HF_HOME=/workspace/hf
```

## Example: Qwen/Qwen3.6-27B-FP8

```env
MODEL=Qwen/Qwen3.6-27B-FP8
SERVED_MODEL_NAME=qwen3.6-27b-fp8
MAX_MODEL_LEN=32768
MAX_NUM_SEQS=4
GPU_MEMORY_UTILIZATION=0.90
ENABLE_PREFIX_CACHING=true
REASONING_PARSER=qwen3
ENABLE_AUTO_TOOL_CHOICE=true
TOOL_CALL_PARSER=qwen3_coder
LANGUAGE_MODEL_ONLY=true
HF_HOME=/data/hf
```

## Example: edp1096/Huihui-Qwen3.6-27B-abliterated-FP8

```env
MODEL=edp1096/Huihui-Qwen3.6-27B-abliterated-FP8
SERVED_MODEL_NAME=huihui-qwen3.6-27b-abliterated-fp8
MAX_MODEL_LEN=32768
MAX_NUM_SEQS=4
GPU_MEMORY_UTILIZATION=0.90
ENABLE_PREFIX_CACHING=true
REASONING_PARSER=qwen3
ENABLE_AUTO_TOOL_CHOICE=true
TOOL_CALL_PARSER=qwen3_coder
LANGUAGE_MODEL_ONLY=true
HF_HOME=/data/hf
```

## Config env vars

| Env var | vLLM flag / behavior |
| --- | --- |
| `MODEL` | positional model id/path. Required. Default in image: `Qwen/Qwen3.6-27B-FP8`. |
| `HOST` | `--host`, default `0.0.0.0`. |
| `PORT` | `--port`, default `8000`. |
| `SERVED_MODEL_NAME` | `--served-model-name`. |
| `DOWNLOAD_DIR` | `--download-dir`. Usually leave empty and use `HF_HOME`. |
| `HF_HOME` | Hugging Face cache. Use `/data/hf` with Vast.ai mounted volume, else `/workspace/hf`. |
| `XDG_CACHE_HOME` | Runtime cache root for libraries such as FlashInfer. Defaults to `/workspace/.cache` so JIT/autotune caches can survive vLLM restarts on the same Vast.ai instance. |
| `VLLM_CACHE_ROOT` | vLLM cache root. Defaults to `/workspace/.cache/vllm`. |
| `TORCHINDUCTOR_CACHE_DIR` | TorchInductor compile cache. Defaults to `/workspace/.cache/vllm/torch_compile_cache`. |
| `FLASHINFER_CACHE_DIR` | FlashInfer kernel cache. Defaults to `/workspace/.cache/flashinfer`; entrypoint symlinks `/root/.cache/flashinfer` here because FlashInfer writes cached FP4 GEMM builds under root's cache directory. |
| `HF_TOKEN` / `HG_TOKEN` / `HUGGING_FACE_HUB_TOKEN` | Hugging Face auth token. `HG_TOKEN` and `HUGGING_FACE_HUB_TOKEN` are copied to `HF_TOKEN` if `HF_TOKEN` is unset. |
| `DTYPE` | `--dtype`, e.g. `auto`, `bfloat16`, `float16`. |
| `QUANTIZATION` | `--quantization`, if needed. FP8 model repos often auto-detect. |
| `TENSOR_PARALLEL_SIZE` | `--tensor-parallel-size` for multi-GPU. |
| `PIPELINE_PARALLEL_SIZE` | `--pipeline-parallel-size`. |
| `MAX_MODEL_LEN` | `--max-model-len`. Lower to fit VRAM. |
| `MAX_NUM_SEQS` | `--max-num-seqs`. Lower to fit VRAM. |
| `MAX_NUM_BATCHED_TOKENS` | `--max-num-batched-tokens`. Useful with speculative decoding. |
| `GPU_MEMORY_UTILIZATION` | `--gpu-memory-utilization`, e.g. `0.90` to `0.95`. |
| `ENABLE_PREFIX_CACHING=true` | adds `--enable-prefix-caching`. |
| `DISABLE_PREFIX_CACHING=true` | adds `--disable-prefix-caching`. Use only if needed. |
| `ENABLE_REASONING=true` | adds `--enable-reasoning`. |
| `REASONING_PARSER` | `--reasoning-parser`, e.g. `qwen3`. |
| `ENABLE_AUTO_TOOL_CHOICE=true` | adds `--enable-auto-tool-choice`. |
| `TOOL_CALL_PARSER` | `--tool-call-parser`, e.g. `qwen3_coder`. |
| `VLLM_API_KEY` | `--api-key`. Set to a secret on private instances; templates should use a placeholder such as `please-change-me-for-security`. |
| `LANGUAGE_MODEL_ONLY=true` | adds `--language-model-only` for text-only Qwen3.6 serving. |
| `ENFORCE_EAGER=true` | adds `--enforce-eager`. Usually slower but can avoid compile issues. |
| `SPECULATIVE_CONFIG` | `--speculative-config`. Pass JSON string or config path accepted by vLLM. |
| `CHAT_TEMPLATE` | `--chat-template`. |
| `TRUST_REMOTE_CODE=true` | adds `--trust-remote-code`. Avoid unless model requires it. |
| `DISABLE_LOG_REQUESTS=true` | adds `--disable-log-requests`. |
| `EXTRA_ARGS` | appended to vLLM command. Escape carefully. |

## Video/comment parameter set

Equivalent to the YouTube comment, adjusted for this image and Qwen3.6:

```env
MODEL=Qwen/Qwen3.6-27B-FP8
SERVED_MODEL_NAME=qwen3.6
PORT=5000
SPECULATIVE_CONFIG={"method":"mtp","num_speculative_tokens":3}
MAX_NUM_SEQS=10
MAX_MODEL_LEN=auto
ENABLE_PREFIX_CACHING=true
GPU_MEMORY_UTILIZATION=0.92
REASONING_PARSER=qwen3
ENABLE_AUTO_TOOL_CHOICE=true
TOOL_CALL_PARSER=qwen3_coder
LANGUAGE_MODEL_ONLY=true
HF_HOME=/data/hf
```

If `MAX_MODEL_LEN=auto` or `MAX_NUM_SEQS=10` OOMs on a single 48GB 4090, use the safer baseline:

```env
MAX_MODEL_LEN=32768
MAX_NUM_SEQS=4
GPU_MEMORY_UTILIZATION=0.90
SPECULATIVE_CONFIG={"method":"mtp","num_speculative_tokens":2}
```

## Speculative decoding example

```env
SPECULATIVE_CONFIG={"method":"mtp","num_speculative_tokens":2}
```

If Vast.ai UI mangles JSON quoting, put config in mounted file and use:

```env
SPECULATIVE_CONFIG=/workspace/speculative.json
```

## Notes

- Image does not include model weights.
- Entrypoint creates `HF_HOME` at startup.
- For mounted Vast.ai volume, prefer `HF_HOME=/data/hf`; otherwise use `HF_HOME=/workspace/hf`.
- Do not store `HF_TOKEN` in Dockerfile or README examples with real values.
