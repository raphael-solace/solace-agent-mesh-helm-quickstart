# Enterprise Bootstrap Demo

This bundle provides a single-command bootstrap for a SAM Enterprise demo:

```bash
./demo up
```

It will:

1. Prompt for `LiteLLM key?`
2. Apply that key to the SAM environment secret
3. Restart core/deployer components
4. Start local access (`http://127.0.0.1:8000` and `http://127.0.0.1:8080`)
5. Create or update the demo agents in `agents/*.json`
6. Create or update the demo project from `config/project.json`
7. Deploy or update the agents

Stop local access with:

```bash
./demo down
```

## Notes

- This bundle assumes your SAM Enterprise is reachable from this machine via `kubectl`.
- If the SAM release is missing and `SAM_INSTALL_IF_MISSING=true`, the script installs it using `config/sam-values.broker-no-key.yaml`.
- `config/sam-values.broker-no-key.yaml` intentionally leaves `llmService.llmServiceApiKey` empty.
- By default the script expects the release `agent-mesh` in namespace `rafa-demos`. Override with:
  - `SAM_RELEASE`
  - `SAM_NAMESPACE`
