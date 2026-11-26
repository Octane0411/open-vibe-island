# Antigravity CLI (agy) Integration

Open Island supports the standalone Antigravity CLI (`agy`) in two layers:

1. **Session detection** — process-based, zero configuration.
2. **Plan-credit usage chips** — polls the language server embedded in a
   running `agy` instance; needs a one-time shell capture hook.

## Session detection

`agy` does not emit hook events Open Island can ingest, so sessions are
discovered from the process table the same way Cursor is: any live `agy`
(or `antigravity`) process becomes a synthetic session carrying the
workspace name, terminal app, and TTY, with jump-back to the originating
terminal. Sessions end when the process stays gone across two polls.

## Plan-credit usage chips

### How it works

Each `agy` instance embeds a language server on two localhost ports. Its
`GetUserStatus` RPC reports plan credits (`monthlyPromptCredits` /
`availablePromptCredits`, plus the flow variants), but the server is
CSRF-protected: requests must carry the instance's scoped token, which
`agy` injects only into the environment of shells spawned by its
`run_command` tool — not into lifecycle hooks, MCP servers, or any file
on disk.

So the capture point is that tool-shell environment. A small snippet in
`~/.zshenv` appends the freshest address/token pair to a drop file every
time an `agy` tool shell starts:

```sh
# ~/.zshenv — Open Island × Antigravity CLI credential capture
if [ -n "$ANTIGRAVITY_CSRF_TOKEN" ] && [ -n "$ANTIGRAVITY_LS_ADDRESS" ]; then
  ( umask 077; printf '%s %s %s\n' "$ANTIGRAVITY_LS_ADDRESS" "$ANTIGRAVITY_CSRF_TOKEN" "$(date +%s)" \
    >> "$HOME/.gemini/antigravity-cli/open-island-credentials" )
fi
```

Lines look like `localhost:58033 <uuid-token> 1795577578`. Open Island
reads this file, keeps the newest entry per address, and polls
`GetUserStatus` every two minutes. Dead instances (connection refused,
rotated token) are skipped silently; the chip simply reflects the
newest live server.

When a snapshot is available, the opened island shows an
`Antigravity Pr NN% · Fl NN%` chip next to the Claude/Codex usage chips,
colored by the usual usage thresholds. Percentages are **used** credits
(`monthly − available` over `monthly`).

### Security notes

- The token is scoped to the `run_command` principal of one local
  `agy` instance and dies with it; the language server only listens on
  localhost.
- Keep the drop file private (the snippet's `umask 077` does this:
  mode `600`).
- The capture self-disables when the environment variables are absent,
  so the same `~/.zshenv` is safe on machines without `agy`.

### Troubleshooting

- **Chip missing** — check that `~/.gemini/antigravity-cli/open-island-credentials`
  exists and has a recent line. If it is empty, run any shell command
  from inside an `agy` session (that is what appends the pair) and
  confirm `~/.zshenv` contains the snippet above.
- **New `agy` instance started** — each instance mints its own token.
  The chip switches over as soon as that instance runs its first
  `run_command` shell command.
- **`agy` updated itself and the chip stopped updating** — the env
  injection names are `ANTIGRAVITY_LS_ADDRESS` /
  `ANTIGRAVITY_CSRF_TOKEN`; re-verify they still appear in tool shells
  (`env | grep ANTIGRAVITY` inside an `agy` session) and file an issue
  if the contract changed.
