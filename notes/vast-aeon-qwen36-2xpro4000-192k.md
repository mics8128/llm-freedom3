# Vast.ai AEON Qwen3.6 27B NVFP4-MTP — 192K serving notes

Date: 2026-05-13

## Status

Working baseline for `AEON-7/Qwen3.6-27B-AEON-Ultimate-Uncensored-Multimodal-NVFP4-MTP` on 2x RTX PRO 4000 Blackwell.

Key finding: FlashInfer FP4 GEMM autotune caused extremely long cold starts. Disabling it made the server start successfully while still outperforming the 1x RTX 4090 Huihui FP8 baseline.

## Instance

```text
Instance ID: 36646499
GPU: 2x NVIDIA RTX PRO 4000 Blackwell
VRAM: 24467 MiB each
API: http://172.4.93.47:40294/v1
SSH: root@172.4.93.47 -p 40044
API key: please-change-me-for-security
Served model: aeon-qwen3.6-nvfp4-mtp
Image: ghcr.io/mics8128/vllm-cu129:0.20.2-cu129
```

## Current runtime configuration

Current serving configuration after 192K change:

```env
MODEL=AEON-7/Qwen3.6-27B-AEON-Ultimate-Uncensored-Multimodal-NVFP4-MTP
SERVED_MODEL_NAME=aeon-qwen3.6-nvfp4-mtp
HOST=0.0.0.0
PORT=8000
HF_HOME=/workspace/hf
XDG_CACHE_HOME=/workspace/.cache
VLLM_CACHE_ROOT=/workspace/.cache/vllm
TORCHINDUCTOR_CACHE_DIR=/workspace/.cache/vllm/torch_compile_cache
QUANTIZATION=modelopt
TRUST_REMOTE_CODE=true
MAX_MODEL_LEN=196608
MAX_NUM_SEQS=10
MAX_NUM_BATCHED_TOKENS=4096
GPU_MEMORY_UTILIZATION=0.92
ENABLE_PREFIX_CACHING=true
LANGUAGE_MODEL_ONLY=false
LIMIT_MM_PER_PROMPT='{"image":4,"video":0}'
REASONING_PARSER=qwen3
ENABLE_AUTO_TOOL_CHOICE=true
TOOL_CALL_PARSER=qwen3_coder
VLLM_API_KEY=please-change-me-for-security
SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":3}'
VLLM_NVFP4_GEMM_BACKEND=flashinfer-cutlass
VLLM_USE_FLASHINFER_MOE_FP4=0
VLLM_USE_FLASHINFER_SAMPLER=1
EXTRA_ARGS="--kv-cache-dtype fp8 --no-enable-flashinfer-autotune"
```

Effective important vLLM args:

```bash
vllm serve AEON-7/Qwen3.6-27B-AEON-Ultimate-Uncensored-Multimodal-NVFP4-MTP \
  --host 0.0.0.0 \
  --port 8000 \
  --served-model-name aeon-qwen3.6-nvfp4-mtp \
  --quantization modelopt \
  --tensor-parallel-size 2 \
  --max-model-len 196608 \
  --max-num-seqs 10 \
  --max-num-batched-tokens 4096 \
  --gpu-memory-utilization 0.92 \
  --reasoning-parser qwen3 \
  --tool-call-parser qwen3_coder \
  --speculative-config '{"method":"mtp","num_speculative_tokens":3}' \
  --limit-mm-per-prompt '{"image":4,"video":0}' \
  --trust-remote-code \
  --enable-prefix-caching \
  --enable-auto-tool-choice \
  --kv-cache-dtype fp8 \
  --no-enable-flashinfer-autotune
```

## Why disable FlashInfer autotune

With `--enable-flashinfer-autotune` default enabled, startup repeatedly ran:

```text
[AutoTuner]: Tuning fp4_gemm
```

Observed before disabling:

```text
100% rounds: 52+
Application startup complete: not reached
```

After adding:

```bash
--no-enable-flashinfer-autotune
```

Startup successfully skipped autotune:

```text
Skipping FlashInfer autotune because it is disabled.
Graph capturing finished in 2 secs
Application startup complete.
```

## 192K health / KV numbers

Current 192K server health:

```text
external /v1/models: HTTP 200
local /v1/models: HTTP 200
max_model_len: 196608
Application startup complete
```

KV cache:

```text
Available KV cache memory: 6.35 GiB
GPU KV cache size: 347,625 tokens
Maximum concurrency for 196,608 tokens per request: 1.77x
```

Interpretation:

```text
MAX_NUM_SEQS=10 allows up to 10 short/medium sequences in scheduler.
It does not mean 10 full 192K requests fit concurrently.
Full 192K request concurrency is about 1.77x.
```

Chunked prefill:

```text
Chunked prefill is enabled with max_num_batched_tokens=4096.
```

This is desired for long context and mixed prefill/decode workloads.

## 128K benchmark before switching to 192K

Configuration used for benchmark:

```env
MAX_MODEL_LEN=131072
MAX_NUM_SEQS=2
MAX_NUM_BATCHED_TOKENS=4096
GPU_MEMORY_UTILIZATION=0.92
SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":3}'
EXTRA_ARGS='--kv-cache-dtype fp8 --no-enable-flashinfer-autotune'
LANGUAGE_MODEL_ONLY=false
LIMIT_MM_PER_PROMPT='{"image":4,"video":0}'
```

128K KV:

```text
GPU KV cache size: 335,111 tokens
Maximum concurrency for 131,072 tokens per request: 2.56x
```

Forced long-output benchmark:

| prompt | max_tokens | concurrency | avg latency | aggregate output tok/s |
|---|---:|---:|---:|---:|
| small | 128 | 1 | 3.07s | 41.6 |
| small | 128 | 2 | 6.51s | 38.1 |
| small | 128 | 2 rerun | 3.29s wall | 77.8 |
| small | 512 | 1 | 10.00s | 51.2 |
| small | 512 | 2 | 10.85s | 92.4 |
| medium ~2.2K prompt toks | 128 | 1 | 3.15s | 40.6 |
| medium ~2.2K prompt toks | 128 | 2 | 4.20s | 61.0 |
| medium ~2.2K prompt toks | 512 | 1 | 9.05s | 56.6 |
| medium ~2.2K prompt toks | 512 | 2 | 10.21s | 95.3 |

Speculative decoding metrics observed during benchmark:

```text
Avg draft acceptance rate: ~35%–49%
Mean acceptance length: ~2.0–2.5
```

## Vision smoke test

Vision is enabled:

```env
LANGUAGE_MODEL_ONLY=false
LIMIT_MM_PER_PROMPT='{"image":4,"video":0}'
```

Boat image test:

```text
Image: /tmp/boat-test.svg.png
Prompt: 請用繁體中文描述這張圖片，回答圖中主要物件是什麼。
seconds: 2.8
prompt_tokens: 286
completion_tokens: 128
```

Model correctly identified the image as a sailboat with hull, mast, sails, sea, sky, and sun.

Streaming TTFT:

```text
text TTFT: 0.406s
total text response: 2.611s
vision TTFT: 0.627s
total vision response: 1.210s
```

## Comparison to current 4090 Huihui baseline

4090 Huihui current forced long-output benchmark:

| case | 4090 Huihui 128K Vision | AEON 2xPRO4000 128K Vision |
|---|---:|---:|
| small 128 c1 | 31.8 tok/s | 41.6 tok/s |
| small 128 c2 | 56.6 tok/s | 77.8 tok/s rerun |
| small 512 c1 | 36.0 tok/s | 51.2 tok/s |
| small 512 c2 | 68.6 tok/s | 92.4 tok/s |
| medium 128 c1 | 27.9 tok/s | 40.6 tok/s |
| medium 128 c2 | 50.2 tok/s | 61.0 tok/s |
| medium 512 c1 | 35.3 tok/s | 56.6 tok/s |
| medium 512 c2 | 72.4 tok/s | 95.3 tok/s |

Summary: AEON 2xPRO4000 is roughly 20%–60% faster than the 1x4090 Huihui 128K vision setup in this benchmark, even with FlashInfer autotune disabled.

## Vast.ai template

Template currently records the 192K baseline env:

```text
id: 414996
hash: 0eabf48b4d524e3bd7f9542ba00346fc
previous hashes: db58ce8606c84a21b1a7e5cb2201e5bf, 816fdf4c96ecb57fa7598c042ee58c6c
name: AEON Qwen3.6 27B Ultimate NVFP4 MTP Vision cu129 192K
image: ghcr.io/mics8128/vllm-cu129:0.20.2-cu129
image digest after entrypoint env persistence build: sha256:5657a4385c3ab6804923bc44797f7ed2b42a0170f8f91d809dc857d9bfc6d5ea
recommended_disk_space: 40 GB
```

Important template env includes:

```env
MAX_MODEL_LEN=196608
MAX_NUM_SEQS=10
MAX_NUM_BATCHED_TOKENS=4096
GPU_MEMORY_UTILIZATION=0.92
EXTRA_ARGS='--kv-cache-dtype fp8 --no-enable-flashinfer-autotune'
```

## Pi integration

Pi model config updated:

```text
/Users/mics/.pi/agent/models.json
```

AEON entry currently points at the 4x RTX 5060 Ti instance:

```json
{
  "baseUrl": "http://24.205.222.196:42525/v1",
  "apiKey": "please-change-me-for-security",
  "id": "aeon-qwen3.6-nvfp4-mtp",
  "name": "Vast AEON Qwen3.6 27B NVFP4 MTP vLLM 4x5060Ti 192K Vision",
  "contextWindow": 196608,
  "input": ["text", "image"]
}
```

## Known caveats

- `--no-enable-flashinfer-autotune` avoids long cold start but may leave performance below optimal autotuned kernels.
- 2xPRO4000 192K full-context concurrency is ~1.77x despite `MAX_NUM_SEQS=10`.
- 4x5060Ti 192K full-context concurrency is ~3.13x despite `MAX_NUM_SEQS=10`.
- FP8 KV logs uncalibrated scale warnings.
- Vast CLI `update template` must be called with all fields, not only `--disk_space`, because a partial update cleared other fields during testing. The fields were restored from raw backup.

## 4x RTX 5060 Ti 192K test

Instance:

```text
Instance ID: 36651377
GPU: 4x NVIDIA GeForce RTX 5060 Ti
VRAM: 16,311 MiB each, 65,244 MiB total
API: http://24.205.222.196:42525/v1
SSH: root@24.205.222.196 -p 42645
API key: please-change-me-for-security
Served model: aeon-qwen3.6-nvfp4-mtp
Template hash at instance creation: db58ce8606c84a21b1a7e5cb2201e5bf
Current template hash after simplified onstart update: 0eabf48b4d524e3bd7f9542ba00346fc
Network: inet_down 1503.3 Mbps, inet_up 437.6 Mbps
Disk: 80 GB instance disk
```

Runtime configuration came from the 192K template:

```env
MAX_MODEL_LEN=196608
MAX_NUM_SEQS=10
MAX_NUM_BATCHED_TOKENS=4096
GPU_MEMORY_UTILIZATION=0.92
LANGUAGE_MODEL_ONLY=false
LIMIT_MM_PER_PROMPT='{"image":4,"video":0}'
SPECULATIVE_CONFIG='{"method":"mtp","num_speculative_tokens":3}'
EXTRA_ARGS='--kv-cache-dtype fp8 --no-enable-flashinfer-autotune'
```

Effective vLLM args included:

```text
--tensor-parallel-size 4
--max-model-len 196608
--max-num-seqs 10
--max-num-batched-tokens 4096
--gpu-memory-utilization 0.92
--quantization modelopt
--kv-cache-dtype fp8
--no-enable-flashinfer-autotune
```

Startup observations:

```text
Weights download: 117.45s
Model loading took: 6.89 GiB memory, 122.48s
Torch compile first stage: 103.49s
Torch compile second stage: 13.79s
FlashInfer FP4 GEMM extension built under /root/.cache/flashinfer/0.6.8.post1/120f/
Graph capturing finished in 3s, took 0.40 GiB
Multi-modal warmup completed in 8.729s
Readonly multi-modal warmup completed in 9.098s
Application startup complete
```

Health:

```text
external /v1/models: HTTP 200
local /v1/models: HTTP 200
max_model_len: 196608
Application startup complete
```

KV cache:

```text
Available KV cache memory: 5.61 GiB
GPU KV cache size: 615,468 tokens
Maximum concurrency for 196,608 tokens per request: 3.13x
```

Comparison to 2xPRO4000 192K:

```text
2x RTX PRO 4000 Blackwell: 347,625 KV tokens, 1.77x @ 196,608 tokens/request
4x RTX 5060 Ti:            615,468 KV tokens, 3.13x @ 196,608 tokens/request
```

Interpretation:

```text
4x5060Ti has more total VRAM (65.2GB vs 48.9GB), so it fits much more KV cache.
Capacity/context is better than 2xPRO4000.
Decode throughput is not guaranteed better because 5060 Ti has lower per-GPU compute/memory bandwidth and TP=4 PCIe overhead.
```

Warm/cold TTFT:

```text
Cold first text TTFT after server ready: 25.342s
Warm text TTFT runs: 0.456s, 0.433s, 0.449s
Vision TTFT: 0.903s
```

Cold first text TTFT interpretation:

```text
The server was already ready and /v1/models returned HTTP 200.
The first real text generation still triggered lazy kernel/graph/cache initialization.
After that warmup, text TTFT returned to ~0.43–0.46s.
Recommended production warmup: send 1–2 text requests after readiness before using from pi.
```

Quick benchmark, non-streaming, forced longer output:

| prompt | prompt tokens | max_tokens | concurrency | wall | avg latency | output tokens | aggregate output tok/s |
|---|---:|---:|---:|---:|---:|---:|---:|
| small | 42 | 128 | 1 | 2.80s | 2.79s | 128 | 45.7 |
| small | 42 | 128 | 2 | 5.04s | 4.79s | 256 | 50.8 |
| small | 42 | 512 | 1 | 11.43s | 11.43s | 512 | 44.8 |
| small | 42 | 512 | 2 | 11.32s | 11.18s | 1024 | 90.5 |
| medium | 3889 | 128 | 1 | 6.29s | 6.29s | 128 | 20.4 |
| medium | 3889 | 128 | 2 | 6.41s | 6.37s | 256 | 40.0 |
| medium | 3889 | 512 | 1 | 11.52s | 11.51s | 512 | 44.5 |
| medium | 3889 | 512 | 2 | 14.08s | 13.95s | 1024 | 72.7 |

Earlier quick run with weaker prompt did not force full output for medium cases, so those numbers are not used for comparison:

```text
medium max=128/512 generated only ~50 tokens in some runs, aggregate tok/s not comparable.
```

## Current recommendation

Use 4x5060Ti when the priority is long-context capacity or more simultaneous 192K requests:

```text
4x5060Ti: ~3.13 full 192K requests fit by KV capacity
2xPRO4000: ~1.77 full 192K requests fit by KV capacity
```

Use 2xPRO4000 when the priority is lower cold-start complexity, steadier throughput, or fewer TP=4 PCIe overhead risks.
