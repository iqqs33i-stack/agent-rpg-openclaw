# agent-rpg profile

This profile provides the OpenClaw-side templates and notes for installing the long-term `agent-rpg` integration.

Read the pack-level safety runbook first:

- `../../docs/safe-config-runbook.md`

## What OpenClaw should do with this profile

1. Validate the app install request against the published request schema.
2. Render local values into `config/agent-profile.template.json5`.
3. Ensure `gateway.http.endpoints.responses.enabled` is on.
4. Prefer `openclaw agents add` / `openclaw agents bind` for agent creation and bindings.
5. Merge the rendered agent profile into the live config only for fields not covered by the agent CLI, without clobbering unrelated agents.
6. Return a machine-readable apply result that matches the published apply-result schema.

## Why the template is not a direct patch

OpenClaw documents that `config.patch` replaces arrays entirely.

Because `agents.list` is an array, the installer must not overwrite it blindly. It should:

- read the current config and base hash
- prefer `openclaw agents add` if it is creating a new agent
- merge or append the `agent-rpg` agent entry in memory
- apply the merged result with `config.patch`
- use `config.apply` only if you intentionally regenerated the full config snapshot

The `templates/responses-enable.patch.json5` file is safe to apply directly because it only touches nested objects.

## Suggested render inputs

- `__AGENT_ID__`
- `__WORKSPACE__`
- `__MODEL_PRIMARY__`
- `__MODEL_ALIAS__`
- `__INSTANCE_ID__`

## Suggested workspace convention

For local installs, a practical default is:

`~/.openclaw/workspaces/agent-rpg/__AGENT_ID__`

The final OpenClaw installer may choose a different location if it already has a workspace policy.
