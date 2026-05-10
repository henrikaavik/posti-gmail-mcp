# posti-gmail-mcp

Self-hosted, single-tenant Gmail MCP server for Henrik Aavik's Posti agent.

Wraps [`taylorwilsdon/google_workspace_mcp`](https://github.com/taylorwilsdon/google_workspace_mcp) in a tiny container that synthesizes the OAuth client + saved-credentials JSON files at boot from environment variables, then runs the upstream server in `--single-user --transport streamable-http` mode.

## Why this exists

Anthropic's claude.ai-hosted Gmail MCP service returns "The caller does not have permission" on `tools/call list_labels` for Workspace-less consumer Google accounts (verified 2026-05-08, 2026-05-09). Self-hosting on Coolify bypasses that gate.

## Required environment variables

| Var | Source |
|-----|--------|
| `GOOGLE_OAUTH_CLIENT_ID` | macOS Keychain `motted-posti-gmail-client-id` |
| `GOOGLE_OAUTH_CLIENT_SECRET` | macOS Keychain `motted-posti-gmail-client-secret` |
| `POSTI_GMAIL_REFRESH_TOKEN` | macOS Keychain `motted-posti-gmail-refresh-token` |
| `POSTI_GMAIL_USER_EMAIL` | optional, defaults to `henrik.aavik@gmail.com` |
| `POSTI_GMAIL_TOOLS` | optional, defaults to `gmail`. Set to `all` to enable every workspace service. |

## Deploy

Coolify → New Application → Public Git Repository → this repo → Build Pack: Dockerfile → Port: 8000 → Add the env vars above → Deploy.

The MCP endpoint will be at `https://<assigned-domain>/mcp` (streamable HTTP).

## Local smoke test

```bash
docker build -t posti-gmail-mcp .
docker run --rm -p 8000:8000 \
  -e GOOGLE_OAUTH_CLIENT_ID=... \
  -e GOOGLE_OAUTH_CLIENT_SECRET=... \
  -e POSTI_GMAIL_REFRESH_TOKEN=... \
  posti-gmail-mcp
```

Then:

```bash
curl -fsS http://localhost:8000/health
curl -fsSN -X POST http://localhost:8000/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

## Upstream version

The Dockerfile pins `taylorwilsdon/google_workspace_mcp` to a release tag via the `UPSTREAM_REF` build arg. To bump, change the default in the Dockerfile or build with `--build-arg UPSTREAM_REF=vX.Y.Z`.

## CHANGELOG

- 2026-05-10: pin upstream `taylorwilsdon/google_workspace_mcp` to `v1.20.4` (was `main`); rebuilds are now reproducible.
