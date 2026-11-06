#!/usr/bin/env bash
# Tests for hc-a. No herdr, no network: `hc` is replaced by a stub via HC_BIN and
# `herdr-app` by one via HERDR_APP_BIN.
# Each case runs in a clean environment (env -i) so nothing leaks from the caller's terminal.
# Run: bash hc-a.test.sh
set -u

HCA="$(cd "$(dirname "$0")" && pwd)/hc-a"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/hca-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

STUB="$TMP/hc"
cat >"$STUB" <<'STUB'
#!/usr/bin/env bash
printf '<%s>\n' "$@" >> "$FAKE_LOG"
key=$1
[[ $key == server ]] && key=status
[[ $key == machine ]] && key=machines
[[ -f "$FAKE_DIR/$key.out" ]] && cat "$FAKE_DIR/$key.out"
[[ -f "$FAKE_DIR/$key.err" ]] && cat "$FAKE_DIR/$key.err" >&2
[[ -f "$FAKE_DIR/$key.rc" ]] && exit "$(cat "$FAKE_DIR/$key.rc")"
exit 0
STUB
chmod +x "$STUB"

# herdr-app is stubbed too: only `tab` uses it.
STUB_APP="$TMP/herdr-app"
cat >"$STUB_APP" <<'STUB'
#!/usr/bin/env bash
printf '<%s>\n' "$@" >> "$APP_LOG"
key=$1
[[ -f "$APP_DIR/$key.out" ]] && cat "$APP_DIR/$key.out"
[[ -f "$APP_DIR/$key.err" ]] && cat "$APP_DIR/$key.err" >&2
[[ -f "$APP_DIR/$key.rc" ]] && exit "$(cat "$APP_DIR/$key.rc")"
exit 0
STUB
chmod +x "$STUB_APP"

TMO=""
if command -v timeout >/dev/null 2>&1; then TMO="timeout 15"; fi

passn=0; failn=0
pass() { passn=$((passn+1)); printf '  ok    %s\n' "$1"; }
fail() { failn=$((failn+1)); printf '  FAIL  %s\n' "$1"; [[ -n ${2:-} ]] && printf '        %s\n' "$2"; }

fx() { # fx <key> <stdout> [stderr] [rc]
  printf '%s' "$2" >"$FAKE_DIR/$1.out"
  [[ -n ${3:-} ]] && printf '%s' "$3" >"$FAKE_DIR/$1.err"
  [[ -n ${4:-} ]] && printf '%s' "$4" >"$FAKE_DIR/$1.rc"
  return 0
}
reset() { rm -rf "$FAKE_DIR" "$APP_DIR"; mkdir -p "$FAKE_DIR" "$APP_DIR"; : >"$FAKE_LOG"; : >"$APP_LOG"; }
fxapp() { # fxapp <key> <stdout> [stderr] [rc]
  printf '%s' "$2" >"$APP_DIR/$1.out"
  [[ -n ${3:-} ]] && printf '%s' "$3" >"$APP_DIR/$1.err"
  [[ -n ${4:-} ]] && printf '%s' "$4" >"$APP_DIR/$1.rc"
  return 0
}

# run_a [-u VAR | VAR=value]... -- hc-a args   (clean environment, stub hc)
run_a() {
  local assigns=() unsets=()
  while [[ ${1:-} != -- ]]; do
    case $1 in
      -u) unsets+=(-u "$2"); shift 2 ;;
      *)  assigns+=("$1"); shift ;;
    esac
  done
  shift
  $TMO env -i ${unsets[@]+"${unsets[@]}"} PATH="$JQDIR:/usr/bin:/bin:/usr/sbin:/sbin" LANG=C \
    TMPDIR="$TMP" HC_BIN="$STUB" FAKE_DIR="$FAKE_DIR" FAKE_LOG="$FAKE_LOG" \
    HERDR_APP_BIN="$STUB_APP" APP_DIR="$APP_DIR" APP_LOG="$APP_LOG" \
    ${assigns[@]+"${assigns[@]}"} "$HCA" "$@"
}
same() { [[ "$1" == "$2" ]] && pass "$3" || fail "$3" "want [$2] got [$1]"; }
has()  { case "$1" in *"$2"*) pass "$3";; *) fail "$3" "want substring [$2] in [$1]";; esac; }
hasnt(){ case "$1" in *"$2"*) fail "$3" "unwanted [$2] in [$1]";; *) pass "$3";; esac; }
rc_is(){ [[ "$1" == "$2" ]] && pass "$3" || fail "$3" "want rc $2 got $1"; }

JQDIR=$(dirname "$(command -v jq)")
FAKE_DIR="$TMP/fx"; FAKE_LOG="$TMP/args.log"; mkdir -p "$FAKE_DIR"
APP_DIR="$TMP/fxapp"; APP_LOG="$TMP/app.log"; mkdir -p "$APP_DIR"; : >"$APP_LOG"

# ------------------------------------------------------------ help without deps
out=$(env -i PATH=/usr/bin:/bin "$HCA" --help 2>&1); rc=$?
rc_is "$rc" 0 "help: works with no jq and no hc"
has "$out" "hc-a — agent view of hc" "help: prints usage"

mkdir -p "$TMP/inst/bin" "$TMP/inst/repo"
cp "$HCA" "$TMP/inst/repo/hc-a"
printf -- '---\nname: x\n---\nBODY-LINE\n' >"$TMP/inst/repo/SKILL.md"
ln -sf ../repo/hc-a "$TMP/inst/bin/hc-a"
out=$(env -i PATH=/usr/bin:/bin "$TMP/inst/bin/hc-a" --skill 2>&1); rc=$?
rc_is "$rc" 0 "skill: works with no jq and no hc"
has "$out" "BODY-LINE" "skill: found through the install symlink"
hasnt "$out" "name: x" "skill: front matter stripped"

mkdir -p "$TMP/alone"; cp "$HCA" "$TMP/alone/hc-a"
out=$(env -i PATH=/usr/bin:/bin "$TMP/alone/hc-a" --skill 2>&1)
has "$out" "standalone install" "skill: incomplete standalone fallback"

# ---------------------------------------------------------------- P1.1 run rc
reset
fx run '' '{"error":{"message":"cannot start","hint":"check the program name"}}' 1
out=$(run_a -- run --name x sh 2>&1); rc=$?
rc_is "$rc" 1 "run: failure keeps hc's exit code"
has "$out" 'error: cannot start' "run: error message parsed"
has "$out" 'help: check the program name' "run: hint becomes help:"

# ------------------------------------------------- P1.x --json must not leak
reset
fx run '{"address":"t9","state":"live","agent":"sh","cwd":"/tmp"}'
out=$(run_a -- run --name x -- sh -c 'echo hi' 2>&1)
log=$(cat "$FAKE_LOG")
has "$log" '<sh>
<-c>
<echo hi>' "argv: program and its argument stay separate"
case "$log" in
  *'<--json>'*'<-->'*) pass "argv: --json sits before the -- delimiter";;
  *) fail "argv: --json sits before the -- delimiter" "got [$log]";;
esac
after=$(sed -n '/^<-->$/,$p' "$FAKE_LOG" | tail -n +2)
same "$after" '<sh>
<-c>
<echo hi>' "argv: nothing but the program after --"

# ------------------------------------------------- send: text starting with --
reset
fx send '{"started":true,"status":"done","turn":3}'
out=$(run_a HC_TERMINAL_ID=t55 -- send t5 --help)
log=$(cat "$FAKE_LOG")
case "$log" in
  *'<-->
<t5>
<--help>'*) pass "send: text after a dash stays data, behind --";;
  *) fail "send: text after a dash stays data, behind --" "got [$log]";;
esac

# ------------------------------------------------------ P1.2 wait rendering
reset
fx wait '{"terminal":"t5","reason":"message","status":"working","ended":false,"exit_code":null,"from":"t7"}'
out=$(run_a -- wait t5)
same "$out" 't5  message  status: working  ended: false  exit: -  from: t7' "wait: reason and from are rendered"

reset
fx wait '{"terminal":"t5","reason":"timeout","status":null,"ended":false,"children":[{"terminal":"t6","reason":"exit","status":null,"ended":true,"exit_code":0},{"terminal":"t7","reason":"running","status":"working","ended":false}]}'
out=$(run_a -- wait t5 --children all)
same "$out" 't5  timeout  status: -  ended: false  exit: -
  t6  exit  status: -  ended: true  exit: 0
  t7  running  status: working  ended: false  exit: -' "wait: one line per child"

# --------------------------------------------------------- P1.3 send --wait
reset
fx send '{"started":true,"status":"done","turn":3,"wait":{"reason":"not_started","status":null}}'
out=$(run_a -- send t5 'hello')
same "$out" 'sent: true  was: done (turn 3)  → not_started  -' "send: --wait outcome is not dropped"

# ------------------------------------------------------- P1.4 first_message
reset
fx run '{"address":"t9","state":"live","agent":"claude","cwd":"/tmp","name":"fix","first_message":{"sent":false,"reason":"readiness"}}'
out=$(run_a HC_TERMINAL_ID=t55 -- run --name fix claude 'do x')
has "$out" 'FIRST MESSAGE NOT SENT: readiness' "run: unsent first message is flagged"
has "$out" 'hc send t55' "run: prints the caller's report line"
has "$out" '/tmp/fix.report.md' "run: prints the fallback report path"

reset
fx get '{"address":"t9","state":"live","cwd":"/tmp","argv":["claude"],"first_message":{"sent":false,"reason":"readiness"}}'
out=$(run_a HC_TERMINAL_ID=t55 -- get t9)
has "$out" 'FIRST MESSAGE NOT SENT: readiness' "get: unsent first message is flagged"

# ------------------------------------------------------------- P2.1 read size
reset
seq 1 100 >"$FAKE_DIR/read.out"
same "$(run_a -- read t5 | wc -l | tr -d ' ')" 60 "read: default keeps the last 60 lines"
same "$(run_a -- read t5 --tail 0 | wc -l | tr -d ' ')" 100 "read: --tail 0 keeps the whole screen"
same "$(run_a -- read t5 --tail 5 | wc -l | tr -d ' ')" 5 "read: --tail N"

# ------------------------------------------------------- P2.1 read error path
reset
fx read '' '{"error":{"kind":"not_found","message":"no terminal \"zzz\"","hint":"see `hc ls --all`"}}' 3
out=$(run_a -- read zzz 2>&1); rc=$?
rc_is "$rc" 3 "read: exit code is hc's"
same "$out" 'error: no terminal "zzz"
help: see `hc ls --all`' "read: error is parsed, not dumped as JSON"

# --------------------------------------------- P2.1 diagnostic before the JSON
reset
fx ls '{"terminals":[]}' 'hc: startup diagnostic
{"error":{"message":"cannot start core","hint":"check the core log"}}' 5
out=$(run_a -- ls 2>&1); rc=$?
rc_is "$rc" 5 "mixed stderr: exit code preserved"
has "$out" 'error: cannot start core' "mixed stderr: structured error extracted"
has "$out" 'help: check the core log' "mixed stderr: hint survives"
hasnt "$out" '"error"' "mixed stderr: no raw JSON leaked"

# ------------------------------------------------------- P2.2 missing values
reset
out=$(run_a -- read t5 --lines 2>&1); rc=$?
rc_is "$rc" 2 "read: --lines without a value fails cleanly"
same "$out" 'error: --lines needs a value' "read: --lines message"
same "$(run_a -- run --cwd 2>&1)" 'error: --cwd needs a value' "run: --cwd message"

# ------------------------------------------------------ P2.3 <t> defaulting
reset
fx get '{"address":"t55","state":"live","cwd":"/tmp","argv":["zsh"]}'
out=$(run_a HC_TERMINAL_ID=t55 -- get)
has "$out" '*t55' "get: no argument means your own terminal"
same "$(cat "$FAKE_LOG")" '<get>
<t55>
<--json>' "get: own address reaches hc"

reset
out=$(run_a -- get 2>&1); rc=$?
rc_is "$rc" 2 "outside herdr: exit code 2, not hc's"
same "$out" 'error: terminal required: pass <t> or run inside a herdr terminal' "outside herdr: single clean message"

for c in read wait; do
  out=$(run_a -- $c 2>&1); rc=$?
  rc_is "$rc" 2 "$c: no terminal outside herdr is rc 2"
done

# --------------------------------------------------------- P2.4 dashboard
reset
fx status '' '{"error":{"message":"core down"}}' 4
out=$(run_a -- dashboard 2>&1); rc=$?
rc_is "$rc" 4 "dashboard: dead core propagates the exit code"
has "$out" 'error: core down' "dashboard: error is parsed"

reset
fx status '{"version":"0.1.18","pid":1,"live":1,"finished":0}'
fx ls '{"terminals":[{"address":"t1","agent":"zsh","state":"live","status":null,"turn":0,"where":"a / 1"}]}'
err=$(run_a -- dashboard 2>&1 >/dev/null)
same "$err" '' "dashboard: nothing on stderr on the happy path"

# --------------------------------------------------------- missing surfaces
reset
fx ls '{"terminals":[]}'
out=$(run_a -- ls --all)
has "$(cat "$FAKE_LOG")" '<--all>' "ls --all: forwarded to hc"

reset
fx exec 'out-line' 'err-line' 7
out=$(run_a -- exec -- /usr/bin/true 2>"$TMP/e"); rc=$?
rc_is "$rc" 7 "exec: program exit code is kept"
same "$out" 'out-line' "exec: stdout passes through"
same "$(cat "$TMP/e")" 'err-line' "exec: stderr passes through"

reset
out=$(run_a -- nope 2>&1); rc=$?
rc_is "$rc" 2 "unknown command: rc 2"
has "$out" 'error: unknown command nope' "unknown command: message"

reset
fx get '' '{"error":{"kind":"not_found","message":"no terminal \"zz\"","hint":"see `hc ls --all`"}}' 3
out=$(run_a -- get zz 2>&1); rc=$?
rc_is "$rc" 3 "get: missing terminal keeps rc 3"
has "$out" 'error: no terminal "zz"' "get: structured error"

reset
fx templates '{"templates":[]}'
same "$(run_a -- templates)" 'no templates' "templates: empty case"
fx templates '{"templates":[{"name":"reviewer","description":"reviews"}]}'
same "$(run_a -- templates)" 'reviewer  reviews' "templates: rows"
fx machines '{"machines":[]}'
same "$(run_a -- machines)" 'no machines' "machines: empty case"

# ------------------------------------------------------------ P2.5 TOON
reset
printf '%s' '{"terminals":[{"address":"t1","agent":"a,b","state":"live","status":"working","turn":2,"where":"x\ny,\"z\\w"}]}' >"$FAKE_DIR/ls.out"
out=$(run_a -- ls)
same "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2 "ls: hostile field stays on one row"
same "$(printf '%s\n' "$out" | tail -1)" '  t1,"a,b",live,working,2,"x\ny,\"z\\w"' "ls: comma/quote/backslash/newline escaped"

# --------------------------------------------------------------- tab: parent space
SPACES='{"spaces":[{"id":"spPARENT","name":"parent","tabs":[{"id":"tbParent","name":"1","terminals":[{"terminal":"t55"}]}]},{"id":"spOTHER","name":"other","tabs":[{"id":"tbOther","name":"1","terminals":[{"terminal":"t99"}]}]}]}'

reset
fxapp ls "$SPACES"
fxapp do '{"space":"spPARENT","tab":"tbNew","terminal":"t5g"}'
fx get '{"address":"t55","labels":{"herdr.space":"spPARENT"}}'
out=$(run_a HC_TERMINAL_ID=t55 -- tab --name builder --folder /tmp --argv '["omp"]' --task 'do x' 2>&1); rc=$?
rc_is "$rc" 0 "tab: creates a tab"
same "$out" 't5g  space parent  tab builder
close: herdr-app do tab.close --id tbNew --confirmed true
report line for the task: hc send t55 "done: …"
read: hc-a read t5g' "tab: prints the landing space and next steps"
same "$(cat "$APP_LOG")" '<ls>
<do>
<tab.new>
<--space>
<spPARENT>
<--name>
<builder>
<--folder>
</tmp>
<--argv>
<["omp"]>
<--task>
<do x>' "tab: parent space is explicit, flags forwarded"

reset
fxapp ls "$SPACES"
fxapp do '{"space":"spPARENT","tab":"tbNew","terminal":"t5g"}'
fx get '{"address":"t55","labels":{}}'
out=$(run_a HC_TERMINAL_ID=t55 -- tab --name builder)
has "$out" 't5g  space parent  tab builder' "tab: falls back to ls when the label is missing"

reset
fxapp ls "$SPACES"
fxapp do '{"space":"spOTHER","tab":"tbNew","terminal":"t5h"}'
fx get '{"address":"t55","labels":{"herdr.space":"spPARENT"}}'
out=$(run_a HC_TERMINAL_ID=t55 -- tab --space other --name probe)
has "$out" 't5h  space other  tab probe' "tab: --space other wins"
has "$(cat "$APP_LOG")" '<spOTHER>' "tab: --space name is resolved to an id"

reset
fxapp ls "$SPACES"
fx get '{"address":"t55","labels":{"herdr.space":"spPARENT"}}'
out=$(run_a HC_TERMINAL_ID=t55 -- tab --space nope 2>&1); rc=$?
rc_is "$rc" 2 "tab: unknown space is a usage error"
same "$out" 'error: no space "nope" (herdr-app ls lists them)' "tab: unknown space message"
hasnt "$(cat "$APP_LOG")" 'tab.new' "tab: unknown space creates nothing"

reset
fxapp ls "$SPACES"
fxapp do '{"space":"spOTHER","tab":"tbNew","terminal":"t5g"}'
fx get '{"address":"t55","labels":{"herdr.space":"spPARENT"}}'
out=$(run_a HC_TERMINAL_ID=t55 -- tab --name builder 2>&1); rc=$?
rc_is "$rc" 1 "tab: wrong landing space fails"
same "$out" 'error: tab created in space spOTHER, wanted spPARENT
help: herdr-app do tab.close --id tbNew --confirmed true' "tab: mismatch names both spaces and the tab"

reset
fxapp ls "$SPACES"
fxapp do '{"space":"spPARENT","tab":"tbMod","pane":"p1"}'
fx get '{"address":"t55","labels":{"herdr.space":"spPARENT"}}'
out=$(run_a HC_TERMINAL_ID=t55 -- tab --name board --mod files --props '{"folder":"/tmp"}' 2>&1); rc=$?
rc_is "$rc" 0 "tab: a mod tab has no terminal and still succeeds"
same "$out" 'tbMod  space parent  tab board
close: herdr-app do tab.close --id tbMod --confirmed true' "tab: mod tab prints no read line"

reset
fxapp ls "$SPACES"
fxapp do '{"space":"spPARENT","tab":"tbNoTerm"}'
fx get '{"address":"t55","labels":{"herdr.space":"spPARENT"}}'
out=$(run_a HC_TERMINAL_ID=t55 -- tab --name x 2>&1); rc=$?
rc_is "$rc" 1 "tab: a terminal tab without a terminal fails"
same "$out" 'error: tab tbNoTerm has no terminal
help: herdr-app ls' "tab: malformed reply message"

reset
fxapp ls "$SPACES"
out=$(run_a -- tab --name builder 2>&1); rc=$?
rc_is "$rc" 2 "tab: outside herdr it refuses to guess"
same "$out" 'error: cannot tell your space: run inside a herdr terminal or pass --space <id|name>' "tab: no selected-space fallback"

reset
fxapp ls '{"error":"no window"}' '' 1
out=$(run_a HC_TERMINAL_ID=t55 -- tab --name x 2>&1); rc=$?
rc_is "$rc" 1 "tab: app error keeps its exit code"
same "$out" 'error: no window
help: herdr-app commands' "tab: app error is mapped"

reset
out=$(run_a -- tab --space 2>&1); rc=$?
rc_is "$rc" 2 "tab: --space without a value fails cleanly"
same "$out" 'error: --space needs a value' "tab: --space message"
same "$(run_a -- tab extra 2>&1)" 'error: unexpected argument: extra (tab takes only flags; see hc-a --help)' "tab: positional argv is rejected"

# ------------------------------------------------- usage and passthrough
reset
out=$(run_a -- send onlytext 2>&1); rc=$?
rc_is "$rc" 2 "send: missing text is a usage error"
same "$out" 'error: text required: hc-a send <t> "text"' "send: usage message"

reset
fx kill 'removed t5' '' 0
out=$(run_a -- kill t5 2>&1); rc=$?
rc_is "$rc" 0 "kill: non-JSON output passes through"
same "$out" 'removed t5' "kill: raw text kept"

printf '\n%d passed, %d failed\n' "$passn" "$failn"
[[ $failn == 0 ]]
