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
- FastAPI Instance Portal using the CoinCync Cream visual language
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
