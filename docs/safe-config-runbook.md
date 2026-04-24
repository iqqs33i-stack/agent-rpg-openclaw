# OpenClaw Safe Config Runbook

This runbook turns the official OpenClaw configuration behavior into a low-risk install strategy for the long-term `agent-rpg` integration.

Use this when writing the OpenClaw-side installer, or when reviewing any prompt or automation that claims it can "configure OpenClaw for agent-rpg".

For phase names, result shapes, and pseudocode, also read:

- `installer-execution-spec.md`

## 1. What the official docs imply

Checked against OpenClaw official docs on April 23, 2026.

### 1.1 Config file path is real state

OpenClaw reads an optional JSON5 config from:

- `$OPENCLAW_CONFIG_PATH`
- otherwise `~/.openclaw/openclaw.json`

If you do not know which file is active, discover it first with:

```bash
openclaw config file
```

Do not assume the default path when an installer can ask OpenClaw directly.

### 1.2 The Gateway watches the config file

The Gateway watches the active config file and, by default, uses `gateway.reload.mode: "hybrid"`.

Official behavior:

- safe changes can hot-apply
- `gateway.*` changes may require restart
- direct file writes can trigger reload while you are still editing

Implication for `agent-rpg`:

- prefer official CLI or Control API operations over piecemeal file editing
- if direct file writing is unavoidable, write atomically and expect restart-sensitive behavior for `gateway.*`

### 1.3 `config.patch` is not safe for arrays unless you merge first

Official docs say `config.patch` uses JSON Merge Patch semantics:

- objects merge recursively
- arrays are replaced entirely
- `null` deletes keys

Implication:

- patching `gateway.http.endpoints.responses.enabled` is safe
- patching `agents.list` without first merging the current list is unsafe

### 1.4 `config.apply` replaces everything

Official docs say `config.apply` validates and writes the full config, then restarts the Gateway.

Implication:

- `config.apply` is only safe when you already have a complete rendered config snapshot
- it is not safe for partial updates
- a partial `config.apply` can wipe unrelated channels, agents, or secrets references

### 1.5 Hashes are there to prevent races

Official docs require `baseHash` from `config.get` when updating an existing config through `config.patch` or `config.apply`.

Implication:

- the installer must always read `config.get` first
- if the hash changed before write, re-read and re-merge

### 1.6 OpenClaw already has safer commands for agent management

Official docs expose:

- `openclaw agents add`
- `openclaw agents bind`
- `openclaw agents unbind`
- `openclaw agents delete`
- `openclaw agents set-identity`

Implication:

- for agent creation and binding, prefer these commands over manually editing `agents.list`
- reserve manual merge-and-patch for fields that the agent CLI does not expose

### 1.7 OpenClaw already has safer commands for single config keys

Official docs expose:

- `openclaw config set`
- `openclaw config unset`
- `openclaw config validate`
- `openclaw config set --dry-run --json`

Implication:

- for single-key changes, prefer `openclaw config set`
- use `--dry-run --json` before writing

## 2. Recommended install strategy

This is the safest default for `agent-rpg`.

### Step A: Preflight

1. Discover the active config path:

```bash
openclaw config file
```

2. Validate the current config before touching anything:

```bash
openclaw config validate --json
```

3. Capture the current config hash:

```bash
openclaw gateway call config.get --params '{}' --json
```

4. Record current agents and bindings:

```bash
openclaw agents list --json
openclaw agents bindings --json
```

5. If validation already fails, stop. Do not stack `agent-rpg` installation on top of a broken Gateway.

### Step B: Enable the OpenResponses endpoint

For `gateway.http.endpoints.responses.enabled`, prefer a narrow key write:

```bash
openclaw config set gateway.http.endpoints.responses.enabled true --strict-json --dry-run --json
openclaw config set gateway.http.endpoints.responses.enabled true --strict-json
```

Why this is safe:

- it targets one key
- it avoids array replacement
- it uses OpenClaw's own config tooling

Alternative:

- If the installer can only talk to the Control API, use an object-only `config.patch` with `baseHash`.

### Step C: Create or update the `agent-rpg` agent

If the target agent does not exist, prefer:

```bash
openclaw agents add agent-rpg-main --workspace ~/.openclaw/workspaces/agent-rpg/agent-rpg-main --model openclaw/default --non-interactive
```

If routing bindings are needed, prefer:

```bash
openclaw agents bind --agent agent-rpg-main --bind telegram:ops
```

If the installer must change fields not covered by `openclaw agents`, use this fallback:

1. read `config.get`
2. merge the target agent entry into the current `agents.list` in memory
3. patch the merged array back using the latest `baseHash`

Do not generate a fresh one-element `agents.list` and patch it directly.

### Step D: Add optional per-agent metadata

Only after the agent exists should the installer merge extra metadata such as:

- `metadata.integration: "agent-rpg"`
- `metadata.instanceId`

If this metadata requires editing `agents.list`, use the same merge-first fallback as Step C.

### Step E: Verify before returning success

At minimum:

```bash
openclaw config validate --json
openclaw status
openclaw health
```

Then verify the HTTP surface:

```bash
./profiles/agent-rpg/scripts/verify.sh http://127.0.0.1:18789 "" agent-rpg-main
```

Only return an `ok` apply result when:

- config validates
- the Gateway is healthy
- `/v1/responses` is reachable

## 3. What the installer should never do

Never do these in the `agent-rpg` installer:

- Do not call `config.apply` with a partial config.
- Do not patch `agents.list` without merging the current array first.
- Do not assume `~/.openclaw/openclaw.json` is the active config when OpenClaw can tell you the real path.
- Do not write directly into the config file in multiple small saves while the Gateway watcher is active.
- Do not return a long-lived owner token to the app.
- Do not report success before `config validate` and endpoint verification both pass.
- Do not continue installation on top of an already-invalid config.

## 4. Rollback strategy

If any write after Step A fails:

1. stop further changes
2. restore the last known config state using the previously captured hash or backup path
3. remove any partially rendered `agent-rpg` overlay
4. run:

```bash
openclaw config validate --json
openclaw status
```

5. return a machine-readable error or rollback result

If config validation still fails after restore, use the official repair flow:

```bash
openclaw doctor --repair
```

If the installer used `openclaw agents add` and later decides to back out, it should explicitly remove the created agent rather than leave a half-installed agent around.

## 5. Decision table

Use this table when choosing the write path.

| Task | Preferred path | Why |
| --- | --- | --- |
| Discover config path | `openclaw config file` | avoids wrong-file edits |
| Validate before/after install | `openclaw config validate --json` | catches schema issues early |
| Enable `/v1/responses` | `openclaw config set gateway.http.endpoints.responses.enabled true` | one-key change, low risk |
| Create a new agent | `openclaw agents add` | avoids manual `agents.list` array edits |
| Add bindings | `openclaw agents bind` | avoids manual routing edits |
| Update unsupported per-agent fields | `config.get` -> merge in memory -> `config.patch` | safe fallback for array-backed data |
| Replace entire config | `config.apply` only with full rendered snapshot | partial use is destructive |

## 6. Minimal safe install checklist

Use this if you need the shortest possible operator version.

1. `openclaw config file`
2. `openclaw config validate --json`
3. `openclaw gateway call config.get --params '{}' --json`
4. `openclaw config set gateway.http.endpoints.responses.enabled true --strict-json --dry-run --json`
5. `openclaw config set gateway.http.endpoints.responses.enabled true --strict-json`
6. `openclaw agents add ...` if the agent is missing
7. merge-and-patch only if extra per-agent fields are still needed
8. `openclaw config validate --json`
9. `openclaw status`
10. `./profiles/agent-rpg/scripts/verify.sh ...`

## 7. References

- OpenClaw Gateway Configuration: https://open-claw.bot/docs/gateway/configuration/
- OpenClaw Config CLI: https://open-claw.bot/docs/cli/config/
- OpenClaw Agents CLI: https://open-claw.bot/docs/cli/agents/
- OpenClaw OpenResponses HTTP API: https://open-claw.bot/docs/gateway/openresponses-http-api/
