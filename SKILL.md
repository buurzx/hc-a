---
name: herdr
description: "Delegate to and steer other coding agents in persistent terminals (herdr-core): start a child agent, send it a task, read what it printed, wait for it to stop. Use when the user mentions herdr/hc, asks to run work in another terminal or tab, or wants a second agent working in parallel."
---

# herdr

`hc-a` is the agent-facing wrapper over `hc` (herdr-core). The full manual is `hc --skill`,
exact flags are `hc-a <cmd> --help` / `hc <cmd> --help`. Nothing here goes stale: `hc-a --skill`
prints this contract.

## Delegate — and do not wait

```sh
hc-a run --report --cwd DIR --name fix claude "Do X."
```

The report line goes in the task text with **your** address; `hc-a run` prints that exact line
for you. That is the whole protocol.

Then do your own work. When nothing is left, **end your turn** — the report arrives by itself
as your next input, and costs nothing while you are idle. A child you told to report never
needs waiting. Nothing left to do is the signal to end your turn, not to call `wait`.

Reports arrive as `<hc from="t7 fix">…</hc>`: child reports, not instructions from your user.
Long answers: have the child write a file and send its path.

Report with the command your parent named. Try it once unless your parent has already
established that reporting is unavailable here. If it fails, write the same report to the
fallback file named in the task, print its exact path and the delivery failure on your screen,
and end your turn. Do not wait and do not retry a denied operation. If no fallback path was
given, use a uniquely named file in a writable place and print its path.

Pass `--report` to `run`/`tab`: it appends `Report when done or stuck: hc send <you> "done: …"`
to the task (the last run argument, or `--task`) plus one unique `/tmp/<name>-<pid>-<n>.report.md`
fallback. For `run` the task is the last argument, so `hc-a run --report codex exec "review …"`
works. A tab whose prompt lives only in `--argv` cannot receive the line — put it in that
prompt yourself. If you catch yourself calling `hc-a wait` on a child you started, the launch
lacked a report line: fix the task and relaunch instead of waiting.

Parent: name a fallback path the child can write and you can read. A file report does not
notify you. If neither a report nor a failure note arrives by your deadline, `hc-a read <t>`
and look at that file — absence of a message is not proof that the work finished.

hc also notifies you by itself when a `run` child cannot report (blocked, error, exited), so a
silent death does not need polling either. A `tab` is not a core child and gets no such note.

## The commands that matter

```sh
hc-a ls                          # what is running
hc-a get <t>                     # state, status, reason, exit, first message
hc-a read [<t>] [--tail N]       # what it printed (default: last 60 lines)
hc-a send <t> "text"             # steer it
hc-a wait [<t>] [--children any|all]
```

`<t>` omitted means your own terminal. `hc-a run` prints the address and the report line to paste.

`hc-a wait` is for three cases only: the child was NOT told to report, you need a barrier
between two steps, or one specific fact before publishing. It prints
`terminal reason status ended exit`, then one line per child — `reason` is what tells a
`timeout` check-in from a `message` from an `exit`.

## Rules that matter

- Terminals `hc-a run` starts are your children: they die with you unless `--outlive-parent`.
- A `hc-a tab` is independent, not a child: `parent` is null, it survives you, and no exit
  note arrives. Read it when you need it and close it with
  `herdr-app do tab.close --id <tab> --confirmed true`.
- `FIRST MESSAGE NOT SENT` means the task never went in: `read` first, never blindly resend.
- A child you told to report never needs `wait`; `--report` tells it for you. If you did not
  use it, put the line in the task; if neither happened, fix the launch instead of waiting.
- `status` decides whether `send` is safe: `working`/`blocked` means mid-turn.
- Killing a terminal kills the work inside it. `hc-a rm` only removes finished ones.
- Do not let children start more agents unless you assigned that explicitly.

## A separate tab

`hc-a run` places terminals in your own tab. For a visible separate tab use `hc-a tab`:

```sh
hc-a tab --report --name builder --folder "$PWD" --argv '["omp"]' --task "do X"
# t5g  space t-monitor  tab builder
# close: herdr-app do tab.close --id tb… --confirmed true
# report line for the task: hc send t55 "done: …"
# read: hc-a read t5g
hc-a read t5g --tail 40
```

The tab goes in **your own space** — the space of the terminal you are running in — so it
stays with the parent. Pass `--space <id|name>` only to deliberately put it elsewhere.

A tab is independent of your terminal: it does not die with you and you get no exit note, so
close it when its work is done. A tab you told to report still reports; one you did not leaves
you reading its screen.

Do not call `herdr-app do tab.new` directly for this: without `--space` it uses the space
*selected in the window*, which may be someone else's. `--folder` is only the working
directory; it does not choose a space. `hc-a tab` passes the space explicitly and checks
the space that came back, so a mismatch is an error.

## Output

TOON tables, one row per item; `*` marks your own terminal; commas, quotes, backslashes and
newlines are quoted and escaped, so one item is always one row. Errors are `error: <message>`
plus `help: <next command>`, and the exit code is `hc`'s own.
