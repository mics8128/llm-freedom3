# Vast.ai CLI Operator Skill

Use this skill whenever working with Vast.ai in this project: CLI, templates, instances, volumes, SSH, ports, drivers/CUDA, GPU RAM, logs, storage, or Docker launch settings.

## Non-negotiable rules

- Do **not** guess Vast.ai parameters. Check this skill plus official docs/`vastai ... --help` before CLI actions.
- Prefer CLI command name `vastai`; if only `vast` exists locally, adapt after confirming `--help`.
- Use `--raw` for machine-readable output when parsing.
- Quote search queries containing `<`, `>`, spaces, lists, or versions.
- Treat destructive actions as irreversible:
  - `vastai destroy instance <id>` deletes instance and container storage.
  - `vastai delete volume <id>` permanently deletes volume data and only works after attached instances destroyed.
- SSH keys: account-level new keys apply to **new instances only**. Existing Docker instances need `vastai attach ssh`; VM key changes require recreation.
- On-start script limit: official OpenAPI notes `onstart` field max 4048 chars; gzip+base64 or fetch remote script for longer setup.
- Poll instance creation: `POST /api/v0/asks/{id}/` / CLI create returns `new_contract` as instance id. If `actual_status` becomes `exited`, `unknown`, or `offline`, it will not reach `running`; destroy/retry after diagnosis.

## Official sources

- Docs index: https://docs.vast.ai/llms.txt
- CLI hello/auth: https://docs.vast.ai/cli/hello-world.md, https://docs.vast.ai/cli/authentication.md
- CLI refs: https://docs.vast.ai/cli/reference/search-offers.md, `/create-instance.md`, `/create-template.md`, `/update-template.md`, `/logs.md`, `/attach-ssh.md`, `/create-ssh-key.md`, `/ssh-url.md`, `/search-volumes.md`, `/create-volume.md`, `/show-volumes.md`, `/copy.md`
- Templates: https://docs.vast.ai/cli/templates.md, https://docs.vast.ai/guides/templates/template-settings.md, https://docs.vast.ai/guides/templates/advanced-setup.md
- Networking/SSH/Docker: https://docs.vast.ai/guides/instances/connect/networking.md, https://docs.vast.ai/guides/instances/connect/ssh.md, https://docs.vast.ai/guides/instances/docker-environment.md
- Storage/volumes/data: https://docs.vast.ai/guides/instances/storage/types.md, `/volumes.md`, `/data-movement.md`
- API show instance OpenAPI notes: https://docs.vast.ai/api-reference/instances/show-instance.md

## Setup/auth

```bash
pip install vastai
vastai --version
vastai set api-key "$VAST_API_KEY"
vastai show user --raw
```

Per global `--help`, CLI reads default key from `~/.config/vastai/vast_api_key` unless `--api-key` passed.

## Search offers

Basic syntax from `vastai search offers --help`:

```text
query = comparison comparison...
comparison = field op value
op = <, <=, ==, !=, >=, >, in, notin
value = bool | int | float | string | any | [value0, value1, ...]
```

Default query is `external=false rentable=true verified=true`; pass `-n` to disable default.

Useful options:

```bash
vastai search offers '<query>' --limit 20 -o 'dph_total,reliability-' --raw
vastai search offers '<query>' --storage 80 --limit 20 --raw  # storage used for pricing, GiB; default 5.0GiB
vastai search offers '<query>' --type on-demand|reserved|bid
```

### Unit traps

CLI docs list some fields as GB, but `--raw` returns memory in MB for some fields. Official OpenAPI says: **`gpu_ram` in CLI query = GB; REST API = MB; CLI auto-converts**.

Use CLI query units:

| Field | Query unit/type | Notes |
|---|---:|---|
| `gpu_ram` | GB per GPU | Query `gpu_ram>=80`, not `>=80000`. Raw output may show `81559` MB. |
| `gpu_total_ram` | GB total | All selected GPUs. |
| `cpu_ram` | GB | Raw/API may show MB. |
| `disk_space` | GB | Host free/offer disk. |
| `--disk` / `--disk_space` | GB | Instance/container disk. |
| `cuda_vers` | float | Example `cuda_vers>=12.1`; max supported CUDA from driver. Raw may include `cuda_max_good`. |
| `driver_version` | string dotted | Example `driver_version>=535.86.05`; help says string like `535.86.05`. Do not use packed integer unless official example for specific command demands it. |
| `direct_port_count` | integer | Needed for direct SSH/custom public ports. |
| `duration` | days | Max rental duration. |
| `inet_up/down` | Mb/s | Network speeds. |
| `disk_bw` | MB/s | Disk bandwidth. |
| `gpu_mem_bw` | GB/s | GPU memory bandwidth. |
| `reliability` | float 0..1 | Example `reliability>0.99`. |

Examples:

```bash
# Reliable H100 80GB-class, CUDA >= 12.1, dotted driver string
vastai search offers 'reliability>0.99 num_gpus=1 gpu_ram>=80 cuda_vers>=12.1 driver_version>=535.86.05 direct_port_count>=2 rented=False' --limit 20 --raw

# 4 GPUs in Taiwan/Sweden
vastai search offers 'reliability>0.99 num_gpus=4 geolocation in [TW,SE]' -o 'num_gpus-,dph_total' --raw

# GPU name with spaces: use underscore or quoted list
vastai search offers 'gpu_name=RTX_4090 num_gpus=1 rented=False' --raw
vastai search offers 'gpu_name in ["RTX 4090", "RTX 3090"] geolocation notin [CN,VN]' --raw
```

## Templates

Templates define Docker image, launch mode, Docker options (`--env`), on-start script, search filters, disk, and readme/visibility.

Launch modes:

- `--ssh`: inject SSH setup, opens internal 22. Original image ENTRYPOINT replaced.
- `--jupyter`: inject Jupyter + SSH, opens internal 8080 and 22. Original ENTRYPOINT replaced.
- Entrypoint/args mode: no SSH/Jupyter injection; image runs as designed. If need access, image must provide it.

In SSH/Jupyter mode, start services from on-start script because original ENTRYPOINT is replaced. Append env to `/etc/environment` if needed in SSH/tmux/Jupyter sessions:

```bash
env | grep _ >> /etc/environment
# or env >> /etc/environment
```

Docker options accepted by GUI/CLI are limited to:

- env vars: `-e KEY=value`
- hostname: `-h name`
- ports: `-p 8081:8081`, `-p 8082:8082/udp`

Other docker run options are ignored per Template Settings docs. `OPEN_BUTTON_PORT` is only a GUI convenience; it does not prove the API is reachable.

Template env/onstart quoting traps:

- JSON env values such as `LIMIT_MM_PER_PROMPT`, `SPECULATIVE_CONFIG`, and `EXTRA_ARGS` need careful shell quoting.
- After create/update, verify actual runtime args in instance logs/process list; do not trust the intended env string alone.
- Keep `onstart` short enough for Vast's field limit; fetch a remote script or use image helpers for long setup.

### Create template

Check exact local syntax first:

```bash
vastai create template --help
```

Example:

```bash
vastai create template \
  --name "vllm-cu129" \
  --image "ghcr.io/OWNER/IMAGE:TAG" \
  --env '-p 8000:8000 -e OPEN_BUTTON_PORT=8000 -e HF_HOME=/data/hf -e VLLM_CACHE_ROOT=/data/vllm' \
  --onstart-cmd 'env >> /etc/environment; mkdir -p /data/hf /data/vllm; vllm serve MODEL --host 0.0.0.0 --port 8000' \
  --search_params 'gpu_ram>=80 cuda_vers>=12.1 driver_version>=535.86.05 num_gpus=1 direct_port_count>=2 rented=False' \
  --disk_space 40 \
  --ssh --direct
```

`--disk_space` is GB and is the template's recommended disk size, not proof of actual instance disk. `create instance --disk <GB>` controls container disk at rent time. `--public` exposes template to public; never use with secrets in env/login/onstart/readme.

### Update template

```bash
vastai update template <HASH_ID> \
  --name "vllm-cu129" \
  --image "ghcr.io/OWNER/IMAGE:NEW_TAG" \
  --env '-p 8000:8000 -e OPEN_BUTTON_PORT=8000' \
  --onstart-cmd 'env >> /etc/environment; ...' \
  --search_params 'gpu_ram>=80 cuda_vers>=12.1 driver_version>=535.86.05 num_gpus=1 rented=False' \
  --disk_space 40 \
  --ssh --direct
```

Local CLI help example has typo `--disk 8.0` under update-template; actual option is `--disk_space` per help options. Verify with `vastai update template --help` before use.

Update pitfalls learned in this project:

- First read the current template with `vastai search templates ... --raw`; preserve existing `name`, `image`, `env`, `onstart`, `repo/href`, visibility/readme, disk, and filters unless intentionally changing them.
- Do not update only `--search_params` or only `--disk_space`; partial updates have cleared unspecified fields to `null` in testing.
- Vast can return a new `hash_id` after update. Record/use the new hash for future instance creation.
- Template update affects future instances created from the new hash. Existing instances do not automatically inherit it; use `vastai update instance ... --template_hash_id <HASH>` or recreate when needed.
- Raw/API output may normalize filters (`gpu_ram` MB, integer `driver_version`, `cuda_max_good`). Do not copy those normalized values back as CLI query input.
- For new model, vision, multi-GPU, or risky tuning changes, prefer creating a new template instead of overwriting a known-good one.

Search/list templates:

```bash
vastai search templates 'name=vllm' --raw
```

## Create instances

Find offer id from `vastai search offers`. Create using template hash or direct image.

```bash
# From existing template hash
vastai create instance <OFFER_ID> --template_hash <TEMPLATE_HASH> --disk 64 --label vllm-test --raw

# Direct image with SSH, direct connections, env/ports, onstart
vastai create instance <OFFER_ID> \
  --image ghcr.io/OWNER/IMAGE:TAG \
  --disk 64 \
  --env '-p 8000:8000 -e OPEN_BUTTON_PORT=8000 -e HF_HOME=/data/hf' \
  --ssh --direct \
  --onstart-cmd 'env >> /etc/environment; mkdir -p /data/hf; vllm serve MODEL --host 0.0.0.0 --port 8000' \
  --label vllm-test \
  --raw
```

Return JSON includes `new_contract`; use as instance id.

Interruptible:

```bash
vastai create instance <OFFER_ID> --template_hash <HASH> --disk 64 --bid_price 0.10 --raw
```

State/log checks:

```bash
vastai show instance <INSTANCE_ID> --raw
vastai show instances --raw
vastai logs <INSTANCE_ID> --tail 200
vastai logs <INSTANCE_ID> --tail 200 --daemon-logs
```

Update/recreate instance template/image fields:

```bash
vastai update instance <INSTANCE_ID> --template_hash_id <HASH>
vastai recycle instance <INSTANCE_ID>   # repull/recreate container in place, preserves contract priority, still risky for container runtime state
vastai reboot instance <INSTANCE_ID>
```

## SSH keys and SSH URL

Create/register key:

```bash
vastai create ssh-key ~/.ssh/id_ed25519.pub
# or generate new ~/.ssh/id_ed25519 and add public key
vastai create ssh-key -y
vastai show ssh-keys --raw
```

Attach to existing Docker instance:

```bash
vastai attach ssh <INSTANCE_ID> ~/.ssh/id_ed25519.pub
vastai attach ssh <INSTANCE_ID> "$(cat ~/.ssh/id_ed25519.pub)"
```

Get SSH command/url:

```bash
vastai ssh-url <INSTANCE_ID>
vastai show instance <INSTANCE_ID> --raw  # fields include ssh_host, ssh_port, public_ipaddr
```

Manual connect example:

```bash
ssh -p <SSH_PORT> root@<SSH_HOST_OR_IP>
ssh -p <SSH_PORT> root@<HOST> -L 8000:localhost:8000
```

SCP/SFTP use uppercase `-P`:

```bash
scp -P <SSH_PORT> file root@<HOST>:/workspace/
sftp -P <SSH_PORT> root@<HOST>
```

## Ports and public endpoints

Vast Docker instances usually share IPs; internal ports map to random external ports. Do not assume public port equals internal port such as `8000`.

Open ports with Docker options/env:

```bash
--env '-p 8000:8000 -p 8082:8082/udp -e OPEN_BUTTON_PORT=8000'
```

Default internal ports:

- SSH mode: internal 22
- Jupyter mode: internal 8080 plus 22

Limit: 64 total open ports per instance. If `direct_port_count`/offer ports are insufficient, SSH/custom public ports may not behave as expected.

Find mapped public ports:

1. GUI: IP Port Info popup shows `PUBLIC_IP:EXTERNAL_PORT -> INTERNAL_PORT/proto`.
2. Inside container: env vars:
   - `PUBLIC_IPADDR`
   - `VAST_TCP_PORT_22`, `VAST_TCP_PORT_8080`, `VAST_TCP_PORT_<INTERNAL>`
   - `VAST_UDP_PORT_<INTERNAL>`
3. CLI/API: `vastai show instance <id> --raw`; inspect `ports`, `public_ipaddr`, `ssh_host`, `ssh_port` and any port map fields present in current CLI output.

Port env example inside instance:

```bash
echo "http://${PUBLIC_IPADDR}:${VAST_TCP_PORT_8000}"
```

`PUBLIC_IPADDR` set at startup and may become stale on dynamic IP; refresh with:

```bash
vastai show instance "$CONTAINER_ID" --api-key "$CONTAINER_API_KEY"
```

Identity-ish port request: docs say if external/internal same needed, request out-of-range `-p 70000:70000`; system maps random external with matching internal, then read `$VAST_TCP_PORT_70000`.

## Logs

```bash
vastai logs <INSTANCE_ID>                 # default tail 1000
vastai logs <INSTANCE_ID> --tail 200
vastai logs <INSTANCE_ID> --filter ERROR
vastai logs <INSTANCE_ID> --daemon-logs   # host daemon/system logs, not container stdout
```

API docs: logs endpoint uploads logs to S3 and returns generated URL under hood; CLI fetches/display.

## Storage and volumes

### Container storage

- Set with `--disk <GB>` when creating instance; template `--disk_space` is only recommendation/default metadata.
- Fixed at creation; cannot resize.
- Persists through stop/start.
- Destroying instance permanently deletes it.
- Storage charges continue while instance exists, even stopped.

### Local volumes

Vast currently provides **local volumes only**:

- Physically tied to machine where created.
- Can attach only to instances on same physical machine.
- Cannot be moved or attached to other machines.
- Fixed size after creation.
- Persistent after instance destruction.
- Separate billing.
- Docker instances only; not VM instances.

Search/create/show:

```bash
vastai search volumes 'disk_space>200 inet_up>500 inet_down>500 verified=true' --limit 20 --raw
vastai create volume <VOLUME_OFFER_ID> -s 200 -n hf_cache
vastai show volumes --raw
vastai show volumes --type local --raw
```

`-s/--size` is GB. Volume name max 64 chars, alphanumeric/underscores per docs.

Create instance with existing volume using official CLI flags:

```bash
vastai create instance <OFFER_ID> \
  --image pytorch/pytorch \
  --disk 30 \
  --ssh --direct \
  --link-volume <EXISTING_VOLUME_ID> \
  --mount-path /data
```

Create new local volume during instance creation:

```bash
vastai create instance <OFFER_ID> \
  --image pytorch/pytorch \
  --disk 30 \
  --ssh --direct \
  --create-volume <VOLUME_ASK_ID> \
  --volume-size 200 \
  --volume-label hf_cache \
  --mount-path /data
```

Docs also show legacy/env mount syntax:

```bash
vastai create instance <OFFER_ID> --image pytorch/pytorch --env '-v V.<VOLUME_ID>:/mnt' --disk 30 --ssh --direct
```

Prefer explicit `--link-volume/--mount-path` or `--create-volume/--volume-size` when available in local CLI help.

Delete volume:

```bash
vastai delete volume <VOLUME_ID>
```

Must destroy all instances using volume first; deletion permanent.

### Copy/data movement

Supported `vastai copy` formats from help:

- `[instance_id:]path` legacy
- `C.<instance_id>:path` container copy
- `local:path`
- `V.<volume_id>:path`
- `drive:path`, `s3.<connection_id>:path`, etc.

Examples:

```bash
vastai copy C.<INSTANCE_ID>:/workspace/ local:backup/workspace
vastai copy local:data/ C.<INSTANCE_ID>:/workspace/data/
vastai copy C.<SRC_INSTANCE>:/workspace/ C.<DST_INSTANCE>:/workspace/
vastai copy V.<SRC_VOLUME_ID>:/data/ V.<DST_VOLUME_ID>:/data/
vastai copy V.<VOLUME_ID>:/data/ C.<INSTANCE_ID>:/workspace/
vastai copy C.<INSTANCE_ID>:/workspace/ V.<VOLUME_ID>:/data/
```

Do **not** copy to `/root` or `/` as destination; CLI help warns this can break SSH folder permissions and future copy operations.

Volume copy restrictions: volume copy supports volume-to-volume and volume-to-instance, not cloud services or local paths.

## Safe operation checklist

Before create/rent:

1. `vastai --version`; `vastai <command> --help` for exact installed syntax.
2. `vastai show user --raw` auth works.
3. If SSH needed, `vastai show ssh-keys --raw` confirms key exists before new instance, or plan `attach ssh` for existing Docker instance.
4. Search with CLI GB units: `gpu_ram>=80`, not MB.
5. Driver query dotted string: `driver_version>=535.86.05`.
6. CUDA query float: `cuda_vers>=12.1`.
7. Disk/container storage sized enough; cannot resize later.
8. Volume locality understood; choose same machine or create with instance.
9. Ports declared with `-p`, app binds `0.0.0.0`, mapped external port discovered after start.
10. Secrets not stored in public templates; use account env vars.

After create:

```bash
INSTANCE_ID=<new_contract>
vastai show instance "$INSTANCE_ID" --raw
vastai logs "$INSTANCE_ID" --tail 200
vastai ssh-url "$INSTANCE_ID"
```

Inside instance:

```bash
env | grep -E 'CONTAINER_ID|PUBLIC_IPADDR|VAST_TCP_PORT|GPU_COUNT|JUPYTER|DATA_DIRECTORY'
nvidia-smi
df -h
```
