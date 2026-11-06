#!/usr/bin/env bash
# Tests for hc-a. No herdr, no network: `hc` is replaced by a stub via HC_BIN.
# Each test pins one defect found in the 3-round review. Run: bash hc-a.test.sh
set -u

HCA="$(cd "$(dirname "$0")" && pwd)/hc-a"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/hca-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

STUB="$TMP/hc"
cat >"$STUB" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
key=$1
[[ $key == server ]] && key=status
[[ $key == machine ]] && key=machines
[[ -f "$FAKE_DIR/$key.out" ]] && cat "$FAKE_DIR/$key.out"
[[ -f "$FAKE_DIR/$key.err" ]] && cat "$FAKE_DIR/$key.err" >&2
[[ -f "$FAKE_DIR/$key.rc" ]] && exit "$(cat "$FAKE_DIR/$key.rc")"
exit 0
STUB
chmod +x "$STUB"

passn=0; failn=0
pass() { passn=$((passn+1)); printf '  ok    %s\n' "$1"; }
fail() { failn=$((failn+1)); printf '  FAIL  %s\n' "$1"; [[ -n ${2:-} ]] && printf '        %s\n' "$2"; }

# fx <key> <stdout> [stderr] [rc]
fx() {
  printf '%s' "$2" >"$FAKE_DIR/$1.out"
  [[ -n ${3:-} ]] && printf '%s' "$3" >"$FAKE_DIR/$1.err"
  [[ -n ${4:-} ]] && printf '%s' "$4" >"$FAKE_DIR/$1.rc"
  return 0
}
reset() { rm -rf "$FAKE_DIR"; mkdir -p "$FAKE_DIR"; : >"$FAKE_LOG"; }
# run_a [env assignments...] -- hc-a args
run_a() {
  local unset_args=() assigns=()
  while [[ ${1:-} != -- ]]; do
    case $1 in
      -u) unset_args+=(-u "$2"); shift 2 ;;
      *)  assigns+=("$1"); shift ;;
    esac
  done
  shift
  env ${unset_args[@]+"${unset_args[@]}"} HC_BIN="$STUB" FAKE_DIR="$FAKE_DIR" FAKE_LOG="$FAKE_LOG" \
    ${assigns[@]+"${assigns[@]}"} "$HCA" "$@"
}
same() { [[ "$1" == "$2" ]] && pass "$3" || fail "$3" "want [$2] got [$1]"; }
has()  { case "$1" in *"$2"*) pass "$3";; *) fail "$3" "want substring [$2] in [$1]";; esac; }
hasnt(){ case "$1" in *"$2"*) fail "$3" "unwanted [$2] in [$1]";; *) pass "$3";; esac; }
rc_is(){ [[ "$1" == "$2" ]] && pass "$3" || fail "$3" "want rc $2 got $1"; }

FAKE_DIR="$TMP/fx"; FAKE_LOG="$TMP/args.log"; mkdir -p "$FAKE_DIR"

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
has "$log" 'run --json --bg' "argv: --json sits before positionals"
case "$log" in
  *'-- sh -c echo hi') pass "argv: program stays last, no --json after it";;
  *) fail "argv: program stays last, no --json after it" "got [$log]";;
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
out=$(run_a -- run --name fix claude 'do x')
has "$out" 'FIRST MESSAGE NOT SENT: readiness' "run: unsent first message is flagged"
has "$out" 'hc send t55' "run: prints the caller's report line"

reset
fx get '{"address":"t9","state":"live","cwd":"/tmp","argv":["claude"],"first_message":{"sent":false,"reason":"readiness"}}'
out=$(run_a HC_TERMINAL_ID=t55 -- get t9)
has "$out" 'FIRST MESSAGE NOT SENT: readiness' "get: unsent first message is flagged"

# ------------------------------------------------------------- P2.1 read size
reset
seq 1 100 >"$FAKE_DIR/read.out"
n=$(run_a -- read t5 | wc -l | tr -d ' ')
same "$n" 60 "read: default keeps the last 60 lines"
n=$(run_a -- read t5 --tail 0 | wc -l | tr -d ' ')
same "$n" 100 "read: --tail 0 keeps the whole screen"
n=$(run_a -- read t5 --tail 5 | wc -l | tr -d ' ')
same "$n" 5 "read: --tail N"

# ------------------------------------------------------- P2.1 read error path
reset
fx read '' '{"error":{"kind":"not_found","message":"no terminal \"zzz\"","hint":"see `hc ls --all`"}}' 3
out=$(run_a -- read zzz 2>&1); rc=$?
rc_is "$rc" 3 "read: exit code is hc's"
same "$out" 'error: no terminal "zzz"
help: see `hc ls --all`' "read: error is parsed, not dumped as JSON"

# ------------------------------------------------------- P2.2 missing values
reset
out=$(run_a -- read --lines 2>&1); rc=$?
rc_is "$rc" 2 "read: --lines without a value fails cleanly"
same "$out" 'error: --lines needs a value' "read: --lines message"
out=$(run_a -- run --cwd 2>&1); rc=$?
same "$out" 'error: --cwd needs a value' "run: --cwd message"

# ------------------------------------------------------ P2.3 <t> defaulting
reset
fx get '{"address":"t55","state":"live","cwd":"/tmp","argv":["zsh"]}'
out=$(run_a HC_TERMINAL_ID=t55 -- get)
has "$out" '*t55' "get: no argument means your own terminal"
log=$(cat "$FAKE_LOG")
same "$log" 'get t55 --json' "get: own address reaches hc"

reset
out=$(run_a -u HC_TERMINAL_ID -- get 2>&1); rc=$?
rc_is "$rc" 2 "outside herdr: exit code 2, not hc's"
same "$out" 'error: terminal required: pass <t> or run inside a herdr terminal' "outside herdr: single clean message"

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

# ------------------------------------------------------------ P2.5 TOON
reset
printf '%s' '{"terminals":[{"address":"t1","agent":"a,b","state":"live","status":"working","turn":2,"where":"x\ny,\"z\\w"}]}' >"$FAKE_DIR/ls.out"
out=$(run_a -- ls)
same "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2 "ls: hostile field stays on one row"
same "$(printf '%s\n' "$out" | tail -1)" '  t1,"a,b",live,working,2,"x\ny,\"z\\w"' "ls: comma/quote/backslash/newline escaped"

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
