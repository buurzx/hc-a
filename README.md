# hc-a

Agent-facing wrapper over `hc` ([herdr-core](https://herdr.dev)): persistent terminals,
child agents, and reports between them, shaped for a model rather than for a person.

`hc-a` does not implement anything. Every command is one `hc` call; the value is in three
places — the payload, the errors, and the contract.

```
$ hc-a
core 0.1.18  pid 65148  live 3  finished 11
terminals[3]{address,agent,state,status,turn,where}:
  t2q,omp,live,done,287,t-monitor / coordinator
  *t55,omp,live,working,3,agentic-system / 2
help[3]:
  working: t55 — end your turn and wait for their report
  hc-a run --cwd DIR --name NAME claude "task + report line" — delegate
  hc-a --skill — the contract
```

## Why not the CLI as-is

`hc` prints compact tables only when stdout is a terminal. An agent's stdout is a pipe, so it
always gets the full JSON: 879 B for six terminals, 787 B for one `get`. `hc-a` projects the
same call to 306 B and 161 B. Errors arrive as `{"error":{kind,message,hint}}` on stderr;
`hc-a` turns them into two lines and keeps `hc`'s exit code.

## Install

```sh
git clone <this repo> ~/projects/hc-a
ln -sf ~/projects/hc-a/hc-a   ~/.local/bin/hc-a
ln -sf ~/projects/hc-a/SKILL.md ~/.agents/skills/herdr/SKILL.md   # optional: teaches agents the contract
```

Requires `bash` (3.2 is fine), `jq`, and `hc` on `PATH` (or `HC_BIN`).

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
| `hc-a exec -- cmd…` | no terminal; text out, exit code kept |
| `hc-a kill\|rm\|label <t>` | lifetime |
| `hc-a templates\|machines` | roles, remote machines |

`<t>` is an address (`t7`), a name, or `machine/t7`; omitted for `get`/`read`/`wait` it means
your own terminal (`$HC_TERMINAL_ID`).

## The contract

The one rule the wrapper exists to teach: **a child you told to report never needs waiting.**

```sh
hc-a run --cwd DIR --name fix claude "Do X. Report when done or stuck: hc send $HC_TERMINAL_ID \"done: ...\""
```

Then do your own work; when nothing is left, end your turn — the report arrives by itself as
the next input and costs nothing while idle. `hc-a wait` is for the three cases where no
report is coming: the child was not told to report, a barrier between steps, or one specific
fact before publishing. `SKILL.md` is the same contract in the form agents load.

## Tests

```sh
bash hc-a.test.sh      # 32 assertions, no herdr, no network
```

`hc` is replaced by a stub through `HC_BIN`, so every test is deterministic and runs anywhere.
Each test pins a real defect found in review: exit codes lost through command substitution,
`--json` leaking into a child's argv after `--`, `wait` hiding `reason`/`children`/`from`,
`send --wait` dropping its outcome, an unsent first message staying invisible, `read` dumping
the whole screen, raw JSON errors, missing `<t>`, missing flag values, a dead core exiting 0,
and TOON fields broken by commas, quotes, backslashes or newlines.
