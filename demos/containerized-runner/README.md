# Containerized Demo Runner

This repo supports two containerized demo profiles:

- `banking` profile (orchestrated banking ESG workflow)
- `10-agents` profile (cross-functional enterprise team of 10 agents)

Both reuse the same container runner image and bootstrap logic.

## Commands

From repo root:

Banking profile:

```bash
./scripts/demo-container-banking.sh build
./scripts/demo-container-banking.sh up
./scripts/demo-container-banking.sh status
./scripts/demo-container-banking.sh logs
./scripts/demo-container-banking.sh down
```

10-agent profile:

```bash
./scripts/demo-container-10-agents.sh build
./scripts/demo-container-10-agents.sh up
./scripts/demo-container-10-agents.sh status
./scripts/demo-container-10-agents.sh logs
./scripts/demo-container-10-agents.sh down
```

If you need a shell in a running container, use:

```bash
./scripts/demo-container-banking.sh shell
./scripts/demo-container-10-agents.sh shell
```

`up` prompts for the LiteLLM key unless already set via `LITELLM_KEY`.

## Default URLs

Banking profile:

- UI: `http://127.0.0.1:8000`
- Platform: `http://127.0.0.1:8080`
- Auth: `http://127.0.0.1:5050`

10-agent profile:

- UI: `http://127.0.0.1:8100`
- Platform: `http://127.0.0.1:8180`
- Auth: `http://127.0.0.1:5150`

Override these with:

- `SAM_HOST_UI_PORT`
- `SAM_HOST_PLATFORM_PORT`
- `SAM_HOST_AUTH_PORT`

## Minikube note

When kubeconfig uses `https://127.0.0.1:<port>` (typical minikube), the container cannot use host loopback directly.

The entrypoint patches a temporary in-container kubeconfig to:

- replace `127.0.0.1` / `localhost` with `host.docker.internal`
- set `insecure-skip-tls-verify=true` for those local clusters
