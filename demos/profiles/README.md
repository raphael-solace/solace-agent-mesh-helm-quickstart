# Demo Profiles

This directory contains portable demo profiles used by the container scripts.

Profiles:

- `banking`: 5-agent banking ESG workflow
- `ten-agents`: 10-agent enterprise workflow

Each profile contains:

- `agents/*.json` agent definitions
- `config/project.json` project settings
- `demo-up.sh` wrapper that invokes `demos/enterprise-bootstrap/demo-up.sh` with profile-specific paths
- `demo-down.sh` wrapper for local access shutdown

Run via container scripts from repo root:

```bash
./scripts/demo-container-banking.sh up
./scripts/demo-container-10-agents.sh up
```
