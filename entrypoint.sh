#!/usr/bin/env bash
# Posti Gmail MCP entrypoint.
#
# Synthesizes the OAuth client_secret.json AND a saved Google Credentials
# JSON (refresh-token bearing) at container boot from environment variables
# pushed from Coolify (and ultimately from Henrik's macOS Keychain).
#
# Then execs the upstream taylorwilsdon/google_workspace_mcp server in
# single-user, streamable-http mode, so Posti can reach it over plain HTTPS
# without going through the FastMCP OAuth dance.
#
# Loud failures: any missing required env var aborts startup with a
# self-explanatory message.

set -euo pipefail

log() { printf '[posti-mcp/entrypoint] %s\n' "$*" >&2; }
fail() { log "FATAL: $*"; exit 1; }

require() {
    local var="$1"
    local val
    eval "val=\${$var:-}"
    [ -n "$val" ] || fail "missing required env var: $var"
}

require GOOGLE_OAUTH_CLIENT_ID
require GOOGLE_OAUTH_CLIENT_SECRET
require POSTI_GMAIL_REFRESH_TOKEN
: "${POSTI_GMAIL_USER_EMAIL:=henrik.aavik@gmail.com}"

UPSTREAM_DIR="/app/upstream"
CREDS_DIR="${WORKSPACE_MCP_CREDENTIALS_DIR:-$UPSTREAM_DIR/store_creds}"
mkdir -p "$CREDS_DIR"

# 1. OAuth client JSON (Web client shape - taylorwilsdon supports both web/installed)
CLIENT_SECRET_PATH="$UPSTREAM_DIR/client_secret.json"
cat > "$CLIENT_SECRET_PATH" <<JSON
{
  "web": {
    "client_id": "${GOOGLE_OAUTH_CLIENT_ID}",
    "client_secret": "${GOOGLE_OAUTH_CLIENT_SECRET}",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
    "redirect_uris": ["http://localhost:8000/oauth2callback"]
  }
}
JSON
chmod 600 "$CLIENT_SECRET_PATH"
export GOOGLE_CLIENT_SECRET_PATH="$CLIENT_SECRET_PATH"
log "wrote $CLIENT_SECRET_PATH"

# 2. Saved credentials JSON for the user (single-user mode picks this up)
# urlencode @ -> %40 to match auth/credential_store.py:_get_credential_path
SAFE_EMAIL="${POSTI_GMAIL_USER_EMAIL//@/%40}"
USER_CREDS_PATH="$CREDS_DIR/${SAFE_EMAIL}.json"
# Scopes MUST match what the refresh token was actually issued for; declaring
# scopes the token lacks causes workspace-mcp to invalidate the credentials.
# As of 2026-05-09 the Posti refresh token is reissued with the full Workspace
# scope set (BASE_SCOPES + GMAIL_SCOPES from taylorwilsdon/google_workspace_mcp
# auth/scopes.py). Override via POSTI_GMAIL_SCOPES (space-separated) only if
# you intentionally want a narrower file-declared set.
DEFAULT_SCOPES='["openid","https://www.googleapis.com/auth/userinfo.email","https://www.googleapis.com/auth/userinfo.profile","https://www.googleapis.com/auth/gmail.readonly","https://www.googleapis.com/auth/gmail.compose","https://www.googleapis.com/auth/gmail.modify","https://www.googleapis.com/auth/gmail.labels","https://www.googleapis.com/auth/gmail.send","https://www.googleapis.com/auth/gmail.settings.basic"]'
if [ -n "${POSTI_GMAIL_SCOPES:-}" ]; then
    SCOPES_JSON='['
    first=1
    for s in $POSTI_GMAIL_SCOPES; do
        if [ "$first" = "1" ]; then first=0; else SCOPES_JSON="${SCOPES_JSON},"; fi
        SCOPES_JSON="${SCOPES_JSON}\"${s}\""
    done
    SCOPES_JSON="${SCOPES_JSON}]"
else
    SCOPES_JSON="$DEFAULT_SCOPES"
fi

cat > "$USER_CREDS_PATH" <<JSON
{
  "token": null,
  "refresh_token": "${POSTI_GMAIL_REFRESH_TOKEN}",
  "token_uri": "https://oauth2.googleapis.com/token",
  "client_id": "${GOOGLE_OAUTH_CLIENT_ID}",
  "client_secret": "${GOOGLE_OAUTH_CLIENT_SECRET}",
  "scopes": ${SCOPES_JSON},
  "expiry": null
}
JSON
chmod 600 "$USER_CREDS_PATH"
log "wrote $USER_CREDS_PATH (single-user creds for ${POSTI_GMAIL_USER_EMAIL})"

# Tell upstream where to look (both var names supported, set both for safety)
export WORKSPACE_MCP_CREDENTIALS_DIR="$CREDS_DIR"
export GOOGLE_MCP_CREDENTIALS_DIR="$CREDS_DIR"

# Restrict to gmail-only tools (smaller surface, matches Posti scope)
TOOL_FILTER_ARGS=()
if [ "${POSTI_GMAIL_TOOLS:-gmail}" != "all" ]; then
    TOOL_FILTER_ARGS=(--tools "${POSTI_GMAIL_TOOLS:-gmail}")
fi

cd "$UPSTREAM_DIR"
log "exec uv run main.py --transport streamable-http --single-user ${TOOL_FILTER_ARGS[*]}"
exec uv run main.py \
    --transport streamable-http \
    --single-user \
    "${TOOL_FILTER_ARGS[@]}"
