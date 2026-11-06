# hc-a

Agent-facing wrapper over `hc` ([herdr-core](https://herdr.dev)): persistent terminals,
child agents, and reports between them, shaped for a model rather than for a person.

`hc-a` does not implement anything: it projects upstream calls. Most commands are one `hc`
call; the dashboard is two (`server status`, then `ls`), and `tab` is `herdr-app ls` plus
`herdr-app do tab.new` (the window owns tabs; an `hc` terminal alone cannot make one). The
value is in three places — the payload, the errors, and the contract.

```
$ hc-a
core 0.1.18  pid 65148  live 2  finished 11
terminals[2]{address,agent,state,status,turn,where}:
  t2q,omp,live,done,287,t-monitor / coordinator
  *t55,omp,live,working,3,agentic-system / 2
help[3]:
  working: t55 — end your turn and wait for their report
  hc-a run --cwd DIR --name NAME claude "task + report line" — delegate
  hc-a --skill — the contract
```

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

## Install

```sh
mkdir -p ~/projects ~/.local/bin ~/.agents/skills/herdr
git clone git@github.com:buurzx/hc-a.git ~/projects/hc-a
ln -sf ~/projects/hc-a/hc-a ~/.local/bin/hc-a
ln -sf ~/projects/hc-a/SKILL.md ~/.agents/skills/herdr/SKILL.md   # optional: agents load it
export PATH="$HOME/.local/bin:$PATH"        # put this in your shell profile to keep it
```

`hc-a` finds its contract through the symlink, so `--skill` works from `~/.local/bin`. Requires
`bash` (3.2 is fine), `jq`, and `hc` on `PATH` (or `HC_BIN`); `tab` also needs `herdr-app`
(or `HERDR_APP_BIN`). `--help` and `--skill` work without any of them, so a fresh machine can
be read before anything is installed.

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

## The contract

The one rule the wrapper exists to teach: **a child you told to report never needs waiting.**

```sh
hc-a run --cwd DIR --name fix claude "Do X. Report when done or stuck: hc send $HC_TERMINAL_ID \"done: ...\""
```

Then do your own work; when nothing is left, end your turn — the report arrives by itself as
the next input and costs nothing while idle. `hc-a wait` is for the three cases where no
report is coming: the child was not told to report, a barrier between steps, or one specific
fact before publishing. `SKILL.md` is the same contract in the form agents load.

Two preconditions for the "silence is never ambiguous" part: automatic notes must be enabled
(`notes = false` in `~/.config/herdr-core/config.toml` and `hc run --no-notify` both disable
them), and a sandboxed child may be unable to run `hc send` at all. So name a fallback file in
the task; if neither a report nor a failure note arrives, `hc-a read <t>` and look there.

## Workflow: one coordinator, several children

```sh
# 1. launch — the report line comes out of the command, paste it into the task
hc-a run --cwd ~/proj --name api claude \
  'Add pagination to /users. Report when done or stuck: hc send t55 "done: ..."'
# t5a  live  claude  /Users/me/proj  name=api
# report line for the task: hc send t55 "done: …"
# read: hc-a read t5a

hc-a run --cwd ~/proj --name tests claude 'Cover it. Report when done: hc send t55 "done: ..."'

# 2. do your own work. Nothing left? End your turn — reports wake you.

# 3. a report arrives as your next input:
#    <hc from="t5a api">done: endpoints paginated, 3 files changed</hc>
hc-a get t5a          # t5a  live · done (turn 7)
                      #   agent: claude   cwd: /Users/me/proj   pid: 81234
hc-a read t5a --tail 40

# 4. barrier before publishing, then clean up
hc-a wait t55 --children all --timeout 900
hc-a kill t5a; hc-a rm t5a
```

A child that dies or blocks without reporting raises its own note
(`<hc>t5a api exited (signal 9)</hc>`), provided notes are enabled. With `--no-notify` or
`notes = false`, step 3 never fires — use `hc-a wait` instead of ending your turn.

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

## License

MIT — see [LICENSE](LICENSE).
