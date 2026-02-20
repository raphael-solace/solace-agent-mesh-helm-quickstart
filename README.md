# Solace Agent Mesh (SAM) - Helm Chart

This Helm chart deploys Solace Agent Mesh (SAM) in enterprise mode on Kubernetes.

For documentation, installation instructions, and configuration options, visit the **[SAM Helm Chart Documentation](https://solaceproducts.github.io/solace-agent-mesh-helm-quickstart/docs/)**.

## Local and Operations Guides

- Local setup runbook: `docs/docs/local-minikube-runbook.md`
- Administration/day-2 guide: `docs/docs/administration-guide.md`
- OpenSearch Docker + OpenAPI integration: `integrations/opensearch/README.md`
- SAM local control script: `scripts/sam-control.sh` (`start`, `stop`, `status`, `restart`)
- Fast local scripts: `scripts/sam-start.sh` (quick start with agent-fetch/CORS self-check + self-heal) and `scripts/sam-stop.sh` (quick stop, `--full` to stop minikube)
- Enterprise one-command bootstrap: `./demo up` (bundle: `demos/enterprise-bootstrap/`)
- Containerized demo runners:
  - Banking profile: `scripts/demo-container-banking.sh`
  - 10-agent profile: `scripts/demo-container-10-agents.sh`
  - Generic runner (advanced): `scripts/demo-container.sh`
  - Docs: `demos/containerized-runner/README.md`

## Quick Container Start

Banking profile:

```bash
./scripts/demo-container-banking.sh build
./scripts/demo-container-banking.sh up
```

10-agent profile:

```bash
./scripts/demo-container-10-agents.sh build
./scripts/demo-container-10-agents.sh up
```
