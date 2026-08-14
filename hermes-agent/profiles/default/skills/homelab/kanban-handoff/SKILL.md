---
name: kanban-handoff
description: "REQUIRED before filing any kanban card or delegating to a homelab specialist (obs, netops, virt, repo, scribe). Load this the moment you decide to hand work off — it has the exact create/subscribe commands, the binary path, the Discord channel id, and how to write a worker brief. Filing without it silently orphans the card so results reach nobody."
version: 1.0.0
author: Zach + Claude
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [kanban, delegation, homelab, orchestration, discord]
    related_skills: [hermes-agent]
---

# Filing work to the specialists

Use this whenever you have decided to hand work off. The decision of *whether* to
delegate is in your SOUL.md; this is only the mechanics.

## Why this is not just `kanban_create`

The `kanban` toolset is not enabled for the Discord platform, so a Discord
session has no `kanban_*` tools at all. You file through `terminal` instead.

Two consequences follow, and both have bitten:

1. **`hermes` is not on `PATH`.** The binary is `/opt/hermes/bin/hermes`. Do not
   go hunting for it.
2. **Auto-subscription does not happen.** `kanban.auto_subscribe_on_create` binds
   the *gateway session* that created a card. A card created through `terminal`
   has no gateway session, so it is silently orphaned — it will run, complete,
   and notify nobody. You must subscribe every card yourself.

If you ever find you *do* have `kanban_create` in your tools, use it directly and
ignore this file; auto-subscribe works on that path.

## The recipe

**Subscribe the channel you were asked in, not a fixed one.** Use the chat id of
the conversation you are currently in — results belong where the question was
asked. `1533648450082836480` (`#hermes`) is only the default home channel, and is
the wrong target if Zach asked somewhere else.

```bash
H=/opt/hermes/bin/hermes
SUB="--platform discord --chat-id <the id of THIS conversation> --chat-type channel"

# One card per investigation. Capture each id — you need them for the parents.
$H kanban create "Backup evidence" \
   --body "<brief: what to find out, and what DONE looks like>" \
   --assignee obs --max-runtime 15m
# -> Created t_aaaa
$H kanban notify-subscribe t_aaaa $SUB

$H kanban create "VM allocation and snapshots" \
   --body "<brief>" --assignee virt --max-runtime 15m
# -> Created t_bbbb
$H kanban notify-subscribe t_bbbb $SUB

# The synthesis card, parented to every investigation.
$H kanban create "Write the answer" \
   --body "<what question to answer, for whom>" \
   --assignee scribe --parent t_aaaa --parent t_bbbb
# -> Created t_cccc
$H kanban notify-subscribe t_cccc $SUB
```

Subscribe **every** card, not just the synthesis one. A fan-out takes four to
seven minutes on this hardware, longer if a worker exhausts its iteration budget
and the dispatcher retries it. With only the write-up subscribed, Zach gets your
acknowledgement and then minutes of silence he cannot distinguish from failure.

## Writing the brief

The `--body` is the entire context the worker gets, and **it is the single
biggest lever on whether the card succeeds.** Workers have a finite iteration
budget; a broad brief spends it enumerating instead of answering.

**Name the specific things to check. Never write an open-ended scope.**

| Don't | Do |
|---|---|
| "the actual runtime state of the media stack" | "memory use and restart count for each media container in the last 24h" |
| "look into DNS" | "does hermes.calzone.zone resolve the same from AdGuard and the UDM, and is it in NetBox" |
| "check if it's healthy" | "is the last backup within its expected daily cadence, and did any task report non-zero status" |

Words like *state*, *health*, *everything*, *anything wrong* have no natural
stopping point. A worker handed one will query metric after metric until its
budget dies and the card blocks — thirteen minutes of real work discarded. This
has already happened. If you cannot name what to check, the question is not ready
to file; ask Zach which part he means.

Say what "done" looks like, and cap the scope: a time window, a named set of
services, a specific metric.

**Scope each brief to what that agent can actually reach.** Each specialist has
one domain and no more — asking `obs` to check the repo and Proxmox produces a
card it can only half-answer. If a brief needs three domains, it is three cards.

## Checking on it

```bash
$H kanban show <id>      # status, summary, comments
$H kanban runs <id>      # attempt history — retries show here
$H kanban log <id>       # the worker's own output, when something looks wrong
```

A card sitting in `todo` with a parent is not stuck; it is correctly waiting.
Children promote to `ready` only once every parent completes.

## Notes

- `--max-runtime 15m` is a sensible default. The dispatcher SIGTERMs and requeues
  past it.
- Only one worker runs at a time by design (`kanban.max_in_progress: 1`) — the
  whole lab shares a single inference slot, so extra workers would queue at the
  model rather than accomplish anything.
- This skill is repo-managed (`hermes-agent/profiles/default/skills/`), not
  agent-authored, so the curator will not archive it. Edit it in the repo and
  re-run `scripts/sync-profiles.sh default`; editing it in place will be
  overwritten.
