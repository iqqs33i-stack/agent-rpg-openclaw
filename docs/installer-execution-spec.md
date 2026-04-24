# OpenClaw Installer Execution Spec

This document describes the OpenClaw-side installer that consumes an `agent-rpg.openclaw.integration-install/v1` request.

It is intentionally stricter than the product design. The purpose is to keep an existing OpenClaw instance working if installation fails halfway through.

## 1. Inputs

The installer receives one JSON object that validates against:

- `schemas/agent-rpg.integration-install.request.v1.schema.json`

Important fields:

- `integration.pack_repo`
- `integration.pack_ref`
- `integration.integrity`
- `client.instance_id`
- `gateway.endpoint_hint`
- `agent.agent_id`
- `agent.model`
- `contract.app_capabilities`
- `safety_contract`

## 2. Outputs

The installer must return one JSON object that validates against:

- `schemas/agent-rpg.integration-apply-result.v1.schema.json`

Supported statuses:

- `ok`
- `error`
- `rolled_back`

## 3. Execution Phases

Use these phase names in `error.phase` so the app and logs can group failures consistently:

| Phase | Meaning |
| --- | --- |
| `validate_request` | install request did not match schema or safety contract |
| `fetch_pack` | GitHub pack could not be fetched, pinned, or checked |
| `preflight` | existing OpenClaw config or health check failed before changes |
| `enable_responses` | `/v1/responses` endpoint could not be enabled |
| `agent_setup` | agent create/bind/update failed |
| `metadata_merge` | optional metadata merge failed |
| `verify` | post-install validation or endpoint verification failed |
| `rollback` | rollback was required and failed |

## 4. Algorithm

### 4.1 Validate request

1. Parse JSON.
2. Validate schema.
3. Confirm `spec_version` is exactly `agent-rpg.openclaw.integration-install/v1`.
4. Confirm `safety_contract` forbids partial `config.apply` and blind `agents.list` patching.
5. Confirm app capabilities include `openresponses` and apply-result import support.

If validation fails, return `status: "error"` with `phase: "validate_request"` and `rollback.status: "not_needed"`.

### 4.2 Fetch and pin the pack

1. Fetch `integration.pack_repo` at `integration.pack_ref`.
2. Reject floating branch refs unless the installer explicitly resolves them to a commit SHA before applying.
3. If `integration.integrity.checksum_sha256` is non-empty, verify it before reading templates.
4. Confirm the pack contains the expected schema and profile paths.

If fetching or integrity validation fails, return `status: "error"` with `phase: "fetch_pack"` and `rollback.status: "not_needed"`.

### 4.3 Preflight live OpenClaw

1. Discover the active config file:

```bash
openclaw config file
```

2. Validate the current config:

```bash
openclaw config validate --json
```

3. Capture live config and hash:

```bash
openclaw gateway call config.get --params '{}' --json
```

4. Capture current agent state:

```bash
openclaw agents list --json
```

If preflight fails, return `status: "error"` with `phase: "preflight"` and `rollback.status: "not_needed"`.

## 5. Mutations

### 5.1 Enable `/v1/responses`

Preferred:

```bash
openclaw config set gateway.http.endpoints.responses.enabled true --strict-json --dry-run --json
openclaw config set gateway.http.endpoints.responses.enabled true --strict-json
```

Fallback:

- Use `config.patch` with `baseHash`.
- Patch only nested objects.
- Do not include arrays in this patch.

### 5.2 Create or update the agent

Preferred create path:

```bash
openclaw agents add <agent_id> --workspace <workspace> --model <model> --non-interactive
```

Preferred binding path:

```bash
openclaw agents bind --agent <agent_id> --bind <binding>
```

Fallback for fields not covered by CLI:

1. read latest config and hash
2. merge the target entry into the current `agents.list`
3. write the merged array with `config.patch` and the latest hash

Never write a fresh one-item `agents.list`.

### 5.3 Track created resources

The installer must remember what it created during the current run:

- endpoint toggle changed from false to true
- agent created
- binding created
- metadata changed

This record is used for rollback and for the final result.

## 6. Verification

After mutations, run:

```bash
openclaw config validate --json
openclaw status
openclaw health
```

Then verify the HTTP API:

```bash
profiles/agent-rpg/scripts/verify.sh <endpoint> <token> <agent_id>
```

Return `status: "ok"` only after verification passes.

## 7. Success Result

Example:

```json
{
  "status": "ok",
  "integration_id": "agent-rpg",
  "pack_repo": "https://github.com/iqqs33i-stack/agent-rpg-openclaw",
  "pack_ref": "v0.1.0",
  "restart_required": false,
  "effective_endpoint": "http://127.0.0.1:18789/v1/responses",
  "agent_id": "agent-rpg-main",
  "verification": {
    "config_validate": "ok",
    "responses_endpoint": "ok",
    "agent_profile": "ok"
  },
  "client_import": {
    "endpoint": "http://127.0.0.1:18789/v1/responses",
    "agentId": "agent-rpg-main",
    "token": null,
    "model": "openclaw/default"
  }
}
```

## 8. Error Result

Return `status: "error"` when no config mutation happened, or when a failure happened and rollback was not needed.

Example:

```json
{
  "status": "error",
  "integration_id": "agent-rpg",
  "pack_repo": "https://github.com/iqqs33i-stack/agent-rpg-openclaw",
  "pack_ref": "v0.1.0",
  "restart_required": false,
  "error": {
    "phase": "preflight",
    "code": "config_invalid_before_install",
    "message": "OpenClaw config was invalid before agent-rpg install started"
  },
  "rollback": {
    "status": "not_needed",
    "config_restored": false,
    "created_agent_removed": false
  },
  "next_action": "Run openclaw config validate --json and fix the existing config first"
}
```

## 9. Rolled Back Result

Return `status: "rolled_back"` when a mutation happened, a later phase failed, and the installer restored the prior state.

Example:

```json
{
  "status": "rolled_back",
  "integration_id": "agent-rpg",
  "pack_repo": "https://github.com/iqqs33i-stack/agent-rpg-openclaw",
  "pack_ref": "v0.1.0",
  "restart_required": false,
  "error": {
    "phase": "verify",
    "code": "responses_endpoint_unreachable",
    "message": "/v1/responses did not answer after install"
  },
  "rollback": {
    "status": "ok",
    "config_restored": true,
    "created_agent_removed": true,
    "message": "Restored previous config hash and removed created agent"
  },
  "next_action": "Check OpenClaw gateway health and retry"
}
```

## 10. Rollback Rules

Rollback should attempt these actions in order:

1. restore the prior config snapshot or hash
2. remove the agent if this run created it
3. remove bindings created by this run
4. validate config
5. report whether rollback fully succeeded

If rollback itself fails, return `status: "error"` with `error.phase: "rollback"` and `rollback.status: "failed"`.

## 11. Hard Prohibitions

The installer must not:

- use `config.apply` with a partial object
- patch `agents.list` without reading and merging the live array
- assume the default config path
- return a long-lived owner token to the app
- report `ok` before post-install verification passes
- continue if preflight validation fails

## 12. Pseudocode

```text
request = parse_and_validate_install_request(input)
pack = fetch_pack(request.integration.pack_repo, request.integration.pack_ref)
verify_pack_integrity_if_present(pack, request.integration.integrity)

preflight = inspect_openclaw()
if preflight.invalid:
  return error("preflight", rollback="not_needed")

changes = []
try:
  enable_responses_endpoint(prefer_config_set=true)
  changes.append("responses_endpoint")

  agent = ensure_agent(prefer_agents_cli=true)
  if agent.created:
    changes.append("agent")

  merge_optional_metadata_if_needed()
  verify_install()
  return ok_result()
catch error:
  rollback_result = rollback(changes, preflight.snapshot)
  if rollback_result.ok:
    return rolled_back_result(error, rollback_result)
  return rollback_failed_result(error, rollback_result)
```
