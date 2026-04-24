#!/usr/bin/env bash

set -euo pipefail

endpoint="${1:-${OPENCLAW_GATEWAY_ENDPOINT:-http://127.0.0.1:18789}}"
token="${2:-${OPENCLAW_TOKEN:-}}"
agent_id="${3:-${OPENCLAW_AGENT_ID:-main}}"
base="${endpoint%/}"

if [[ "$base" == */v1/responses ]]; then
  base="${base%/v1/responses}"
fi

headers=()
if [[ -n "$token" ]]; then
  headers+=(-H "Authorization: Bearer $token")
fi

echo "Checking OpenClaw model list at $base/v1/models"
curl -fsS "${headers[@]}" "$base/v1/models" >/dev/null

echo "Checking OpenClaw responses endpoint at $base/v1/responses for agent $agent_id"
curl -fsS "${headers[@]}" \
  -H "Content-Type: application/json" \
  -H "x-openclaw-agent-id: $agent_id" \
  -d '{"model":"openclaw/default","input":"agent-rpg integration health check"}' \
  "$base/v1/responses" >/dev/null

echo "OpenClaw integration verification succeeded"
