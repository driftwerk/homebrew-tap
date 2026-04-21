# workforce-local-mcp

A local MCP (Model Context Protocol) server that gives
[Claude Code](https://docs.anthropic.com/en/docs/claude-code) three
things it doesn't get out of the box:

1. **A fast code graph** over your repos — symbol lookup, call-graph
   traversal, cross-repo impact analysis, a file skeleton in one call.
   Built from tree-sitter ASTs over Rust, TypeScript, JavaScript,
   Python, Go, Ruby, and Kotlin.
2. **Durable memory across sessions** — remember architectural
   decisions, gotchas, team conventions, ongoing work. Hybrid BM25
   keyword + 384-dim vector search so paraphrased questions still
   hit relevant notes.
3. **Adapter tools** for Jira, Linear, Datadog, and Metabase —
   ~90 tools across the four, only activated when you configure
   credentials.

Runs as a single static binary (~40 MB). All data stays on your
machine; the only network calls are the ones you explicitly enable
(adapter API calls, and a one-time ~130 MB download of the embedding
model).

This repository is the **public Homebrew tap** for the server. The
source lives in a private repo; signed + notarized release tarballs
are mirrored here for distribution.

---

## Install

```bash
brew tap driftwerk/tap
brew install workforce-local-mcp
```

Supported platforms:

| Platform | Target | Signed? |
|-|-|-|
| macOS Apple Silicon | `aarch64-apple-darwin` | Yes — Developer ID + notarized |
| Linux x86_64 (incl. WSL2) | `x86_64-unknown-linux-gnu` | No |

Intel macOS and ARM Linux aren't packaged today — see
[Platform notes](#platform-notes) for the reasoning.

## Post-install setup (2 minutes)

`brew info workforce-local-mcp` will re-print these caveats at any
time. Three steps:

### 1. Register the server with Claude Code

```bash
claude mcp add workforce-local --scope user -- \
  "$(brew --prefix)/bin/workforce-local-mcp"
```

`--scope user` makes the server available in every Claude Code
session, not just the directory you ran the command in. Verify:

```bash
claude mcp list
# workforce-local: /opt/homebrew/bin/workforce-local-mcp - ✓ Connected
```

### 2. Symlink the bundled SKILL docs

Claude Code reads `~/.claude/skills/*/SKILL.md` files to know when to
reach for which tool. The tarball ships three skill dirs; link them
in:

```bash
PKGSHARE="$(brew --prefix workforce-local-mcp)/share/workforce-local-mcp"
mkdir -p ~/.claude/skills
ln -sfn "$PKGSHARE/skills/codebase-knowledge"   ~/.claude/skills/codebase-knowledge
ln -sfn "$PKGSHARE/skills/project-memory"       ~/.claude/skills/project-memory
ln -sfn "$PKGSHARE/skills/adapter-integrations" ~/.claude/skills/adapter-integrations
```

### 3. (Optional) Configure adapter credentials

Skip this entirely if you don't use Jira / Linear / Datadog /
Metabase — everything else works without it. Each adapter activates
only when its creds are present.

```bash
workforce-local-mcp config jira \
  --email you@example.com --site https://you.atlassian.net
# prompts for API token (input hidden)

workforce-local-mcp config linear
# prompts for API key

workforce-local-mcp config datadog --site eu1
# prompts for API key + application key

workforce-local-mcp config metabase --site-url https://mb.yourcompany.com
# prompts for API key
```

Check what's set: `workforce-local-mcp config show` (secrets
redacted). Remove: `workforce-local-mcp config clear
jira|linear|datadog|metabase|all`.

Restart Claude Code after setting creds so the MCP server picks them
up.

## First tasks to try

Open a fresh Claude Code session inside a repo you want to explore:

```bash
cd ~/some/repo
claude
```

In the session, type `/mcp` — you should see `workforce-local`
connected with between 14 and ~105 tools depending on which adapters
you configured.

Try these prompts to see what each piece does:

**Code graph** — symbol and call-graph questions Claude would
otherwise answer via `grep`:

> Index this codebase and show me the main entry point.

> Where is `PaymentProcessor` defined, and what calls it?

> What does `handle_webhook` call transitively? Go 3 levels deep.

**Memory** — persists across sessions, per-repo and per-user:

> Remember that we picked SQLite over DuckDB because of concurrent
> writer restart limitations.

Start a *new* session later:

> What do I know about this project's storage choices?

**Cross-cutting questions** — `context.fuse` runs code-graph search
and memory recall in parallel, returning both in one round-trip:

> How does the indexer decide what to parse, and what did we decide
> about incremental vs. full reindexing?

**Multi-repo projects** — create a TOML file per project so one
"project" can span several repos:

```toml
# ~/Library/Application Support/workforce-local/projects/myproject.toml  (macOS)
# ~/.local/share/workforce-local/projects/myproject.toml                 (Linux)
name = "myproject"
[[repos]]
name = "backend"
path = "/path/to/backend-repo"
[[repos]]
name = "web"
path = "/path/to/frontend-repo"
```

Then:

> Index the myproject project.

> What in the frontend repo calls the `/api/users` endpoint in
> the backend?  _(cross-repo impact)_

**Adapters** — when credentials are configured:

> Find the five most recently updated Jira tickets assigned to me.

> What did CI report for the last deploy — check Datadog logs for
> the `deploy.apply` service in the past 30 minutes.

> Run the Metabase question "Revenue by plan last 30 days" and
> summarize the result.

## What tools are available

| Namespace      | Count | What it does                                              |
|----------------|-------|-----------------------------------------------------------|
| `codegraph.*`  | 5     | Index a repo, find symbols, walk the call graph           |
| `memory.*`     | 4     | Store / recall notes across sessions                      |
| `project.*`    | 2     | Manage multi-repo projects (shared graph)                 |
| `impact.*`     | 1     | BFS across the shared graph for impact analysis           |
| `context.fuse` | 1     | Concurrent code + memory fan-out in one call              |
| `ping`         | 1     | Liveness check                                            |
| `jira.*`       | 18    | Full Jira REST coverage (search, CRUD, transitions, …)    |
| `linear.*`     | 22    | Full Linear GraphQL coverage                              |
| `datadog.*`    | 31    | Logs, metrics, monitors, incidents, dashboards            |
| `metabase.*`   | 12    | Run saved questions and ad-hoc SQL                        |

Use `/mcp tools` in a Claude Code session to see the full
schema-annotated catalog.

## Where things live

Per-platform data directories:

| | macOS | Linux |
|-|-|-|
| Code graphs & memory | `~/Library/Application Support/workforce-local/` | `~/.local/share/workforce-local/` |
| Embedding model cache | `<above>/embeddings/`                  | `<above>/embeddings/` |
| Project TOMLs         | `<above>/projects/`                    | `<above>/projects/` |
| Credentials           | login Keychain (service `workforce-local-mcp`) | `~/.local/share/workforce-local-mcp/secrets.toml` (mode 0600) |

Overrides via env vars:
`WORKFORCE_LOCAL_DATA_DIR`,
`WORKFORCE_LOCAL_WORKSPACE`,
`WORKFORCE_LOCAL_PROJECTS_DIR`,
`WORKFORCE_LOCAL_EMBEDDINGS=off` (disables embeddings — falls back to
keyword-only memory recall, skips the model download),
`WORKFORCE_LOCAL_MCP_SECRETS=<path>` (Linux only, override secrets
file path).

## Updating

```bash
brew update
brew upgrade workforce-local-mcp
```

Your code graphs, memories, and credentials survive upgrades. After
an upgrade, restart Claude Code so the MCP server reconnects with
the new binary.

On macOS, the Keychain ACL is tied to the binary's code signature —
same Developer ID each release means no re-prompt. If you do see
"access denied" warnings from `config show` after an upgrade, re-run
the `config <adapter>` commands to rewrite the entries under the new
binary's ACL.

## Platform notes

- **macOS Apple Silicon only for Mac.** The embedded ONNX runtime
  (via `fastembed` → `ort`) doesn't ship prebuilt x86_64 macOS
  binaries, and cross-compiling the runtime from source wasn't
  worth the CI fragility for the shrinking Intel-Mac audience. If
  you need Intel macOS, file an issue — the workaround is to switch
  to fastembed's pure-Rust `ort-tract` backend.
- **Linux x86_64 via Linuxbrew or WSL2.** Credentials use a
  mode-0600 TOML file rather than the D-Bus Secret Service, since
  Secret Service isn't reliably present on WSL or headless Linux
  and requiring `gnome-keyring-daemon` would push that papercut
  onto every dev. Override the file's location with
  `WORKFORCE_LOCAL_MCP_SECRETS`.
- **Signed + notarized** with
  `Developer ID Application: Kingsley Hendrickse (CHA3FP8ENJ)` on
  macOS. Verify:
  ```bash
  codesign --verify --verbose $(brew --prefix workforce-local-mcp)/bin/workforce-local-mcp
  spctl    --assess --type execute --verbose $(brew --prefix workforce-local-mcp)/bin/workforce-local-mcp
  # Expected: "accepted  source=Notarized Developer ID"
  ```
  Linux builds aren't signed.

## Troubleshooting

**`claude mcp list` doesn't show `workforce-local` as Connected.**
Most likely cause: registered without `--scope user`, so it's only
visible from the directory the `mcp add` ran in. Re-register:
```bash
claude mcp remove workforce-local
claude mcp add workforce-local --scope user -- \
  "$(brew --prefix)/bin/workforce-local-mcp"
```

**`config show` reports "access denied" entries (macOS).** The
keychain items were written by a differently-signed binary (e.g. an
older install.sh build). Re-run the relevant `workforce-local-mcp
config <adapter>` commands to rewrite them under the current
binary's ACL, clicking **Always Allow** on each Keychain prompt.

**Claude doesn't reach for the codegraph tools when you ask about
code.** The SKILL.md symlinks probably aren't in place. Confirm:
```bash
ls -la ~/.claude/skills/ | grep workforce
```
Should show three symlinks into the brew prefix. Re-run the step-2
caveats commands if not.

**Memory recall misses paraphrased queries.** The 130 MB embedding
model is downloading on first use. Watch the
`<data-dir>/embeddings/` directory fill up (path depends on
platform — see
[Where things live](#where-things-live)). To disable embeddings
entirely and run on keyword-only recall, set
`WORKFORCE_LOCAL_EMBEDDINGS=off`.

**Binary has a macOS quarantine flag (rare, unsigned local builds
only).** Shouldn't happen for brew-installed builds, but if it
does:
```bash
xattr -d com.apple.quarantine $(brew --prefix workforce-local-mcp)/bin/workforce-local-mcp
```

**Nuke everything and start over:**
```bash
# macOS
rm -rf ~/Library/Application\ Support/workforce-local
workforce-local-mcp config clear all

# Linux
rm -rf ~/.local/share/workforce-local ~/.local/share/workforce-local-mcp
# (on Linux `config clear all` just deletes the TOML file too)
```

## Uninstall

```bash
brew uninstall workforce-local-mcp
brew untap driftwerk/tap
claude mcp remove workforce-local

# Optional: remove SKILL.md symlinks
rm -f ~/.claude/skills/{codebase-knowledge,project-memory,adapter-integrations}

# Optional: remove all local data (code graphs, memories, creds)
# macOS:
rm -rf ~/Library/Application\ Support/workforce-local
for p in skills/jira skills/linear skills/datadog skills/metabase; do
  security delete-generic-password -s workforce-local-mcp -a "$p" 2>/dev/null || true
done
# Linux:
rm -rf ~/.local/share/workforce-local ~/.local/share/workforce-local-mcp
```

## License

MIT.
