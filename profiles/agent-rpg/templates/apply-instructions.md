# Apply notes for OpenClaw

Use this profile as a long-term integration install, not a one-off chat prompt.

## Safe install sequence

1. Validate the incoming install request with the published JSON Schema.
2. Discover the active config path with `openclaw config file`.
3. Run `openclaw config validate --json`. Stop if the current config is already invalid.
4. Fetch the current config and capture `payload.hash`.
5. Prefer `openclaw config set gateway.http.endpoints.responses.enabled true --strict-json` for the endpoint toggle. Use `templates/responses-enable.patch.json5` only if the installer cannot use the CLI helper.
6. If the target agent does not exist, prefer `openclaw agents add ... --non-interactive`.
7. Render `config/agent-profile.template.json5` with concrete values from the install request.
8. Merge the rendered `agents.list` entry with the current `agents.list` in memory only for fields not covered by the agent CLI.
9. Apply the merged agent config using the current base hash.
10. Run `openclaw config validate --json`, then verify the endpoint and return a machine-readable apply result.

## Why step 5 matters

OpenClaw documents that `config.patch` replaces arrays entirely.

If the installer posts a patch containing only:

```json5
{
  agents: {
    list: [
      { id: "agent-rpg-main", workspace: "~/.openclaw/workspaces/agent-rpg/agent-rpg-main" }
    ]
  }
}
```

it can erase existing agents. Merge first, then apply.

## Stronger rule

If a safe CLI command exists, use it before falling back to direct config mutation:

- `openclaw config set` for single-key changes
- `openclaw agents add` / `bind` / `unbind` for agent and routing management

Only use merge-and-patch when the CLI does not expose the field you need.
