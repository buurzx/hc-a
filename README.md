# hc-a

**An agent-friendly CLI for [Herdr](https://herdr.dev) / [herdr-core](https://github.com/herdrdev/herdr-core): see your terminals, delegate work to other agents, and get the result back — without burning context on JSON.**

`hc-a` is a thin wrapper over `hc`, the command-line interface of herdr-core. It is for
people who run coding agents (Claude Code, Codex, OpenCode, Pi, omp, …) inside Herdr and
want one agent to start, steer and collect results from another.

It does four things:

- **Shows state compactly.** `hc-a ls` is one short TOON table instead of a JSON document.
- **Delegates without waiting.** `hc-a run` starts a helper and prints the exact report line
  to put in its task; the report arrives as the parent's next input.
- **Keeps reports unambiguous.** A child dies, blocks or exits without a report — you get a
  note, not silence. `hc-a wait` exists for the three cases where no report is coming.
- **Creates tabs in the right space.** `hc-a tab` puts a new Herdr tab in **the caller's
  space**, not in whichever space the window happens to be showing.

No daemon, no state, no config. Every command is one or two calls to `hc` or `herdr-app`.

```
$ hc-a
core 0.1.18  pid 65148  live 2  finished 11
terminals[2]{address,agent,state,status,turn,where}:
  t2q,omp,live,done,287,t-monitor / coordinator
  *t55,omp,live,working,3,agentic-system / 2
help[4]:
  working: t55 — end your turn and wait for their report
  hc-a run --cwd DIR --name NAME claude "task + report line" — delegate
  hc-a tab --name NAME --argv '["claude"]' --task "…" — own space
  hc-a --skill — the contract
```

## What it is for

A coordinator agent should not poll a helper, and should not spend context parsing `hc`'s
full JSON. `hc-a` gives it one compact view and one rule:

> **A child you told to report never needs waiting.**

```sh
hc-a run --cwd ~/proj --name api claude \
  'Add pagination to /users. Report when done or stuck: hc send t55 "done: ..."'
# t5a  live  claude  /Users/me/proj  name=api
# report line for the task: hc send t55 "done: …"
# read: hc-a read t5a
```

Do your own work. When nothing is left, end your turn — the report wakes you. A child that
dies or blocks without reporting raises its own note (`<hc>t5a api exited (signal 9)</hc>`),
provided notes are enabled (`notes = false` in `~/.config/herdr-core/config.toml` and
`hc run --no-notify` disable them). A sandboxed child may be unable to run `hc send` at all,
so name a fallback file in its task; if nothing arrives, `hc-a read <t>` and look there.

## Requirements

- [Herdr](https://herdr.dev) and its `hc` (herdr-core) on `PATH` — `hc-a` is a wrapper, not a
  terminal server.
- `bash` (3.2 is fine) and `jq`.
- `herdr-app` for `hc-a tab` (it ships with the Herdr desktop app).
- Optional: an agent CLI such as `claude`, `codex`, `opencode`, `pi` or `omp` for delegation.

`--help` and `--skill` work without any dependency, so a fresh machine can read the contract
before installing anything.

## Install

```sh
mkdir -p ~/projects ~/.local/bin ~/.agents/skills/herdr
git clone https://github.com/buurzx/hc-a.git ~/projects/hc-a
ln -sf ~/projects/hc-a/hc-a ~/.local/bin/hc-a
ln -sf ~/projects/hc-a/SKILL.md ~/.agents/skills/herdr/SKILL.md   # optional: agents load it
export PATH="$HOME/.local/bin:$PATH"        # put this in your shell profile to keep it
```

`hc-a` finds its contract through the symlink, so `--skill` works from `~/.local/bin`.

## Commands

| | |
|---|---|
| `hc-a` | dashboard: core, terminals, next steps |
| `hc-a ls [--all]` | live terminals, 6 fields, `*` = your own |
| `hc-a get [<t>]` | state, status, reason, exit code, `FIRST MESSAGE NOT SENT` |
| `hc-a read [<t>] [--tail N]` | what it printed; default last 60 lines, `--tail 0` = whole screen |
| `hc-a send <t> "text" [--wait]` | steer it; with `--wait`, reports how the turn ended |
| `hc-a wait [<t>] [--children any\|all]` | blocks in the core; prints `reason`, so a timeout check-in is not mistaken for an exit |
| `hc-a run [--name N] [--cwd P] cmd…` | start a terminal; prints the report line to put in its task |
| `hc-a tab [--space S] [--name N] [--folder P] [--argv JSON] [--task T]` | a visible tab in **your** space (default); `--space <id\|name>` to override; checks where it landed |
| `hc-a exec -- cmd…` | no terminal; text out, exit code kept |
| `hc-a kill <t>` / `rm <t>` / `label <t> k=v…` | lifetime, labels |
| `hc-a templates\|machines` | roles, remote machines |

`<t>` is an address (`t7`), a name, or `machine/t7`. For `get`/`read`/`wait` it may be omitted
and means your own terminal (`$HC_TERMINAL_ID`); `send` always needs one, because a message is
not a terminal. Text after a dash (`--help`) is sent as data, not read as an option.

## A separate tab

`hc-a run` places terminals in your own tab. For a visible separate tab use `hc-a tab`:

```sh
hc-a tab --name builder --folder "$PWD" --argv '["claude"]' --task "do X"
# t5g  space t-monitor  tab builder
# close: herdr-app do tab.close --id tb… --confirmed true
# report line for the task: hc send t55 "done: …"
# read: hc-a read t5g
```

The tab goes in **your own space** — the space of the terminal you are running in — so it
stays with the parent. Pass `--space <id|name>` only to deliberately put it elsewhere.

Do not call `herdr-app do tab.new` directly for this: without `--space` it uses the space
*selected in the window*, which may be someone else's. `--folder` is only the working
directory; it does not choose a space. `hc-a tab` passes the space explicitly and checks
the space that came back, so a mismatch is an error.

## Why not the CLI as-is

`hc` prints compact tables only when stdout is a terminal. An agent's stdout is a pipe, so it
always gets the full JSON. One observed snapshot on 2026-11-06 with `hc 0.1.18`, six live
terminals:

```sh
hc ls --json | wc -c      # 879      hc-a ls | wc -c      # 306
hc get t2q --json | wc -c # 787      hc-a get t2q | wc -c # 161
```

Sizes depend on terminal count and content; this is one measurement, not a guarantee. Errors
arrive as `{"error":{kind,message,hint}}` on stderr — sometimes after a startup diagnostic line
— and `hc-a` turns the last structured one into two lines while keeping `hc`'s exit code.

## How it works

- **Compact payload.** `ls`/`get`/`wait` are projected into TOON-like rows; commas, quotes,
  backslashes and newlines are quoted so one item is always one row.
- **Stable errors.** `error: <message>` + `help: <next command>`, with `hc`'s exit code kept.
- **Projection, not implementation.** `kill`, `rm`, `label`, `templates` and `machines` pass
  through; `exec` is the program itself. `tab` is the only command that needs `herdr-app`.
- **A contract for agents.** `SKILL.md` ships the workflow; `hc-a --skill` prints it.

## Tests

```sh
bash hc-a.test.sh      # 80 assertions, no herdr, no network
```

`hc` is replaced by a stub through `HC_BIN` and `herdr-app` by one through `HERDR_APP_BIN`,
so every test is deterministic and runs anywhere.
Each test pins a real defect found in review: exit codes lost through command substitution,
`--json` leaking into a child's argv after `--`, `wait` hiding `reason`/`children`/`from`,
`send --wait` dropping its outcome, an unsent first message staying invisible, `read` dumping
the whole screen, raw JSON errors, missing `<t>`, missing flag values, a dead core exiting 0,
TOON fields broken by commas, quotes, backslashes or newlines, and a tab landing in the
window's selected space instead of the caller's.

## Contributing

Issues and pull requests are welcome. Keep the wrapper thin: fix the payload, the error or the
contract, not the upstream program. Run `bash hc-a.test.sh` before sending a change; new tests
should pin a defect that a user could actually see.

## License

MIT — see [LICENSE](LICENSE).
