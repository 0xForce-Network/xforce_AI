# xforce_AI

`xforce_AI` is the Docker base platform for the xforce GPU / AI runtime stack.

## Scope

The project is planned around the following runtime layers:

- POSIX Bash boot and compatibility engine
- CUDA / ROCm toolkit adaptation
- persistent workspace and user-state synchronization
- Python declarative provisioner
- Nushell interactive environment
- native PTY process wrapper and log pipeline
- Supervisor-managed services
- Caddy reverse proxy and Cloudflare tunnel support
- FastAPI Instance Portal using the Claude Cream visual language
- Safe output file browser with local IPFS backup metadata and gateway links
- CI image publishing to GHCR with Docker Hub mirror support
- GPU hardware-in-the-loop validation and model-to-GPU scheduling readiness

## References

- `docs/requirements.md`
- `docs/architecture.md`
- `docs/roadmap.md`
- `../tasks/F001_task_xforce_ai_docker_base_platform_plan.md`

## Repository Status

This repository was initialized as the implementation root for the F001 Docker base platform bootstrap task.

## F002 Docker Image Matrix

The first implementation scaffold defines three Docker variants:

- `cpu`: local smoke tests and generic non-GPU tooling
- `nvidia`: CUDA GPU workloads
- `rocm`: AMD ROCm GPU workloads

Runtime-owned paths use xforce names only:

- `/opt/xforce-ai/`
- `/etc/xforce_ai_boot.d/`
- `/workspace/`
- `/venv/main/`

Build entrypoints:

```bash
scripts/build-image.sh cpu
scripts/build-image.sh nvidia
scripts/build-image.sh rocm
```

Release builds use each upstream base image's default package sources by default. Set
`ENABLE_FASTSOURCES=1` only for local or test-environment builds that need mirror
acceleration.

## Release pipeline

F011 adds a GitHub Actions release pipeline for multi-arch Buildx publishing to GHCR with an optional Docker Hub mirror.

Useful local helpers:

```bash
make preflight
IMAGE_TAG=v1.2.3 make print-tags
IMAGE_TAG=v0.0.0-test VARIANTS=cpu,nvidia,rocm PLATFORMS=linux/amd64 PUSH=0 make release-dry-run
```

Release procedure and required secrets are documented in `docs/release.md`.

## GPU HIL and scheduling readiness

## Deploy-time Docker resource profiles

xforce_AI based app images can share the Docker resource profile helper at `scripts/docker-resource-profile.sh` from their host-side deployment scripts. The helper is intentionally deploy-time only: it turns package/quote tiers into Docker run flags and read-only container metadata, rather than allowing an end user to resize a running container from the Portal.

Supported built-in profiles are:

- `custom`: use only explicit variables.
- `gpu-small`: 4 CPU threads, 16g memory, 4g shm, 4096 PID limit, all GPUs, 80G writable layer hint.
- `gpu-pro`: 8 CPU threads, 32g memory, 8g shm, 8192 PID limit, all GPUs, 160G writable layer hint.
- `gpu-studio`: 16 CPU threads, 64g memory, 16g shm, 16384 PID limit, all GPUs, 320G writable layer hint.

Override variables:

- `XFORCE_DOCKER_RESOURCE_PROFILE`
- `XFORCE_DOCKER_CPUS`
- `XFORCE_DOCKER_CPUSET_CPUS`
- `XFORCE_DOCKER_MEMORY`
- `XFORCE_DOCKER_MEMORY_SWAP`
- `XFORCE_DOCKER_SHM_SIZE`
- `XFORCE_DOCKER_PIDS_LIMIT`
- `XFORCE_DOCKER_GPUS`
- `XFORCE_DOCKER_STORAGE_SIZE`

`XFORCE_DOCKER_STORAGE_SIZE` maps to Docker `--storage-opt size=...` and requires a compatible Docker storage driver. Deployment scripts should leave it empty for hosts that do not support per-container writable-layer quotas.

F012 adds a fixture-backed HIL orchestrator and model scheduler readiness layer:

```bash
make hil-validate
make hil-smoke
make scheduler-smoke
python3 -m hil_orchestrator preflight --model-id stable-diffusion-xl --max-price-per-hour 1.0
```

Operational details are documented in `docs/hil-validation.md` and `docs/model-scheduling.md`.

## Local IPFS output backup

F014 adds a base-platform IPFS backup surface for generated outputs. Images now include a local Kubo daemon managed by Supervisor and a Portal file browser for safe output access.

Default runtime settings:

- `XFORCE_IPFS_ENABLED=1`
- `XFORCE_IPFS_REPO=/workspace/.xforce-ipfs/repo`
- `XFORCE_IPFS_API_URL=http://127.0.0.1:5001`
- `XFORCE_IPFS_GATEWAY_URL=/ipfs/{cid}`
- `XFORCE_IPFS_PUBLIC_GATEWAY_ENABLED=0` (set to `1` only when the node can publish providers to the public IPFS network)
- `XFORCE_IPFS_PUBLIC_GATEWAY_URL=https://ipfs.io/ipfs/{cid}`
- `XFORCE_IPFS_AUTO_ROOTS=outputs`
- `XFORCE_IPFS_AUTO_MAX_BYTES=1073741824`
- `XFORCE_FILE_ROOTS=outputs:/workspace/outputs`

Files under `/workspace/outputs` are shown through `/files/` and `/api/v1/files/*`. Files at or below 1 GiB are queued for background local IPFS `add --pin`; larger files are marked `manual_required` and can be backed up via `POST /api/v1/ipfs/backup`.
