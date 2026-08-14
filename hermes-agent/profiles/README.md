# Sub-agents

Each directory here is one Hermes **profile** — an independent agent with its own
identity, memory, sessions, skills, and tool surface. `scripts/sync-profiles.sh`
applies them to the live agent at `/docker-data/hermes-agent/profiles/<name>/`.

The data dir is agent-mutable state and is not in git. A profile's *identity* is
authored config, so it lives here and is reviewed like any other change. The sync
is one-way: repo → data dir, never back.

## Roster

| Profile | Servers | Tools | Owns |
|---|---|---|---|
| `obs` | grafana | 52, all read | Why is X broken; what changed at time T |
| `netops` | adguard, netbox | 33, no mutations | DNS, filtering, addressing, documented-vs-observed |
| `virt` | proxmox_ro | 42 tools, writes 403 at the API | Proxmox guests, storage, backups, capacity |
| `repo` | github (readonly header) | repos, issues, PRs | What the infra is *declared* to be |
| `scribe` | none | none | Turning other agents' results into one written answer |

`default` is unchanged and keeps the full surface — it is the front door and the
escalation target, not a specialist.

Planned: `virt` (Proxmox — blocked on `privsep=1` + `PVEAuditor`; see below).

Two profiles scope differently and are worth understanding before copying the
pattern:

- **`repo`** has no MCPJungle token. GitHub is configured straight against
  `api.githubcopilot.com`, so its fences are `X-MCP-Readonly`, `X-MCP-Toolsets`,
  and the PAT's own scopes. It currently shares `default`'s `GITHUB_TOKEN`, and
  the readonly header is a client-side request — so that header bounds the
  agent's schema, not the credential. Minting `repo` its own read-only PAT is the
  obvious next hardening step.
- **`scribe`** has no tools at all, deliberately. It cannot check anything, so an
  unsupported claim has nowhere to come from except invention — which is exactly
  what its invariants are written to catch.

## The three files that shape an agent

They are not interchangeable, and you generally want all three.

| | Where | Loaded | Purpose |
|---|---|---|---|
| `SOUL.md` | `$HERMES_HOME/profiles/<n>/` | **Every prompt**, always | Who the agent is, what it refuses, how it reports |
| `describe` | profile metadata | By the kanban decomposer | One paragraph deciding whether a card routes here |
| `.hermes.md` | a task's workspace dir | When cwd is that dir | Repo/project rules for that specific work |

`SOUL.md` is how the agent behaves. `describe` is how the board *finds* it — a
vague description means well-written souls never get the right work.

## Budget: SOUL.md around 3 KB

`SOUL.md` is always-on — it is in the system prompt of every turn this profile
ever takes. Measure with `hermes -p <name> prompt-size`:

| | system prompt | of which SOUL.md |
|---|---|---|
| `default` (stock 514 B soul) | 21.9 KB | 0.5 KB |
| `obs` | 24.6 KB | 3.0 KB |
| `netops` | 24.7 KB | 3.1 KB |

So a soul is roughly an eighth of the system prompt — worth keeping tight, not
worth agonising over. The sync script warns above 3072 bytes; `netops` sits at
3122 B and that is fine. Trim when a soul is repeating itself, not to hit a number.

Don't confuse this with the ~65k tokens you may see on the llama.cpp slot
(`/slots` → `n_prompt_tokens`). That is accumulated *session* context, not the
system prompt.

**Don't bother trimming the bundled skills.** Cloning copies all 71 into each
profile, which looks alarming, but the always-on cost is the skills *index* at
~7 KB flat — bodies are read on demand. `--no-skills` is mutually exclusive with
`--clone-from` anyway, and you need the clone (see below). One real caveat: a
cloned skill can document tooling the specialist does not have — `netops` found
one describing UniFi tools it lacks. It handled that correctly by verifying the
tools were absent rather than trusting the doc, which is exactly what its
invariants ask for.

## What makes a good soul

Two failure modes, opposite directions:

- **Too vague** — "You are a helpful networking assistant." The agent stays
  general, wanders outside its domain, and its summaries are unusable to the next
  agent. The stock 514-byte Nous boilerplate on the `default` profile is this.
- **Too procedural** — a runbook. Skills are for procedure; souls are for
  judgment and boundaries. A soul that lists commands goes stale silently.

What actually earns its bytes:

1. **A refusal.** Name the work that is *not* yours and what to do instead. An
   agent that knows what it isn't stays cheap.
2. **The tools you don't have**, listed explicitly. Otherwise the model burns
   turns discovering absence, then narrates around it.
3. **A reporting contract** with a concrete example. `kanban_complete(summary=…)`
   is the *only* context the next agent receives — a summary written for applause
   instead of for a machine breaks the handoff. Show the shape you want.
4. **Domain-specific invariants.** Not "be careful" — the specific thing that
   goes wrong here. For `obs` it's unbounded LogQL queries; for a Proxmox agent
   it's naming the destructive tools it must never call.

Write invariants as things to *do*, not only things to avoid. "Bound every query
with an explicit time range" beats "don't run expensive queries."

## Enforcement is not prose

A soul is the **third** layer, and the weakest. It states intent; it does not
constrain a confused or prompt-injected agent. The two that actually hold:

1. **MCPJungle client token** — one per profile, `--allow` limited to the servers
   that profile owns. This is auth. A token without `proxmox` in its allow-list
   cannot see or invoke a Proxmox tool at all. Verified for `obs`: its token
   returns 52 tools, all `grafana__*`.
2. **Upstream read-only registration** — what tools exist in the first place.
   Grafana is read-only twice over (Viewer service account + `--disable-write`);
   AdGuard via `ADGUARD_ACCESS_TIER=read-only`; NetBox has no write tools at all.

Two upstreams have **no** read-only mode and need care:

- **Proxmox** — done, and the mechanics are worth knowing because they bit us.
  `proxmox` (full Administrator) stays with `default`; `proxmox_ro` is a second
  registration of the *same* MCP server with a different credential. All 42
  tools including `delete_vm` are present in `virt`'s schema either way — the
  fence is the Proxmox token alone, not the server.

  With `privsep=1`, effective rights are the **intersection** of the user's and
  the token's own permissions. `mcp-viewer@pam` was in the `readonly` group, but
  the *token* had no ACL entry, so the intersection was empty: every read
  returned nothing and every write 403'd. It looked scoped and was simply inert.
  The fix is an ACL entry on the token itself — `path=/`, `PVEAuditor`,
  `propagate=1` — after which reads work and writes stay refused.

  Verify with `GET /access/permissions` as the token: it should show exactly
  seven `*.Audit` privileges. Do not verify with a write against a non-existent
  VMID — before the grant that returns 403 (no rights anywhere) and after it
  returns 500 (path resolves, guest missing), so the result flips for reasons
  unrelated to what you are testing. Use a real guest and a harmless write like
  `set_vm_description`; it must return 403.
- **UniFi** — fully read-write, and the surface is *hidden*: `tools/list` shows
  five tools, but `unifi_execute` dispatches to ~200 including
  `unifi_delete_firewall_policy`. Upstream has no read-only env var and relies on
  a preview-then-confirm flow an agent can simply confirm. The only real fix is a
  dedicated UniFi local admin with the **View Only** role.

Never give a profile a token whose allow-list is wider than its soul claims. The
soul is documentation of the boundary, not the boundary.

## Adding a sub-agent

```bash
# 1. Mint its token — allow-list only the servers it genuinely owns.
mcpjungle --registry https://mcp.calzone.zone \
  create mcp-client hermes-<name> --allow "<server>,<server>"
op item edit hermes-agent --vault docker "MCP_<NAME>_API_KEY[password]=<token>"

# 2. Wire the passthrough: .env.tpl + docker-compose.yaml `environment:`.

# 3. Author the identity.
mkdir profiles/<name> && $EDITOR profiles/<name>/{SOUL.md,profile.conf}

# 4. Redeploy (picks up the new env var), then sync.
ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh hermes-agent"'
ssh root@docker01 '/root/homelab-docker/hermes-agent/scripts/sync-profiles.sh <name>'

# 5. Prove the boundary before trusting it — ask for something it must not reach
#    and confirm the tool is ABSENT from its schema, not merely declined.
ssh root@docker01 'docker exec hermes-agent hermes -p <name> chat -q "..."'
```

Kanban workers are spawned by the dispatcher as children of the gateway and
inherit the whole container environment, so every profile can read every
`MCP_*_API_KEY`. What keeps them apart is that each profile's `config.yaml`
interpolates only its own name, backed by the server-side ACL. Distinct variable
names are load-bearing; reusing one collapses two agents into the same authority.

## Concurrency

One inference slot means one agent thinking at a time. `kanban.max_in_progress`
stays at 1 — the board queues, so nothing is lost.

**Memory is not the reason.** Measured on a freshly restarted container: 516 MiB
total with a worker running, of which the worker is ~177 MB (gateway ~186 MB,
dashboard ~153 MB). Several workers would fit in the 4 GB cap comfortably. The
constraint is the model — `total_slots: 1` — so extra workers would queue at the
llama.cpp server instead of doing anything.

Worth knowing when you read `docker stats`: the gateway grows with uptime. After
about a week it had reached 1.43 GB on its own, which makes a worker look far
more expensive than it is. Compare against a fresh restart before concluding a
worker leaked.
