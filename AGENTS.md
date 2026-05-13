# AGENTS.md

- Vast.ai 操作先讀 `skills/vast-ai/SKILL.md` / 官方 docs / `vastai ... --help`，不要憑記憶猜 CLI、template、instance、volume、port、driver、CUDA、GPU RAM 參數。
- 改 Vast template 前先 `vastai search templates ... --raw` 讀現況；用現有 `extra_filters`/欄位當準，不要只丟局部 `--search_params`。`update template` 未帶欄位可能變 `null`，且會回新 `hash_id`。
- template filter 輸入單位用 CLI 格式：`gpu_ram`=GB、`driver_version`=點號版本、`cuda_vers`=CUDA；不要把 raw/API 顯示的 MB、整數 driver、`cuda_max_good` 當輸入。
- template `--env` 只放 Vast 支援的 `-e`/`-p`/`-h`；SSH/Jupyter runtype 會取代 image entrypoint，服務要由 `onstart` 啟動。
- 新模型/vision/多卡/高風險調參優先新建 template，不要覆蓋已可用 template；不要把 secrets 放 public template。
- template update 只影響之後用新 `hash_id` 建的 instance；已存在 instance 不會自動套用，必要時明確 `update instance`/重建。
- `onstart` 有長度限制，JSON env（如 `LIMIT_MM_PER_PROMPT`/`SPECULATIVE_CONFIG`/`EXTRA_ARGS`）要特別注意 shell quoting；改完用實例 logs 驗證實際 vLLM args。
