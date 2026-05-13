# Vast.ai Huihui Qwen3.6 27B FP8 — RTX 4090 128K Working Setup

Date: 2026-05-13

## Status

This is the current accepted working setup for serving `edp1096/Huihui-Qwen3.6-27B-abliterated-FP8` on a single Vast.ai RTX 4090 48GB instance.

User assessment: current speed is good enough; keep this setup as reference.

## Instance

```text
Instance ID: 36625605
GPU: NVIDIA GeForce RTX 4090
VRAM: 49140 MiB
Compute capability: 8.9
Driver: 580.65.06
CUDA max: 13.0
CPU: AMD Ryzen Threadripper PRO 5955WX 16-Cores
System RAM: ~257386 MB
Disk: 80 GB
Image: ghcr.io/mics8128/vllm-cu129:0.20.2-cu129
```

## Endpoints

```env
API_URL=http://67.223.143.80:20068/v1
API_KEY=vast
MODEL=huihui-qwen3.6
```

SSH:

```bash
ssh -p 20016 root@67.223.143.80
```

Note: current vLLM server does not enforce the dummy `vast` API key.

## Runtime configuration

`/workspace/vllm.env`:

```env
MODEL=edp1096/Huihui-Qwen3.6-27B-abliterated-FP8
SERVED_MODEL_NAME=huihui-qwen3.6
HOST=0.0.0.0
PORT=8000
HF_HOME=/workspace/hf
MAX_MODEL_LEN=131072
MAX_NUM_SEQS=2
GPU_MEMORY_UTILIZATION=0.90
ENABLE_PREFIX_CACHING=true
LANGUAGE_MODEL_ONLY=false
LIMIT_MM_PER_PROMPT='{"image":4,"video":0}'
REASONING_PARSER=qwen3
ENABLE_AUTO_TOOL_CHOICE=true
TOOL_CALL_PARSER=qwen3_coder
SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":3}'
EXTRA_ARGS="--kv-cache-dtype fp8 --calculate-kv-scales --attention-backend TRITON_ATTN"
```

Effective vLLM command:

```bash
vllm serve edp1096/Huihui-Qwen3.6-27B-abliterated-FP8 \
  --host 0.0.0.0 \
  --port 8000 \
  --served-model-name huihui-qwen3.6 \
  --max-model-len 131072 \
  --max-num-seqs 2 \
  --gpu-memory-utilization 0.90 \
  --reasoning-parser qwen3 \
  --tool-call-parser qwen3_coder \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
  --enable-prefix-caching \
  --enable-auto-tool-choice \
  --limit-mm-per-prompt '{"image":4,"video":0}' \
  --kv-cache-dtype fp8 \
  --calculate-kv-scales \
  --attention-backend TRITON_ATTN
```

## Why this setup

### 128K + seqs=2 requires FP8 KV cache

Without KV cache compression, one RTX 4090 48GB cannot fit 128K context with `MAX_NUM_SEQS=2`.

With FP8 KV cache, vLLM reported:

```text
Available KV cache memory: 11.75 GiB
GPU KV cache size: 305,384 tokens
Maximum concurrency for 131,072 tokens per request: 2.33x
```

So `128K / seqs=2` is viable.

### Force TRITON attention backend

Auto backend selected FlashInfer and crashed on first request because current runtime image lacks `nvcc`:

```text
/usr/local/cuda/bin/nvcc: not found
```

`FLASH_ATTN` is also not valid with this KV dtype:

```text
ValueError: Selected backend AttentionBackendEnum.FLASH_ATTN is not valid for this configuration. Reason: ['kv_cache_dtype not supported']
```

Therefore keep:

```bash
--attention-backend TRITON_ATTN
```

## Benchmark results

Setup:

```text
MAX_MODEL_LEN=131072
MAX_NUM_SEQS=2
KV cache dtype=fp8
Attention backend=TRITON_ATTN
MTP speculative tokens=3
```

| prompt | max_tokens | concurrency | avg latency | aggregate output tok/s |
|---|---:|---:|---:|---:|
| small | 128 | 1 | 5.37s | 23.8 |
| small | 128 | 2 | 5.37s | 47.6 |
| small | 512 | 1 | 10.87s | 47.1 |
| small | 512 | 2 | 12.20s | 78.0 |
| medium | 128 | 1 | 3.03s | 42.3 |
| medium | 128 | 2 | 3.43s | 74.6 |
| medium | 512 | 1 | 10.33s | 49.6 |
| medium | 512 | 2 | 10.32s | 99.2 |

Observed during real pi/API use:

```text
GPU util: ~98%
VRAM: ~42186 / 49140 MiB
Running: usually 1 request
Waiting: 0 requests
GPU KV cache usage: ~17–22% on observed prompts
Prefix cache hit rate: ~83–91%
Generation throughput while active: ~15–50 tok/s
Speculative decoding acceptance: varied ~37–99%, workload dependent
```

## Comparison: faster 32K setup

Previous faster text-only setup:

```env
MAX_MODEL_LEN=32768
MAX_NUM_SEQS=4
GPU_MEMORY_UTILIZATION=0.90
SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":3}'
ENABLE_PREFIX_CACHING=true
LANGUAGE_MODEL_ONLY=true
```

Observed benchmark:

```text
32K / seqs=4: ~155–188 aggregate output tok/s at concurrency 4
128K / seqs=2 / fp8 KV: ~99 aggregate output tok/s at concurrency 2
```

Tradeoff: current 128K setup is ~35% slower in aggregate than the 32K sweet spot, but gives 4x context and real `seqs=2` capacity.

## Pi integration

`~/.pi/agent/models.json` points to:

```json
{
  "baseUrl": "http://67.223.143.80:20068/v1",
  "api": "openai-completions",
  "apiKey": "vast",
  "models": [
    {
      "id": "huihui-qwen3.6",
      "name": "Vast Huihui Qwen3.6 27B FP8 vLLM 4090 128K",
      "contextWindow": 131072,
      "input": ["text"]
    }
  ]
}
```

The instance currently accepts text and image input because `LANGUAGE_MODEL_ONLY=false` and `LIMIT_MM_PER_PROMPT={"image":4,"video":0}`.

## Current vision-enabled retest — 2026-05-13

Current runtime checked before retest:

```env
MAX_MODEL_LEN=131072
MAX_NUM_SEQS=2
GPU_MEMORY_UTILIZATION=0.90
LANGUAGE_MODEL_ONLY=false
LIMIT_MM_PER_PROMPT='{"image":4,"video":0}'
SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":3}'
EXTRA_ARGS="--kv-cache-dtype fp8 --calculate-kv-scales --attention-backend TRITON_ATTN"
```

Health:

```text
/v1/models: HTTP 200
VRAM idle: ~42844 / 49140 MiB
```

Forced long-output benchmark, so `max_tokens` is actually reached:

| prompt | max_tokens | concurrency | avg latency | aggregate output tok/s |
|---|---:|---:|---:|---:|
| small | 128 | 1 | 4.02s | 31.8 |
| small | 128 | 2 | 4.41s | 56.6 |
| small | 512 | 1 | 14.24s | 36.0 |
| small | 512 | 2 | 14.75s | 68.6 |
| medium ~2.2K prompt toks | 128 | 1 | 4.59s | 27.9 |
| medium ~2.2K prompt toks | 128 | 2 | 4.96s | 50.2 |
| medium ~2.2K prompt toks | 512 | 1 | 14.53s | 35.3 |
| medium ~2.2K prompt toks | 512 | 2 | 14.02s | 72.4 |

Short-answer benchmark, not directly comparable because model stopped early before `max_tokens`:

| prompt | max_tokens | concurrency | avg latency | aggregate output tok/s | actual output tokens |
|---|---:|---:|---:|---:|---:|
| small | 128 | 1 | 3.72s | 32.0 | 119 |
| small | 128 | 2 | 3.91s | 65.5 | 256 |
| small | 512 | 1 | 3.43s | 34.7 | 119 |
| small | 512 | 2 | 4.06s | 70.5 | 294 |
| medium ~1.5K prompt toks | 128 | 1 | 2.96s | 28.4 | 84 |
| medium ~1.5K prompt toks | 128 | 2 | 3.05s | 55.0 | 173 |
| medium ~1.5K prompt toks | 512 | 1 | 3.00s | 28.0 | 84 |
| medium ~1.5K prompt toks | 512 | 2 | 3.01s | 56.5 | 173 |

## Known caveats

- FP8 KV cache logs warnings about uncalibrated scales:

```text
Using KV cache scaling factor 1.0 for fp8_e4m3
Using uncalibrated q_scale 1.0 and/or prob_scale 1.0 with fp8 attention
```

- This may have accuracy risk. Short tests and pi usage were stable.
- MTP=3 sometimes has lower acceptance on some prompts, but overall current speed is acceptable.
- If user perceives hanging, check log first. It may simply be running a long request at 15–50 tok/s, not crashed.

## Health check commands

```bash
curl http://67.223.143.80:20068/v1/models
ssh -p 20016 root@67.223.143.80 'pgrep -af "vllm serve|EngineCore|python"; nvidia-smi; tail -n 120 /workspace/vllm.log'
```

Search recent errors:

```bash
ssh -p 20016 root@67.223.143.80 \
  'grep -n -E "ERROR|Traceback|RuntimeError|ValueError|Exception|OOM|out of memory|Ninja|nvcc|HTTP/1.1\\\" 500" /workspace/vllm.log | tail -120'
```

Check throughput metrics:

```bash
ssh -p 20016 root@67.223.143.80 \
  'grep -E "Avg prompt throughput|Avg generation throughput|Running:|Waiting:|KV cache usage|Prefix cache" /workspace/vllm.log | tail -30'
```

## Template maintenance — 2026-05-13

Huihui 128K Vision template updated to use the rebuilt `ghcr.io/mics8128/vllm-cu129:0.20.2-cu129` image that includes CUDA compile deps, `nvidia-modelopt`, runtime cache defaults, FlashInfer cache persistence, and entrypoint-managed `/workspace/vllm.env` persistence.

Template:

```text
id: 414917
previous hash: 999d731aa780f56057887b55dbfa7c4f
current hash: f0f25b1c9ac40e7d7c46d539d4ec1cf2
image: ghcr.io/mics8128/vllm-cu129:0.20.2-cu129
image digest: sha256:5657a4385c3ab6804923bc44797f7ed2b42a0170f8f91d809dc857d9bfc6d5ea
```

Only `onstart` was simplified; verified unchanged fields include name, image/tag, env, disk, SSH/direct settings, readme visibility, description, and search filters.

Simplified onstart:

```bash
nohup /usr/local/bin/vllm-entrypoint > /workspace/vllm.log 2>&1 &
```

The 4090 runtime env remains the 128K vision baseline:

```env
MAX_MODEL_LEN=131072
MAX_NUM_SEQS=2
GPU_MEMORY_UTILIZATION=0.90
LANGUAGE_MODEL_ONLY=false
LIMIT_MM_PER_PROMPT='{"image":4,"video":0}'
SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":3}'
EXTRA_ARGS='--kv-cache-dtype fp8 --calculate-kv-scales --attention-backend TRITON_ATTN'
```
